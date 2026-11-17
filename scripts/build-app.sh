#!/bin/zsh
# Собирает DevCleaner.app (release) в папку build/.
# Полноценный .app нужен, чтобы выдать ему «Полный доступ к диску»
# (для очистки Корзины и бэкапов iOS).
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release

APP="build/DevCleaner.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/DevCleaner" "$APP/Contents/MacOS/DevCleaner"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>DevCleaner</string>
    <key>CFBundleDisplayName</key><string>DevCleaner</string>
    <key>CFBundleIdentifier</key><string>local.devcleaner.app</string>
    <key>CFBundleExecutable</key><string>DevCleaner</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"

echo "Готово: $APP"
echo "Перенести в программы:  cp -R \"$APP\" /Applications/"
