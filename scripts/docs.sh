#!/usr/bin/env bash
# Build the documentation exactly as CI does, then serve it: docs-builder, then the landing page over the generated
# index.html. `docs-builder serve` renders on demand and never applies that override, so it would preview the wrong
# home page.
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
# or set DOCS_BUILDER_VERSION to pin one.
tool=".artifacts/tools/docs-builder"
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

"$tool" build --path docs --path-prefix "$path_prefix"
out=".artifacts/docs/html"
scripts/docs-landing.sh "$out"
echo "docs: built $out (landing page applied)"

[[ "${1:-}" == "--noserve" ]] && exit 0
# Served from a folder named for the prefix, so /reel/ resolves as it does on GitHub Pages.
serve="$(mktemp -d)"
ln -s "$root/$out" "$serve/$path_prefix"
echo "docs: serving http://localhost:4000/$path_prefix/"
cd "$serve" && exec python3 -m http.server 4000
