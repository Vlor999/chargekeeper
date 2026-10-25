#!/bin/sh
# Release packaging. CI runs: package.sh sign → notarize + staple the app → package.sh dmg → notarize + staple the dmg.
#   package.sh sign   re-sign Sparkle's nested helpers, then the app (Developer ID, hardened runtime, timestamp)
#   package.sh dmg    build/Jauge-<version>.dmg from the (stapled) app, signed
set -eu
APP=build/Build/Products/Release/Jauge.app
ID=${APPLE_SIGNING_IDENTITY:-Developer ID Application}
cs() { codesign -f -s "$ID" -o runtime --timestamp "$@"; }

case ${1:-} in
sign)
    F=$APP/Contents/Frameworks/Sparkle.framework/Versions/B
    cs "$F/XPCServices/Installer.xpc"
    cs --preserve-metadata=entitlements "$F/XPCServices/Downloader.xpc"
    cs "$F/Autoupdate"
    cs "$F/Updater.app"
    cs "$APP/Contents/Frameworks/Sparkle.framework"
    cs --identifier com.vlor999.jauge.service "$APP/Contents/MacOS/jaugectl"
    cs "$APP"
    codesign --verify --deep --strict "$APP"
    ;;
dmg)
    V=$(cat VERSION)
    D=build/dmg
    rm -rf "$D" && mkdir -p "$D"
    cp -R "$APP" "$D/"
    ln -s /Applications "$D/Applications"
    hdiutil create -quiet -volname Jauge -srcfolder "$D" -ov -format UDZO "build/Jauge-$V.dmg"
    codesign -f -s "$ID" --timestamp "build/Jauge-$V.dmg"
    echo "build/Jauge-$V.dmg"
    ;;
*) echo "usage: $0 sign|dmg"; exit 1 ;;
esac
