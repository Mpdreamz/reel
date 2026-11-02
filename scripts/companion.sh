#!/bin/bash
# Builds build/Reel Companion.app: the menu bar app that shows what reel runs are doing (Sources/ReelCompanion), its
# icon from design/brand/icons/reel.iconset and the brand's line icons beside it. Debug unless CONFIGURATION=release;
# ARCH=arm64 builds for that architecture alone, as the release does. Ad-hoc signed: scripts/sign.sh signs it for
# distribution.
set -euo pipefail
cd "$(dirname "$0")/.."
configuration=${CONFIGURATION:-debug}
version=${VERSION:-0.0.0}
flags=(-c "$configuration")
[ -n "${ARCH:-}" ] && flags+=(--arch "$ARCH")
swift build "${flags[@]}" --product ReelCompanion
app="build/Reel Companion.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/line-icons"
cp "$(swift build "${flags[@]}" --show-bin-path)/ReelCompanion" "$app/Contents/MacOS/ReelCompanion"
iconutil -c icns design/brand/icons/reel.iconset -o "$app/Contents/Resources/AppIcon.icns"
for icon in design/brand/line-icons/*.svg; do
    case "$(basename "$icon")" in _* | sprite.svg) continue ;; esac
    cp "$icon" "$app/Contents/Resources/line-icons/"
done
cat >"$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>io.github.mpdreamz.reel.companion</string>
  <key>CFBundleName</key><string>Reel Companion</string>
  <key>CFBundleDisplayName</key><string>Reel Companion</string>
  <key>CFBundleExecutable</key><string>ReelCompanion</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$app" >/dev/null
echo "$app"
