#!/bin/bash
# 把编译好的 CoinCoding 二进制打包成 CoinCoding.app
set -e
cd "$(dirname "$0")"

APP="CoinCoding.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp CoinCoding "$APP/Contents/MacOS/CoinCoding"

# 图标：assets/icon.png → icns（如果存在）
if [ -f ../assets/icon.png ]; then
  ICONSET=$(mktemp -d)/icon.iconset
  mkdir -p "$ICONSET"
  for s in 16 32 64 128 256 512; do
    sips -z $s $s ../assets/icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) ../assets/icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/icon.icns"
fi

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>CoinCoding</string>
  <key>CFBundleIdentifier</key><string>com.coincoding.app</string>
  <key>CFBundleName</key><string>Coin Coding</string>
  <key>CFBundleDisplayName</key><string>Coin Coding</string>
  <key>CFBundleVersion</key><string>0.2.0</string>
  <key>CFBundleShortVersionString</key><string>0.2.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

echo "✓ packaged $APP"
