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
"$binary_dir/Newtv1CoreChecks"
app="dist/Newtv1.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/Newtv1" "$app/Contents/MacOS/Newtv1.next"
mv -f "$app/Contents/MacOS/Newtv1.next" "$app/Contents/MacOS/Newtv1"
cp "$binary_dir/Newtv1BrowserHost" "$app/Contents/MacOS/Newtv1BrowserHost"
codesign --force --sign "${NEWTV1_SIGN_IDENTITY:--}" "$app/Contents/MacOS/Newtv1BrowserHost"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift scripts/make-icon.swift "$app/Contents/Resources/Newtv1.icns"
if [[ -n "${NEWTV1_SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --sign "$NEWTV1_SIGN_IDENTITY" --entitlements Resources/Newtv1.entitlements "$app"
else
    codesign --force --sign - --entitlements Resources/Newtv1.entitlements "$app"
    echo "Development signature: after rebuilding, macOS may require re-adding this app in its Mac control permission pane."
fi
echo "Built $PWD/$app"
