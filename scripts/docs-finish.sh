#!/usr/bin/env bash
# What both builds (scripts/docs.sh and .github/workflows/docs.yml, and the docs job in ci.yml) do after docs-builder,
# so they cannot drift apart: the reel theme appended to the design system's stylesheet, root links and the header
# logo patched, and the landing page over the generated index.html with what it loads (its fonts, icons, the demo
# videos and their posters). Needs a build with FEATURE_NAVIGATION_PREVIEW=true: without it the pages load no ds.css
# and this fails.
#
#   scripts/docs-finish.sh .artifacts/docs/html reel
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:?usage: docs-finish.sh <docs-builder output dir> <path prefix>}"
prefix="${2:?usage: docs-finish.sh <docs-builder output dir> <path prefix>}"
theme="$root/docs/reel-docs.css"

# The theme's @font-face URLs carry the prefix; a build for another prefix would load no fonts.
if ! grep -q "url('/$prefix/fonts/" "$theme"; then
  echo "docs: $theme does not load its fonts from /$prefix/fonts/" >&2
  exit 1
fi

# The theme goes into the ds.css the pages actually load. Its name comes from docs-builder (plain ds.css with ?v=, or a
# hashed file), so read it from a built page instead of guessing. Before the landing page replaces index.html.
probe="$out/getting-started/index.html"
[[ -f "$probe" ]] || { echo "docs: $probe is missing, cannot find the design-system stylesheet" >&2; exit 1; }
href="$(grep -o 'href="[^"]*/_static/ds[^"/]*\.css[^"]*"' "$probe" | grep -v 'ds-layers' | head -n1 | sed 's/^href="//; s/"$//; s/?.*$//')" || true
if [[ -z "$href" ]]; then
  echo "docs: $probe loads no design-system ds.css; build with FEATURE_NAVIGATION_PREVIEW=true" >&2
  exit 1
fi
css="$out/_static/${href##*/_static/}"
[[ -f "$css" ]] || { echo "docs: $css (from $href) does not exist" >&2; exit 1; }
# An incremental docs-builder build keeps the previous ds.css, theme and all: cut it at the marker before appending.
marker="/* reel-docs.css: appended by scripts/docs-finish.sh */"
awk -v m="$marker" '$0 == m { exit } { print }' "$css" > "$css.tmp"
{ printf '%s\n' "$marker"; cat "$theme"; } >> "$css.tmp"
mv "$css.tmp" "$css"

# Root links that skip htmx, and the header logo: see scripts/docs-pages.py.
python3 -I "$root/scripts/docs-pages.py" "$out" "$root/docs" "$prefix"

cp "$root/docs/reel-landing.html" "$out/index.html"
cp "$root/docs/robots.txt" "$out/robots.txt"
cp -R "$root/docs/landing/." "$out/"
# docs-builder copies images, not fonts; the landing page and the theme need these six.
mkdir -p "$out/fonts" && cp "$root"/docs/fonts/*.woff2 "$out/fonts/"
echo "docs: finished $out (theme appended to ${css#"$out"/}, landing page applied)"
