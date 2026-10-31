#!/bin/bash
# Puts Monaco, the editor a code screen is drawn with, into reel's resources: the pinned version from npm, checked
# against the checksum npm publishes for it, cut down to the editor itself. Its language workers (TypeScript, CSS,
# HTML and JSON checking, about 17 MB) are left out: reel only colours code, which the editor does on its own for
# every language it ships. Run it to change the version; the result is committed.
#
#   scripts/vendor-monaco.sh
set -euo pipefail
cd "$(dirname "$0")/.."
version="0.57.0"
integrity="sha512-5BkI9KGoqrNvBGUe15/QlZq3OooZ8WLg1AxTpaqHRCP3HNpzPPZKE2EDz8M7c+VRmCeUw1Brp4cx/PWm3kI/5A=="
target="Sources/ReelCore/Resources/Screen/monaco"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
curl -fsSL "https://registry.npmjs.org/monaco-editor/-/monaco-editor-$version.tgz" -o "$work/monaco.tgz"
actual="sha512-$(openssl dgst -sha512 -binary "$work/monaco.tgz" | base64)"
if [[ "$actual" != "$integrity" ]]; then
  echo "vendor-monaco: monaco-editor $version does not match its published checksum" >&2
  exit 1
fi
mkdir -p "$work/x" && tar -xzf "$work/monaco.tgz" -C "$work/x"
rm -rf "$target" && mkdir -p "$target"
cp -R "$work/x/package/min/vs" "$target/vs"
rm -rf "$target/vs/assets" "$target/vs/language"
cp "$work/x/package/LICENSE" "$work/x/package/ThirdPartyNotices.txt" "$target/"
echo "$version" > "$target/VERSION"
echo "vendor-monaco: monaco-editor $version in $target ($(du -sh "$target" | cut -f1))"
