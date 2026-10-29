#!/bin/bash
# Records tapes/web.tape against tapes/web/fixture.html in a browser reel starts, and checks the take. Needs Screen
# Recording; plays a quiet tone. The tape drives the page over DevTools, so the mouse and keyboard stay yours.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -q
# A tiling yabai would resize the browser and defeat Set Viewport: let it float while the tape plays. The rule lives
# only in the running yabai, and goes again on exit.
if pgrep -xq yabai; then
    yabai -m rule --add label=reel-web app='^(Google Chrome|Google Chrome for Testing|Chromium|Brave Browser|Microsoft Edge)$' manage=off
    trap 'yabai -m rule --remove reel-web' EXIT
fi
.build/debug/reel tapes/web.tape
swift scripts/check-web.swift tapes/.reel/web build/web.mp4
