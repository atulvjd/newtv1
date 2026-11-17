#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/newtv1-apple-speech.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
# No microphone, provider key, network recognition or Mac commands are used.
# The signed application preserves its existing Speech Recognition permission.
say -r 160 -o "$check_dir/spoken.aiff" "Newt, open Calculator and then tell me the weather tomorrow."
dist/Newtv1.app/Contents/MacOS/Newtv1 --check-apple-speech "$check_dir/spoken.aiff"
