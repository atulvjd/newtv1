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
sign_identity="${NEWTV1_SIGN_IDENTITY:-}"
if [[ -z "$sign_identity" ]]; then
    available_identities="$(security find-identity -v -p codesigning | sed -nE '/"(Apple Development:|Developer ID Application:)/s/^[[:space:]]*[0-9]+\) ([0-9A-F]+).*/\1/p')"
    identity_count="$(printf '%s\n' "$available_identities" | awk 'NF { count++ } END { print count+0 }')"
    if [[ "$identity_count" == "1" ]]; then
        sign_identity="$available_identities"
    fi
fi
sign_identity="${sign_identity:--}"
fingerprint_file=".build/app-package-fingerprint"
package_fingerprint="$(
    shasum -a 256 "$binary_dir/Newtv1" "$binary_dir/Newtv1BrowserHost" Resources/Info.plist Resources/Newtv1.entitlements scripts/make-icon.swift scripts/build-app.sh
    printf '%s\n' "$sign_identity"
)"
if [[ -f "$fingerprint_file" && -d "$app" ]] && [[ "$(cat "$fingerprint_file")" == "$package_fingerprint" ]] && codesign --verify --deep --strict "$app" 2>/dev/null; then
    echo "App inputs are unchanged. Keeping the existing signed app and its permission identity."
    echo "Built $PWD/$app"
    exit 0
fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/Newtv1" "$app/Contents/MacOS/Newtv1.next"
mv -f "$app/Contents/MacOS/Newtv1.next" "$app/Contents/MacOS/Newtv1"
cp "$binary_dir/Newtv1BrowserHost" "$app/Contents/MacOS/Newtv1BrowserHost"
codesign --force --sign "$sign_identity" "$app/Contents/MacOS/Newtv1BrowserHost"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift scripts/make-icon.swift "$app/Contents/Resources/Newtv1.icns"
if [[ "$sign_identity" != "-" ]]; then
    codesign --force --options runtime --sign "$sign_identity" --entitlements Resources/Newtv1.entitlements "$app"
else
    codesign --force --sign - --entitlements Resources/Newtv1.entitlements "$app"
    echo "Development signature: after rebuilding, macOS may require re-adding this app in its Mac control permission pane."
fi
codesign --verify --deep --strict "$app"
printf '%s\n' "$package_fingerprint" > "$fingerprint_file"
echo "Built $PWD/$app"
