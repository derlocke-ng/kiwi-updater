#!/usr/bin/env bash
# install.sh — template installer for kiwi-managed tools
#
# kiwi runs this from the repo root as:  ./install.sh install|update|uninstall
# with these environment variables set:
#   KIWI_SCOPE    user | system   — ONCE PER SCOPE your manifest declares
#   KIWI_PREFIX   ~/.local (user)  or  /usr/local (system)
#   KIWI_APP_DIR  absolute path of this repo's clone
#   KIWI_ACTION   same as $1
#   KIWI_GUI      0 on a headless machine or with --cli-only
#
# If your manifest says SCOPES=user system, this script is invoked TWICE — once
# with KIWI_SCOPE=user (as the user) and once with KIWI_SCOPE=system (as root).
# Branch on it and do only that half each time; see the kiwi-killswitch
# installer for a worked example.
#
# For SCOPE=system apps this script already runs as root — no sudo needed.
set -euo pipefail

# fallbacks so the script also works standalone (without kiwi)
KIWI_SCOPE="${KIWI_SCOPE:-user}"
if [[ $KIWI_SCOPE == system ]]; then
    KIWI_PREFIX="${KIWI_PREFIX:-/usr/local}"
else
    KIWI_PREFIX="${KIWI_PREFIX:-$HOME/.local}"
fi
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APP=my-tool   # keep in sync with NAME in kiwi.manifest

do_install() {
    # --- CLI tool example -------------------------------------------------
    install -Dm755 "$SRC/bin/$APP" "$KIWI_PREFIX/bin/$APP"

    # --- GTK GUI example (uncomment) ---------------------------------------
    # kiwi exports KIWI_GUI=0 on headless machines — skip GUI parts then:
    # if [[ "${KIWI_GUI:-1}" == 1 ]]; then
    #     install -Dm755 "$SRC/gui/$APP-gui" "$KIWI_PREFIX/bin/$APP-gui"
    #     install -Dm644 "$SRC/data/$APP.desktop" "$KIWI_PREFIX/share/applications/$APP.desktop"
    # fi

    # --- GNOME extension example (SCOPE=user, TYPE=gnome-extension) --------
    # UUID="my-ext@kiwi-network"
    # EXT_DIR="$HOME/.local/share/gnome-shell/extensions/$UUID"
    # mkdir -p "$EXT_DIR" && cp -r "$SRC/src/." "$EXT_DIR/"
    # gnome-extensions enable "$UUID" || true   # takes effect after re-login

    # --- system config / services example (SCOPE=system) --------------------
    # install -Dm600 "$SRC/conf/wg0.conf" /etc/wireguard/wg0.conf
    # install -Dm644 "$SRC/systemd/$APP.service" /etc/systemd/system/$APP.service
    # systemctl daemon-reload && systemctl enable --now "$APP.service"
    :
}

do_update() {
    # most tools can simply reinstall; add migrations here if needed
    do_install
}

do_uninstall() {
    rm -f "$KIWI_PREFIX/bin/$APP"
    # rm -f "$KIWI_PREFIX/bin/$APP-gui" "$KIWI_PREFIX/share/applications/$APP.desktop"
    # gnome-extensions disable "$UUID" || true; rm -rf "$EXT_DIR"
    # systemctl disable --now "$APP.service" || true; rm -f /etc/systemd/system/$APP.service
    :
}

case "${1:-install}" in
    install)   do_install ;;
    update)    do_update ;;
    uninstall) do_uninstall ;;
    *) echo "usage: $0 install|update|uninstall" >&2; exit 1 ;;
esac
