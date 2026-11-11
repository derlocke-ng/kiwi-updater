#!/usr/bin/env bash
# tests/smoke.sh — a real install on whatever distro this container is,
# over the network (PORTPLAN T2). repro.sh stubs the network, systemctl and
# pkexec and checks behaviour in detail; this one checks that the plain path a
# new user takes works here at all:
#
#   1. install.sh as a user (CLI)               -> ~/.local/bin/kiwi
#   2. the first `kiwi list`                    -> the real default catalog's apps (K7)
#   3. the root bootstrap, from a root-owned tagged copy of THIS tree
#      (named in /etc/kiwi-updater/self-url, as M5 requires)  -> /usr/local/bin/kiwi
#   4. `kiwi doctor` as root                    -> exits 0
#   5. `kiwi install syncman` as the user       -> installed (a real app, real installer)
#
# DESTRUCTIVE in the same way as repro.sh (creates a user, writes /etc and
# /usr/local). Container only, needs network:
#
#   podman run --rm -v "$PWD":/src:ro,z debian:13 bash -c \
#     'apt-get update -qq && apt-get install -y -qq git ca-certificates >/dev/null && bash /src/tests/smoke.sh'
set -uo pipefail

if [[ ! -f /run/.containerenv && ! -f /.dockerenv && ${KIWI_REPRO_FORCE:-0} != 1 ]]; then
    echo "refusing to run outside a container (set KIWI_REPRO_FORCE=1 if this box is disposable)" >&2
    exit 2
fi
[[ $EUID -eq 0 ]] || { echo "must run as root (inside the container)" >&2; exit 2; }

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
U=kiwismoke; UH=/home/$U
FAILS=0
ok()   { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; [[ -n ${2:-} ]] && printf '%s\n' "$2" | sed 's/^/     /'; FAILS=$((FAILS+1)); }

id $U >/dev/null 2>&1 || useradd -m -s /bin/bash $U 2>/dev/null || adduser -D -s /bin/bash $U
asu() { # command, as the user, with a login-like minimal environment
    if command -v runuser >/dev/null 2>&1; then
        runuser -u $U -- env -i HOME=$UH USER=$U PATH="$UH/.local/bin:/usr/local/bin:/usr/bin:/bin" bash -c "$1"
    else
        su $U -s /bin/bash -c "env -i HOME=$UH USER=$U PATH=$UH/.local/bin:/usr/local/bin:/usr/bin:/bin bash -c '$1'"
    fi
}
git config --system user.email smoke@example.com 2>/dev/null || true
git config --system user.name smoke 2>/dev/null || true

# 1
cp -r "$SRC" $UH/kiwi-src && chown -R $U $UH/kiwi-src
out="$(asu 'cd ~ && bash kiwi-src/install.sh install --cli-only' 2>&1)"
if [[ -x $UH/.local/bin/kiwi ]]; then ok "user install"; else fail "user install" "$out"; fi

# 2
out="$(asu 'kiwi list --porcelain' 2>&1)"
n="$(grep -c $'\t' <<<"$out" || true)"
if (( n >= 5 )); then ok "first kiwi list shows the catalog ($n apps)"; else fail "first kiwi list shows the catalog ($n apps)" "$out"; fi

# 3: a root-owned, release-tagged copy of this tree, so the bootstrap installs
# what is being tested rather than the published release
v="$(sed -n 's/^VERSION=//p' "$SRC/kiwi.manifest" | head -1)"
w=/srv/kiwi-smoke-work; r=/srv/kiwi-smoke/kiwi-updater.git
rm -rf $w /srv/kiwi-smoke; mkdir -p $w /srv/kiwi-smoke; cp -r "$SRC"/. $w/; rm -rf $w/.git
( cd $w && git init -q && git add -A && git commit -qm smoke && git tag -a "v$v" -m "v$v" ) >/dev/null
git clone -q --bare $w $r; chown -R root:root /srv/kiwi-smoke; chmod -R go-w /srv/kiwi-smoke; chmod 755 /srv/kiwi-smoke
mkdir -p /etc/kiwi-updater; echo $r > /etc/kiwi-updater/self-url
out="$(bash "$SRC/install.sh" install --with-system 2>&1)"
if [[ -x /usr/local/bin/kiwi ]] && grep -q "KIWI_VERSION=$v" /usr/local/bin/kiwi; then
    ok "root bootstrap ($(grep -o '([a-z]* mode)' <<<"$out" | head -1))"
else
    fail "root bootstrap" "$out"
fi

# 4
out="$(/usr/local/bin/kiwi doctor 2>&1)"; rc=$?
if (( rc == 0 )); then ok "kiwi doctor as root"; else fail "kiwi doctor as root (rc=$rc)" "$(grep -v '^\s*ok' <<<"$out")"; fi

# 5
out="$(asu 'kiwi install syncman' 2>&1)"
if [[ -f $UH/.local/share/kiwi-updater/repos/syncman/.kiwi-installed ]]; then ok "kiwi install syncman"
else fail "kiwi install syncman" "$out"; fi

echo
if (( FAILS )); then echo "$FAILS smoke step(s) failed"; exit 1; fi
echo "smoke test passes"
