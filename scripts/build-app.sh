#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
if [[ "$configuration" != "release" && "$configuration" != "debug" ]]; then
    echo "Usage: bash scripts/build-app.sh [release|debug]" >&2
    exit 1
fi
swift build -c "$configuration" --scratch-path .build
binary_dir="$(swift build -c "$configuration" --scratch-path .build --show-bin-path)"
app="dist/Vox.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/Vox" "$app/Contents/MacOS/Vox"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift scripts/make-icon.swift "$app/Contents/Resources/Vox.icns"
if [[ -n "${VOX_SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --sign "$VOX_SIGN_IDENTITY" --entitlements Resources/Vox.entitlements "$app"
else
    codesign --force --sign - --entitlements Resources/Vox.entitlements "$app"
fi
echo "Built $PWD/$app"
