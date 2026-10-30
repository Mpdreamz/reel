#!/bin/bash
# Records reel's own demos: every tape in demos/, into docs/media/. Needs Screen Recording and Accessibility, and the
# apps they record (demos/musicbox.reel: Musicbox built in ~/Projects/musicbox). Plays sound, and app tapes take the
# mouse and keyboard while they play.
#
#   scripts/demos.sh                 every demo
#   scripts/demos.sh musicbox        one
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -q
# A tiling yabai would resize the windows and defeat Set Size: let the recorded apps float while the tapes play. The
# rule lives only in the running yabai, and goes again on exit.
if pgrep -xq yabai; then
    yabai -m rule --add label=reel-demos app='^(Musicbox)$' manage=off
    trap 'yabai -m rule --remove reel-demos' EXIT
fi
tapes=("$@")
[ ${#tapes[@]} -gt 0 ] || tapes=(demos/*.reel)
for tape in "${tapes[@]}"; do
    [ -f "$tape" ] || tape="demos/$tape.reel"
    echo "== $tape"
    .build/debug/reel "$tape"
done
