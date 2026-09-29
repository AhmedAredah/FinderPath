#!/bin/zsh
# Builds a universal (Apple silicon + Intel) FinderPath and packages it as dist/FinderPath-<version>.dmg
# for other people to install.
#
# FinderPath isn't signed with an Apple Developer ID, so macOS blocks it the first time it's opened;
# the disk image includes "How to Install.txt" explaining how to open it anyway. Signing with the
# "FinderPath Local Signing" certificate (when present) keeps each release's identity stable, so
# macOS keeps users' permissions when they update.
set -euo pipefail
cd "${0:A:h}/.."

IDENTITY="FinderPath Local Signing"
BUILD=build/release
APP=$BUILD/Build/Products/Release/FinderPath.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" FinderPath/Info.plist)
DMG=dist/FinderPath-$VERSION.dmg

echo "Building FinderPath $VERSION…"
rm -rf $BUILD
if ! output=$(xcodebuild -project FinderPath.xcodeproj -scheme FinderPath -configuration Release \
        -derivedDataPath $BUILD ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build 2>&1); then
    print -r -- "$output" | grep -E "error:" || print -r -- "$output" | tail -20
    exit 1
fi

if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    sign=$IDENTITY
else
    sign=-
    echo "“$IDENTITY” not found; signing ad hoc (users' permissions will reset with each update)."
fi
# Inside out: the extension first, then the app that contains it.
codesign --force --sign "$sign" --entitlements FinderPathSync/FinderPathSync.entitlements \
    $APP/Contents/PlugIns/FinderPathSync.appex
codesign --force --sign "$sign" --entitlements FinderPath/FinderPath.entitlements $APP
codesign --verify --deep --strict $APP
echo "Architectures: $(lipo -archs $APP/Contents/MacOS/FinderPath)"

# Disk image contents: the app, a shortcut to Applications to drag it onto, and instructions.
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
ditto $APP "$staging/FinderPath.app"
ln -s /Applications "$staging/Applications"
sed "s/{{VERSION}}/$VERSION/" scripts/How\ to\ Install.txt > "$staging/How to Install.txt"

mkdir -p dist
rm -f "$DMG" "$staging.dmg"
hdiutil create -volname "FinderPath $VERSION" -srcfolder "$staging" -fs HFS+ -format UDRW -ov \
    "$staging.dmg" >/dev/null

# Lay out the window: app on the left, Applications on the right, instructions below. Cosmetic,
# so a failure (e.g. Terminal not allowed to control Finder) only leaves the default layout.
device=$(hdiutil attach -readwrite -noverify -noautoopen "$staging.dmg" | grep -E '^/dev/' | head -1 | awk '{print $1}')
volume="FinderPath $VERSION"
osascript <<APPLESCRIPT || echo "Couldn't arrange the disk image window; keeping the default layout."
tell application "Finder"
    tell disk "$volume"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, 740, 500}
        set arrangement of icon view options of container window to not arranged
        set icon size of icon view options of container window to 96
        set text size of icon view options of container window to 13
        set position of item "FinderPath.app" of container window to {140, 140}
        set position of item "Applications" of container window to {400, 140}
        set position of item "How to Install.txt" of container window to {270, 290}
        close
    end tell
end tell
APPLESCRIPT
sync
hdiutil detach "$device" -quiet
hdiutil convert "$staging.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$staging.dmg"

echo "Created $DMG ($(du -h "$DMG" | cut -f1))"
echo "SHA-256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
