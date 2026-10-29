#!/usr/bin/env bash
# Sign a reel binary for distribution: Developer ID, the hardened runtime (notarization requires it) and a secure
# timestamp. Replaces the linker's ad-hoc signature.
#
#   scripts/sign.sh <binary> "Developer ID Application: Name (TEAMID)" [keychain]
set -euo pipefail
binary="${1:?usage: scripts/sign.sh <binary> <identity> [keychain]}"
identity="${2:?usage: scripts/sign.sh <binary> <identity> [keychain]}"
keychain=()
[ -n "${3:-}" ] && keychain=(--keychain "$3")
codesign --force --options runtime --timestamp --identifier io.github.mpdreamz.reel --sign "$identity" \
  ${keychain[@]+"${keychain[@]}"} "$binary"
codesign --verify --strict --verbose=2 "$binary"
echo "sign: $binary signed by $identity"
