#!/bin/sh
# CI: pinned XcodeGen, checked against its sha256 (runs before any signing secret is loaded).
set -eu
V=2.46.0
SHA=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806
D=${RUNNER_TEMP:-/tmp}/xcodegen
curl -fsSL -o "$D.zip" "https://github.com/yonaskolb/XcodeGen/releases/download/$V/xcodegen.zip"
echo "$SHA  $D.zip" | shasum -a 256 -c -
rm -rf "$D" && mkdir -p "$D" && unzip -q "$D.zip" -d "$D"
echo "$D/xcodegen/bin" >> "${GITHUB_PATH:-/dev/null}"
