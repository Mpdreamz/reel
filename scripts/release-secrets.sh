#!/usr/bin/env bash
# Store the release workflow's signing, notarization and Homebrew secrets on GitHub, from this Mac. Run it yourself; it
# prints no secret, and removes every file it makes.
#
#   scripts/release-secrets.sh                     the Developer ID certificate (and its password)
#   scripts/release-secrets.sh --p8 ~/Downloads/AuthKey_ABC123.p8 --key-id ABC123 --issuer-id <uuid>
#                                                  the notarization API key too
#   scripts/release-secrets.sh --tap               only the token that lets releases update mpdreamz/homebrew-tap
#                                                  (asked for, not shown: a fine-grained token with contents:write there)
#
# The certificate: macOS asks to allow exporting your keychain's signing identities. Only the "Developer ID
# Application" certificate and its private key are kept, repackaged with a random password in the format a CI
# keychain imports, and checked by signing a file with it in a throwaway keychain before anything is uploaded.
set -euo pipefail

repo="mpdreamz/reel"
openssl=/usr/bin/openssl # LibreSSL: reads what `security export` writes without -legacy, writes what `security import` reads
p8="" key_id="" issuer_id="" tap=false

while [ $# -gt 0 ]; do
  case "$1" in
    --p8) p8="$2"; shift 2 ;;
    --key-id) key_id="$2"; shift 2 ;;
    --issuer-id) issuer_id="$2"; shift 2 ;;
    --tap) tap=true; shift ;;
    -h | --help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "release-secrets: unknown argument $1 (see --help)" >&2; exit 1 ;;
  esac
done
if [ -n "$p8$key_id$issuer_id" ] && { [ -z "$p8" ] || [ -z "$key_id" ] || [ -z "$issuer_id" ]; }; then
  echo "release-secrets: --p8, --key-id and --issuer-id go together" >&2
  exit 1
fi
[ -z "$p8" ] || [ -f "$p8" ] || { echo "release-secrets: no file $p8" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "release-secrets: sign in to gh first (gh auth login)" >&2; exit 1; }

# The tap token: asked for by gh, which reads it without echoing it.
if $tap; then
  echo "release-secrets: paste a token that can push to mpdreamz/homebrew-tap (contents: write), then return"
  gh secret set HOMEBREW_TAP_TOKEN --repo "$repo"
  echo "release-secrets: HOMEBREW_TAP_TOKEN stored on $repo"
  exit 0
fi

umask 077
work="$(mktemp -d)"
scratch_keychain="$work/check.keychain-db"
cleanup() {
  security delete-keychain "$scratch_keychain" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

# 1. Every signing identity in the login keychain, under a throwaway password (macOS asks to allow this).
export_pw="$($openssl rand -hex 24)"
echo "release-secrets: exporting signing identities (allow it in the dialog)…"
security export -k "$HOME/Library/Keychains/login.keychain-db" -t identities -f pkcs12 -P "$export_pw" \
  -o "$work/all.p12" >/dev/null
$openssl pkcs12 -in "$work/all.p12" -passin "pass:$export_pw" -nodes -out "$work/all.pem" 2>/dev/null

# 2. Split it into certificates and keys, and keep the Developer ID Application certificate and the key that matches it.
awk -v dir="$work" '
  /-----BEGIN CERTIFICATE-----/ { n++; out = dir "/cert" n ".pem" }
  /-----BEGIN (RSA |EC )?PRIVATE KEY-----/ { k++; out = dir "/key" k ".pem" }
  out { print > out }
  /-----END/ { out = "" }
' "$work/all.pem"
cert=""
for candidate in "$work"/cert*.pem; do
  if $openssl x509 -in "$candidate" -noout -subject | grep -q "Developer ID Application"; then
    cert="$candidate"
    break
  fi
done
[ -n "$cert" ] || { echo "release-secrets: no Developer ID Application certificate in the login keychain" >&2; exit 1; }
cert_pub="$($openssl x509 -in "$cert" -noout -pubkey)"
key=""
for candidate in "$work"/key*.pem; do
  if [ "$($openssl pkey -in "$candidate" -pubout 2>/dev/null)" = "$cert_pub" ]; then
    key="$candidate"
    break
  fi
done
[ -n "$key" ] || { echo "release-secrets: the Developer ID certificate's private key is not in the login keychain" >&2; exit 1; }
name="$($openssl x509 -in "$cert" -noout -subject | sed -E 's/.*CN ?= ?([^,/]*).*/\1/')"

# 3. Just that identity, under a new random password, in the legacy format macOS keychains import.
p12_pw="$($openssl rand -hex 24)"
$openssl pkcs12 -export -in "$cert" -inkey "$key" -name "$name" -out "$work/developer-id.p12" \
  -passout "pass:$p12_pw" -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1

# 4. Prove it works as CI will use it: import into a throwaway keychain and sign a file.
security create-keychain -p check "$scratch_keychain"
security unlock-keychain -p check "$scratch_keychain"
security import "$work/developer-id.p12" -k "$scratch_keychain" -P "$p12_pw" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k check "$scratch_keychain" >/dev/null
cp /bin/echo "$work/probe"
codesign --force --sign "$name" --keychain "$scratch_keychain" --timestamp=none "$work/probe" 2>/dev/null \
  || { echo "release-secrets: the repackaged certificate does not sign; nothing uploaded" >&2; exit 1; }
echo "release-secrets: $name signs from a fresh keychain"

# 5. Upload. Secrets go to GitHub over stdin; none is echoed.
base64 -i "$work/developer-id.p12" | gh secret set DEVELOPER_ID_P12 --repo "$repo"
printf '%s' "$p12_pw" | gh secret set DEVELOPER_ID_P12_PASSWORD --repo "$repo"
team="$(sed -E 's/.*\(([A-Z0-9]{10})\).*/\1/' <<<"$name")"
gh secret set APPLE_TEAM_ID --repo "$repo" --body "$team"
if [ -n "$p8" ]; then
  gh secret set NOTARY_KEY_P8 --repo "$repo" <"$p8"
  gh secret set NOTARY_KEY_ID --repo "$repo" --body "$key_id"
  gh secret set NOTARY_ISSUER_ID --repo "$repo" --body "$issuer_id"
fi

echo "release-secrets: stored on $repo:"
gh secret list --repo "$repo"
[ -n "$p8" ] || echo "release-secrets: the notarization key is still to do: run again with --p8, --key-id and --issuer-id"
