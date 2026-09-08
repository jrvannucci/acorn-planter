#!/usr/bin/env sh
# acorn installer (bash/zsh/sh) -- mirrors how `uv` installs itself.
# Requires nothing pre-installed except a POSIX shell and curl/wget (both
# already present on essentially every macOS/Linux system).
#
# Usage (from a local checkout of this repo, either works):
#   sh ./install.cmd
#   sh installers/install.sh
#
# Usage (remote):
#   curl -fsSL https://raw.githubusercontent.com/jrvannucci/acorn-planter/main/acorn-planter/installers/install.sh | sh
#   ACORN_REPO=https://github.com/someone/fork.git curl -fsSL .../installers/install.sh | sh

set -eu

# Built-in defaults. global.conf ships with these same values written
# out, so a conf that still matches them changes nothing -- only edited
# values have any effect. The baked-in copies exist for the piped
# one-liner install, where no local global.conf exists yet to consult.
DEFAULT_ACORN_REPO="https://github.com/jrvannucci/acorn-planter.git"
DEFAULT_VENV_PACKAGES="ipython,ruff,ipykernel"

ACORN_REPO_FROM_ENV="${ACORN_REPO:-}"
ACORN_HOME_FROM_ENV="${ACORN_HOME:-}"
ACORN_AUTO_SETUP_FROM_ENV="${ACORN_AUTO_SETUP:-}"
ACORN_AUTO_VSCODE_FROM_ENV="${ACORN_AUTO_VSCODE:-}"
# Captured before global.conf is sourced (which would overwrite it). This
# is what lets a user point the PIPED one-liner at their own profile, where
# there is no local conf to edit:
#   curl -fsSL .../install.sh | ACORN_PROFILE=./team.toml sh
ACORN_PROFILE_FROM_ENV="${ACORN_PROFILE:-}"
# Same reasoning, for custom commands (see docs/CUSTOM-COMMANDS.md).
ACORN_CUSTOM_COMMANDS_FROM_ENV="${ACORN_CUSTOM_COMMANDS:-}"
# Same reasoning, for an org's own VS Code settings/keybindings.
ACORN_VSCODE_CONFIG_DIR_FROM_ENV="${ACORN_VSCODE_CONFIG_DIR:-}"
# The directory the user invoked from, captured before any `cd`, so a
# relative profile path resolves against where they actually are.
ACORN_INVOKED_FROM="$(pwd)"

info()  { printf '\033[1;32m==>\033[0m %s\n' "$1"; }
warn()  { printf '\033[1;33m!!\033[0m %s\n' "$1"; }
die()   { printf '\033[1;31merror:\033[0m %s\n' "$1" >&2; exit 1; }

# The AUTO_* / NATIVE_TLS conf settings are booleans -- "true" / "false"
# (any case). AUTO_* default to true, NATIVE_TLS to false.
is_false() { [ "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" = "false" ]; }
is_true()  { [ "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" = "true" ]; }

# ---------------------------------------------------------------------------
# 1. Locate the acorn source (local checkout next to this script, or clone)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# This script lives in installers/; the repo root (GET_STARTED/, src/) is
# one level up.
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# global.conf is the deployment config: organizations
# distributing acorn from their own git host or a network drive set the
# source (and any install-time settings) there ONCE, and their users install
# with no flags or env vars. Standard internet installs ship a conf whose
# values match the baked-in defaults, so nothing changes for them.
ACORN_REPO_URL=""
ACORN_HOME_DIR=""
ACORN_VENV_DEFAULT_PACKAGES=""
ACORN_AUTO_SETUP=""
ACORN_AUTO_VSCODE=""
ACORN_PYTHON_MIRROR=""
ACORN_PACKAGE_INDEX=""
ACORN_PACKAGE_UPLOAD_URL=""
ACORN_PACKAGE_UPLOAD_TOKEN=""
ACORN_NATIVE_TLS=""
ACORN_CONDA_CHANNEL=""
ACORN_VSCODE_FLAVOR=""
ACORN_EXTENSION_GALLERY=""
ACORN_VSCODE_EXTENSIONS=""
ACORN_VSCODE_CONFIG_DIR=""
ACORN_PROFILE=""
ACORN_CUSTOM_COMMANDS=""
ACORN_STARTUP_COMMANDS=""
CONF_FILE=""
if [ -f "$REPO_ROOT/global.conf" ]; then
    CONF_FILE="$REPO_ROOT/global.conf"
    . "$CONF_FILE"
fi

# Source resolution: ACORN_REPO env var (one-run override) beats
# global.conf, which beats the baked-in default.
if [ -n "$ACORN_REPO_FROM_ENV" ]; then
    ACORN_REPO="$ACORN_REPO_FROM_ENV"
elif [ -n "$ACORN_REPO_URL" ]; then
    ACORN_REPO="$ACORN_REPO_URL"
else
    ACORN_REPO="$DEFAULT_ACORN_REPO"
fi

# Home resolution follows the same order. A leading "~" in the conf value
# means the installing user's home directory.
if [ -n "$ACORN_HOME_FROM_ENV" ]; then
    ACORN_HOME="$ACORN_HOME_FROM_ENV"
elif [ -n "$ACORN_HOME_DIR" ]; then
    case "$ACORN_HOME_DIR" in
        "~")   ACORN_HOME="$HOME" ;;
        "~/"*) ACORN_HOME="$HOME/${ACORN_HOME_DIR#??}" ;;
        *)     ACORN_HOME="$ACORN_HOME_DIR" ;;
    esac
else
    ACORN_HOME="$HOME/acorn"
fi

# {user} -> the installing user's login name, so a shared install root
# (e.g. C:\acorn\{user}) gives every user a private, conflict-free
# folder. git-bash may not set $USER, so fall back through $USERNAME/id.
# When the token is used, record the shared root (the parent of the
# per-user home) so the elevated admin-* commands know this is a
# multi-user deployment.
ACORN_SHARED_ROOT=""
case "$ACORN_HOME" in
    *"{user}"*)
        _acorn_user="${USER:-${USERNAME:-$(id -un 2>/dev/null || echo user)}}"
        ACORN_HOME=$(printf '%s' "$ACORN_HOME" | sed "s/{user}/$_acorn_user/g")
        ACORN_SHARED_ROOT=$(dirname "$ACORN_HOME")
        ;;
esac

# ---------------------------------------------------------------------------
# 1b. Capture this whole install into the acorn logs, so `acorn logs-viewer`
#     shows the bootstrap alongside your `acorn` commands. Everything from here
#     down is tee'd (ANSI-stripped, like the daily logs) into a per-install
#     log and still shown live. Best-effort: a logs dir we can't create just
#     means this install runs without a log.
# ---------------------------------------------------------------------------
ACORN_INSTALL_LOG=""
if mkdir -p "$ACORN_HOME/system/logs" 2>/dev/null; then
    ACORN_INSTALL_LOG="$ACORN_HOME/system/logs/install-$(date +%Y%m%d-%H%M%S).log"
    printf '=== [%s] installer (bootstrap)\n' "$(date '+%Y-%m-%d %H:%M:%S')" > "$ACORN_INSTALL_LOG"
fi
_acorn_rc_file="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/acorn-rc.$$")"
{
trap 'printf %s "$?" > "$_acorn_rc_file" 2>/dev/null' EXIT

INSTALLED_FROM_DIR=""
CLONE_MODE=0
if [ -f "$REPO_ROOT/src/pyproject.toml" ]; then
    ORIGINAL_SRC="$REPO_ROOT"
    CLEANUP_ORIGINAL_SRC=0
elif [ -d "$ACORN_REPO" ] && { [ -f "$ACORN_REPO/src/pyproject.toml" ] || [ -f "$ACORN_REPO/acorn-planter/src/pyproject.toml" ]; }; then
    # ACORN_REPO can be a plain directory instead of a git URL -- e.g. a
    # network drive holding a copy of this repo, on machines/networks with
    # no GitHub access at all.
    info "Installing from directory $ACORN_REPO ..."
    ORIGINAL_SRC="$ACORN_REPO"
    CLEANUP_ORIGINAL_SRC=0
    INSTALLED_FROM_DIR="$ACORN_REPO"
else
    command -v git >/dev/null 2>&1 || die "git is required to clone $ACORN_REPO."
    ORIGINAL_SRC="$(mktemp -d)"
    CLEANUP_ORIGINAL_SRC=1
    CLONE_MODE=1
    info "Cloning $ACORN_REPO ..."
    git clone --depth 1 "$ACORN_REPO" "$ORIGINAL_SRC"
fi

SOURCE_ROOT="$ORIGINAL_SRC"
if [ -f "$ORIGINAL_SRC/acorn-planter/src/pyproject.toml" ]; then
    ORIGINAL_SRC="$ORIGINAL_SRC/acorn-planter"
fi

# ---------------------------------------------------------------------------
# 2. Lay out the folder structure
# ---------------------------------------------------------------------------
info "Setting up $ACORN_HOME"
mkdir -p "$ACORN_HOME/system/bin" \
         "$ACORN_HOME/system/config" \
         "$ACORN_HOME/system/shell" \
         "$ACORN_HOME/python/base" \
         "$ACORN_HOME/python/venvs" \
         "$ACORN_HOME/extensions" \
         "$ACORN_HOME/repo"

# ---------------------------------------------------------------------------
# 2b. Copy the source INTO acorn itself. This is what makes updates
#     explicit: acorn-cli gets installed from $ACORN_HOME/src, a copy that
#     nothing outside of `acorn update-commands` ever touches again. Deleting,
#     moving, or `git pull`-ing wherever you originally downloaded this from
#     has zero effect on the installed commands after this point.
# ---------------------------------------------------------------------------
info "Copying source into $ACORN_HOME/system/src ..."
rm -rf "$ACORN_HOME/system/src"
mkdir -p "$ACORN_HOME/system/src"
# Shared resource collections stay at their configured source, not in each user copy.
for _source_entry in "$ORIGINAL_SRC"/* "$ORIGINAL_SRC"/.[!.]* "$ORIGINAL_SRC"/..?*; do
    [ -e "$_source_entry" ] || continue
    case "$(basename "$_source_entry")" in
        wheels|python-builds|conda-channel|MANIFEST.json|.git|.venv) continue ;;
    esac
    cp -R "$_source_entry" "$ACORN_HOME/system/src/"
done
SRC_DIR="$ACORN_HOME/system/src"
# No git checkout lives inside ~/acorn: updates re-download from the
# recorded update_source (see below) instead of `git pull`-ing, so the
# .git folder would be dead weight (and its read-only object files used
# to break deletion on Windows).
rm -rf "$SRC_DIR/.git"

# The deployment profile travels with the source copy, so `acorn apply` keeps
# working after the share it was installed from goes away. An absolute path
# in the conf is honoured as-is.
PROFILE_PATH=""
if [ -n "$ACORN_PROFILE_FROM_ENV" ]; then
    # User-supplied, for the piped one-liner. Relative paths resolve against
    # the directory they ran the installer from, not the source copy -- they
    # are pointing at THEIR file.
    case "$ACORN_PROFILE_FROM_ENV" in
        /*|?:[\\/]*) PROFILE_SRC="$ACORN_PROFILE_FROM_ENV" ;;
        *)           PROFILE_SRC="$ACORN_INVOKED_FROM/$ACORN_PROFILE_FROM_ENV" ;;
    esac
    # A missing path here is FATAL, unlike the conf case below. Someone who
    # explicitly named a profile and silently got the default environment
    # instead would not find out until something they expected is missing.
    [ -f "$PROFILE_SRC" ] || die "ACORN_PROFILE=$ACORN_PROFILE_FROM_ENV was set, but no file exists at $PROFILE_SRC."
    # Copy it in: the original may be a downloads folder, a mounted share, or
    # a temp file, and `acorn apply` has to keep working long after that goes
    # away -- the same reason the source itself is copied.
    PROFILE_PATH="$ACORN_HOME/system/config/profile.toml"
    cp "$PROFILE_SRC" "$PROFILE_PATH"
    info "Using profile $PROFILE_SRC (copied to $PROFILE_PATH)"
elif [ -n "$ACORN_PROFILE" ]; then
    # Conf-supplied: ships inside the distributed copy, so it already lives
    # under ~/acorn and `acorn update-commands` refreshes it.
    case "$ACORN_PROFILE" in
        /*|?:[\\/]*) PROFILE_PATH="$ACORN_PROFILE" ;;
        *)           PROFILE_PATH="$SRC_DIR/$ACORN_PROFILE" ;;
    esac
    # Either a single file or the FOLDER of profiles, in which case
    # `acorn apply` resolves which of them this user is distributed.
    if [ ! -f "$PROFILE_PATH" ] && [ ! -d "$PROFILE_PATH" ]; then
        # Non-fatal, unlike the env case: a conf naming a profile that wasn't
        # distributed shouldn't brick installs across a whole fleet.
        warn "ACORN_PROFILE=$ACORN_PROFILE was set, but no profile "
        warn "was found at $PROFILE_PATH -- falling back to the default setup."
        PROFILE_PATH=""
        ACORN_PROFILE=""
    fi
fi

# Custom commands (see docs/CUSTOM-COMMANDS.md): one TOML file naming every
# command, including any `script = "..."` files -- wired exactly like the
# profile above: env-var override (copied in, since its origin may not
# survive) beats conf (left in place, since it already lives inside the
# copied source tree -- any sibling script files ride along for free).
# The env-var branch copies the file's WHOLE containing directory, not just
# the file, so a relative `script = "..."` entry's sibling files (and their
# own companion data, like a script's own quotes.txt) survive too -- the
# same thing the conf-distributed form already gets for free from the
# source-tree copy. This assumes the directory holding the TOML file is
# scoped to this deployment (as it should be for anything with script
# files); point ACORN_CUSTOM_COMMANDS at a dedicated folder, not
# somewhere with unrelated large content, if using the env-var override.
CUSTOM_COMMANDS_PATH=""
if [ -n "$ACORN_CUSTOM_COMMANDS_FROM_ENV" ]; then
    case "$ACORN_CUSTOM_COMMANDS_FROM_ENV" in
        /*|?:[\\/]*) CC_SRC="$ACORN_CUSTOM_COMMANDS_FROM_ENV" ;;
        *)           CC_SRC="$ACORN_INVOKED_FROM/$ACORN_CUSTOM_COMMANDS_FROM_ENV" ;;
    esac
    [ -f "$CC_SRC" ] || die "ACORN_CUSTOM_COMMANDS=$ACORN_CUSTOM_COMMANDS_FROM_ENV was set, but no file exists at $CC_SRC."
    CC_SRC_DIR=$(dirname "$CC_SRC")
    CC_BASENAME=$(basename "$CC_SRC")
    CC_DEST_DIR="$ACORN_HOME/system/config/custom-commands"
    rm -rf "$CC_DEST_DIR"
    cp -R "$CC_SRC_DIR" "$CC_DEST_DIR"
    CUSTOM_COMMANDS_PATH="$CC_DEST_DIR/$CC_BASENAME"
    info "Using custom commands $CC_SRC (copied to $CUSTOM_COMMANDS_PATH)"
elif [ -n "$ACORN_CUSTOM_COMMANDS" ]; then
    case "$ACORN_CUSTOM_COMMANDS" in
        /*|?:[\\/]*) CUSTOM_COMMANDS_PATH="$ACORN_CUSTOM_COMMANDS" ;;
        *)           CUSTOM_COMMANDS_PATH="$SRC_DIR/$ACORN_CUSTOM_COMMANDS" ;;
    esac
    if [ ! -f "$CUSTOM_COMMANDS_PATH" ]; then
        warn "ACORN_CUSTOM_COMMANDS=$ACORN_CUSTOM_COMMANDS was set, but no file "
        warn "was found at $CUSTOM_COMMANDS_PATH -- no custom commands."
        CUSTOM_COMMANDS_PATH=""
    fi
fi

# An organization's own settings.json/keybindings.json to acorn into a fresh
# editor (see docs/DEPLOYMENT.md) -- same env-var/conf split as everything
# above. The env var names the directory itself (not a file whose parent is
# inferred), so the whole-directory copy here is exactly what was asked for,
# not a guess at what else might be needed.
VSCODE_CONFIG_DIR_PATH=""
if [ -n "$ACORN_VSCODE_CONFIG_DIR_FROM_ENV" ]; then
    case "$ACORN_VSCODE_CONFIG_DIR_FROM_ENV" in
        /*|?:[\\/]*) VCD_SRC="$ACORN_VSCODE_CONFIG_DIR_FROM_ENV" ;;
        *)           VCD_SRC="$ACORN_INVOKED_FROM/$ACORN_VSCODE_CONFIG_DIR_FROM_ENV" ;;
    esac
    [ -d "$VCD_SRC" ] || die "ACORN_VSCODE_CONFIG_DIR=$ACORN_VSCODE_CONFIG_DIR_FROM_ENV was set, but no folder exists at $VCD_SRC."
    VSCODE_CONFIG_DIR_PATH="$ACORN_HOME/system/config/vscode-config"
    rm -rf "$VSCODE_CONFIG_DIR_PATH"
    cp -R "$VCD_SRC" "$VSCODE_CONFIG_DIR_PATH"
    info "Using VS Code config $VCD_SRC (copied to $VSCODE_CONFIG_DIR_PATH)"
elif [ -n "$ACORN_VSCODE_CONFIG_DIR" ]; then
    case "$ACORN_VSCODE_CONFIG_DIR" in
        /*|?:[\\/]*) VSCODE_CONFIG_DIR_PATH="$ACORN_VSCODE_CONFIG_DIR" ;;
        *)           VSCODE_CONFIG_DIR_PATH="$SRC_DIR/$ACORN_VSCODE_CONFIG_DIR" ;;
    esac
    if [ ! -d "$VSCODE_CONFIG_DIR_PATH" ]; then
        warn "ACORN_VSCODE_CONFIG_DIR=$ACORN_VSCODE_CONFIG_DIR was set, but no "
        warn "folder was found at $VSCODE_CONFIG_DIR_PATH -- no settings/keybindings to acorn."
        VSCODE_CONFIG_DIR_PATH=""
    fi
fi

# ---------------------------------------------------------------------------
# 2b-vendor. Offline binaries shipped inside the install source (see
#     docs/OFFLINE.md): a `vendor/` folder in the distributed copy can hold
#     the uv binary, a portable git, and a pre-seeded VS Code. Whatever is
#     present gets copied into place BEFORE the download steps below --
#     each of which skips itself when its target already exists -- so an
#     offline share needs no wrapper scripts and no extra configuration:
#     presence equals intent. Every payload is a folder whose CONTENTS go
#     to the destination:
#       vendor/uv/     (uv.exe / uv, uvx too if present) -> ~/acorn/system/bin/
#       vendor/git/    (an extracted MinGit)             -> ~/acorn/extensions/git/
#       vendor/vscode/ (a pre-seeded portable VS Code)   -> ~/acorn/extensions/vscode/
#       vendor/certs/  (PEM CA certificates)             -> concatenated into
#                       ~/acorn/system/certs/ca-bundle.pem and trusted for
#                       all HTTPS (uv, git, acorn's own downloads)
# ---------------------------------------------------------------------------
CERT_BUNDLE=""
if [ -d "$SRC_DIR/vendor" ]; then
    if [ -d "$SRC_DIR/vendor/uv" ] && [ ! -e "$ACORN_HOME/system/bin/uv" ] && [ ! -e "$ACORN_HOME/system/bin/uv.exe" ]; then
        cp -R "$SRC_DIR/vendor/uv/." "$ACORN_HOME/system/bin/"
        chmod +x "$ACORN_HOME/system/bin/"uv* 2>/dev/null || true
        info "Using vendored uv from the install source."
    fi
    if [ -d "$SRC_DIR/vendor/micromamba" ] && [ ! -e "$ACORN_HOME/system/bin/micromamba" ] && [ ! -e "$ACORN_HOME/system/bin/micromamba.exe" ]; then
        cp -R "$SRC_DIR/vendor/micromamba/." "$ACORN_HOME/system/bin/"
        chmod +x "$ACORN_HOME/system/bin/"micromamba* 2>/dev/null || true
        info "Using vendored micromamba (conda-forge tools) from the install source."
    fi
    if [ -d "$SRC_DIR/vendor/git" ] && [ ! -d "$ACORN_HOME/extensions/git" ]; then
        mkdir -p "$ACORN_HOME/extensions/git"
        cp -R "$SRC_DIR/vendor/git/." "$ACORN_HOME/extensions/git/"
        info "Using vendored portable git from the install source."
    fi
    if [ -d "$SRC_DIR/vendor/vscode" ] && [ ! -d "$ACORN_HOME/extensions/vscode/app" ]; then
        mkdir -p "$ACORN_HOME/extensions/vscode"
        cp -R "$SRC_DIR/vendor/vscode/." "$ACORN_HOME/extensions/vscode/"
        info "Using vendored VS Code from the install source."
    fi
    if [ -d "$SRC_DIR/vendor/certs" ]; then
        # Unlike the binaries above, the bundle is REBUILT on every install
        # so certificate rotation propagates with a plain reinstall.
        mkdir -p "$ACORN_HOME/system/certs"
        CERT_BUNDLE="$ACORN_HOME/system/certs/ca-bundle.pem"
        : > "$CERT_BUNDLE"
        for _cert in "$SRC_DIR/vendor/certs/"*.pem "$SRC_DIR/vendor/certs/"*.crt; do
            [ -f "$_cert" ] || continue
            cat "$_cert" >> "$CERT_BUNDLE"
            printf '\n' >> "$CERT_BUNDLE"
        done
        if [ -s "$CERT_BUNDLE" ]; then
            info "Installed the vendored CA certificate bundle."
        else
            rm -f "$CERT_BUNDLE"
            CERT_BUNDLE=""
            warn "vendor/certs exists but holds no .pem/.crt files; no CA bundle installed."
        fi
    fi
    # The payloads live on the distribution source, not inside acorn's
    # private source copy -- a pre-seeded VS Code would otherwise bloat
    # system/src by hundreds of MB and get re-copied on every update.
    rm -rf "$SRC_DIR/vendor"
fi

if [ "$CLEANUP_ORIGINAL_SRC" = "1" ]; then
    rm -rf "$SOURCE_ROOT"
fi

# ---------------------------------------------------------------------------
# 2c. Seed acorn's settings from global.conf (first install only --
#     an existing settings.json is never touched, so reinstalls don't
#     clobber choices made later with `acorn config set`).
# ---------------------------------------------------------------------------
# Piped installs have no local conf, but the clone we just copied does.
if [ -z "$CONF_FILE" ] && [ -f "$SRC_DIR/global.conf" ]; then
    . "$SRC_DIR/global.conf"
fi

# Record where this install came from, so `acorn update-commands` knows
# where to fetch newer versions (there's no git checkout inside ~/acorn
# to pull with -- updating re-downloads from this source instead):
#   - directory install  -> that directory
#   - cloned from a URL  -> that URL
#   - local checkout     -> the checkout DIRECTORY itself, so updates re-copy
#                           from that working tree (local edits, or a
#                           `git pull` there, reach the install)
UPDATE_SOURCE_SEED=""
if [ -n "$INSTALLED_FROM_DIR" ]; then
    UPDATE_SOURCE_SEED="$INSTALLED_FROM_DIR"
elif [ "$CLONE_MODE" = "1" ]; then
    UPDATE_SOURCE_SEED="$ACORN_REPO"
else
    # Local checkout. An explicit env var or an org-edited conf states intent
    # and wins; otherwise update straight from the checkout directory this was
    # installed from -- re-copying its working tree -- which is what a
    # developer iterating on the commands wants (consistent with the
    # directory-install case above).
    if [ -n "$ACORN_REPO_FROM_ENV" ]; then
        UPDATE_SOURCE_SEED="$ACORN_REPO"
    elif [ -n "$ACORN_REPO_URL" ] && [ "$ACORN_REPO_URL" != "$DEFAULT_ACORN_REPO" ]; then
        UPDATE_SOURCE_SEED="$ACORN_REPO_URL"
    else
        UPDATE_SOURCE_SEED="$REPO_ROOT"
    fi
fi

SETTINGS_FILE="$ACORN_HOME/system/config/settings.json"
if [ ! -f "$SETTINGS_FILE" ]; then
    json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
    entries=""
    if [ -n "$UPDATE_SOURCE_SEED" ]; then
        entries="  \"update_source\": \"$(json_escape "$UPDATE_SOURCE_SEED")\""
    fi
    # Only seed the package list when it was actually changed -- the conf
    # ships with the built-in default written out for discoverability.
    pkgs_norm=$(printf '%s' "$ACORN_VENV_DEFAULT_PACKAGES" | tr -d ' ')
    if [ -n "$pkgs_norm" ] && [ "$pkgs_norm" != "$DEFAULT_VENV_PACKAGES" ]; then
        pkgs=""
        OLD_IFS=$IFS; IFS=,
        for p in $ACORN_VENV_DEFAULT_PACKAGES; do
            p=$(printf '%s' "$p" | sed -e 's/^ *//' -e 's/ *$//')
            [ -z "$p" ] && continue
            [ -n "$pkgs" ] && pkgs="$pkgs, "
            pkgs="$pkgs\"$(json_escape "$p")\""
        done
        IFS=$OLD_IFS
        if [ -n "$pkgs" ]; then
            [ -n "$entries" ] && entries="$entries,
"
            entries="$entries  \"venv_default_packages\": [$pkgs]"
        fi
    fi
    # Offline sources (see docs/OFFLINE.md): recorded so every future
    # `acorn` command applies them automatically -- users never set
    # environment variables themselves.
    if [ -n "$ACORN_PYTHON_MIRROR" ]; then
        [ -n "$entries" ] && entries="$entries,
"
        entries="$entries  \"python_mirror\": \"$(json_escape "$ACORN_PYTHON_MIRROR")\""
    fi
    if [ -n "$ACORN_PACKAGE_INDEX" ]; then
        [ -n "$entries" ] && entries="$entries,
"
        entries="$entries  \"package_index\": \"$(json_escape "$ACORN_PACKAGE_INDEX")\""
    fi
    if [ -n "$ACORN_PACKAGE_UPLOAD_URL" ]; then
        [ -n "$entries" ] && entries="$entries,
"
        entries="$entries  \"package_upload_url\": \"$(json_escape "$ACORN_PACKAGE_UPLOAD_URL")\""
    fi
    # A WRITE credential. Normally left empty in a distributed conf and set
    # only on the machine that publishes (`acorn config set`); seeding it here
    # would hand every user of this share publish rights to the index.
    if [ -n "$ACORN_PACKAGE_UPLOAD_TOKEN" ]; then
        [ -n "$entries" ] && entries="$entries,
"
        entries="$entries  \"package_upload_token\": \"$(json_escape "$ACORN_PACKAGE_UPLOAD_TOKEN")\""
    fi
    # conda-forge channel for `acorn forge-install`. Only seeded when overridden
    # (an internal mirror / offline path); the built-in default is conda-forge.
    channel_norm=$(printf '%s' "$ACORN_CONDA_CHANNEL" | tr -d ' ')
    if [ -n "$channel_norm" ] && [ "$channel_norm" != "conda-forge" ]; then
        [ -n "$entries" ] && entries="$entries,
"
        entries="$entries  \"conda_channel\": \"$(json_escape "$ACORN_CONDA_CHANNEL")\""
    fi
    if is_true "$ACORN_NATIVE_TLS"; then
        [ -n "$entries" ] && entries="$entries,
"
        entries="$entries  \"native_tls\": true"
    fi
    # Editor flavor/gallery/extensions. Only seeded when actually changed --
    # the conf ships with the built-in defaults written out, same as the
    # package list above.
    flavor_norm=$(printf '%s' "$ACORN_VSCODE_FLAVOR" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
    if [ -n "$flavor_norm" ] && [ "$flavor_norm" != "microsoft" ]; then
        [ -n "$entries" ] && entries="$entries,
"
        entries="$entries  \"vscode_flavor\": \"$(json_escape "$flavor_norm")\""
    fi
    if [ -n "$ACORN_EXTENSION_GALLERY" ]; then
        [ -n "$entries" ] && entries="$entries,
"
        entries="$entries  \"extension_gallery\": \"$(json_escape "$ACORN_EXTENSION_GALLERY")\""
    fi
    # Keyed off the RESOLVED path, not the conf variable: a profile supplied
    # by the ACORN_PROFILE env var (the piped one-liner) leaves the conf
    # variable empty, and would otherwise never be recorded -- so `acorn
    # apply` with no arguments would find nothing afterwards.
    if [ -n "$PROFILE_PATH" ]; then
        [ -n "$entries" ] && entries="$entries,
"
        entries="$entries  \"profile\": \"$(json_escape "$PROFILE_PATH")\""
    fi
    if [ -n "$CUSTOM_COMMANDS_PATH" ]; then
        [ -n "$entries" ] && entries="$entries,
"
        entries="$entries  \"custom_commands\": \"$(json_escape "$CUSTOM_COMMANDS_PATH")\""
    fi
    if [ -n "$VSCODE_CONFIG_DIR_PATH" ]; then
        [ -n "$entries" ] && entries="$entries,
"
        entries="$entries  \"vscode_config_dir\": \"$(json_escape "$VSCODE_CONFIG_DIR_PATH")\""
    fi
    startup_norm=$(printf '%s' "$ACORN_STARTUP_COMMANDS" | tr -d ' ')
    if [ -n "$startup_norm" ]; then
        startups=""
        OLD_IFS=$IFS; IFS=,
        for c in $ACORN_STARTUP_COMMANDS; do
            c=$(printf '%s' "$c" | sed -e 's/^ *//' -e 's/ *$//')
            [ -z "$c" ] && continue
            [ -n "$startups" ] && startups="$startups, "
            startups="$startups\"$(json_escape "$c")\""
        done
        IFS=$OLD_IFS
        if [ -n "$startups" ]; then
            [ -n "$entries" ] && entries="$entries,
"
            entries="$entries  \"startup_commands\": [$startups]"
        fi
    fi
    exts_norm=$(printf '%s' "$ACORN_VSCODE_EXTENSIONS" | tr -d ' ')
    if [ "$exts_norm" = "none" ]; then
        [ -n "$entries" ] && entries="$entries,
"
        entries="$entries  \"vscode_extensions\": []"
    elif [ -n "$exts_norm" ]; then
        exts=""
        OLD_IFS=$IFS; IFS=,
        for e in $ACORN_VSCODE_EXTENSIONS; do
            e=$(printf '%s' "$e" | sed -e 's/^ *//' -e 's/ *$//')
            [ -z "$e" ] && continue
            [ -n "$exts" ] && exts="$exts, "
            exts="$exts\"$(json_escape "$e")\""
        done
        IFS=$OLD_IFS
        if [ -n "$exts" ]; then
            [ -n "$entries" ] && entries="$entries,
"
            entries="$entries  \"vscode_extensions\": [$exts]"
        fi
    fi
    if [ -n "$CERT_BUNDLE" ]; then
        [ -n "$entries" ] && entries="$entries,
"
        entries="$entries  \"ca_cert\": \"$(json_escape "$CERT_BUNDLE")\""
    fi
    if [ -n "$ACORN_SHARED_ROOT" ]; then
        [ -n "$entries" ] && entries="$entries,
"
        entries="$entries  \"shared_root\": \"$(json_escape "$ACORN_SHARED_ROOT")\""
    fi
    if [ -n "$entries" ]; then
        printf '{\n%s\n}\n' "$entries" > "$SETTINGS_FILE"
        info "Seeded acorn settings from global.conf"
    fi
fi

# ---------------------------------------------------------------------------
# 2d. Apply the offline sources to THIS installer's own uv/acorn-cli calls
#     too (building acorn-cli needs the package index; the default
#     environment setup needs both). Pre-set UV_* variables still win.
# ---------------------------------------------------------------------------
to_file_url() {
    _v=$(printf '%s' "$1" | tr '\\' '/')
    case "$_v" in
        *"://"*)     printf '%s' "$_v" ;;
        [A-Za-z]:/*) printf 'file:///%s' "$_v" ;;
        /*)          printf 'file://%s' "$_v" ;;
        *)           printf '%s' "$_v" ;;
    esac
}

# TLS first: the vendored CA bundle / native trust store must cover the
# uv bootstrap and everything after it.
if [ -n "$CERT_BUNDLE" ] && [ -z "${SSL_CERT_FILE:-}" ]; then
    SSL_CERT_FILE="$CERT_BUNDLE"
    GIT_SSL_CAINFO="$CERT_BUNDLE"
    export SSL_CERT_FILE GIT_SSL_CAINFO
fi
if is_true "$ACORN_NATIVE_TLS" && [ -z "${UV_NATIVE_TLS:-}" ]; then
    UV_NATIVE_TLS=1
    export UV_NATIVE_TLS
fi

if [ -n "$ACORN_PYTHON_MIRROR" ] && [ -z "${UV_PYTHON_INSTALL_MIRROR:-}" ]; then
    UV_PYTHON_INSTALL_MIRROR="$(to_file_url "$ACORN_PYTHON_MIRROR")"
    export UV_PYTHON_INSTALL_MIRROR
fi
if [ -n "$ACORN_PACKAGE_INDEX" ]; then
    case "$ACORN_PACKAGE_INDEX" in
        *"://"*)
            if [ -z "${UV_DEFAULT_INDEX:-}" ]; then
                UV_DEFAULT_INDEX="$ACORN_PACKAGE_INDEX"
                export UV_DEFAULT_INDEX
            fi
            ;;
        *)
            # A directory of wheels: uv has no reliable env var for "flat
            # directory index, internet disabled", but honors a config
            # file. acorn-cli generates the same file from settings later.
            if [ -z "${UV_CONFIG_FILE:-}" ]; then
                UV_TOML="$ACORN_HOME/system/config/uv.toml"
                {
                    echo "# Generated by acorn from the \`package_index\` setting. Do not edit;"
                    echo "# change it with:  acorn config set package_index <url-or-directory>"
                    echo "[[index]]"
                    echo "name = \"acorn-offline\""
                    echo "url = \"$(to_file_url "$ACORN_PACKAGE_INDEX")\""
                    echo "format = \"flat\""
                    echo "default = true"
                } > "$UV_TOML"
                UV_CONFIG_FILE="$UV_TOML"
                export UV_CONFIG_FILE
            fi
            ;;
    esac
fi


# ---------------------------------------------------------------------------
# 3. Install uv itself into acorn/bin (uv is the one true dependency, and
#    its own official installer has zero prerequisites, same as this script)
# ---------------------------------------------------------------------------
if [ ! -x "$ACORN_HOME/system/bin/uv" ]; then
    info "Installing uv into $ACORN_HOME/system/bin ..."
    if command -v curl >/dev/null 2>&1; then
        env UV_INSTALL_DIR="$ACORN_HOME/system/bin" UV_NO_MODIFY_PATH=1 \
            sh -c "$(curl -fsSL https://astral.sh/uv/install.sh)"
    elif command -v wget >/dev/null 2>&1; then
        env UV_INSTALL_DIR="$ACORN_HOME/system/bin" UV_NO_MODIFY_PATH=1 \
            sh -c "$(wget -qO- https://astral.sh/uv/install.sh)"
    else
        die "Neither curl nor wget is available; cannot bootstrap uv."
    fi
else
    info "uv already present, skipping."
fi

UV="$ACORN_HOME/system/bin/uv"
[ -x "$UV" ] || die "uv install appears to have failed (not found at $UV)."

# ---------------------------------------------------------------------------
# 4. Install the acorn CLI itself as an isolated uv tool, from the copy
#    living inside ~/acorn/src (not the original download location).
#    `acorn update-commands` is the only thing that ever re-runs this step.
# ---------------------------------------------------------------------------
info "Installing the acorn CLI ..."
env UV_TOOL_DIR="$ACORN_HOME/system/tool" UV_TOOL_BIN_DIR="$ACORN_HOME/system/bin" \
    UV_CACHE_DIR="$ACORN_HOME/system/cache/uv" \
    "$UV" tool install --force --reinstall "$SRC_DIR/src"

[ -x "$ACORN_HOME/system/bin/acorn-cli" ] || die "acorn-cli was not installed correctly."
ACORN_CLI="$ACORN_HOME/system/bin/acorn-cli"

# ---------------------------------------------------------------------------
# 4b. Default environment: the newest stable Python plus a 'dev' venv (with
#     the default packages) that every new shell auto-activates -- so a
#     fresh install is immediately usable with plain `python`/`ipython`.
#     Skip with ACORN_AUTO_SETUP="false" (env var or global.conf). Never
#     fatal: a network hiccup here still leaves a working acorn.
# ---------------------------------------------------------------------------
if [ -n "$ACORN_AUTO_SETUP_FROM_ENV" ]; then
    AUTO_SETUP="$ACORN_AUTO_SETUP_FROM_ENV"
elif [ -n "$ACORN_AUTO_SETUP" ]; then
    AUTO_SETUP="$ACORN_AUTO_SETUP"
else
    AUTO_SETUP="true"
fi

DEV_READY=0
if is_false "$AUTO_SETUP"; then
    info "Skipping default environment setup (ACORN_AUTO_SETUP=$AUTO_SETUP)."
else
        # VS Code setup starts FIRST, in the background: it's independent of
        # the python/venv steps and dominated by a ~300MB download, so it
        # overlaps them instead of adding its whole duration to the install.
        # ACORN_NO_LOG=1 keeps the background run from interleaving with
        # the foreground acorn commands inside the daily log; its output is
        # buffered to a file and replayed below (which also lands it in the
        # install log). Idempotent (skips if already present), never fatal.
        if [ -n "$ACORN_AUTO_VSCODE_FROM_ENV" ]; then
            AUTO_VSCODE="$ACORN_AUTO_VSCODE_FROM_ENV"
        elif [ -n "$ACORN_AUTO_VSCODE" ]; then
            AUTO_VSCODE="$ACORN_AUTO_VSCODE"
        else
            AUTO_VSCODE="true"
        fi
        VSCODE_PID=""
        VSCODE_OUT=""
        VSCODE_RC=""
        # A profile that names an editor OUTRANKS ACORN_AUTO_VSCODE: a
        # deployment that asked for Spyder shouldn't also be handed ~300MB of
        # VS Code it never mentioned. Asked here rather than after `acorn
        # apply` because the VS Code job starts first (it overlaps the Python
        # setup), so the answer is needed before it launches. An empty answer
        # means the profile doesn't say, and the conf setting decides as
        # before. When the profile DOES say "vscode", the job still starts --
        # apply then finds it installed and skips, keeping the parallelism.
        PROFILE_EDITOR=""
        if [ -n "$PROFILE_PATH" ]; then
            PROFILE_EDITOR="$(env ACORN_HOME="$ACORN_HOME" ACORN_NO_LOG=1                 "$ACORN_CLI" apply "$PROFILE_PATH" --print-editor 2>/dev/null || true)"
        fi
        # The profile may name several editors; skip the VS Code job only if
        # it names some and VS Code isn't among them.
        SKIP_VSCODE=0
        if [ -n "$PROFILE_EDITOR" ]; then
            case " $PROFILE_EDITOR " in
                *" vscode "*) SKIP_VSCODE=0 ;;
                *)            SKIP_VSCODE=1 ;;
            esac
        fi
        if [ "$SKIP_VSCODE" = "1" ]; then
            info "Profile selects '$PROFILE_EDITOR' as the editor; skipping VS Code."
        elif is_false "$AUTO_VSCODE"; then
            info "Skipping VS Code install (ACORN_AUTO_VSCODE=$AUTO_VSCODE)."
        else
            info "Setting up VS Code in the background (continues while Python is set up) ..."
            VSCODE_OUT="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/acorn-vscode-out.$$")"
            VSCODE_RC="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/acorn-vscode-rc.$$")"
            ( env ACORN_HOME="$ACORN_HOME" ACORN_NO_LOG=1 \
                  "$ACORN_CLI" vscode --no-open -y >"$VSCODE_OUT" 2>&1
              echo "$?" >"$VSCODE_RC" ) &
            VSCODE_PID=$!
        fi

        if [ -n "$PROFILE_PATH" ]; then
            # A profile is the authoritative definition of this deployment's
            # environment, so it REPLACES the built-in single-'dev'-venv
            # setup rather than layering on top of it -- otherwise every
            # machine would carry a 'dev' venv the admin never asked for.
            info "Applying deployment profile: $PROFILE_PATH"
            if env ACORN_HOME="$ACORN_HOME" "$ACORN_CLI" python &&                env ACORN_HOME="$ACORN_HOME" "$ACORN_CLI" apply "$PROFILE_PATH"; then
                DEV_READY=1
            else
                warn "The deployment profile didn't fully apply."
                warn "Re-run it later with:  acorn apply"
            fi
        elif [ -d "$ACORN_HOME/python/venvs/dev" ]; then
            info "Default 'dev' venv already exists, leaving it as-is."
            DEV_READY=1
        else
            info "Setting up the default environment: newest Python + a 'dev' venv ..."
            if env ACORN_HOME="$ACORN_HOME" "$ACORN_CLI" python && \
               env ACORN_HOME="$ACORN_HOME" "$ACORN_CLI" venv dev; then
                # Make 'dev' the venv new shells auto-activate -- unless the
                # user already chose one (reinstall case).
                if [ -z "$(env ACORN_HOME="$ACORN_HOME" ACORN_NO_LOG=1 "$ACORN_CLI" config get default_venv 2>/dev/null)" ]; then
                    env ACORN_HOME="$ACORN_HOME" "$ACORN_CLI" config set default_venv dev
                fi
                DEV_READY=1
            else
                warn "Default environment setup didn't finish (network problem?)."
                warn "Set it up later with:  acorn python && acorn venv dev && acorn config set default_venv dev"
            fi
        fi

        # Collect the background VS Code setup started above. `|| true`
        # because under `set -e` a non-zero child status from wait would
        # abort the whole install -- VS Code stays non-fatal.
        if [ -n "$VSCODE_PID" ]; then
            info "Waiting for the background VS Code setup to finish ..."
            # Live status bar: acorn-cli mirrors its progress into a one-line
            # status file ("<phase> <done> <total>"); poll it and repaint one
            # line in place. Only repaint on change so the install log
            # doesn't fill with duplicate frames.
            _status_file="$ACORN_HOME/extensions/vscode/setup-status"
            _last_bar=""
            while kill -0 "$VSCODE_PID" 2>/dev/null; do
                _bar="VS Code: setting up ..."
                if [ -f "$_status_file" ]; then
                    _ph=""; _d=0; _t=0
                    read -r _ph _d _t < "$_status_file" 2>/dev/null || _ph=""
                    # Sanitize before arithmetic: $((...)) on a non-number is
                    # a FATAL shell error in dash, even without set -e.
                    case "$_d" in ''|*[!0-9]*) _d=0 ;; esac
                    case "$_t" in ''|*[!0-9]*) _t=0 ;; esac
                    case "$_ph" in
                        downloading)
                            if [ "$_t" -gt 0 ]; then
                                _pct=$(( _d * 100 / _t ))
                                _bar="VS Code: downloading ${_pct}% of $(( _t / 1048576 )) MB"
                            else
                                _bar="VS Code: downloading $(( _d / 1048576 )) MB ..."
                            fi ;;
                        resolving)  _bar="VS Code: finding the latest build ..." ;;
                        extracting) _bar="VS Code: extracting ..." ;;
                        extensions) _bar="VS Code: installing extensions (Python, Jupyter, linting) ..." ;;
                    esac
                fi
                if [ "$_bar" != "$_last_bar" ]; then
                    printf '\r%-70s' "$_bar"
                    _last_bar="$_bar"
                fi
                sleep 1
            done
            # Plain `[ -n ... ] && printf` would return 1 when no bar was
            # ever painted, and set -e would abort the install on that.
            if [ -n "$_last_bar" ]; then printf '\r%-70s\r' " "; fi
            wait "$VSCODE_PID" || true
            cat "$VSCODE_OUT" 2>/dev/null || true
            _vscode_rc="$(cat "$VSCODE_RC" 2>/dev/null || echo 1)"
            rm -f "$VSCODE_OUT" "$VSCODE_RC"
            if [ "$_vscode_rc" != "0" ]; then
                warn "VS Code setup didn't finish (network problem?). Install it later with:  acorn vscode"
            fi
        fi
fi

# ---------------------------------------------------------------------------
# 5. Write the `acorn` shell function and hook it into the user's shell
# ---------------------------------------------------------------------------
info "Writing shell integration ..."
sed "s#__ACORN_HOME_PLACEHOLDER__#$ACORN_HOME#g" \
    "$SRC_DIR/src/acorn/shell/acorn.sh.template" > "$ACORN_HOME/system/shell/acorn.sh"

HOOK_LINE=". \"$ACORN_HOME/system/shell/acorn.sh\""

add_hook() {
    profile="$1"
    [ -f "$profile" ] || touch "$profile"
    # Drop hook lines left by older acorn layouts (e.g. ~/acorn/shell/
    # before it moved under system/) before adding the current one, so a
    # reinstall never leaves a stale line erroring in every new shell.
    awk -v home="$ACORN_HOME" -v keep="$HOOK_LINE" '
        index($0, home) && (index($0, "acorn.sh") || index($0, "acorn.ps1")) && $0 != keep { next }
        { print }
    ' "$profile" > "$profile.tmp"
    if cmp -s "$profile" "$profile.tmp"; then
        rm -f "$profile.tmp"
    else
        mv "$profile.tmp" "$profile"
        info "Removed stale acorn hook line(s) from $profile"
    fi
    if ! grep -qF "$HOOK_LINE" "$profile" 2>/dev/null; then
        {
            echo ""
            echo "# acorn"
            echo "$HOOK_LINE"
        } >> "$profile"
        info "Added acorn to $profile"
    fi
}

case "${SHELL:-}" in
    */zsh)  add_hook "$HOME/.zshrc" ;;
    */bash) add_hook "$HOME/.bashrc" ;;
    *)      add_hook "$HOME/.profile" ;;
esac

info "acorn is installed."
echo
if [ "$DEV_READY" = "1" ]; then
    echo "Open a new terminal (or run: . \"$ACORN_HOME/system/shell/acorn.sh\") --"
    echo "the 'dev' venv auto-activates there, so you can immediately try:"
    echo "  python / ipython          # the newest Python, ready to go"
    echo "  acorn install <package>    # add packages to 'dev'"
    echo "  acorn venv myproject       # create another venv"
    echo "  acorn summary              # see everything acorn has installed"
else
    echo "Open a new terminal (or run: . \"$ACORN_HOME/system/shell/acorn.sh\") and try:"
    echo "  acorn python               # install the newest Python"
    echo "  acorn venv myproject"
    echo "  acorn activate myproject"
    echo "  acorn summary"
fi
echo
echo "Note: acorn-cli was installed from a private copy at $ACORN_HOME/system/src."
echo "Nothing updates it automatically -- run 'acorn update-commands' whenever"
echo "you want to pull in changes."
# sed strips ANSI codes from the combined stream before tee displays and
# records it. Deliberate: the logs stay plain text end to end, so they can
# be shipped to a server, grepped, or displayed anywhere with zero
# escape-code handling (the live install output loses its colors in this
# captured region -- that's the accepted cost).
} 2>&1 | sed "s/$(printf '\033')\[[0-9;]*[A-Za-z]//g" | { if [ -n "$ACORN_INSTALL_LOG" ]; then tee -a "$ACORN_INSTALL_LOG"; else cat; fi; }

# Close the install-capture block opened in step 1b: record the exit code in
# the log (block format, so `acorn logs-viewer` parses it like a `acorn`
# command) and exit with the installer's real status.
_acorn_rc="$(cat "$_acorn_rc_file" 2>/dev/null || echo 0)"
rm -f "$_acorn_rc_file" 2>/dev/null || true
if [ -n "$ACORN_INSTALL_LOG" ]; then
    printf '=== [%s] exit code %s\n' "$(date '+%H:%M:%S')" "$_acorn_rc" >> "$ACORN_INSTALL_LOG"
fi
exit "${_acorn_rc:-0}"
