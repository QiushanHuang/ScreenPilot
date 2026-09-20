#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=1.6.3
release_dir="$PWD/dist/release-$version"
app_dir="$release_dir/屏幕管家.app"
mkdir -p "$release_dir"
python3 scripts/package-windows-ready.py
SCREENPILOT_APP_DIR="$app_dir" ./scripts/build-app.sh
cp dist/ScreenPilot-Windows.zip "$release_dir/ScreenPilot-$version-Windows.zip"
cp dist/ScreenPilot-WindowsBridge.zip "$release_dir/ScreenPilot-$version-WindowsBridge-source.zip"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$release_dir/ScreenPilot-$version-macOS-arm64.zip"
staging_dir="$release_dir/dmg-content"
mkdir -p "$staging_dir"
ditto "$app_dir" "$staging_dir/屏幕管家.app"
ln -sfn /Applications "$staging_dir/Applications"
cp README.md "$staging_dir/README.md"
cp LICENSE "$staging_dir/LICENSE.txt"
hdiutil create -volname "ScreenPilot $version" -srcfolder "$staging_dir" -ov -format UDZO "$release_dir/ScreenPilot-$version-macOS-arm64.dmg"
(cd "$release_dir" && shasum -a 256 ScreenPilot-*.zip ScreenPilot-*.dmg > SHA256SUMS.txt)
printf 'Release files: %s\n' "$release_dir"
