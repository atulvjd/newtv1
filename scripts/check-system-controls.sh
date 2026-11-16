#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/newtv1-system-check.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
# Compile the same backend sources in a standalone fixture without launching the app.
# Core module imports are removed because its relevant sources are compiled in this module.
sed '/^import Newtv1Core$/d' Sources/Newtv1/SystemAudio.swift > "$check_dir/SystemAudio.swift"
sed '/^import Newtv1Core$/d' Sources/Newtv1/SystemControls.swift > "$check_dir/SystemControls.swift"
sed '/^import Newtv1Core$/d' Tests/SystemControls/main.swift > "$check_dir/main.swift"
swiftc -O -parse-as-library -module-cache-path /tmp/newtv1-swift-cache \
    Sources/Newtv1Core/Command.swift Sources/Newtv1Core/SystemCommand.swift Sources/Newtv1Core/AudioDeviceMatch.swift \
    "$check_dir/SystemAudio.swift" "$check_dir/SystemControls.swift" "$check_dir/main.swift" -o "$check_dir/checks"
"$check_dir/checks"
