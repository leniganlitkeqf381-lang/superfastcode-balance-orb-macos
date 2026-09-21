#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
app="dist/TokenOrb.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" build
xcrun swiftc -target arm64-apple-macos14.0 -swift-version 5 -O -parse-as-library Sources/Quota.swift Sources/App.swift -framework AppKit -framework WebKit -o "$app/Contents/MacOS/TokenOrb"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.superfastcode-balance-orb.macos</string>
<key>CFBundleName</key><string>Token悬浮球</string>
<key>CFBundleDisplayName</key><string>Token悬浮球</string>
<key>CFBundleExecutable</key><string>TokenOrb</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$app"
printf 'Built: %s\n' "$app"
