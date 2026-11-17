#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/.build"
DIST="$ROOT/dist"
IDENTITY="${CODESIGN_IDENTITY:--}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/App/Info.plist")
mkdir -p "$BUILD" "$DIST"
xcodebuild -project "$ROOT/Daylight.xcodeproj" -scheme Daylight \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath "$BUILD/DerivedData" CODE_SIGNING_ALLOWED=NO build
STAGE="$(mktemp -d "$BUILD/package.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/root/Applications/Daily.app"
mkdir -p "$STAGE/root/Applications"
ditto "$BUILD/DerivedData/Build/Products/Release/Daylight.app" "$APP"
codesign --force --sign "$IDENTITY" --entitlements "$ROOT/Widget/Widget.entitlements" \
    "$APP/Contents/PlugIns/DaylightWidget.appex"
codesign --force --sign "$IDENTITY" --entitlements "$ROOT/App/App.entitlements" "$APP"
codesign --verify --deep --strict "$APP"
lipo "$APP/Contents/MacOS/Daylight" -verify_arch x86_64
lipo "$APP/Contents/MacOS/Daylight" -verify_arch arm64
lipo "$APP/Contents/PlugIns/DaylightWidget.appex/Contents/MacOS/DaylightWidget" -verify_arch x86_64
lipo "$APP/Contents/PlugIns/DaylightWidget.appex/Contents/MacOS/DaylightWidget" -verify_arch arm64
pkgbuild --analyze --root "$STAGE/root" "$STAGE/components.plist"
index=0
while /usr/libexec/PlistBuddy -c "Print :$index" "$STAGE/components.plist" >/dev/null 2>&1; do
    /usr/libexec/PlistBuddy -c "Set :$index:BundleIsRelocatable false" "$STAGE/components.plist"
    /usr/libexec/PlistBuddy -c "Set :$index:BundleOverwriteAction upgrade" "$STAGE/components.plist"
    /usr/libexec/PlistBuddy -c "Set :$index:BundleIsVersionChecked true" "$STAGE/components.plist"
    index=$((index + 1))
done
PKG="$DIST/Daily-macOS-$VERSION.pkg"
ZIP="$DIST/Daily-macOS-$VERSION.zip"
pkgbuild --root "$STAGE/root" --component-plist "$STAGE/components.plist" \
    --identifier com.example.Daylight.installer --version "$VERSION" --install-location / "$PKG"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
(cd "$DIST" && shasum -a 256 "$(basename "$PKG")" "$(basename "$ZIP")" > SHA256SUMS.txt)
printf '\nBuilt macOS %s:\n%s\n%s\n' "$VERSION" "$PKG" "$ZIP"
