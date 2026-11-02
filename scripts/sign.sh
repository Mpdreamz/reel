#!/usr/bin/env bash
# Sign reel for distribution: Developer ID, the hardened runtime (notarization requires it) and a secure timestamp.
# Replaces the ad-hoc signature. A binary is signed as io.github.mpdreamz.reel; an .app (Reel Companion) as the bundle
# id its Info.plist gives, its executable with it.
#
#   scripts/sign.sh <binary or .app> "Developer ID Application: Name (TEAMID)" [keychain]
set -euo pipefail
binary="${1:?usage: scripts/sign.sh <binary> <identity> [keychain]}"
identity="${2:?usage: scripts/sign.sh <binary> <identity> [keychain]}"
keychain=()
[ -n "${3:-}" ] && keychain=(--keychain "$3")
identifier=()
case "$binary" in *.app | *.app/) ;; *) identifier=(--identifier io.github.mpdreamz.reel) ;; esac
codesign --force --options runtime --timestamp ${identifier[@]+"${identifier[@]}"} --sign "$identity" \
  ${keychain[@]+"${keychain[@]}"} "$binary"
codesign --verify --strict --verbose=2 "$binary"
echo "sign: $binary signed by $identity"
