#!/usr/bin/env bash
# tests/repro.sh — reproduces the findings in FIXPLAN.md against the working tree.
#
# Every check asserts BEHAVIOUR, not message text, so it prints
#     BUG  <id>   while the problem is still there
#     ok   <id>   once it is fixed
# and exits non-zero while any BUG is left.
#
# DESTRUCTIVE: it needs root, creates a user called "kiwitest", and wipes
# /etc/kiwi-updater, /var/lib/kiwi-updater and /usr/local/bin/kiwi.
# Run it in a throwaway container, never on your real machine:
#
#   podman run --rm -v "$PWD":/src:ro,Z fedora:latest bash -c \
#     'dnf -y -q install git-core gawk util-linux shadow-utils procps-ng python3 >/dev/null && bash /src/tests/repro.sh'
#
# gawk matters: fedora:latest ships no awk, and without it remote_target fails
# on every app, so checks "pass" because nothing can be reached at all.
#
#   bash tests/repro.sh F1 F6      # run only some checks (F9 runs as part of F8)
set -uo pipefail

if [[ ! -f /run/.containerenv && ! -f /.dockerenv && ${KIWI_REPRO_FORCE:-0} != 1 ]]; then
    echo "refusing to run outside a container (set KIWI_REPRO_FORCE=1 if this box is disposable)" >&2
    exit 2
fi
[[ $EUID -eq 0 ]] || { echo "must run as root (inside the container)" >&2; exit 2; }
for c in git awk sed grep flock timeout runuser useradd pkill; do
    command -v "$c" >/dev/null || { echo "missing: $c (the suite would report false passes without it)" >&2; exit 2; }
done

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f $SRC/bin/kiwi ]] || SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f $SRC/bin/kiwi ]] || { echo "cannot find bin/kiwi next to this script" >&2; exit 2; }

T=kiwitest; TH=/home/$T
W=/opt/kiwi-under-test; STUBS=/opt/kiwi-stubs; GITROOT=/srv/kiwi-git; ESC=/tmp/kt-escalations.log
K=$W/bin/kiwi

id $T >/dev/null 2>&1 || useradd -m -s /bin/bash $T
git config --system safe.directory '*'
git config --system user.email t@example.com
git config --system user.name tester
git config --system init.defaultBranch main
rm -rf $W && mkdir -p $W $STUBS && cp -r "$SRC"/. $W/ && rm -rf $W/.git && chmod -R a+rX $W

stub_systemctl() { printf '#!/bin/sh\nexit %s\n' "${1:-0}" > $STUBS/systemctl; chmod +x $STUBS/systemctl; }
stub_systemctl 0
# pkexec/sudo stub: records what would have been run as root, runs nothing
printf '#!/bin/sh\necho "$*" >> %s\nexit 126\n' "$ESC" > $STUBS/pkexec
cp $STUBS/pkexec $STUBS/sudo; chmod +x $STUBS/pkexec $STUBS/sudo

ku() { runuser -u $T -- env -i HOME=$TH USER=$T PATH=$STUBS:/usr/bin:/bin KIWI_LOCK_WAIT=3 ${KENV:-} bash $K "$@" </dev/null; }
kr() { env -i HOME=/root USER=root PATH=$STUBS:/usr/sbin:/usr/bin:/bin KIWI_LOCK_WAIT=3 ${KENV:-} bash $K "$@" </dev/null; }
urepo() { echo "$TH/.local/share/kiwi-updater/repos/$1"; }

reset() {
    pkill -u $T sleep 2>/dev/null
    rm -rf $TH/.config/kiwi-updater $TH/.config/systemd $TH/.local /etc/kiwi-updater /var/lib/kiwi-updater \
           /root/.config/kiwi-updater /usr/local/bin/kiwi /usr/local/libexec/kiwi-system-update \
           $GITROOT /tmp/kt-*
    mkdir -p $GITROOT; chown $T $GITROOT; : > $ESC; chmod 666 $ESC
}

# mkapp owner name "SCOPES" [installer-body] [tag]
mkapp() {
    local o=$1 n=$2 sc=$3 body=${4:-'echo "installer: $* scope=$KIWI_SCOPE"'} tag=${5:-v1.0.0}
    local w=/tmp/kt-work-$o-$n; rm -rf "$w"; mkdir -p "$w" $GITROOT/"$o"
    ( cd "$w" && git init -q &&
      printf 'NAME=%s\nDESCRIPTION=desc of %s\nVERSION=%s\nCOMPONENTS=cli gui\nSCOPES=%s\n' "$n" "$n" "${tag#v}" "$sc" > kiwi.manifest &&
      printf '#!/usr/bin/env bash\nset -euo pipefail\n%s\n' "$body" > install.sh &&
      git add -A && git commit -qm init && git tag -a "$tag" -m "$tag" &&
      git clone -q --bare . $GITROOT/"$o"/"$n".git && git remote add origin $GITROOT/"$o"/"$n".git )
    chown -R $T $GITROOT/"$o" "$w"
}
release() { # owner name tag
    ( cd /tmp/kt-work-"$1"-"$2" && sed -i "s/^VERSION=.*/VERSION=${3#v}/" kiwi.manifest &&
      git commit -qam "release $3" && git tag -a "$3" -m "$3" && git push -q origin HEAD --tags )
}
mkcat() { # owner name url...
    local o=$1 n=$2; shift 2; local w=/tmp/kt-cat-$o-$n; rm -rf "$w"; mkdir -p "$w" $GITROOT/"$o"
    ( cd "$w" && git init -q && printf '%s\n' "$@" > apps.list &&
      printf 'NAME=%s\nDESCRIPTION=test catalog\n' "$n" > catalog.manifest &&
      git add -A && git commit -qm cat && git clone -q --bare . $GITROOT/"$o"/"$n".git )
    chown -R $T $GITROOT/"$o"
}

BUGS=0
bug() { printf 'BUG  %-4s %s\n' "$1" "$2"; BUGS=$((BUGS+1)); }
ok()  { printf 'ok   %-4s %s\n' "$1" "$2"; }
check() { # id description condition-that-means-FIXED...
    local id=$1 d=$2; shift 2
    if "$@"; then ok "$id" "$d"; else bug "$id" "$d"; fi
}
want() { [[ $# -eq 0 ]] && return 0; local x; for x in "$@"; do [[ $x == "$CUR" ]] && return 0; done; return 1; }
ONLY=("$@")
run() { CUR=$1; want ${ONLY[@]+"${ONLY[@]}"} || return 0; reset; "t_$1" 2>/tmp/kt-stderr.log; }

# ---------------------------------------------------------------------------
t_F1() { # a failing installer must not be recorded as installed
    mkapp a bad user 'echo about-to-fail; false'
    ku add $GITROOT/a/bad.git >/dev/null
    ku install bad >/dev/null; local rc=$?
    f() { [[ $rc -ne 0 && ! -f $(urepo bad)/.kiwi-installed ]]; }
    check F1 "failed installer -> non-zero exit and no installed marker" f
}

t_F2() { # a failing uninstaller must not throw away the clone
    mkapp a app2 user 'if [[ $1 == uninstall ]]; then exit 1; fi; mkdir -p "$KIWI_PREFIX/bin"; touch "$KIWI_PREFIX/bin/app2"'
    ku add $GITROOT/a/app2.git >/dev/null; ku install app2 >/dev/null
    ku uninstall app2 >/dev/null; local rc=$?
    f() { [[ $rc -ne 0 && -d $(urepo app2) ]]; }
    check F2 "failed uninstaller -> non-zero exit and the clone is kept" f
}

t_F3() { # install.sh must only forward --purge when it was given
    runuser -u $T -- env -i HOME=$TH PATH=$STUBS:/usr/bin:/bin bash $W/install.sh uninstall --with-system </dev/null >/dev/null 2>&1
    f() { ! grep -q -- '--purge' $ESC; }
    check F3 "install.sh uninstall --with-system does not purge the system scope" f
}

t_F4() { # the root-owned kiwi must be able to update itself from the timer
    local w=/tmp/kt-work-self; mkdir -p $w $GITROOT/d
    cp -r $W/. $w/
    ( cd $w && git init -q && git add -A && git commit -qm one && git tag -a v0.0.1 -m v0.0.1 &&
      git commit -q --allow-empty -m two && git tag -a v0.0.2 -m v0.0.2 &&
      git clone -q --bare . $GITROOT/d/kiwi-updater.git )
    mkdir -p /etc/kiwi-updater /var/lib/kiwi-updater/repos
    echo "$GITROOT/d/kiwi-updater.git" > /etc/kiwi-updater/apps.list
    local r=/var/lib/kiwi-updater/repos/kiwi-updater
    git clone -q $GITROOT/d/kiwi-updater.git $r && git -C $r checkout -q v0.0.1
    git -C $r rev-parse HEAD > $r/.kiwi-installed
    kr update --all --system --quiet >/dev/null; local rc=$?
    f() { [[ $rc -eq 0 && "$(git -C $r rev-parse HEAD)" == "$(git -C $w rev-parse 'v0.0.2^{commit}')" ]]; }
    check F4 "root timer run updates the root-owned kiwi-updater and exits 0" f
}

t_F5() { # update must not ask for root on behalf of system apps that are not installed
    mkapp a usertool user; mkapp a rootsvc "user system"
    mkcat c cat1 $GITROOT/a/usertool.git $GITROOT/a/rootsvc.git
    ku catalog add $GITROOT/c/cat1.git >/dev/null 2>&1
    ku install usertool >/dev/null
    : > $ESC
    ku update >/dev/null; local rc=$?
    f() { [[ $rc -eq 0 && ! -s $ESC ]]; }
    check F5 "'kiwi update' with no system app installed never escalates" f
}

t_F6() { # a process the installer leaves behind must not keep the scope lock
    mkapp a daemonish user '(sleep 30 >/dev/null 2>&1 &)'
    mkapp a other user
    ku add $GITROOT/a/daemonish.git >/dev/null; ku add $GITROOT/a/other.git >/dev/null
    ku install daemonish >/dev/null
    ku install other >/dev/null; local rc=$?
    f() { [[ $rc -eq 0 ]]; }
    check F6 "lock is free after an installer leaves a background process" f
}

t_F7() { # 'kiwi install' with no arguments must not install the whole catalog
    mkapp a one user; mkapp a two user
    mkcat c cat1 $GITROOT/a/one.git $GITROOT/a/two.git
    ku catalog add $GITROOT/c/cat1.git >/dev/null 2>&1
    ku install >/dev/null
    f() { [[ ! -f $(urepo one)/.kiwi-installed && ! -f $(urepo two)/.kiwi-installed ]]; }
    check F7 "bare 'kiwi install' installs nothing (needs a name or --all)" f
}

t_F8() { # F8 + F9 share a setup: a system app from a catalog, seen by the user
    mkapp a rootsvc system
    mkcat c cat1 $GITROOT/a/rootsvc.git
    mkdir -p /etc/kiwi-updater; echo $GITROOT/c/cat1.git > /etc/kiwi-updater/catalogs.list
    ku catalog add $GITROOT/c/cat1.git >/dev/null 2>&1
    ku list >/dev/null 2>&1
    kr install --system rootsvc >/dev/null
    release a rootsvc v1.1.0
    ku check >/dev/null; local rc=$?
    f9() { [[ $rc -eq 10 ]]; }
    check F9 "'kiwi check' reports a pending update of a catalog system app (exit 10)" f9
    kr update --system rootsvc >/dev/null
    local line; line="$(ku list --porcelain --check 2>/dev/null | grep '^rootsvc')"
    f8() { [[ "$(cut -f4 <<<"$line")" == installed && "$(cut -f5 <<<"$line")" == 1.1.0 ]]; }
    check F8 "after the system update the user sees it as installed at 1.1.0" f8
}

t_F10() { # only version tags are releases; a pre-release must not beat its release
    mkapp a tagged user
    ( cd /tmp/kt-work-a-tagged && git tag -a v2.0.0-rc1 -m rc &&
      git commit -q --allow-empty -m final && git tag -a v2.0.0 -m final &&
      git commit -q --allow-empty -m wip && git tag wip-test && git push -q origin HEAD --tags )
    ku add $GITROOT/a/tagged.git >/dev/null; ku install tagged >/dev/null
    f() { [[ "$(git -C "$(urepo tagged)" rev-parse HEAD 2>/dev/null)" == "$(git -C /tmp/kt-work-a-tagged rev-parse 'v2.0.0^{commit}')" ]]; }
    check F10 "latest release is v2.0.0, not v2.0.0-rc1 or a non-version tag" f
}

t_F11() { # two catalogs whose repo names collide
    mkapp a alpha user; mkapp b beta user
    mkcat org1 catalog $GITROOT/a/alpha.git; mkcat org2 catalog $GITROOT/b/beta.git
    ku catalog add $GITROOT/org1/catalog.git >/dev/null 2>&1
    ku catalog add $GITROOT/org2/catalog.git >/dev/null 2>&1; local rc=$?
    local names; names="$(ku list --porcelain 2>/dev/null | cut -f1)"
    # fixed = either the second add is refused, or both catalogs really work
    f() { [[ $rc -ne 0 ]] || grep -qx beta <<<"$names"; }
    check F11 "second catalog with the same repo name is refused or fully usable" f
}

t_F11b() { # an installed app must not be silently re-pointed at another repo
    mkapp a shifty user 'echo "installer from A"'
    ku add $GITROOT/a/shifty.git >/dev/null
    ku install shifty >/dev/null
    # a different repo, same basename, with a visibly different installer
    mkapp b shifty user 'touch /tmp/kt-ran-from-B'
    echo "$GITROOT/b/shifty.git" > $TH/.config/kiwi-updater/apps.list
    ku install shifty >/dev/null 2>&1; local rc=$?
    f() { [[ $rc -ne 0 && ! -e /tmp/kt-ran-from-B ]]; }
    check F11b "an installed app is not silently reinstalled from a changed URL" f
}

t_F12() { # --cli-only must survive more than one update
    mkapp a flav user 'echo "KIWI_GUI=$KIWI_GUI"'
    ku add $GITROOT/a/flav.git >/dev/null
    ku install flav --cli-only >/dev/null
    release a flav v1.0.1; KENV="KIWI_GUI=1" ku update flav >/dev/null
    release a flav v1.0.2
    local out; out="$(KENV="KIWI_GUI=1" ku update flav)"
    f() { grep -q 'KIWI_GUI=0' <<<"$out"; }
    check F12 "a --cli-only install stays cli-only on the second update" f
}

t_F13() { # an unreachable remote is not "up to date"
    mkapp a net user; ku add $GITROOT/a/net.git >/dev/null; ku install net >/dev/null
    mv $GITROOT/a/net.git $GITROOT/a/net.gone
    local out; out="$(ku update net 2>&1)"
    f() { ! grep -qi 'up to date' <<<"$out"; }
    check F13 "update of an unreachable app does not claim 'up to date'" f
}

t_F14() { # --purge has to reach the app's own installer
    mkapp a cfg user 'echo "args=[$*] purge=${KIWI_PURGE:-0}"'
    ku add $GITROOT/a/cfg.git >/dev/null; ku install cfg >/dev/null
    local out; out="$(ku uninstall cfg --purge 2>&1)"
    f() { grep -Eq 'args=\[uninstall --purge\]|purge=1' <<<"$out"; }
    check F14 "'kiwi uninstall --purge' tells the installer to purge" f
}

t_F15() { # list files are matched by exact URL, not by substring
    mkapp a foo user; mkapp a foo-bar user
    ku add $GITROOT/a/foo-bar >/dev/null
    ku add $GITROOT/a/foo >/dev/null 2>&1; local rc=$?
    f() { [[ $rc -eq 0 ]]; }
    check F15 "adding .../foo works when .../foo-bar is already listed" f
}

t_F16() { # do not ask for a password and then say "unknown app"
    mkapp a rootsvc "user system"
    mkcat c usercat $GITROOT/a/rootsvc.git
    ku catalog add $GITROOT/c/usercat.git >/dev/null 2>&1       # user-level only
    mkdir -p /etc/kiwi-updater /var/lib/kiwi-updater
    install -Dm755 $K /usr/local/bin/kiwi
    : > $ESC
    ku install rootsvc >/dev/null 2>&1
    f() { ! grep -q 'install --system' $ESC; }
    check F16 "no escalation for a system app that root cannot resolve" f
}

t_F17() { # installing without a systemd user session must still finish
    stub_systemctl 1
    runuser -u $T -- env -i HOME=$TH PATH=$STUBS:/usr/bin:/bin bash $W/install.sh install --cli-only </dev/null >/dev/null 2>&1
    stub_systemctl 0
    f() { [[ -f $TH/.config/kiwi-updater/catalogs.list ]]; }
    check F17 "install.sh completes when 'systemctl --user' is unavailable" f
}

t_F18() { # a manifest saved with CRLF line endings must still parse
    mkapp a crlf user
    ( cd /tmp/kt-work-a-crlf && sed -i 's/$/\r/' kiwi.manifest && git commit -qam crlf &&
      git tag -a v1.0.1 -m x && git push -q origin HEAD --tags )
    ku add $GITROOT/a/crlf.git >/dev/null
    ku install crlf >/dev/null 2>&1
    f() { [[ -f $(urepo crlf)/.kiwi-installed ]]; }
    check F18 "app with a CRLF manifest installs" f
}

t_F19() { # the app-folder glob has to match the ids apps actually use
    f() { ! grep -q "org\.kiwinetwork\.\*\.desktop" $K; }
    check F19 "sync_app_folder does not look for org.kiwinetwork.* (apps use eu.kiwinetwork.*)" f
}

t_S5() { # a name the wrapper accepts must never be able to look like an option
    # Asserted against the pattern itself: with NAME now validated in kiwi too,
    # there is no longer a route that gets an option-shaped name into the
    # known-apps list to test behaviourally.
    f() { grep -q '\^\[A-Za-z0-9\]\[A-Za-z0-9\._-\]\*\$' $W/data/kiwi-system-update; }
    check S5 "kiwi-system-update's name pattern cannot match an option" f
}

t_S1() { # no credential helper on ANY network call, including ls-remote
    command -v python3 >/dev/null || { echo "skip S1   (needs python3)"; return 0; }
    local port=18473 log=/tmp/kt-cred.log
    : > $log; chmod 666 $log
    printf '#!/bin/sh\necho "$*" >> %s\n' "$log" > $STUBS/cred-helper; chmod +x $STUBS/cred-helper
    python3 - "$port" <<'PY' &
import sys, http.server
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(401); self.send_header("WWW-Authenticate", 'Basic realm="x"'); self.end_headers()
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
    local srv=$!; sleep 1
    mkapp a private user; ku add $GITROOT/a/private.git >/dev/null; ku install private >/dev/null
    runuser -u $T -- env HOME=$TH git config --global credential.helper $STUBS/cred-helper
    echo "http://127.0.0.1:$port/private.git" > $TH/.config/kiwi-updater/apps.list
    ku check >/dev/null 2>&1
    kill $srv 2>/dev/null
    runuser -u $T -- env HOME=$TH git config --global --unset credential.helper
    f() { [[ ! -s $log ]]; }
    check S1 "credential helper is never invoked (ls-remote path)" f
}

t_S2() { # root must not resolve apps from a list the user can write
    mkapp mallory evil system 'touch /tmp/kt-ran-as-root'
    mkdir -p $TH/.config/kiwi-updater /etc/kiwi-updater /var/lib/kiwi-updater
    echo $GITROOT/mallory/evil.git > $TH/.config/kiwi-updater/apps.list; chown -R $T $TH/.config
    env -i HOME=/root XDG_CONFIG_HOME=$TH/.config USER=root PATH=$STUBS:/usr/sbin:/usr/bin:/bin \
        bash $K install --system evil </dev/null >/dev/null 2>&1
    f() { [[ ! -e /tmp/kt-ran-as-root ]]; }
    check S2 "root kiwi ignores HOME/XDG and user-writable lists" f
}

# ---------------------------------------------------------------------------
# Phase 4 features. Not findings — these assert that what the plan asked for
# actually behaves, so the same harness covers them.
# ---------------------------------------------------------------------------
t_P1() { # pin holds a version across updates; unpin releases it
    mkapp a pinned user 'echo installing'
    ku add $GITROOT/a/pinned.git >/dev/null
    ku install pinned >/dev/null
    release a pinned v1.1.0
    ku pin pinned v1.0.0 >/dev/null 2>&1
    ku update pinned >/dev/null 2>&1
    local held; held="$(sed -n 's/^VERSION=//p' "$(urepo pinned)/kiwi.manifest" | head -1)"
    ku unpin pinned >/dev/null 2>&1
    ku update pinned >/dev/null 2>&1
    local freed; freed="$(sed -n 's/^VERSION=//p' "$(urepo pinned)/kiwi.manifest" | head -1)"
    f() { [[ $held == 1.0.0 && $freed == 1.1.0 ]]; }
    check P1 "kiwi pin holds a version, kiwi unpin releases it (held=$held freed=$freed)" f
}

t_P2() { # diff shows the installer change an update would bring
    mkapp a dif user 'echo one'
    ku add $GITROOT/a/dif.git >/dev/null; ku install dif >/dev/null
    ( cd /tmp/kt-work-a-dif &&
      sed -i 's/^VERSION=.*/VERSION=1.1.0/' kiwi.manifest &&
      printf '#!/usr/bin/env bash\nset -euo pipefail\necho two\n' > install.sh &&
      git commit -qam two && git tag -a v1.1.0 -m v1.1.0 && git push -q origin HEAD --tags )
    local out; out="$(ku diff dif 2>&1)"
    f() { grep -q 'install.sh changes' <<<"$out" && grep -q 'echo two' <<<"$out"; }
    check P2 "kiwi diff shows the installer diff an update would apply" f
}

t_P3() { # info --installer prints the script before anything runs
    mkapp a shown user 'echo "the thing that runs"'
    ku add $GITROOT/a/shown.git >/dev/null
    local out; out="$(ku info --installer shown 2>&1)"
    f() { grep -q 'the thing that runs' <<<"$out" && [[ ! -f $(urepo shown)/.kiwi-installed ]]; }
    check P3 "kiwi info --installer shows the script and installs nothing" f
}

t_P4() { # --dry-run must describe the work and do none of it
    mkapp a dry user 'touch /tmp/kt-dry-ran'
    ku add $GITROOT/a/dry.git >/dev/null
    local out; out="$(ku install dry --dry-run 2>&1)"
    f() { [[ ! -e /tmp/kt-dry-ran && ! -f $(urepo dry)/.kiwi-installed ]] &&
          grep -q 'install.sh' <<<"$out" && grep -q 'v1.0.0' <<<"$out"; }
    check P4 "install --dry-run names the installer and ref, and runs nothing" f
}

t_P5() { # doctor has to actually spot a stale lock and a bad list file
    mkapp a dok user
    ku add $GITROOT/a/dok.git >/dev/null; ku install dok >/dev/null
    local L=$TH/.local/share/kiwi-updater/lock
    mkdir -p "$(dirname $L)"; : > $L; chown -R $T "$(dirname $L)"
    # Hold the flock from a process that is NOT the pid recorded in the file:
    # the orphaned-fd case from F6, which is the only way a lock can really be
    # stuck (if the recorded holder were gone, the kernel would have released
    # it). Same host fallback acquire_lock uses, so doctor matches on it.
    setsid bash -c "exec 9<>$L; flock 9; sleep 60" >/dev/null 2>&1 &
    local holder=$!
    sleep 1
    printf '%s pid=999999 started=now\n' "$(hostname 2>/dev/null || echo unknown)" > $L
    chown $T $L
    # a system list root would ignore
    mkdir -p /etc/kiwi-updater; echo "# x" > /etc/kiwi-updater/apps.list
    chmod 666 /etc/kiwi-updater/apps.list
    local out rc
    out="$(ku doctor 2>&1)"; rc=$?
    kill $holder 2>/dev/null; pkill -f "flock 9" 2>/dev/null
    f() { [[ $rc -ne 0 ]] && grep -qi 'stale' <<<"$out" &&
          grep -qi 'writable by group or other' <<<"$out"; }
    check P5 "kiwi doctor finds a stale lock and a world-writable system list" f
}

for t in F1 F2 F3 F4 F5 F6 F7 F8 F10 F11 F11b F12 F13 F14 F15 F16 F17 F18 F19 S1 S2 S5 \
         P1 P2 P3 P4 P5; do run $t; done
reset
echo
if (( BUGS )); then echo "$BUGS finding(s) still reproduce"; exit 1; fi
echo "all checks pass"
