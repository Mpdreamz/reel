#!/bin/bash
# Puts xterm.js, the terminal a terminal screen is drawn with, into reel's resources: the pinned version from npm,
# checked against the checksum npm publishes for it. Only the library, its stylesheet and its licence. Run it to change
# the version; the result is committed.
#
#   scripts/vendor-xterm.sh
set -euo pipefail
cd "$(dirname "$0")/.."
version="6.0.0"
integrity="sha512-TQwDdQGtwwDt+2cgKDLn0IRaSxYu1tSUjgKarSDkUM0ZNiSRXFpjxEsvc/Zgc5kq5omJ+V0a8/kIM2WD3sMOYg=="
target="Sources/ReelCore/Resources/Screen/xterm"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
curl -fsSL "https://registry.npmjs.org/@xterm/xterm/-/xterm-$version.tgz" -o "$work/xterm.tgz"
actual="sha512-$(openssl dgst -sha512 -binary "$work/xterm.tgz" | base64)"
if [[ "$actual" != "$integrity" ]]; then
  echo "vendor-xterm: @xterm/xterm $version does not match its published checksum" >&2
  exit 1
fi
mkdir -p "$work/x" && tar -xzf "$work/xterm.tgz" -C "$work/x"
rm -rf "$target" && mkdir -p "$target"
cp "$work/x/package/lib/xterm.js" "$work/x/package/css/xterm.css" "$work/x/package/LICENSE" "$target/"
echo "$version" > "$target/VERSION"
echo "vendor-xterm: @xterm/xterm $version in $target ($(du -sh "$target" | cut -f1))"
