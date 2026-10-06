#!/usr/bin/env bash
# installer for kiwi-updater itself — follows its own convention:
#   ./install.sh install|update|uninstall [--purge] [--with-system]
#
# Default install is 100% user-level (~/.local) — NO root needed:
#   kiwi + kiwi-gui   -> ~/.local/bin
#   desktop entry     -> ~/.local/share/applications
#   user timer        -> ~/.config/systemd/user   (auto-updates user apps + kiwi)
#
# --with-system additionally sets up the OPTIONAL system scope (root once):
#   root-owned kiwi   -> /usr/local/bin/kiwi   (root never executes a file the
#                        user can write; this copy does the system-scope work)
#   update wrapper    -> /usr/local/libexec + a polkit rule: wheel users' updates
#                        reach the system halves without a password. The USER
#                        timer drives both scopes; there is no root timer.
#   config / repos    -> /etc/kiwi-updater, /var/lib/kiwi-updater
#
# When executed as root (e.g. by kiwi's system update service) only the
# system-level parts are (re)installed.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SRC/install.sh"

ACTION="${1:-install}"
PURGE=0
WITH_SYSTEM=0
CLI_ONLY=0
# How the system scope behaves, recorded in /etc/kiwi-updater/mode:
#   auto    your own timer updates the system halves too, without a password,
#           through the wrapper the polkit rule grants to active wheel sessions
#   manual  root-owned kiwi and lists only — no wrapper, no polkit rule. Every
#           change to the system scope asks for a password, and your timer
#           leaves system halves for your next interactive `kiwi update`.
# Empty means "keep what the machine has" (auto on a fresh install).
SYSTEM_MODE=""
for arg in "${@:2}"; do
    case "$arg" in
        --purge)              PURGE=1 ;;
        --with-system)        WITH_SYSTEM=1 ;;
        --with-system=auto)   WITH_SYSTEM=1; SYSTEM_MODE=auto ;;
        --with-system=manual) WITH_SYSTEM=1; SYSTEM_MODE=manual ;;
        --cli-only)           CLI_ONLY=1 ;;
        *) echo "unknown option: $arg" >&2; exit 1 ;;
    esac
done

# the official catalog, preregistered on every install
DEFAULT_CATALOG="https://github.com/derlocke-ng/kiwi-catalog.git"

# GUI parts are skipped on headless machines (no GTK4 stack), with
# --cli-only / KIWI_GUI=0 as explicit overrides. Not based on $DISPLAY —
# ssh sessions to desktop machines have none.
want_gui() {
    (( CLI_ONLY )) && return 1
    [[ ${KIWI_GUI:-} == 0 ]] && return 1
    [[ -n ${KIWI_GUI:-} ]] && return 0
    [[ -e /usr/lib64/girepository-1.0/Gtk-4.0.typelib ||
       -e /usr/lib/girepository-1.0/Gtk-4.0.typelib ]]
}

USER_BIN="$HOME/.local/bin"
USER_APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
USER_UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
USER_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/kiwi-updater"
USER_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/kiwi-updater"

SYS_BIN="/usr/local/bin"
SYS_UNIT_DIR="/etc/systemd/system"
SYS_CONF="/etc/kiwi-updater"
SYS_DATA="/var/lib/kiwi-updater"

say() { printf ':: %s\n' "$*"; }

as_root() {
    if [[ $EUID -eq 0 ]]; then "$@"
    elif [[ -t 0 ]] && command -v sudo >/dev/null 2>&1; then sudo "$@"
    elif command -v pkexec >/dev/null 2>&1; then pkexec "$@"
    else echo "error: need sudo or pkexec" >&2; exit 1
    fi
}

# -c safe.directory: the bootstrap runs this as root inside the USER's
# checkout. Under sudo git treats a directory owned by SUDO_UID as safe; under
# pkexec — the path `curl … | bash -s -- --with-system` takes on a desktop,
# since stdin is a pipe — there is no SUDO_UID, git refused the repo as
# "dubious ownership", this returned empty, and register_self printed
# "no git origin found". The root clone was never created, so the root-owned
# kiwi had nothing to self-update from: F4 all over again, silently, on every
# desktop bootstrap. Reading one URL out of a config file is not executing it.
origin_url() {
    git -c safe.directory="$SRC" -C "$SRC" remote get-url origin 2>/dev/null || true
}

seed_list() { # file header-comment
    [[ -f $1 ]] || printf '# %s\n' "$2" > "$1"
}

# Same exact-first-field match kiwi uses. `grep -qF` matches a substring, so a
# list already holding .../kiwi-catalog-extra counted as holding
# .../kiwi-catalog and the real entry was never added.
list_has() { # file url
    [[ -r $1 ]] || return 1
    local u want="${2%/}"; want="${want%.git}"
    while read -r u _; do
        [[ -z ${u:-} || $u == \#* ]] && continue
        u="${u%/}"; [[ "${u%.git}" == "$want" ]] && return 0
    done < "$1"
    return 1
}

register_self() { # list-file repos-dir
    local url; url="$(origin_url)"
    if [[ -z $url ]]; then
        say "note: no git origin found — self-update not registered"
        return 0
    fi
    list_has "$1" "$url" || echo "$url" >> "$1"
    local d="$2/kiwi-updater"
    if [[ "$(realpath "$SRC")" != "$(realpath -m "$d")" && ! -d "$d/.git" ]]; then
        git clone --quiet "$url" "$d"
    fi
    [[ -d "$d/.git" ]] && git -C "$d" rev-parse HEAD > "$d/.kiwi-installed"
    say "self-update registered ($url)"
}

system_present() {
    [[ -x "$SYS_BIN/kiwi" || -f "$SYS_UNIT_DIR/kiwi-updater-system.timer" ]]
}

# ---------------------------------------------------------------------------
# The system half, done WITHOUT running this script as root.
#
# This file lives under ~/.local/share. Running it as root is exactly what the
# split layout exists to prevent: anything running as the user could edit it
# and own root on the next update — and with a cached sudo timestamp that
# happens without even a prompt. The root-owned copy at $SYS_BIN/kiwi updates
# itself from the root-owned clone in /var/lib instead.
#
# Bootstrap (--with-system) is the one documented exception: there is no
# root-owned copy yet, so nothing else can create one, and it is password-gated.
# ---------------------------------------------------------------------------
system_update() {
    if [[ -x /usr/local/libexec/kiwi-system-update ]] && command -v pkexec >/dev/null 2>&1; then
        # the fixed-purpose wrapper — passwordless for active wheel sessions
        pkexec /usr/local/libexec/kiwi-system-update kiwi-updater && return 0
    fi
    [[ -x "$SYS_BIN/kiwi" ]] && as_root "$SYS_BIN/kiwi" update --system kiwi-updater && return 0
    say "could not update the root-owned copy of kiwi."
    say "  a copy from 1.2.1 or older cannot update itself; re-run the bootstrap once:"
    say "  curl -fsSL https://raw.githubusercontent.com/derlocke-ng/kiwi-updater/main/get-kiwi.sh | bash -s -- --with-system"
    return 1
}

system_uninstall() {
    if [[ -x "$SYS_BIN/kiwi" ]]; then
        local args=(uninstall --system)
        (( PURGE )) && args+=(--purge)
        as_root "$SYS_BIN/kiwi" "${args[@]}" kiwi-updater
        return
    fi
    # No root-owned kiwi left to ask, so the units and the polkit rule can only
    # be removed by this script. One-shot, explicitly requested, and the
    # recurring-update risk above does not apply.
    say "no root-owned kiwi found — removing the remaining system files directly"
    local root_args=(); (( PURGE )) && root_args+=(--purge)
    as_root bash "$SELF" uninstall ${root_args[@]+"${root_args[@]}"}
}

# ---------------- user phase (default, no root) -------------------------------
user_install() {
    say "installing kiwi to $USER_BIN"
    install -Dm755 "$SRC/bin/kiwi" "$USER_BIN/kiwi"

    if want_gui; then
        say "installing kiwi-gui + desktop entry + icon"
        install -Dm755 "$SRC/gui/kiwi-gui" "$USER_BIN/kiwi-gui"
        mkdir -p "$USER_APPS"
        # file name must match the GTK application id for GNOME Shell association
        sed "s|^Exec=.*|Exec=$USER_BIN/kiwi-gui|" "$SRC/data/kiwi.desktop" \
            > "$USER_APPS/eu.kiwinetwork.KiwiUpdater.desktop"
        rm -f "$USER_APPS/kiwi-gui.desktop"   # pre-1.0 name
        # one scalable icon rather than a pile of bitmaps
        install -Dm644 "$SRC/data/icons/eu.kiwinetwork.KiwiUpdater.svg" \
            "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps/eu.kiwinetwork.KiwiUpdater.svg"
        command -v gtk-update-icon-cache >/dev/null 2>&1 && \
            gtk-update-icon-cache -qtf "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor" 2>/dev/null || true
        command -v update-desktop-database >/dev/null 2>&1 && \
            update-desktop-database -q "$USER_APPS" 2>/dev/null || true
    else
        say "no GTK4 stack (or --cli-only) — skipping GUI"
    fi

    # bash completion is a plain file; no service, nothing to enable
    install -Dm644 "$SRC/data/bash-completion/kiwi" \
        "${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/kiwi"

    mkdir -p "$USER_CONF" "$USER_DATA/repos"
    seed_list "$USER_CONF/apps.list"     "kiwi user apps — one git URL per line; options: branch=<b> ref=<tag>"
    seed_list "$USER_CONF/catalogs.list" "kiwi catalogs — git URLs of catalog repos (shared app lists)"
    list_has "$USER_CONF/catalogs.list" "$DEFAULT_CATALOG" || {
        echo "$DEFAULT_CATALOG" >> "$USER_CONF/catalogs.list"
        say "registered default catalog ($DEFAULT_CATALOG)"
    }
    register_self "$USER_CONF/apps.list" "$USER_DATA/repos"

    # The timer goes LAST. `enable --now` starts it, and with Persistent=true
    # on a machine up longer than OnBootSec it fires at once — so it used to
    # run `kiwi update --all` while this script was still writing the lists
    # it would read. Everything it needs exists by this point.
    say "installing user update service"
    install -Dm644 "$SRC/data/systemd/kiwi-updater.service" "$USER_UNIT_DIR/kiwi-updater.service"
    install -Dm644 "$SRC/data/systemd/kiwi-updater.timer"   "$USER_UNIT_DIR/kiwi-updater.timer"
    # The timer is optional, and this script runs under set -e. `systemctl
    # --user` fails over ssh without lingering, in containers and under `su -`,
    # and that used to abort the install part way through.
    if ! { systemctl --user daemon-reload &&
           systemctl --user enable --now kiwi-updater.timer; } 2>/dev/null; then
        say "no systemd user session here — background updates are NOT enabled"
        say "  enable them later with: systemctl --user enable --now kiwi-updater.timer"
    fi

    say "done — try: kiwi list  |  kiwi add <git-url>  |  kiwi-gui"
    # Report what is actually on the machine, not which flag this run was given.
    # `kiwi update kiwi-updater` re-runs this installer without --with-system,
    # so testing the flag announced "not set up" on every single update — even
    # on a machine where the system scope had been installed as root.
    if (( ! WITH_SYSTEM )) && ! system_present; then
        say "system scope not set up: apps with a root half (kiwi-killswitch) cannot install"
        say "  that half until it is. Add it any time:  get-kiwi.sh --with-system"
        say "  (or --with-system=manual: no passwordless updates; every system change asks for a password)"
    fi
}

user_update() { user_install; }

user_uninstall() {
    say "removing user service, binaries, desktop entry"
    systemctl --user disable --now kiwi-updater.timer 2>/dev/null || true
    rm -f "$USER_UNIT_DIR/kiwi-updater.service" "$USER_UNIT_DIR/kiwi-updater.timer"
    systemctl --user daemon-reload
    rm -f "$USER_BIN/kiwi" "$USER_BIN/kiwi-gui" \
          "${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/kiwi" \
          "$USER_APPS/eu.kiwinetwork.KiwiUpdater.desktop" "$USER_APPS/kiwi-gui.desktop" \
          "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps/eu.kiwinetwork.KiwiUpdater.png" \
          "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps/eu.kiwinetwork.KiwiUpdater.svg"
    if (( PURGE )); then
        say "purging $USER_CONF and $USER_DATA"
        rm -rf "$USER_CONF" "$USER_DATA"
    else
        say "kept: $USER_CONF and $USER_DATA — use 'install.sh uninstall --purge' to remove"
    fi
}

# ---------------- system phase (opt-in, runs as root) --------------------------
root_install() {
    local mode="${SYSTEM_MODE:-$(cat "$SYS_CONF/mode" 2>/dev/null || echo auto)}"
    say "installing root-owned kiwi to $SYS_BIN ($mode mode)"
    install -Dm755 "$SRC/bin/kiwi" "$SYS_BIN/kiwi"
    # /usr is immutable on ostree; /usr/local is the writable one
    install -Dm644 "$SRC/data/bash-completion/kiwi" \
        /usr/local/share/bash-completion/completions/kiwi

    mkdir -p "$SYS_CONF" "$SYS_DATA/repos"
    chmod 755 "$SYS_DATA" "$SYS_DATA/repos"
    printf '%s\n' "$mode" > "$SYS_CONF/mode"; chmod 644 "$SYS_CONF/mode"
    seed_list "$SYS_CONF/apps.list"     "kiwi system apps — installed as root; options: branch=<b> ref=<tag>"
    seed_list "$SYS_CONF/catalogs.list" "kiwi system catalogs — git URLs of catalog repos"
    list_has "$SYS_CONF/catalogs.list" "$DEFAULT_CATALOG" || echo "$DEFAULT_CATALOG" >> "$SYS_CONF/catalogs.list"
    register_self "$SYS_CONF/apps.list" "$SYS_DATA/repos"

    # kiwi <= 1.8 ran a root timer. System halves are updated from the USER
    # timer through the wrapper now, so remove it wherever it is still around.
    systemctl disable --now kiwi-updater-system.timer 2>/dev/null || true
    rm -f "$SYS_UNIT_DIR/kiwi-updater-system.service" "$SYS_UNIT_DIR/kiwi-updater-system.timer"
    systemctl daemon-reload 2>/dev/null || true

    if [[ $mode == manual ]]; then
        # Nothing of kiwi's runs as root unless an admin types a password: no
        # wrapper, no polkit rule. Remove them if a previous auto install left
        # them, so switching modes is one command.
        rm -f /usr/local/libexec/kiwi-system-update /etc/polkit-1/rules.d/50-kiwi-updater.rules
        systemctl reload polkit 2>/dev/null || true
        say "manual mode: every system change asks for a password; the timer leaves system halves for your next 'kiwi update'"
        return 0
    fi

    # The fixed-purpose wrapper plus the polkit rule that lets active and
    # background wheel sessions run it without a password. That is the whole
    # auto-update path for system halves. (/etc/polkit-1/rules.d is writable
    # on ostree systems.)
    install -Dm755 "$SRC/data/kiwi-system-update" /usr/local/libexec/kiwi-system-update
    install -Dm644 "$SRC/data/polkit/50-kiwi-updater.rules" \
        /etc/polkit-1/rules.d/50-kiwi-updater.rules
    systemctl reload polkit 2>/dev/null || systemctl restart polkit 2>/dev/null || true
    say "system halves update from your own timer, without a password"
}

root_update() { root_install; }

root_uninstall() {
    say "removing system service and root-owned kiwi"
    systemctl disable --now kiwi-updater-system.timer 2>/dev/null || true
    rm -f "$SYS_UNIT_DIR/kiwi-updater-system.service" "$SYS_UNIT_DIR/kiwi-updater-system.timer" \
          /etc/polkit-1/rules.d/50-kiwi-updater.rules
    systemctl daemon-reload
    rm -f "$SYS_BIN/kiwi" /usr/local/libexec/kiwi-system-update \
          /usr/local/share/bash-completion/completions/kiwi

    if (( PURGE )); then
        local other=() d
        for d in "$SYS_DATA"/repos/*/; do
            [[ -f "$d/.kiwi-installed" && "$(basename "$d")" != "kiwi-updater" ]] && other+=("$(basename "$d")")
        done
        if [[ ${#other[@]} -gt 0 ]]; then
            say "WARNING: these system apps stay installed but lose their updater: ${other[*]}"
            say "         (uninstall them first with 'kiwi uninstall <name>' if you want them gone)"
        fi
        say "purging $SYS_CONF and $SYS_DATA"
        rm -rf "$SYS_CONF" "$SYS_DATA"
    else
        say "kept: $SYS_CONF and $SYS_DATA — use 'install.sh uninstall --purge' to remove"
    fi
}

# ---------------- dispatch ------------------------------------------------------
case "$ACTION" in install|update|uninstall) ;; *)
    echo "usage: $0 install|update|uninstall [--purge] [--with-system[=auto|manual]] [--cli-only]" >&2; exit 1 ;;
esac

if [[ $EUID -eq 0 ]]; then
    # invoked as root (the system service, or the bootstrap below)
    "root_$ACTION"
elif (( WITH_SYSTEM )) && [[ $ACTION == install ]]; then
    user_install
    # Bootstrap: the ONLY path that runs this script as root, because no
    # root-owned copy exists yet that could do it instead. Password-gated, and
    # documented as the exception in the README.
    say "setting up the system scope (root)"
    as_root bash "$SELF" install ${SYSTEM_MODE:+--with-system=$SYSTEM_MODE}
else
    "user_$ACTION"
    # Update and uninstall of the system half go through the root-owned copy —
    # never this file. Only when a person runs this script directly, though:
    # under kiwi (KIWI_SCOPE is set) kiwi-updater is a dual-scope app like any
    # other and kiwi handles its system half itself. Doing it here as well ran
    # the root update twice for every `kiwi update kiwi-updater` typed in a
    # terminal — and in manual mode asked for the password twice.
    if [[ -z ${KIWI_SCOPE:-} && $ACTION != install ]] &&
       { (( WITH_SYSTEM )) || { [[ -t 0 ]] && system_present; }; }; then
        say "handling the system scope (root)"
        "system_$ACTION" || true
    fi
fi
