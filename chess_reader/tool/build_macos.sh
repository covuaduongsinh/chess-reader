#!/usr/bin/env bash
# Builds the macOS app and packages it into a distributable .dmg.
#
# Run on macOS (not Windows) with Flutter + Xcode installed:
#   tool/build_macos.sh
#
# Output: dist/chess_reader-<version>-macos.dmg
#
# Notes:
# - Uses only macOS built-ins (hdiutil); no extra tools to install.
# - The .app is unsigned (no paid Apple Developer account needed). On first
#   launch macOS Gatekeeper will warn — right-click the app → Open, or run
#   `xattr -dr com.apple.quarantine /Applications/chess_reader.app`.
# - The engine uses a bundled/installed Stockfish; if analysis is unavailable,
#   `brew install stockfish` provides one.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION=$(grep '^version:' pubspec.yaml | sed -E 's/version:[[:space:]]*//' | cut -d'+' -f1)
APP="build/macos/Build/Products/Release/chess_reader.app"
DIST="dist"
DMG="$DIST/chess_reader-${VERSION}-macos.dmg"

echo "Building Chess Reader ${VERSION} for macOS..."
flutter build macos --release

if [ ! -d "$APP" ]; then
  echo "error: $APP not found after build" >&2
  exit 1
fi

mkdir -p "$DIST"
rm -f "$DMG"

# Stage the .app alongside an /Applications symlink for drag-to-install.
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Chess Reader" -srcfolder "$STAGE" \
  -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "Created $DMG"
