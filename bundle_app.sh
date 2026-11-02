#!/bin/bash
set -euo pipefail

# Script untuk membungkus MacVolumeMixer menjadi bundle macOS App (.app) resmi
# dengan Designated Requirement permanen agar izin Screen & Audio Recording dapat
# diberikan secara permanen oleh macOS tanpa ter-reset saat rebuild.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="MacVolumeMixer"
BUILD_DIR="$SCRIPT_DIR/.build/release"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🔨 Mengkompilasi MacVolumeMixer versi release..."
cd "$SCRIPT_DIR"
swift build -c release

echo "📦 Membuat struktur bundle $APP_NAME.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Salin binary yang sudah dikompilasi
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

# Salin Info.plist
cp "$SCRIPT_DIR/App/Info.plist" "$CONTENTS_DIR/Info.plist"

# Pastikan designated requirement file tersedia
REQ_FILE="$SCRIPT_DIR/App/designated_requirement.txt"
if [ ! -f "$REQ_FILE" ]; then
    echo 'designated => identifier "com.macvolumemixer.app"' > "$REQ_FILE"
fi

# Codesign dengan Designated Requirement permanen
echo "🔏 Menandatangani aplikasi dengan designated requirement permanen..."
codesign --force --deep --identifier "com.macvolumemixer.app" -r "$REQ_FILE" --sign - "$APP_BUNDLE"

# Pindahkan / buat shortcut ke ~/Applications
USER_APPS="$HOME/Applications"
mkdir -p "$USER_APPS"
rm -rf "$USER_APPS/$APP_NAME.app"
cp -R "$APP_BUNDLE" "$USER_APPS/$APP_NAME.app"

echo "✅ Berhasil! $APP_NAME.app telah terpasang di: $USER_APPS/$APP_NAME.app"
echo "👉 Designated requirement:"
codesign -d -r- "$USER_APPS/$APP_NAME.app"
