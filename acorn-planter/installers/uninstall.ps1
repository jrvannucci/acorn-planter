# Standalone acorn uninstaller (PowerShell) -- removes the managed folder
# AND the $PROFILE hook line.
#
# The normal way to uninstall is `acorn purge` (more thorough, and it knows
# its own install location). This script is the FALLBACK for when acorn-cli
# itself is broken and can't run. It resolves the install location the same
# way the installer did -- ACORN_HOME env override, else global.conf's
# ACORN_HOME_DIR with "~" and "{user}" expansion -- so relocated and
# shared multi-user installs are targeted correctly, not a hardcoded
# ~\acorn.
$ErrorActionPreference = "Stop"

# This script lives in installers\; the conf is in GET_STARTED\ alongside it.
# $MyInvocation.MyCommand.Path is $null when this is run via `irm ... | iex`
# (no backing file), so guard against that before Split-Path -- and fall
# back to ACORN_HOME / the default location when there's no local conf.
$ScriptPath = $MyInvocation.MyCommand.Path
$ScriptDir = if ($ScriptPath) { Split-Path -Parent $ScriptPath } else { $null }
$RepoRoot = if ($ScriptDir) { Split-Path -Parent $ScriptDir } else { $null }
$Conf = @{}
if ($RepoRoot) {
    $confPath = Join-Path $RepoRoot "global.conf"
    if (Test-Path $confPath) {
        foreach ($line in Get-Content $confPath) {
            if ($line -match '^\s*([A-Z_]+)\s*=\s*"([^"]*)"\s*$') { $Conf[$Matches[1]] = $Matches[2] }
        }
    }
}

# Home resolution -- identical to the installer.
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
# {user} -> current login name: removes THIS user's install, like `acorn purge`.
if ($ACORNHome -like "*{user}*") {
    $ACORNHome = $ACORNHome -replace [regex]::Escape("{user}"), $env:USERNAME
}

Write-Host "Uninstalling acorn at: $ACORNHome"

if (Test-Path $PROFILE) {
    # Match any line sourcing a acorn shell script from under the acorn
    # home -- not just the exact current hook text -- so hooks written by
    # older acorn layouts (e.g. ~\acorn\shell\ before it moved under
    # system\) are cleaned up too instead of erroring in every new shell.
    $lines = Get-Content $PROFILE | Where-Object {
        -not ($_.Contains($ACORNHome) -and ($_ -match "acorn\.(ps1|sh)")) -and $_.Trim() -ne "# acorn"
    }
    Set-Content -Path $PROFILE -Value $lines
    Write-Host "Removed acorn hook from $PROFILE"
}

if (Test-Path $ACORNHome) {
    Remove-Item -Recurse -Force $ACORNHome
    Write-Host "Removed $ACORNHome"
}

Write-Host "acorn fully uninstalled. Open a new terminal for it to take effect."
