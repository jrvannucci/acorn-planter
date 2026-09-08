# acorn installer (PowerShell) -- mirrors how `uv` installs itself.
# Requires nothing pre-installed; works on a stock Windows PowerShell / pwsh.
#
# Usage (from a local checkout of this repo, either works):
#   .\GET_STARTED\install.cmd  (permits this installer to run; checks profile policy separately)
#   .\installers\install.ps1
#
# Usage (remote):
#   irm https://raw.githubusercontent.com/jrvannucci/acorn-planter/main/acorn-planter/installers/install.ps1 | iex
#   $env:ACORN_REPO = "https://github.com/someone/fork.git"; irm .../installers/install.ps1 | iex

$ErrorActionPreference = "Stop"

# Built-in defaults. global.conf ships with these same values written
# out, so a conf that still matches them changes nothing -- only edited
# values have any effect. The baked-in copies exist for the piped
# one-liner install, where no local global.conf exists yet to consult.
$DefaultACORNRepo = "https://github.com/jrvannucci/acorn-planter.git"
$DefaultVenvPackages = "ipython,ruff,ipykernel"

function Info($msg)  { Write-Host "==> $msg" -ForegroundColor Green }
function Warn($msg)  { Write-Host "!! $msg" -ForegroundColor Yellow }
function Die($msg)   {
    Write-Host "error: $msg" -ForegroundColor Red
    # The exit-code marker is what `acorn logs-viewer` parses to show whether
    # this install completed; Stop-Transcript both finalizes the install log
    # and -- for piped `irm | iex` installs, where no process exit is coming
    # -- stops the transcript from silently recording the user's session
    # forever after. Guarded: transcription may never have started.
    Write-Host "acorn install FAILED (exit code 1)"
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}

# global.conf is the deployment config: organizations distributing
# acorn from their own git host or a network drive set the source (and
# any install-time settings) there ONCE, and their users install with no
# flags or env vars. Standard internet installs ship a conf whose values
# match the baked-in defaults, so nothing changes for them.
function Read-ACORNConf($path) {
    $conf = @{}
    if ($path -and (Test-Path $path)) {
        foreach ($line in Get-Content $path) {
            if ($line -match '^\s*([A-Z_]+)\s*=\s*"([^"]*)"\s*$') {
                $conf[$Matches[1]] = $Matches[2]
            }
        }
    }
    return $conf
}

# Resolve a usable git for the clone below: system git if present, else
# bootstrap a portable MinGit into $GitDir (extensions\git) -- the SAME
# location and mechanism `acorn repo-clone` uses (see git_tool.py), so the
# copy is reused later and never downloaded twice. This is what lets the
# public/self-hosted URL one-liners live up to "requires nothing
# pre-installed" on a stock Windows box. Windows-only by nature: Git for
# Windows ships an official dependency-free portable build (MinGit); macOS
# and Linux have no equivalent, so install.sh keeps requiring system git.
function Resolve-ACORNGit {
    param([string]$GitDir)

    $sys = Get-Command git -ErrorAction SilentlyContinue
    if ($sys) { return "git" }
    foreach ($rel in @("cmd\git.exe", "bin\git.exe")) {
        $existing = Join-Path $GitDir $rel
        if (Test-Path $existing) { return $existing }
    }

    Info "git isn't installed -- downloading a portable copy (MinGit) into $GitDir ..."
    New-Item -ItemType Directory -Force -Path $GitDir | Out-Null

    # GitHub's release API publishes a per-asset SHA-256 digest, so the zip
    # can be verified before it's extracted -- same policy as download.py.
    $api = "https://api.github.com/repos/git-for-windows/git/releases/latest"
    try {
        $release = Invoke-RestMethod -Uri $api -Headers @{ "User-Agent" = "acorn" }
    } catch {
        Die ("Could not reach GitHub's API to download MinGit ($($_.Exception.Message)). " +
             "Install git and re-run, or download the '...-64-bit.zip' asset from " +
             "https://github.com/git-for-windows/git/releases and extract it into $GitDir.")
    }
    # The 64-bit MinGit zip -- not the busybox variant, which lacks tools git
    # needs for cloning over https.
    $asset = $release.assets | Where-Object {
        $_.name -like "MinGit-*-64-bit.zip" -and $_.name -notlike "*busybox*"
    } | Select-Object -First 1
    if (-not $asset) { Die "Could not find a MinGit release asset to download." }

    $zip = Join-Path $GitDir "mingit-download.zip"
    Info "Downloading $($asset.name) ..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -Headers @{ "User-Agent" = "acorn" }

    if ($asset.digest) {
        $expected = ($asset.digest -replace '^sha256:', '').ToLower()
        $actual = (Get-FileHash -Path $zip -Algorithm SHA256).Hash.ToLower()
        if ($actual -ne $expected) {
            Remove-Item -Force $zip -ErrorAction SilentlyContinue
            Die ("SHA-256 verification FAILED for MinGit (expected $expected, got $actual). " +
                 "The download was deleted -- try again on a trusted network.")
        }
        Info "Verified SHA-256 checksum for MinGit."
    } else {
        Warn "No published checksum was available for MinGit; skipping verification."
    }

    Expand-Archive -Path $zip -DestinationPath $GitDir -Force
    Remove-Item -Force $zip -ErrorAction SilentlyContinue

    foreach ($rel in @("cmd\git.exe", "bin\git.exe")) {
        $exe = Join-Path $GitDir $rel
        if (Test-Path $exe) { return $exe }
    }
    Die "MinGit was downloaded but its git.exe couldn't be located in $GitDir."
}

# ---------------------------------------------------------------------------
# 1. Locate the acorn source (local checkout next to this script, or clone)
# ---------------------------------------------------------------------------
# $MyInvocation.MyCommand.Path is $null when this script is run via
# `irm ... | iex` (there's no backing file for a piped-in script), so guard
# against that instead of calling Split-Path on a null value.
$ScriptPath = $MyInvocation.MyCommand.Path
$ScriptDir = if ($ScriptPath) { Split-Path -Parent $ScriptPath } else { $null }
# This script lives in installers\; the repo root (GET_STARTED\, src\) is
# one level up.
$RepoRoot = if ($ScriptDir) { Split-Path -Parent $ScriptDir } else { $null }

$HasLocalCheckout = $false
if ($RepoRoot) {
    if (Test-Path (Join-Path $RepoRoot "src\pyproject.toml")) {
        $HasLocalCheckout = $true
    }
}

$Conf = if ($RepoRoot) { Read-ACORNConf (Join-Path $RepoRoot "global.conf") } else { @{} }

# Source resolution: ACORN_REPO env var (one-run override) beats
# global.conf, which beats the baked-in default.
$ACORNRepo = if ($env:ACORN_REPO) {
    $env:ACORN_REPO
} elseif ($Conf["ACORN_REPO_URL"]) {
    $Conf["ACORN_REPO_URL"]
} else {
    $DefaultACORNRepo
}

# Home resolution follows the same order. A leading "~" in the conf value
# means the installing user's home directory.
$ACORNHome = if ($env:ACORN_HOME) {
    $env:ACORN_HOME
} elseif ($Conf["ACORN_HOME_DIR"]) {
    $dir = $Conf["ACORN_HOME_DIR"]
    if ($dir -eq "~") { $HOME }
    elseif ($dir.StartsWith("~/") -or $dir.StartsWith("~\")) { Join-Path $HOME $dir.Substring(2) }
    else { $dir }
} else {
    Join-Path $HOME "acorn"
}

# {user} -> the installing user's login name, so a shared install root
# (e.g. C:\acorn\{user}) gives every user a private, conflict-free folder.
# When the token is used, record the shared root (the parent of the per-user
# home) so the elevated admin-* commands know this is a multi-user install.
$ACORNSharedRoot = $null
if ($ACORNHome -like "*{user}*") {
    $ACORNHome = $ACORNHome -replace [regex]::Escape("{user}"), $env:USERNAME
    $ACORNSharedRoot = Split-Path -Parent $ACORNHome
}

# Capture this whole install into the acorn logs, so `acorn logs-viewer`
# shows the bootstrap alongside your `acorn` commands. Start-Transcript records
# the console live WITHOUT redirecting any streams -- which matters because uv
# writes its normal progress to stderr, and redirecting a native command's
# stderr under $ErrorActionPreference='Stop' turns it into a fatal
# NativeCommandError (this broke the install once). Best-effort: never let
# logging break the install; the transcript auto-finalizes when the script exits.
try {
    $AcornLogDir = Join-Path $ACORNHome "system\logs"
    New-Item -ItemType Directory -Force -Path $AcornLogDir -ErrorAction Stop | Out-Null
    $AcornInstallLog = Join-Path $AcornLogDir ("install-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
    Start-Transcript -Path $AcornInstallLog -Force -ErrorAction Stop | Out-Null
} catch { }

$InstalledFromDir = $null
$CloneMode = $false
if ($HasLocalCheckout) {
    $OriginalSrc = $RepoRoot
    $CleanupOriginalSrc = $false
} elseif ((Test-Path $ACORNRepo -PathType Container) -and ((Test-Path (Join-Path $ACORNRepo "src\pyproject.toml")) -or (Test-Path (Join-Path $ACORNRepo "acorn-planter\src\pyproject.toml")))) {
    # ACORN_REPO can be a plain directory instead of a git URL -- e.g. a
    # network drive holding a copy of this repo, on machines/networks with
    # no GitHub access at all.
    Info "Installing from directory $ACORNRepo ..."
    $OriginalSrc = $ACORNRepo
    $CleanupOriginalSrc = $false
    $InstalledFromDir = $ACORNRepo
} else {
    # No system git? Bootstrap portable MinGit into extensions\git before the
    # clone, so a bare Windows box can still install from a URL.
    $Git = Resolve-ACORNGit (Join-Path $ACORNHome "extensions\git")
    $OriginalSrc = Join-Path ([System.IO.Path]::GetTempPath()) ("acorn-src-" + [System.Guid]::NewGuid())
    $CleanupOriginalSrc = $true
    $CloneMode = $true
    Info "Cloning $ACORNRepo ..."
    & $Git clone --depth 1 $ACORNRepo $OriginalSrc
}

$SourceRoot = $OriginalSrc
if (Test-Path (Join-Path $OriginalSrc "acorn-planter\src\pyproject.toml")) {
    $OriginalSrc = Join-Path $OriginalSrc "acorn-planter"
}

# ---------------------------------------------------------------------------
# 2. Lay out the folder structure
# ---------------------------------------------------------------------------
Info "Setting up $ACORNHome"
$null = New-Item -ItemType Directory -Force -Path `
    "$ACORNHome\system\bin", `
    "$ACORNHome\system\config", `
    "$ACORNHome\system\shell", `
    "$ACORNHome\python\base", `
    "$ACORNHome\python\venvs", `
    "$ACORNHome\extensions", `
    "$ACORNHome\repo"

# ---------------------------------------------------------------------------
# 2b. Copy the source INTO acorn itself. This is what makes updates
#     explicit: acorn-cli gets installed from $ACORNHome\src, a copy that
#     nothing outside of `acorn update-commands` ever touches again. Deleting,
#     moving, or `git pull`-ing wherever you originally downloaded this from
#     has zero effect on the installed commands after this point.
# ---------------------------------------------------------------------------
Info "Copying source into $ACORNHome\system\src ..."
$SrcDir = Join-Path $ACORNHome "system\src"
if (Test-Path $SrcDir) { Remove-Item -Recurse -Force $SrcDir }
$null = New-Item -ItemType Directory -Force -Path $SrcDir
# Shared resource collections stay at their configured source.
Get-ChildItem -LiteralPath $OriginalSrc -Force | Where-Object {
    $_.Name -notin @("wheels", "python-builds", "conda-channel", "MANIFEST.json", ".git", ".venv")
} | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $SrcDir -Recurse -Force }
# No git checkout lives inside ~\acorn: updates re-download from the
# recorded update_source (see below) instead of `git pull`-ing, so the
# .git folder would be dead weight (and its read-only object files used
# to break deletion on Windows).
# The deployment profile travels with the source copy, so `acorn apply` keeps
# working after the share it was installed from goes away. An absolute path
# in the conf is honoured as-is.
$ProfilePath = ""
if ($env:ACORN_PROFILE) {
    # User-supplied, for the piped one-liner (`$env:ACORN_PROFILE = ...;
    # irm ... | iex`), where there is no local conf to edit. Relative paths
    # resolve against the directory they ran the installer from -- they are
    # pointing at THEIR file.
    $rawProfile = $env:ACORN_PROFILE
    $profileSrc = if ([System.IO.Path]::IsPathRooted($rawProfile)) {
        $rawProfile
    } else {
        Join-Path (Get-Location).Path $rawProfile
    }
    # Fatal, unlike the conf case below: someone who explicitly named a
    # profile and silently got the default environment instead would not
    # find out until something they expected is missing.
    if (-not (Test-Path $profileSrc)) {
        Die "ACORN_PROFILE=$rawProfile was set, but no file exists at $profileSrc."
    }
    # Copy it in: the original may be a downloads folder, a mounted share or
    # a temp file, and `acorn apply` has to keep working long after that goes
    # away -- the same reason the source itself is copied.
    $ProfilePath = Join-Path $ACORNHome "system\config\profile.toml"
    Copy-Item -Force $profileSrc $ProfilePath
    Info "Using profile $profileSrc (copied to $ProfilePath)"
} elseif ($Conf["ACORN_PROFILE"]) {
    # Conf-supplied: ships inside the distributed copy, so it already lives
    # under the acorn home and `acorn update-commands` refreshes it.
    $rawProfile = $Conf["ACORN_PROFILE"]
    if ([System.IO.Path]::IsPathRooted($rawProfile)) {
        $ProfilePath = $rawProfile
    } else {
        $ProfilePath = Join-Path $SrcDir $rawProfile
    }
    if (-not (Test-Path $ProfilePath)) {
        # Non-fatal, unlike the env case: a conf naming a profile that wasn't
        # distributed shouldn't brick installs across a whole fleet.
        Warn "ACORN_PROFILE=$rawProfile was set, but no profile was found at"
        Warn "$ProfilePath -- falling back to the default setup."
        $ProfilePath = ""
    }
}

# Custom commands (see docs/CUSTOM-COMMANDS.md): one TOML file naming every
# command, including any `script = "..."` files -- wired exactly like the
# profile above: env-var override (copied in, since its origin may not
# survive) beats conf (left in place, since it already lives inside the
# copied source tree -- any sibling script files ride along for free).
# The env-var branch copies the file's WHOLE containing directory, not just
# the file, so a relative `script = "..."` entry's sibling files (and their
# own companion data) survive too -- the same thing the conf-distributed
# form already gets for free from the source-tree copy. This assumes the
# directory holding the TOML file is scoped to this deployment; point
# ACORN_CUSTOM_COMMANDS at a dedicated folder, not somewhere with
# unrelated large content, if using the env-var override.
$CustomCommandsPath = ""
if ($env:ACORN_CUSTOM_COMMANDS) {
    $rawCC = $env:ACORN_CUSTOM_COMMANDS
    $ccSrc = if ([System.IO.Path]::IsPathRooted($rawCC)) { $rawCC } else { Join-Path (Get-Location).Path $rawCC }
    if (-not (Test-Path $ccSrc)) {
        Die "ACORN_CUSTOM_COMMANDS=$rawCC was set, but no file exists at $ccSrc."
    }
    $ccSrcDir = Split-Path -Parent $ccSrc
    $ccBasename = Split-Path -Leaf $ccSrc
    $ccDestDir = Join-Path $ACORNHome "system\config\custom-commands"
    if (Test-Path $ccDestDir) { Remove-Item -Recurse -Force $ccDestDir }
    Copy-Item -Recurse -Force $ccSrcDir $ccDestDir
    $CustomCommandsPath = Join-Path $ccDestDir $ccBasename
    Info "Using custom commands $ccSrc (copied to $CustomCommandsPath)"
} elseif ($Conf["ACORN_CUSTOM_COMMANDS"]) {
    $rawCC = $Conf["ACORN_CUSTOM_COMMANDS"]
    $CustomCommandsPath = if ([System.IO.Path]::IsPathRooted($rawCC)) { $rawCC } else { Join-Path $SrcDir $rawCC }
    if (-not (Test-Path $CustomCommandsPath)) {
        Warn "ACORN_CUSTOM_COMMANDS=$rawCC was set, but no file was found at"
        Warn "$CustomCommandsPath -- no custom commands."
        $CustomCommandsPath = ""
    }
}

# An organization's own settings.json/keybindings.json to acorn into a fresh
# editor (see docs/DEPLOYMENT.md) -- same env-var/conf split as everything
# above. The env var names the directory itself (not a file whose parent is
# inferred), so the whole-directory copy here is exactly what was asked
# for, not a guess at what else might be needed.
$VscodeConfigDirPath = ""
if ($env:ACORN_VSCODE_CONFIG_DIR) {
    $rawVCD = $env:ACORN_VSCODE_CONFIG_DIR
    $vcdSrc = if ([System.IO.Path]::IsPathRooted($rawVCD)) { $rawVCD } else { Join-Path (Get-Location).Path $rawVCD }
    if (-not (Test-Path $vcdSrc -PathType Container)) {
        Die "ACORN_VSCODE_CONFIG_DIR=$rawVCD was set, but no folder exists at $vcdSrc."
    }
    $VscodeConfigDirPath = Join-Path $ACORNHome "system\config\vscode-config"
    if (Test-Path $VscodeConfigDirPath) { Remove-Item -Recurse -Force $VscodeConfigDirPath }
    Copy-Item -Recurse -Force $vcdSrc $VscodeConfigDirPath
    Info "Using VS Code config $vcdSrc (copied to $VscodeConfigDirPath)"
} elseif ($Conf["ACORN_VSCODE_CONFIG_DIR"]) {
    $rawVCD = $Conf["ACORN_VSCODE_CONFIG_DIR"]
    $VscodeConfigDirPath = if ([System.IO.Path]::IsPathRooted($rawVCD)) { $rawVCD } else { Join-Path $SrcDir $rawVCD }
    if (-not (Test-Path $VscodeConfigDirPath -PathType Container)) {
        Warn "ACORN_VSCODE_CONFIG_DIR=$rawVCD was set, but no folder was found at"
        Warn "$VscodeConfigDirPath -- no settings/keybindings to acorn."
        $VscodeConfigDirPath = ""
    }
}

$SrcGit = Join-Path $SrcDir ".git"
if (Test-Path $SrcGit) { Remove-Item -Recurse -Force $SrcGit }

# ---------------------------------------------------------------------------
# 2b-vendor. Offline binaries shipped inside the install source (see
#     docs/OFFLINE.md): a `vendor\` folder in the distributed copy can hold
#     the uv binary, a portable git, and a pre-seeded VS Code. Whatever is
#     present gets copied into place BEFORE the download steps below --
#     each of which skips itself when its target already exists -- so an
#     offline share needs no wrapper scripts and no extra configuration:
#     presence equals intent. Every payload is a folder whose CONTENTS go
#     to the destination:
#       vendor\uv\     (uv.exe, uvx too if present)     -> ~\acorn\system\bin\
#       vendor\git\    (an extracted MinGit)            -> ~\acorn\extensions\git\
#       vendor\vscode\ (a pre-seeded portable VS Code)  -> ~\acorn\extensions\vscode\
#       vendor\certs\  (PEM CA certificates)            -> concatenated into
#                       ~\acorn\system\certs\ca-bundle.pem and trusted for
#                       all HTTPS (uv, git, acorn's own downloads)
# ---------------------------------------------------------------------------
$CertBundle = $null
$VendorDir = Join-Path $SrcDir "vendor"
if (Test-Path $VendorDir) {
    $vendorUv = Join-Path $VendorDir "uv"
    if ((Test-Path $vendorUv) -and -not (Test-Path "$ACORNHome\system\bin\uv.exe")) {
        Copy-Item "$vendorUv\*" -Destination "$ACORNHome\system\bin" -Recurse -Force
        Info "Using vendored uv from the install source."
    }
    $vendorMm = Join-Path $VendorDir "micromamba"
    if ((Test-Path $vendorMm) -and -not (Test-Path "$ACORNHome\system\bin\micromamba.exe")) {
        Copy-Item "$vendorMm\*" -Destination "$ACORNHome\system\bin" -Recurse -Force
        Info "Using vendored micromamba (conda-forge tools) from the install source."
    }
    $vendorGit = Join-Path $VendorDir "git"
    if ((Test-Path $vendorGit) -and -not (Test-Path "$ACORNHome\extensions\git")) {
        New-Item -ItemType Directory -Force -Path "$ACORNHome\extensions\git" | Out-Null
        Copy-Item "$vendorGit\*" -Destination "$ACORNHome\extensions\git" -Recurse -Force
        Info "Using vendored portable git from the install source."
    }
    $vendorVscode = Join-Path $VendorDir "vscode"
    if ((Test-Path $vendorVscode) -and -not (Test-Path "$ACORNHome\extensions\vscode\app")) {
        New-Item -ItemType Directory -Force -Path "$ACORNHome\extensions\vscode" | Out-Null
        Copy-Item "$vendorVscode\*" -Destination "$ACORNHome\extensions\vscode" -Recurse -Force
        Info "Using vendored VS Code from the install source."
    }
    $vendorCerts = Join-Path $VendorDir "certs"
    if (Test-Path $vendorCerts) {
        # Unlike the binaries above, the bundle is REBUILT on every install
        # so certificate rotation propagates with a plain reinstall.
        $certFiles = @(Get-ChildItem -Path $vendorCerts -File | Where-Object { $_.Extension -in ".pem", ".crt" })
        if ($certFiles.Count -gt 0) {
            New-Item -ItemType Directory -Force -Path "$ACORNHome\system\certs" | Out-Null
            $CertBundle = "$ACORNHome\system\certs\ca-bundle.pem"
            ($certFiles | ForEach-Object { (Get-Content $_.FullName -Raw).TrimEnd() }) -join "`n" |
                Set-Content -Path $CertBundle -Encoding ASCII
            Info "Installed the vendored CA certificate bundle."
        } else {
            Warn "vendor\certs exists but holds no .pem/.crt files; no CA bundle installed."
        }
    }
    # The payloads live on the distribution source, not inside acorn's
    # private source copy -- a pre-seeded VS Code would otherwise bloat
    # system\src by hundreds of MB and get re-copied on every update.
    Remove-Item -Recurse -Force $VendorDir
}

if ($CleanupOriginalSrc) {
    Remove-Item -Recurse -Force $SourceRoot -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# 2c. Seed acorn's settings from global.conf (first install only --
#     an existing settings.json is never touched, so reinstalls don't
#     clobber choices made later with `acorn config set`).
# ---------------------------------------------------------------------------
# Piped installs have no local conf, but the clone we just copied does.
if ($Conf.Count -eq 0) {
    $Conf = Read-ACORNConf (Join-Path $SrcDir "global.conf")
}

# Record where this install came from, so `acorn update-commands` knows
# where to fetch newer versions (there's no git checkout inside ~\acorn
# to pull with -- updating re-downloads from this source instead):
#   - directory install  -> that directory
#   - cloned from a URL  -> that URL
#   - local checkout     -> env var / org-edited conf if given, else the
#                           checkout DIRECTORY itself, so updates re-copy from
#                           that working tree (a developer's local edits, or a
#                           `git pull` there, reach the install via
#                           `acorn update-commands`)
$UpdateSourceSeed = $null
if ($InstalledFromDir) {
    $UpdateSourceSeed = $InstalledFromDir
} elseif ($CloneMode) {
    $UpdateSourceSeed = $ACORNRepo
} else {
    if ($env:ACORN_REPO) {
        $UpdateSourceSeed = $ACORNRepo
    } elseif ($Conf["ACORN_REPO_URL"] -and $Conf["ACORN_REPO_URL"] -ne $DefaultACORNRepo) {
        $UpdateSourceSeed = $Conf["ACORN_REPO_URL"]
    } else {
        # No explicit override: update straight from the checkout this was
        # installed from -- installing from a repo directory means updating
        # from that same directory (consistent with the directory-install
        # case above), which is what a developer iterating on the commands
        # wants. `git pull` there, then `acorn update-commands`, to test edits.
        $UpdateSourceSeed = $RepoRoot
    }
}

$SettingsFile = Join-Path $ACORNHome "system\config\settings.json"
if (-not (Test-Path $SettingsFile)) {
    $acorn = @{}
    if ($UpdateSourceSeed) { $acorn["update_source"] = "$UpdateSourceSeed" }
    # Only seed the package list when it was actually changed -- the conf
    # ships with the built-in default written out for discoverability.
    if ($Conf["ACORN_VENV_DEFAULT_PACKAGES"]) {
        $pkgs = @($Conf["ACORN_VENV_DEFAULT_PACKAGES"].Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($pkgs.Count -gt 0 -and (($pkgs -join ",") -ne $DefaultVenvPackages)) {
            $acorn["venv_default_packages"] = $pkgs
        }
    }
    # Offline sources (see docs/OFFLINE.md): recorded so every future
    # `acorn` command applies them automatically -- users never set
    # environment variables themselves.
    if ($Conf["ACORN_PYTHON_MIRROR"]) { $acorn["python_mirror"] = $Conf["ACORN_PYTHON_MIRROR"] }
    if ($Conf["ACORN_PACKAGE_INDEX"]) { $acorn["package_index"] = $Conf["ACORN_PACKAGE_INDEX"] }
    if ($Conf["ACORN_PACKAGE_UPLOAD_URL"]) { $acorn["package_upload_url"] = $Conf["ACORN_PACKAGE_UPLOAD_URL"] }
    # A WRITE credential -- normally empty in a distributed conf, set only on
    # the machine that publishes. Seeding it here gives every user of this
    # share publish rights to the index.
    if ($Conf["ACORN_PACKAGE_UPLOAD_TOKEN"]) { $acorn["package_upload_token"] = $Conf["ACORN_PACKAGE_UPLOAD_TOKEN"] }
    # conda-forge channel for `acorn forge-install`. Only seeded when overridden
    # (an internal mirror / offline path); the built-in default is conda-forge.
    if ($Conf["ACORN_CONDA_CHANNEL"]) {
        $channel = $Conf["ACORN_CONDA_CHANNEL"].Trim()
        if ($channel -and $channel -ne "conda-forge") { $acorn["conda_channel"] = $channel }
    }
    if ($Conf["ACORN_NATIVE_TLS"] -and $Conf["ACORN_NATIVE_TLS"].ToLower() -eq "true") {
        $acorn["native_tls"] = $true
    }
    if ($CertBundle) { $acorn["ca_cert"] = "$CertBundle" }
    if ($ACORNSharedRoot) { $acorn["shared_root"] = "$ACORNSharedRoot" }
    # Editor flavor/gallery/extensions. Only seeded when actually changed --
    # the conf ships with the built-in defaults written out, same as the
    # package list above.
    if ($Conf["ACORN_VSCODE_FLAVOR"]) {
        $flavor = $Conf["ACORN_VSCODE_FLAVOR"].Trim().ToLower()
        if ($flavor -and $flavor -ne "microsoft") { $acorn["vscode_flavor"] = $flavor }
    }
    if ($Conf["ACORN_EXTENSION_GALLERY"]) {
        $acorn["extension_gallery"] = $Conf["ACORN_EXTENSION_GALLERY"]
    }
    if ($ProfilePath) { $acorn["profile"] = "$ProfilePath" }
    if ($CustomCommandsPath) { $acorn["custom_commands"] = "$CustomCommandsPath" }
    if ($VscodeConfigDirPath) { $acorn["vscode_config_dir"] = "$VscodeConfigDirPath" }
    if ($Conf["ACORN_STARTUP_COMMANDS"]) {
        $startups = @($Conf["ACORN_STARTUP_COMMANDS"].Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($startups.Count -gt 0) { $acorn["startup_commands"] = $startups }
    }
    if ($Conf["ACORN_VSCODE_EXTENSIONS"]) {
        $extsRaw = $Conf["ACORN_VSCODE_EXTENSIONS"].Trim()
        if ($extsRaw.ToLower() -eq "none") {
            # A deliberate "install nothing", distinct from "unset".
            $acorn["vscode_extensions"] = @()
        } else {
            $exts = @($extsRaw.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            if ($exts.Count -gt 0) { $acorn["vscode_extensions"] = $exts }
        }
    }
    if ($acorn.Count -gt 0) {
        $acorn | ConvertTo-Json | Set-Content -Path $SettingsFile -Encoding UTF8
        Info "Seeded acorn settings from global.conf"
    }
}

# ---------------------------------------------------------------------------
# 2d. Apply the offline sources to THIS installer's own uv/acorn-cli calls
#     too (building acorn-cli needs the package index; the default
#     environment setup needs both). Pre-set UV_* variables still win.
# ---------------------------------------------------------------------------
function To-FileUrl($value) {
    if ($value -match "://") { return $value }
    $u = $value -replace "\\", "/"
    if ($u -match "^[A-Za-z]:/") { return "file:///$u" }
    if ($u.StartsWith("/")) { return "file://$u" }
    return $value
}

# TLS first: the vendored CA bundle / native trust store must cover the
# uv bootstrap and everything after it.
if ($CertBundle -and -not $env:SSL_CERT_FILE) {
    $env:SSL_CERT_FILE = $CertBundle
    $env:GIT_SSL_CAINFO = $CertBundle
}
if ($Conf["ACORN_NATIVE_TLS"] -and $Conf["ACORN_NATIVE_TLS"].ToLower() -eq "true" -and -not $env:UV_NATIVE_TLS) {
    $env:UV_NATIVE_TLS = "1"
}

if ($Conf["ACORN_PYTHON_MIRROR"] -and -not $env:UV_PYTHON_INSTALL_MIRROR) {
    $env:UV_PYTHON_INSTALL_MIRROR = To-FileUrl $Conf["ACORN_PYTHON_MIRROR"]
}
if ($Conf["ACORN_PACKAGE_INDEX"]) {
    $idx = $Conf["ACORN_PACKAGE_INDEX"]
    if ($idx -match "://") {
        if (-not $env:UV_DEFAULT_INDEX) { $env:UV_DEFAULT_INDEX = $idx }
    } elseif (-not $env:UV_CONFIG_FILE) {
        # A directory of wheels: uv has no reliable env var for "flat
        # directory index, internet disabled", but honors a config file.
        # acorn-cli generates the same file from settings later.
        $UvToml = Join-Path $ACORNHome "system\config\uv.toml"
        @(
            "# Generated by acorn from the ``package_index`` setting. Do not edit;"
            "# change it with:  acorn config set package_index <url-or-directory>"
            "[[index]]"
            'name = "acorn-offline"'
            "url = `"$(To-FileUrl $idx)`""
            'format = "flat"'
            "default = true"
        ) | Set-Content -Path $UvToml -Encoding UTF8
        $env:UV_CONFIG_FILE = $UvToml
    }
}


# ---------------------------------------------------------------------------
# 3. Install uv itself into acorn\bin
# ---------------------------------------------------------------------------
$UvExe = Join-Path $ACORNHome "system\bin\uv.exe"
if (-not (Test-Path $UvExe)) {
    Info "Installing uv into $ACORNHome\system\bin ..."
    $env:UV_INSTALL_DIR = "$ACORNHome\system\bin"
    $env:UV_NO_MODIFY_PATH = "1"
    Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression
} else {
    Info "uv already present, skipping."
}

if (-not (Test-Path $UvExe)) { Die "uv install appears to have failed (not found at $UvExe)." }

# ---------------------------------------------------------------------------
# 3b. Add system\bin to the persistent user PATH -- so acorn-cli (and uv,
#     micromamba) are reachable as a bare command from ANY process, not just
#     an interactive shell that has sourced the `acorn` function below. This
#     is what makes acorn-cli usable from a script, a CI job, or an AI coding
#     agent's shell tool: many of those spawn a fresh, non-interactive
#     process that never loads $PROFILE. The `acorn` FUNCTION still wins in
#     an interactive shell (PowerShell resolves functions before PATH), so
#     nothing here changes what a person at a terminal sees or does.
#     User-scope (HKCU), never Machine-scope: no admin rights needed, and it
#     matches the per-user install model everywhere else in this script.
#     Undone by `acorn purge` (purge_cmd._windows_path_bin_entry).
#
#     Placed HERE, before step 4's `uv tool install`, not after -- and also
#     applied to THIS PROCESS's $env:PATH, not just the registry: uv checks
#     the running process's PATH, which [Environment]::SetEnvironmentVariable
#     never touches (that only affects processes started after it runs).
#     Registering the entry after step 4 left it correct for every FUTURE
#     shell but too late for uv's own install, which printed its own
#     "is not on your PATH" warning regardless -- confusing right after this
#     script just added it.
#
#     ACORN_SKIP_PATH_REGISTER is a test-only escape hatch (set by
#     run_powershell_install in tests/conftest.py): every installer test
#     runs against a throwaway ACORN_HOME but the REAL registry -- there
#     is no fake HKCU to redirect this into the way $PROFILE gets faked
#     above, so tests opt out of this one step entirely rather than risk
#     writing a test's tmp path into a real machine's PATH.
# ---------------------------------------------------------------------------
if (-not $env:ACORN_SKIP_PATH_REGISTER) {
    $BinDir = Join-Path $ACORNHome "system\bin"
    $UserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $UserPathEntries = @(if ($UserPath) { $UserPath -split ';' } else { @() })
    if ($UserPathEntries -notcontains $BinDir) {
        $NewUserPath = if ($UserPath) { "$UserPath;$BinDir" } else { $BinDir }
        [Environment]::SetEnvironmentVariable("PATH", $NewUserPath, "User")
        Info "Added $BinDir to your PATH (new terminals/processes will see it)."
    }
    if (($env:PATH -split ';') -notcontains $BinDir) {
        $env:PATH = "$BinDir;$env:PATH"
    }
}

# ---------------------------------------------------------------------------
# 4. Install the acorn CLI itself as an isolated uv tool
# ---------------------------------------------------------------------------
Info "Installing the acorn CLI ..."
$env:UV_TOOL_DIR = "$ACORNHome\system\tool"
$env:UV_TOOL_BIN_DIR = "$ACORNHome\system\bin"
$env:UV_CACHE_DIR = "$ACORNHome\system\cache\uv"
& $UvExe tool install --force --reinstall (Join-Path $SrcDir "src")

$AcornCli = Join-Path $ACORNHome "system\bin\acorn-cli.exe"
if (-not (Test-Path $AcornCli)) { Die "acorn-cli was not installed correctly." }

# ---------------------------------------------------------------------------
# 4b. Default environment: the newest stable Python plus a 'dev' venv (with
#     the default packages) that every new shell auto-activates -- so a
#     fresh install is immediately usable with plain `python`/`ipython`.
#     Skip with ACORN_AUTO_SETUP="false" (env var or global.conf). Never
#     fatal: a network hiccup here still leaves a working acorn.
# ---------------------------------------------------------------------------
$AutoSetup = if ($env:ACORN_AUTO_SETUP) {
    $env:ACORN_AUTO_SETUP
} elseif ($Conf["ACORN_AUTO_SETUP"]) {
    $Conf["ACORN_AUTO_SETUP"]
} else {
    "true"
}

$DevReady = $false
if ($AutoSetup.ToLower() -eq "false") {
    Info "Skipping default environment setup (ACORN_AUTO_SETUP=$AutoSetup)."
} else {
    # VS Code setup starts FIRST, as a background job: it's independent of
    # the python/venv steps and dominated by a ~300MB download, so it
    # overlaps them instead of adding its whole duration to the install.
    # ACORN_NO_LOG=1 keeps the background run from interleaving with the
    # foreground acorn commands inside the daily log; its output is replayed
    # below (which also lands it in the install transcript). Idempotent
    # (skips if already present) and never fatal. Note: the job runs in its
    # own runspace where $ErrorActionPreference is the default 'Continue',
    # so uv/acorn-cli writing progress to stderr can't become a fatal
    # NativeCommandError there.
    $AutoVscode = if ($env:ACORN_AUTO_VSCODE) {
        $env:ACORN_AUTO_VSCODE
    } elseif ($Conf["ACORN_AUTO_VSCODE"]) {
        $Conf["ACORN_AUTO_VSCODE"]
    } else {
        "true"
    }
    # A profile that names an editor OUTRANKS ACORN_AUTO_VSCODE: a
    # deployment that asked for Spyder shouldn't also be handed ~300MB of VS
    # Code it never mentioned. Asked here rather than after `acorn apply`
    # because the VS Code job starts first (it overlaps the Python setup), so
    # the answer is needed before it launches. Empty means the profile doesn't
    # say, and the conf setting decides as before. When the profile DOES say
    # "vscode" the job still starts -- apply then finds it installed and
    # skips, so the parallelism is kept.
    $ProfileEditor = ""
    if ($ProfilePath) {
        try {
            $env:ACORN_HOME = $ACORNHome
            $env:ACORN_NO_LOG = "1"
            $ProfileEditor = (& $AcornCli apply $ProfilePath --print-editor | Out-String).Trim()
        } catch {
            $ProfileEditor = ""
        }
    }
    # The profile may name several editors; skip the VS Code job only if it
    # names some and VS Code isn't among them.
    $SkipVscode = $false
    if ($ProfileEditor) {
        $SkipVscode = -not (($ProfileEditor -split '\s+') -contains "vscode")
    }
    $VscodeJob = $null
    if ($SkipVscode) {
        Info "Profile selects '$ProfileEditor' as the editor; skipping VS Code."
    } elseif ($AutoVscode.ToLower() -eq "false") {
        Info "Skipping VS Code install (ACORN_AUTO_VSCODE=$AutoVscode)."
    } else {
        Info "Setting up VS Code in the background (continues while Python is set up) ..."
        $VscodeJob = Start-Job -ScriptBlock {
            # NOT `param($cli, $home)`: $home is PowerShell's read-only
            # automatic variable, and binding a parameter to it kills the
            # job instantly ("Cannot overwrite variable home").
            param($cli, $seedHome)
            $env:ACORN_HOME = $seedHome
            $env:ACORN_NO_LOG = "1"
            # -y: this runs as a background job with no console to prompt at,
            # and the user already opted in via ACORN_AUTO_VSCODE.
            & $cli vscode --no-open -y
            "SEEDVSC_EXIT=$LASTEXITCODE"
        } -ArgumentList $AcornCli, $ACORNHome
    }

    if ($ProfilePath) {
        # A profile is the authoritative definition of this deployment's
        # environment, so it REPLACES the built-in single-'dev'-venv setup
        # rather than layering on top of it -- otherwise every machine would
        # carry a 'dev' venv the admin never asked for.
        Info "Applying deployment profile: $ProfilePath"
        $env:ACORN_HOME = $ACORNHome
        & $AcornCli python
        if ($LASTEXITCODE -eq 0) { & $AcornCli apply $ProfilePath }
        if ($LASTEXITCODE -eq 0) {
            $DevReady = $true
        } else {
            Warn "The deployment profile didn't fully apply."
            Warn "Re-run it later with:  acorn apply"
        }
    } elseif (Test-Path (Join-Path $ACORNHome "python\venvs\dev")) {
        Info "Default 'dev' venv already exists, leaving it as-is."
        $DevReady = $true
    } else {
        Info "Setting up the default environment: newest Python + a 'dev' venv ..."
        $env:ACORN_HOME = $ACORNHome
        & $AcornCli python
        if ($LASTEXITCODE -eq 0) { & $AcornCli venv dev }
        if ($LASTEXITCODE -eq 0) {
            # Make 'dev' the venv new shells auto-activate -- unless the user
            # already chose one (reinstall case).
            $env:ACORN_NO_LOG = "1"
            $existingDefault = & $AcornCli config get default_venv
            Remove-Item Env:ACORN_NO_LOG -ErrorAction SilentlyContinue
            if (-not $existingDefault) { & $AcornCli config set default_venv dev }
            $DevReady = $true
        } else {
            Warn "Default environment setup didn't finish (network problem?)."
            Warn "Set it up later with:  acorn python; acorn venv dev; acorn config set default_venv dev"
        }
    }

    # Collect the background VS Code job: replay its buffered output, pick
    # out the exit-code sentinel, and warn -- never fail -- on a bad exit.
    # $ErrorActionPreference is relaxed JUST around Receive-Job: the job's
    # error stream can hold native-stderr records (uv progress etc.), and
    # receiving those under 'Stop' throws a fatal NativeCommandError
    # (verified); under 'Continue' the `*>&1` merge turns them into plain
    # replayable strings.
    if ($VscodeJob) {
        Info "Waiting for the background VS Code setup to finish ..."
        # Live status bar: acorn-cli mirrors its progress into a one-line
        # status file ("<phase> <done> <total>"); poll it and repaint one
        # console line in place. Only repaint on change, so the install
        # transcript doesn't fill with duplicate frames.
        $StatusFile = Join-Path $ACORNHome "extensions\vscode\setup-status"
        $lastBar = ""
        while ($VscodeJob.State -eq "Running") {
            Start-Sleep -Milliseconds 500
            $bar = "VS Code: setting up ..."
            if (Test-Path $StatusFile) {
                try {
                    $parts = (Get-Content $StatusFile -TotalCount 1 -ErrorAction Stop) -split " "
                    switch ($parts[0]) {
                        "downloading" {
                            $done = [long]$parts[1]; $total = [long]$parts[2]
                            if ($total -gt 0) {
                                $pct = [int](100 * $done / $total)
                                $filled = [int]($pct / 5)
                                $bar = ("VS Code: downloading [{0}{1}] {2,3}% of {3:N0} MB" -f
                                        ("#" * $filled), ("-" * (20 - $filled)), $pct, ($total / 1MB))
                            } else {
                                $bar = ("VS Code: downloading {0:N0} MB ..." -f ($done / 1MB))
                            }
                        }
                        "resolving"  { $bar = "VS Code: finding the latest build ..." }
                        "extracting" { $bar = "VS Code: extracting ..." }
                        "extensions" { $bar = "VS Code: installing extensions (Python, Jupyter, linting) ..." }
                    }
                } catch { }
            }
            if ($bar -ne $lastBar) {
                Write-Host -NoNewline ("`r" + $bar.PadRight(78))
                $lastBar = $bar
            }
        }
        if ($lastBar) { Write-Host ("`r" + (" " * 78) + "`r") -NoNewline }
        Wait-Job $VscodeJob | Out-Null
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $vscodeLines = @(Receive-Job $VscodeJob *>&1 | ForEach-Object { "$_" })
        $ErrorActionPreference = $prevEap
        Remove-Job $VscodeJob -Force -ErrorAction SilentlyContinue
        $vscodeExit = 1
        foreach ($line in $vscodeLines) {
            if ($line -match '^SEEDVSC_EXIT=(-?\d+)$') { $vscodeExit = [int]$Matches[1] }
            elseif ($line) { Write-Host $line }
        }
        if ($vscodeExit -ne 0) {
            Warn "VS Code setup didn't finish (network problem?). Install it later with:  acorn vscode"
        }
    }
}

# ---------------------------------------------------------------------------
# 5. Write the `acorn` PowerShell function and hook it into $PROFILE
# ---------------------------------------------------------------------------
Info "Writing shell integration ..."
$templatePath = Join-Path $SrcDir "src\acorn\shell\acorn.ps1.template"
$content = Get-Content $templatePath -Raw
$content = $content -replace [regex]::Escape("__ACORN_HOME_PLACEHOLDER__"), $ACORNHome
$seedPs1 = Join-Path $ACORNHome "system\shell\acorn.ps1"
Set-Content -Path $seedPs1 -Value $content -Encoding UTF8

$hookLine = ". `"$seedPs1`""

function Enable-ACORNProfilePolicy {
    param(
        # ACORN_POWERSHELL_POLICY, resolved by the caller. "" asks an
        # interactive person and otherwise only prints the command;
        # "remotesigned"/"true" is the deployment answering yes on the user's
        # behalf; "skip"/"false" is the deployment saying it manages policy
        # itself (Group Policy, a machine image) and the installer must not
        # look at or touch it.
        [string]$Preference = "",
        [bool]$CanPrompt = (-not [Console]::IsInputRedirected)
    )
    $pref = $Preference.Trim().ToLower()
    if ($pref -in @("skip", "false", "no", "off")) { return $true }
    $forced = $pref -in @("true", "remotesigned", "remote-signed", "force")
    # Ignore Process: install.cmd uses Bypass only for this installer process.
    try {
        $policy = "Restricted"
        $policyScope = "Default"
        foreach ($scope in @("MachinePolicy", "UserPolicy", "CurrentUser", "LocalMachine")) {
            $value = [string](Get-ExecutionPolicy -Scope $scope -ErrorAction Stop)
            if ($value -ne "Undefined") {
                $policy = $value
                $policyScope = $scope
                break
            }
        }
        if ($policy -in @("RemoteSigned", "Unrestricted", "Bypass")) { return $true }
        Warn "New PowerShell windows use $policy ($policyScope); the ACORN profile may not load."
        if ($policyScope -in @("MachinePolicy", "UserPolicy") -or $policy -eq "AllSigned") {
            Warn "Ask your administrator about allowing or signing the PowerShell profile and ACORN shell script."
            return $false
        }
        Warn "RemoteSigned lets locally created scripts run for your account; downloaded scripts need a trusted signature."
        Write-Host "To enable the profile: Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned"
        if ($forced) {
            # The deployment already answered, in global.conf. Machine-wide
            # policy and AllSigned were ruled out above -- those it still
            # cannot override -- so this only removes the prompt on the path
            # the installer could always handle.
            Info "Setting RemoteSigned for your account (ACORN_POWERSHELL_POLICY)."
        } else {
            if ($env:ACORN_NONINTERACTIVE -or -not $CanPrompt) { return $false }
            $answer = Read-Host "Set RemoteSigned for your account? This affects all your PowerShell scripts [y/N]"
            if ($answer -notmatch '^(?i:y|yes)$') { return $false }
        }
        try {
            Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop
        } catch {
            # Process Bypass can report an override even after the persistent
            # setting was saved. Check the value new terminals will inherit.
            if ((Get-ExecutionPolicy -Scope CurrentUser) -ne "RemoteSigned") { throw }
        }
        if ((Get-ExecutionPolicy -Scope CurrentUser) -ne "RemoteSigned") {
            Warn "The policy change did not take effect. Check Get-ExecutionPolicy -List."
            return $false
        }
        Info "PowerShell profile loading enabled for your account."
        return $true
    } catch {
        Warn "Could not enable PowerShell profile loading: $_"
        Warn "Check Get-ExecutionPolicy -List before opening a new terminal."
        return $false
    }
}

function Add-ACORNHook($ProfilePath) {
    if (-not (Test-Path $ProfilePath)) {
        New-Item -ItemType File -Force -Path $ProfilePath | Out-Null
    }
    # Drop hook lines left by older acorn layouts (e.g. ~\acorn\shell\
    # before it moved under system\) before adding the current one, so a
    # reinstall never leaves a stale line erroring in every new shell.
    $lines = @(Get-Content $ProfilePath -ErrorAction SilentlyContinue)
    $cleaned = @($lines | Where-Object {
        -not ($_.Contains($ACORNHome) -and ($_ -match "acorn\.(ps1|sh)") -and $_ -ne $hookLine)
    })
    if ($cleaned.Count -ne $lines.Count) {
        Set-Content -Path $ProfilePath -Value $cleaned
        Info "Removed stale acorn hook line(s) from $ProfilePath"
    }
    if (-not ($cleaned -contains $hookLine)) {
        Add-Content -Path $ProfilePath -Value "`n# acorn`n$hookLine"
        Info "Added acorn to $ProfilePath"
    }
}

Add-ACORNHook $PROFILE

# Windows PowerShell (5.1, "Desktop" edition) and PowerShell (6+, "Core")
# keep SEPARATE profile files under Documents\WindowsPowerShell\ and
# Documents\PowerShell\ -- $PROFILE only ever points at the one for the
# edition currently running the installer. Hook the OTHER edition's profile
# too, so `acorn` isn't missing just because someone opened the PowerShell
# they didn't install from. Derived by swapping the folder name WITHIN
# $PROFILE's own path (rather than recomputing Documents independently) so
# a test overriding $PROFILE to a throwaway path is naturally respected --
# the swap is simply a no-op if that path doesn't contain either folder
# name, which also means it never touches a REAL profile the test didn't
# ask for. 5.1 always ships on Windows, so its profile is always worth
# hooking; the 7+ profile is only hooked if `pwsh` is actually on PATH --
# writing one for an edition that isn't installed would be clutter, not a
# convenience.
if ($PSVersionTable.PSEdition -eq "Core" -and $PROFILE -match "\\PowerShell\\") {
    $siblingProfile = $PROFILE -replace "\\PowerShell\\", "\WindowsPowerShell\"
    Add-ACORNHook $siblingProfile
} elseif ($PSVersionTable.PSEdition -ne "Core" -and $PROFILE -match "\\WindowsPowerShell\\" `
          -and (Get-Command pwsh -ErrorAction SilentlyContinue)) {
    $siblingProfile = $PROFILE -replace "\\WindowsPowerShell\\", "\PowerShell\"
    Add-ACORNHook $siblingProfile
}

# ACORN_POWERSHELL_POLICY: env var (one run) beats global.conf beats "" --
# the same precedence every other setting here uses.
$PsPolicyPref = if ($env:ACORN_POWERSHELL_POLICY) {
    $env:ACORN_POWERSHELL_POLICY
} elseif ($Conf["ACORN_POWERSHELL_POLICY"]) {
    $Conf["ACORN_POWERSHELL_POLICY"]
} else { "" }
$ProfilePolicyReady = Enable-ACORNProfilePolicy -Preference $PsPolicyPref
Info "acorn is installed."
if (-not $ProfilePolicyReady) {
    Warn "Installation is complete, but the acorn shell command requires the profile policy issue above to be resolved."
}
Write-Host ""
if ($DevReady) {
    Write-Host "Open a new terminal (or run: . `"$seedPs1`") --"
    Write-Host "the 'dev' venv auto-activates there, so you can immediately try:"
    Write-Host "  python / ipython          # the newest Python, ready to go"
    Write-Host "  acorn install <package>    # add packages to 'dev'"
    Write-Host "  acorn venv myproject       # create another venv"
    Write-Host "  acorn summary              # see everything acorn has installed"
} else {
    Write-Host "Open a new terminal (or run: . `"$seedPs1`") and try:"
    Write-Host "  acorn python               # install the newest Python"
    Write-Host "  acorn venv myproject"
    Write-Host "  acorn activate myproject"
    Write-Host "  acorn summary"
}
Write-Host ""
Write-Host "Note: acorn-cli was installed from a private copy at $SrcDir."
Write-Host "Nothing updates it automatically -- run 'acorn update-commands' whenever"
Write-Host "you want to pull in changes."

# Completion marker for `acorn logs-viewer` (it parses the exit code out of
# this exact line), then finalize the install log. Stop-Transcript matters
# most for piped `irm | iex` installs: without it the transcript keeps
# recording the user's session long after the install finished. Guarded:
# transcription may never have started (locked logs dir).
Write-Host "acorn install completed (exit code 0)"
try { Stop-Transcript | Out-Null } catch { }
