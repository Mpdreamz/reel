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
fi
# The same tape twice: in WebKit (the default), and in a Chromium-based browser from a copy that Sets Browser chromium.
sed 's/^Set Viewport/Set Browser chromium\nSet Viewport/; s#build/web\.#build/web-chromium.#' tapes/web.tape >tapes/web-chromium.tape
trap 'rm -f tapes/web-chromium.tape; pgrep -xq yabai && yabai -m rule --remove reel-web' EXIT
for tape in web web-chromium; do
    echo "== $tape"
    .build/debug/reel "tapes/$tape.tape"
    swift scripts/check-web.swift "tapes/.reel/$tape" "build/$tape.mp4"
done
