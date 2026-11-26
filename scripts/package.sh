#!/bin/sh
set -eu
APP=build/Build/Products/Release/ChargeKeeper.app
ID=${APPLE_SIGNING_IDENTITY:-Developer ID Application}
cs() { codesign -f -s "$ID" -o runtime --timestamp "$@"; }

sign_sparkle_helpers_then_app() {
    F=$APP/Contents/Frameworks/Sparkle.framework/Versions/B
    cs "$F/XPCServices/Installer.xpc"
    cs --preserve-metadata=entitlements "$F/XPCServices/Downloader.xpc"
    cs "$F/Autoupdate"
    cs "$F/Updater.app"
    cs "$APP/Contents/Frameworks/Sparkle.framework"
    cs --identifier com.vlor999.jauge.service "$APP/Contents/MacOS/chargekeeperctl"
    cs "$APP"
    codesign --verify --deep --strict "$APP"
}

build_signed_dmg_from_stapled_app() {
    V=$(cat VERSION)
    D=build/dmg
    rm -rf "$D" && mkdir -p "$D"
    cp -R "$APP" "$D/"
    ln -s /Applications "$D/Applications"
    hdiutil create -quiet -volname ChargeKeeper -srcfolder "$D" -ov -format UDZO "build/ChargeKeeper-$V.dmg"
    codesign -f -s "$ID" --timestamp "build/ChargeKeeper-$V.dmg"
    echo "build/ChargeKeeper-$V.dmg"
}

case ${1:-} in
sign) sign_sparkle_helpers_then_app ;;
dmg) build_signed_dmg_from_stapled_app ;;
*) echo "usage: $0 sign|dmg"; exit 1 ;;
esac
