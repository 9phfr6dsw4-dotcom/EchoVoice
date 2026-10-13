#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

APP="dist/EchoVoice.app"
ICONSET="dist/AppIcon.iconset"
VERIFY_DIR="dist/verify-extracted"
ZIP="dist/EchoVoice.zip"
DERIVED=".xcbuild"
PRODUCTS="$DERIVED/Build/Products/Release"
VERSION="0.1.0"
BUILD="1"

fail() {
    echo "error: $*" >&2
    exit 1
}

# Each check names the key that doesn't match, so a failure is never silent.
expect_plist() {
    local actual
    actual="$(/usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist")" || fail "Info.plist has no $2"
    [ "$actual" = "$3" ] || fail "Info.plist $2 is '$actual', expected '$3'"
}

# MLX's GPU code (Metal) is compiled only by Xcode, so the app is built with xcodebuild, not swift build.
xcodebuild build \
    -scheme EchoVoiceApp \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$DERIVED" \
    -skipMacroValidation \
    -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO \
    -quiet || fail "xcodebuild failed; the lines above show the first error."

test -x "$PRODUCTS/EchoVoiceApp" || fail "the built program is missing at $PRODUCTS/EchoVoiceApp"

rm -rf "$APP" "$ICONSET" "$VERIFY_DIR" "$ZIP" "$ZIP.sha256"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
install -m 755 "$PRODUCTS/EchoVoiceApp" "$APP/Contents/MacOS/EchoVoice"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Resource bundles from the packages (including MLX's compiled GPU code) go in Contents/Resources,
# where MLX looks for them next to the program.
bundles=0
while IFS= read -r bundle; do
    cp -R "$bundle" "$APP/Contents/Resources/"
    bundles=$((bundles + 1))
done < <(find "$PRODUCTS" -maxdepth 1 -type d -name '*.bundle' -print)
[ "$bundles" -gt 0 ] || { find "$PRODUCTS" -maxdepth 2 >&2; fail "no resource bundles were built"; }
CMLX_BUNDLE="$APP/Contents/Resources/mlx-swift_Cmlx.bundle"
if [ -z "$(find "$CMLX_BUNDLE" -name default.metallib -size +0 -print -quit 2>/dev/null)" ]; then
    find "$APP/Contents/Resources" -name '*.metallib' >&2 || true
    find "$PRODUCTS" -maxdepth 3 -name '*mlx*' >&2 || true
    fail "MLX's GPU library (default.metallib) is missing from $CMLX_BUNDLE"
fi

swift Scripts/GenerateIcon.swift "$ICONSET" "Resources/AppIcon-1024.png"
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"
cp Resources/AppIcon-1024.png "$APP/Contents/Resources/AppIcon-1024.png"
python3 Scripts/test_icon_package.py "$ROOT_DIR/Resources/AppIcon-1024.png" "$ROOT_DIR/$APP"

plutil -lint "$APP/Contents/Info.plist"
expect_plist "$APP" CFBundleExecutable EchoVoice
expect_plist "$APP" CFBundleName EchoVoice
expect_plist "$APP" LSMinimumSystemVersion 26.0
expect_plist "$APP" CFBundleShortVersionString "$VERSION"
expect_plist "$APP" CFBundleVersion "$BUILD"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

# Verify the exact ZIP people download.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
mkdir -p "$VERIFY_DIR"
ditto -x -k "$ZIP" "$VERIFY_DIR"
EXTRACTED="$VERIFY_DIR/EchoVoice.app"
test -x "$EXTRACTED/Contents/MacOS/EchoVoice" || fail "the program isn't executable inside the ZIP"
[ -n "$(find "$EXTRACTED/Contents/Resources/mlx-swift_Cmlx.bundle" -name default.metallib -size +0 -print -quit 2>/dev/null)" ] || fail "the GPU library is missing inside the ZIP"
python3 Scripts/test_icon_package.py "$ROOT_DIR/Resources/AppIcon-1024.png" "$ROOT_DIR/$EXTRACTED"
expect_plist "$EXTRACTED" CFBundleShortVersionString "$VERSION"
codesign --verify --deep --strict "$EXTRACTED"
file "$EXTRACTED/Contents/MacOS/EchoVoice"
bash Scripts/write-checksum-sidecar.sh "$ZIP"
( cd dist && shasum -a 256 -c EchoVoice.zip.sha256 )
printf 'Verified package: %s\n' "$ZIP"
