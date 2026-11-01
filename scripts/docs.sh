#!/usr/bin/env bash
# Build the documentation exactly as CI does, then serve it: docs-builder with the design-system layout, then
# scripts/docs-finish.sh (the theme, the header mark, the landing page over the generated index.html).
# `docs-builder serve` renders on demand and never applies those, so it would preview the wrong site.
#
#   mise run docs              build and serve on http://localhost:4000/reel/
#   mise run docs -- --noserve build only
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

# The sub-path GitHub Pages serves from: mpdreamz.github.io/reel. The landing page's <base href> and the workflow's
# prefix: input must agree with it, and nothing but this check would notice if they drifted.
path_prefix="reel"
landing="docs/reel-landing.html"
workflow=".github/workflows/docs.yml"
expected_base="/"
[[ -n "$path_prefix" ]] && expected_base="/$path_prefix/"
actual_base="$(grep -o '<base href="[^"]*"' "$landing" | sed 's/<base href="//; s/"$//')"
if [[ "$actual_base" != "$expected_base" ]]; then
  echo "docs: $landing has <base href=\"$actual_base\"> but the site builds for \"$expected_base\"" >&2
  exit 1
fi
if ! grep -q "prefix: $path_prefix\$" "$workflow"; then
  echo "docs: $workflow does not build with prefix: $path_prefix" >&2
  exit 1
fi

# docs-builder is a native binary, not a dotnet tool; cached under .artifacts. Delete it to pick up a newer release,
# set DOCS_BUILDER_VERSION to pin one, or DOCS_BUILDER to use one already installed.
tool="${DOCS_BUILDER:-.artifacts/tools/docs-builder}"
if [[ ! -x "$tool" && -n "${DOCS_BUILDER:-}" ]]; then
  echo "docs: DOCS_BUILDER=$DOCS_BUILDER is not an executable" >&2
  exit 1
fi
if [[ ! -x "$tool" ]]; then
  arch="$(uname -m)"; [[ "$arch" == "x86_64" ]] && arch="x64"
  archive="docs-builder-mac-$arch.zip"
  version="${DOCS_BUILDER_VERSION:-latest}"
  if [[ "$version" == "latest" ]]; then
    url="https://github.com/elastic/docs-builder/releases/latest/download/$archive"
  else
    url="https://github.com/elastic/docs-builder/releases/download/$version/$archive"
  fi
  echo "docs: downloading $url"
  mkdir -p .artifacts/tools
  curl -fsSL "$url" -o "/tmp/$archive"
  unzip -o -q -j "/tmp/$archive" docs-builder -d .artifacts/tools
  rm "/tmp/$archive"
  chmod +x "$tool"
fi

# The design-system layout the theme (docs/reel-docs.css) is written for; the workflows set it too.
FEATURE_NAVIGATION_PREVIEW=true "$tool" build --path docs --path-prefix "$path_prefix"
out=".artifacts/docs/html"
scripts/docs-finish.sh "$out" "$path_prefix"

[[ "${1:-}" == "--noserve" ]] && exit 0
# Served from a folder named for the prefix, so /reel/ resolves as it does on GitHub Pages.
serve="$(mktemp -d)"
ln -s "$root/$out" "$serve/$path_prefix"
echo "docs: serving http://localhost:4000/$path_prefix/"
cd "$serve" && exec python3 -m http.server 4000
