#!/bin/bash
set -euo pipefail

# Script untuk membungkus MacVolumeMixer menjadi bundle macOS App (.app) resmi
# agar izin Screen & Audio Recording dapat diberikan secara permanen oleh macOS.

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

# Codesign ad-hoc agar macOS mengenali binary dan bundle ID-nya di System Settings
echo "🔏 Menandatangani aplikasi (ad-hoc codesign)..."
codesign --force --deep --sign - "$APP_BUNDLE"

# Pindahkan / buat shortcut ke ~/Applications jika diinginkan
USER_APPS="$HOME/Applications"
mkdir -p "$USER_APPS"
rm -rf "$USER_APPS/$APP_NAME.app"
cp -R "$APP_BUNDLE" "$USER_APPS/$APP_NAME.app"

echo "✅ Berhasil! $APP_NAME.app telah terpasang di: $USER_APPS/$APP_NAME.app"
echo "👉 Anda dapat menjalankannya dengan: open $USER_APPS/$APP_NAME.app"
