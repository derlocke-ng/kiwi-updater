#!/usr/bin/env bash
# tests/check-version.sh — the release gate, run before every tag and in CI.
#
# 1. The version lives in three places; keep them equal.
# bin/kiwi's KIWI_VERSION is what `kiwi version` prints, kiwi.manifest's VERSION
# is what every other machine sees in `kiwi list`, and the git tag is what an
# update actually checks out. A release where they disagree tells users they are
# on a version they are not.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

bin="$(sed -n 's/^KIWI_VERSION=//p' bin/kiwi | head -1)"
man="$(sed -n 's/^VERSION=//p' kiwi.manifest | head -1)"
rc=0

say_bad() { printf 'check-version: %s\n' "$*" >&2; rc=1; }

[[ -n $bin ]] || say_bad "no KIWI_VERSION in bin/kiwi"
[[ -n $man ]] || say_bad "no VERSION in kiwi.manifest"
[[ $bin == "$man" ]] || say_bad "bin/kiwi says $bin, kiwi.manifest says $man"

# Only when HEAD itself is tagged: on a normal commit the next tag does not
# exist yet, and demanding one would fail every ordinary push.
if tag="$(git describe --exact-match --tags HEAD 2>/dev/null)"; then
    [[ ${tag#v} == "$bin" ]] || say_bad "tag $tag does not match version $bin"
fi

# 2. The scripts are executable IN GIT, which is what a clone gets. Something on
# a development machine reset these files to 0644 between 1.6.1 and 1.7.0, a
# `git add -A` recorded it, and five releases shipped with `./install.sh` and
# `./bin/kiwi` answering "Permission denied" from a fresh clone. Nothing in
# kiwi's own paths noticed — it runs everything through `bash` or reinstalls
# with `install -m755` — which is exactly why it needs checking here.
for f in bin/kiwi install.sh get-kiwi.sh gui/kiwi-gui templates/install.sh \
         tests/check-version.sh tests/repro.sh; do
    mode="$(git ls-files -s -- "$f" | awk '{print $1}')"
    [[ $mode == 100755 ]] || say_bad "$f is tracked as ${mode:-<untracked>}, not 100755 — chmod 755 it and re-add"
done

(( rc )) || printf 'check-version: ok (%s, scripts executable)\n' "$bin"
exit $rc
