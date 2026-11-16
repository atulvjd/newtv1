#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
extension_id="${1:-}"
browser_scope="${2:-all}"
requested_app="${3:-${NEWTV1_APP_PATH:-}}"
case "$browser_scope" in all|brave|chrome|edge|arc|vivaldi|chromium) ;; *) echo "Choose all, brave, chrome, edge, arc, vivaldi, or chromium." >&2; exit 1 ;; esac
if [[ ! "$extension_id" =~ ^[a-p]{32}$ ]]; then
    echo "Usage: bash scripts/install-browser-host.sh EXTENSION_ID [BROWSER] [APP_PATH]" >&2
    echo "Load browser-extension unpacked in your Chromium browser, then copy its extension ID." >&2
    exit 1
fi
if [[ -n "$requested_app" ]]; then
    app_path="$requested_app"
elif [[ -d "$PWD/dist/Newtv1.app" ]]; then
    app_path="$PWD/dist/Newtv1.app"
elif [[ -d "/Applications/Newtv1.app" ]]; then
    app_path="/Applications/Newtv1.app"
else
    app_path="$HOME/Applications/Newtv1.app"
fi
host_path="$app_path/Contents/MacOS/Newtv1BrowserHost"
if [[ ! -x "$host_path" ]]; then
    echo "Newtv1BrowserHost was not found in: $app_path" >&2
    echo "Install Newtv1.app first, or supply its path as the third argument." >&2
    exit 1
fi
# User-run installation, scoped to this extension's exact origin.
python3 - "$extension_id" "$host_path" "$browser_scope" <<'PY'
import json, pathlib, shutil, sys
extension_id, executable, scope = sys.argv[1:]
# Browsers can be unable to inspect/launch helpers inside protected Desktop folders.
# Install an unchanged signed helper at a stable per-user application-support path.
helper_directory = pathlib.Path.home() / "Library/Application Support/Newtv1/NativeHost"
helper_directory.mkdir(parents=True, exist_ok=True, mode=0o700)
helper = helper_directory / "Newtv1BrowserHost"
shutil.copy2(executable, helper)
helper.chmod(0o700)
executable = str(helper)
manifest = {"name": "dev.newtv1.browser", "description": "Newtv1 local page preview receiver", "path": executable, "type": "stdio", "allowed_origins": [f"chrome-extension://{extension_id}/"]}
folders = {"chrome": ["Google/Chrome", "Google/Chrome Beta"], "edge": ["Microsoft Edge"], "brave": ["BraveSoftware/Brave-Browser", "Google/Chrome"], "arc": ["Arc/User Data"], "vivaldi": ["Vivaldi"], "chromium": ["Chromium"]}
# Brave's macOS delegate overrides native-host lookup to Google/Chrome.
for browser in ([item for group in folders.values() for item in group] if scope == "all" else folders[scope]):
    root = pathlib.Path.home() / "Library/Application Support" / browser
    if not root.exists() and not (scope == "brave" and browser == "Google/Chrome"):
        continue
    directory = root / "NativeMessagingHosts"
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / "dev.newtv1.browser.json"
    target.write_text(json.dumps(manifest, indent=2))
    target.chmod(0o600)
    print(f"Installed {target}")
PY
