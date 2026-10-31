#!/usr/bin/env bash
# Build reel for release into build/reel: arm64, optimised, the version written into it and checked. Beside it,
# build/Reel_ReelCore.bundle holds what the code screen loads (Monaco, its page, the fonts); reel finds it there.
#
#   scripts/build-release.sh 0.1.0
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?usage: scripts/build-release.sh <version>}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "build-release: '$version' is not a version like 0.1.0" >&2; exit 1; }
source=Sources/reel/Version.swift
# Put back as it was afterwards, whatever happens: the version is only for this build.
kept="$(mktemp)"
cp "$source" "$kept"
trap 'cp "$kept" "$source"; rm -f "$kept"' EXIT
sed -i '' "s/^let reelVersion = \"dev\"$/let reelVersion = \"$version\"/" "$source"
grep -q "\"$version\"" "$source" || { echo "build-release: could not write the version into $source" >&2; exit 1; }
swift build -c release --arch arm64 --product reel
mkdir -p build
products="$(swift build -c release --arch arm64 --show-bin-path)"
cp "$products/reel" build/reel
rm -rf build/Reel_ReelCore.bundle
cp -R "$products/Reel_ReelCore.bundle" build/
shown="$(build/reel --version)"
[ "$shown" = "$version" ] || { echo "build-release: reel --version says $shown, not $version" >&2; exit 1; }
echo "build-release: build/reel $shown"
