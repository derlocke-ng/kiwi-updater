#!/usr/bin/env bash
# kiwi-updater bootstrap — install with one line:
#
#   curl -fsSL https://raw.githubusercontent.com/derlocke-ng/kiwi-updater/main/get-kiwi.sh | bash
#
# with the optional system scope (root via pkexec):
#
#   curl -fsSL https://raw.githubusercontent.com/derlocke-ng/kiwi-updater/main/get-kiwi.sh | bash -s -- --with-system
#
# Clones straight into kiwi's own repo cache (so self-update just works),
# checks out the latest release tag, and runs the normal installer.
set -euo pipefail

REPO="${KIWI_REPO:-https://github.com/derlocke-ng/kiwi-updater.git}"
DIR="${XDG_DATA_HOME:-$HOME/.local/share}/kiwi-updater/repos/kiwi-updater"

command -v git >/dev/null 2>&1 || { echo "error: git is required (in the base image on Silverblue/Bluefin)" >&2; exit 1; }

if [[ -d "$DIR/.git" ]]; then
    echo ":: refreshing existing clone in $DIR"
    git -C "$DIR" fetch --quiet --tags origin
    git -C "$DIR" reset --hard --quiet origin/HEAD
else
    echo ":: cloning $REPO"
    mkdir -p "$(dirname "$DIR")"
    git clone --quiet "$REPO" "$DIR"
fi

# same release rule kiwi itself uses: latest version tag, HEAD if untagged
tag="$(git -C "$DIR" tag --sort=version:refname | tail -1)"
if [[ -n $tag ]]; then
    echo ":: checking out release $tag"
    git -C "$DIR" -c advice.detachedHead=false checkout --quiet --force "$tag"
fi

exec bash "$DIR/install.sh" install "$@"
