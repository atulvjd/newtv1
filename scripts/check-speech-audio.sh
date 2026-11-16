#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/newtv1-speech-check.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
# Synthesize to a file; this does not play audio or open the microphone.
say -r 170 -o "$check_dir/spoken.aiff" "Newt, open Calculator and then tell me what the weather looks like tomorrow."
swiftc -O -parse-as-library -module-cache-path /tmp/newtv1-swift-cache \
    Sources/Newtv1Core/SpeechEndpoint.swift Sources/Newtv1/SpeechAudioCapture.swift \
    Tests/SpeechAudio/main.swift -o "$check_dir/checks"
"$check_dir/checks" "$check_dir/spoken.aiff"
