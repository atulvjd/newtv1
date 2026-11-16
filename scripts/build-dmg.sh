#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${1:-}" == "--skip-build" && "$#" == 1 ]]; then
    : # Package an existing, verified app without replacing its permission identity.
elif [[ "$#" == 0 ]]; then
    bash scripts/build-app.sh
else
    echo "Usage: bash scripts/build-dmg.sh [--skip-build]" >&2
    exit 1
fi

app="$PWD/dist/Newtv1.app"
if [[ ! -d "$app" ]]; then
    echo "Build the app first: bash scripts/build-app.sh" >&2
    exit 1
fi
codesign --verify --deep --strict "$app"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
if [[ ! "$version" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "The app version is not suitable for a release filename." >&2
    exit 1
fi
architectures="$(lipo -archs "$app/Contents/MacOS/Newtv1")"
case "$architectures" in
    arm64) architecture="arm64"; hardware="Apple Silicon (M-series)" ;;
    x86_64) architecture="x86_64"; hardware="Intel" ;;
    *arm64*x86_64*|*x86_64*arm64*) architecture="universal"; hardware="Apple Silicon or Intel" ;;
    *) echo "Unrecognized app architecture: $architectures" >&2; exit 1 ;;
esac

mkdir -p .build dist
work="$(mktemp -d "$PWD/.build/dmg.XXXXXX")"
mountpoint="$work/mounted"
attached=false
cleanup() {
    if [[ "$attached" == true ]]; then
        if ! hdiutil detach "$mountpoint" -quiet; then
            echo "Could not unmount the verification image at $mountpoint; leaving its temporary directory intact." >&2
            return
        fi
    fi
    rm -rf "$work"
}
trap cleanup EXIT

stage="$work/staging"
integration="$stage/Extras/Browser Integration"
mkdir -p "$integration/scripts" "$mountpoint"
ditto "$app" "$stage/Newtv1.app"
ln -s /Applications "$stage/Applications"
ditto browser-extension "$integration/browser-extension"
cp scripts/install-browser-host.sh "$integration/scripts/install-browser-host.sh"
cp docs/DMG_BROWSER_SETUP.txt "$integration/README.txt"
cat > "$stage/Install Newtv1.txt" <<EOF
Newtv1 $version

INSTALL
1. Quit any older Newtv1 copy.
2. Drag Newtv1.app onto the Applications shortcut in this disk image.
3. Open Newtv1 from Applications, then eject this disk image.

Requires macOS 13 or later on $hardware.
Screen previews and visual guidance require macOS 14 or later.

FIRST LAUNCH
Open System Controls to configure Mac control and Screen Recording access.
Microphone, Speech Recognition and Automation permissions are requested when
their corresponding features are used. macOS controls these permissions.

Voice: press Option-Space, speak, then pause for two seconds to send.
Your existing app settings stay on this Mac. Configure an AI provider in
Settings > AI if you want cloud answers and planning. This image includes
no API keys, sign-in tokens, conversation history or other personal settings.

OPTIONAL BROWSER INTEGRATION
See Extras > Browser Integration > README.txt. Copy the integration folder
to a permanent location before loading the extension, so it keeps working
after this disk image is ejected.

DEVELOPMENT BUILD
This release is locally signed, not Apple-notarized. Public distribution
requires Developer ID signing and notarization. macOS may require updating
permissions when you move or replace a development copy.
EOF

# Copy the already-signed app unchanged; do not re-sign it while making a DMG.
codesign --verify --deep --strict "$stage/Newtv1.app"
image_name="Newtv1-$version-$architecture.dmg"
image="$work/$image_name"
hdiutil create -volname "Newtv1 $version" -fs HFS+ -format UDZO -srcfolder "$stage" -ov "$image"
hdiutil verify "$image"
hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$mountpoint" "$image"
attached=true
codesign --verify --deep --strict "$mountpoint/Newtv1.app"
diff -qr "$app" "$mountpoint/Newtv1.app"
if [[ "$(readlink "$mountpoint/Applications")" != "/Applications" ]]; then
    echo "The Applications shortcut did not survive packaging." >&2
    exit 1
fi
test -f "$mountpoint/Install Newtv1.txt"
test -f "$mountpoint/Extras/Browser Integration/browser-extension/manifest.json"
test -f "$mountpoint/Extras/Browser Integration/scripts/install-browser-host.sh"
bash -n "$mountpoint/Extras/Browser Integration/scripts/install-browser-host.sh"
hdiutil detach "$mountpoint" -quiet
attached=false

mv -f "$image" "$PWD/dist/$image_name"
(
    cd dist
    shasum -a 256 "$image_name" > "$image_name.sha256"
)
echo "Created and verified: $PWD/dist/$image_name"
echo "SHA-256: $PWD/dist/$image_name.sha256"
