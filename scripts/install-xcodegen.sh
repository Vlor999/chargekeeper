#!/bin/sh
set -eu
XCODEGEN_VERSION=2.46.0
XCODEGEN_SHA256=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806
D=${RUNNER_TEMP:-/tmp}/xcodegen
curl -fsSL -o "$D.zip" "https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip"
echo "$XCODEGEN_SHA256  $D.zip" | shasum -a 256 -c -
rm -rf "$D" && mkdir -p "$D" && unzip -q "$D.zip" -d "$D"
echo "$D/xcodegen/bin" >> "${GITHUB_PATH:-/dev/null}"
