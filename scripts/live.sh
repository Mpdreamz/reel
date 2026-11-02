#!/bin/bash
# Records reels/fixture.reel against the fixture app for real and checks the take: what CI cannot run, since it
# needs Screen Recording and Accessibility. Plays a quiet tone, and takes the mouse and keyboard for a few seconds.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/fixture.sh >/dev/null
# A tiling yabai would resize the fixture and defeat Set Size: let it float while the reel plays. The rule lives
# only in the running yabai, and goes again on exit.
if pgrep -xq yabai; then
    yabai -m rule --add label=reel-fixture app='^ReelFixture$' manage=off
    trap 'yabai -m rule --remove reel-fixture' EXIT
fi
swift build -q
# An app that opens in the middle of the take, over the window: the take must not show it.
swiftc -sdk "$(xcrun --show-sdk-path)" -o build/intruder scripts/intruder.swift 2>/dev/null
rm -f build/fixture-events.log build/intruder.log
build/intruder build/intruder.log &
intruder=$!
status=0
.build/debug/reel reels/fixture.reel || status=$?
pkill -x ReelFixture || true
wait "$intruder" || true
[ "$status" -eq 0 ] || exit "$status"
swift scripts/check-take.swift reels/.reel/fixture build/fixture-events.log build/fixture.mp4 build/fixture.gif \
    build/intruder.log
