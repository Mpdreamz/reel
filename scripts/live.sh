#!/bin/bash
# Records tapes/fixture.tape against the fixture app for real and checks the take: what CI cannot run, since it
# needs Screen Recording and Accessibility. Plays a quiet tone, and takes the mouse and keyboard for a few seconds.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/fixture.sh >/dev/null
# A tiling yabai would resize the fixture and defeat Set Size: let it float while the tape plays. The rule lives
# only in the running yabai, and goes again on exit.
if pgrep -xq yabai; then
    yabai -m rule --add label=reel-fixture app='^ReelFixture$' manage=off
    trap 'yabai -m rule --remove reel-fixture' EXIT
fi
swift build -q
rm -f build/fixture-events.log
status=0
.build/debug/reel tapes/fixture.tape || status=$?
pkill -x ReelFixture || true
[ "$status" -eq 0 ] || exit "$status"
swift scripts/check-take.swift tapes/.reel/fixture build/fixture-events.log build/fixture.mp4 build/fixture.gif
