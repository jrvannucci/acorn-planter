#!/usr/bin/env sh
# Standalone acorn uninstaller (bash/zsh/sh) -- removes the managed
# folder AND the shell hook line.
#
# The normal way to uninstall is `acorn purge` (more thorough, and it knows
# its own install location). This script is the FALLBACK for when acorn-cli
# itself is broken and can't run. It resolves the install location the same
# way the installer did -- ACORN_HOME env override, else global.conf's
# ACORN_HOME_DIR with "~" and "{user}" expansion -- so relocated and
# shared multi-user installs are targeted correctly, not a hardcoded
# ~/acorn.
set -eu

ACORN_HOME_FROM_ENV="${ACORN_HOME:-}"

# This script lives in installers/; the conf is in GET_STARTED/ alongside it.
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ACORN_HOME_DIR=""
[ -f "$REPO_ROOT/GET_STARTED/global.conf" ] && . "$REPO_ROOT/GET_STARTED/global.conf"

# Home resolution: env override, else conf's ACORN_HOME_DIR (leading "~"
# means $HOME), else the default -- identical to the installer.
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

# {user} -> the current login name: this removes THIS user's install, like
# `acorn purge` (all-users teardown is `acorn admin-purge-all-users`).
case "$ACORN_HOME" in
    *"{user}"*)
        _acorn_user="${USER:-${USERNAME:-$(id -un 2>/dev/null || echo user)}}"
        ACORN_HOME=$(printf '%s' "$ACORN_HOME" | sed "s/{user}/$_acorn_user/g")
        ;;
esac

echo "Uninstalling acorn at: $ACORN_HOME"

# Match any line sourcing a acorn shell script from under the acorn home
# -- not just the exact current hook text -- so hooks written by older
# acorn layouts (e.g. ~/acorn/shell/ before it moved under system/)
# are cleaned up too instead of erroring in every new shell.
for profile in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    [ -f "$profile" ] || continue
    awk -v home="$ACORN_HOME" '
        $0 == "# acorn" { next }
        index($0, home) && (index($0, "acorn.sh") || index($0, "acorn.ps1")) { next }
        { print }
    ' "$profile" > "$profile.tmp"
    if cmp -s "$profile" "$profile.tmp"; then
        rm -f "$profile.tmp"
    else
        mv "$profile.tmp" "$profile"
        echo "Removed acorn hook from $profile"
    fi
done

if [ -d "$ACORN_HOME" ]; then
    rm -rf "$ACORN_HOME"
    echo "Removed $ACORN_HOME"
fi

echo "acorn fully uninstalled. Open a new terminal for it to take effect."
