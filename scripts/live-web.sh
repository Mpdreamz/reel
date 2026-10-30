#!/bin/bash
# Records reels/web.reel against reels/web/fixture.html in a browser reel starts, and checks the take. Needs Screen
# Recording; plays a quiet tone. The reel drives the page over DevTools, so the mouse and keyboard stay yours.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -q
# A tiling yabai would resize the browser and defeat Set Viewport: let it float while the reel plays. The rule lives
# only in the running yabai, and goes again on exit.
if pgrep -xq yabai; then
    yabai -m rule --add label=reel-web app='^(Google Chrome|Google Chrome for Testing|Chromium|Brave Browser|Microsoft Edge)$' manage=off
fi
# The same reel twice: in WebKit (the default), and in a Chromium-based browser from a copy that Sets Browser chromium.
sed 's/^Set Viewport/Set Browser chromium\nSet Viewport/; s#build/web\.#build/web-chromium.#' reels/web.reel >reels/web-chromium.reel
trap 'rm -f reels/web-chromium.reel; pgrep -xq yabai && yabai -m rule --remove reel-web' EXIT
for reel in web web-chromium; do
    echo "== $reel"
    .build/debug/reel "reels/$reel.reel"
    swift scripts/check-web.swift "reels/.reel/$reel" "build/$reel.mp4"
done
