#!/usr/bin/env bash
# tests/check-version.sh — the version lives in three places; keep them equal.
#
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

(( rc )) || printf 'check-version: ok (%s)\n' "$bin"
exit $rc
