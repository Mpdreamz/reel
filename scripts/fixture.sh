#!/bin/bash
# Builds build/ReelFixture.app: the fixture app reels/fixture.reel records.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product ReelFixture
app=build/ReelFixture.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/debug/ReelFixture "$app/Contents/MacOS/ReelFixture"
cat >"$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.mpdreamz.reel.fixture</string>
  <key>CFBundleName</key><string>ReelFixture</string>
  <key>CFBundleExecutable</key><string>ReelFixture</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$app" >/dev/null
echo "$app"
