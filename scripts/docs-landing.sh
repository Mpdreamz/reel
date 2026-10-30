#!/usr/bin/env bash
# Puts the landing page over the index.html docs-builder generated, with what it loads: its fonts, icons, the demo
# video and its poster. scripts/docs.sh and the docs workflow both run it, so they cannot drift apart.
#
#   scripts/docs-landing.sh .artifacts/docs/html
set -euo pipefail
out="$1"
cd "$(dirname "$0")/.."
cp docs/reel-landing.html "$out/index.html"
cp docs/robots.txt "$out/robots.txt"
cp -R docs/landing/. "$out/"
# docs-builder copies images, not fonts; the landing page needs its six.
mkdir -p "$out/fonts" && cp docs/fonts/*.woff2 "$out/fonts/"
