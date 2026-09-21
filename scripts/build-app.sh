#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if /usr/bin/pgrep -f "$PWD/dist/屏幕管家.app/Contents/MacOS/ScreenPilot" >/dev/null; then
    echo '请先退出屏幕管家，再重新构建。' >&2
    exit 1
fi
if /usr/bin/pgrep -f "$PWD/dist/屏幕管家.app/Contents/Resources/ConnectionGuard" >/dev/null; then
    echo '独立恢复程序仍在运行，请等待屏幕恢复后再构建。' >&2
    exit 1
fi
python3 scripts/package-windows-bridge.py
./scripts/build-helper.sh
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="${SCREENPILOT_APP_DIR:-$PWD/dist/屏幕管家.app}"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/ScreenPilot" "$app_dir/Contents/MacOS/ScreenPilot"
cp .build/native/DisplayBridge "$app_dir/Contents/Resources/DisplayBridge"
cp .build/native/ConnectionProbe "$app_dir/Contents/Resources/DisplayConnection"
cp "$binary_dir/ConnectionGuard" "$app_dir/Contents/Resources/ConnectionGuard"
cp Vendor/m1ddc/LICENSE "$app_dir/Contents/Resources/m1ddc-LICENSE.txt"
cp "${SCREENPILOT_VERIFIED_INPUTS:-Config/VerifiedInputs.example.json}" "$app_dir/Contents/Resources/VerifiedInputs.json"
cp dist/ScreenPilot-WindowsBridge.zip "$app_dir/Contents/Resources/WindowsBridge.zip"
cp README.md "$app_dir/Contents/Resources/README.md"
cp docs/images/logo.png "$app_dir/Contents/Resources/ScreenPilot-logo.png"
cp LICENSE "$app_dir/Contents/Resources/LICENSE.txt"
if [ ! -f .build/ScreenPilot.icns ] || [ scripts/make-icon.swift -nt .build/ScreenPilot.icns ]; then
    swift scripts/make-icon.swift .build/ScreenPilot.iconset
    iconutil -c icns .build/ScreenPilot.iconset -o .build/ScreenPilot.icns
fi
cp .build/ScreenPilot.icns "$app_dir/Contents/Resources/ScreenPilotBrand-v2.icns"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>studio.qiushan.ScreenPilot</string>
<key>CFBundleName</key><string>屏幕管家</string>
<key>CFBundleDisplayName</key><string>屏幕管家</string>
<key>CFBundleExecutable</key><string>ScreenPilot</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.6.3</string>
<key>CFBundleVersion</key><string>15</string>
<key>NSHumanReadableCopyright</key><string>© 2026 QiushanHuang</string>
<key>SPCopyrightOwner</key><string>QiushanHuang</string>
<key>CFBundleIconFile</key><string>ScreenPilotBrand-v2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$app_dir/Contents/Resources/DisplayBridge"
codesign --force --sign - "$app_dir/Contents/Resources/DisplayConnection"
codesign --force --sign - "$app_dir/Contents/Resources/ConnectionGuard"
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
printf 'Built: %s\n' "$app_dir"
