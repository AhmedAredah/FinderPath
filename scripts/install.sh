#!/bin/zsh
# Builds FinderPath, signs it and installs it in /Applications with the Finder extension enabled.
#
# Signs with the "FinderPath Local Signing" certificate when it is in your keychain, so macOS keeps
# the Accessibility and Automation permissions across rebuilds. Without it the build stays ad hoc
# signed, and macOS treats every rebuild as a new app.
set -euo pipefail
cd "${0:A:h}/.."

IDENTITY="FinderPath Local Signing"
APP=build/Build/Products/Release/FinderPath.app
EXTENSION=$APP/Contents/PlugIns/FinderPathSync.appex

if ! output=$(xcodebuild -project FinderPath.xcodeproj -scheme FinderPath -configuration Release \
        -derivedDataPath build build 2>&1); then
    print -r -- "$output" | grep -E "error:" || print -r -- "$output" | tail -20
    exit 1
fi
echo "Built $APP"

if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    # Inside out: the extension first, then the app that contains it.
    codesign --force --sign "$IDENTITY" --entitlements FinderPathSync/FinderPathSync.entitlements "$EXTENSION"
    codesign --force --sign "$IDENTITY" --entitlements FinderPath/FinderPath.entitlements "$APP"
    echo "Signed with “$IDENTITY”"
else
    echo "“$IDENTITY” not found; keeping the ad hoc signature (permissions reset on every rebuild)."
fi

pkill -x FinderPath || true
pkill -9 -f FinderPathSync.appex || true
ditto "$APP" /Applications/FinderPath.app
pluginkit -a /Applications/FinderPath.app/Contents/PlugIns/FinderPathSync.appex
pluginkit -e use -i com.aredah.FinderPath.FinderPathSync
codesign --verify --deep --strict /Applications/FinderPath.app
echo "Installed /Applications/FinderPath.app"
