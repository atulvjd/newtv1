#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
extension_id="${1:-}"
if [[ ! "$extension_id" =~ ^[a-p]{32}$ ]]; then
    echo "Usage: bash scripts/install-browser-host.sh EXTENSION_ID" >&2
    echo "Load browser-extension unpacked in your Chromium browser, then copy its extension ID." >&2
    exit 1
fi
app_path="$PWD/dist/Newtv1.app"
host_path="$app_path/Contents/MacOS/Newtv1BrowserHost"
if [[ ! -x "$host_path" ]]; then
    echo "Build Newtv1 first: bash scripts/build-app.sh" >&2
    exit 1
fi
# User-run installation, scoped to this extension's exact origin.
python3 - "$extension_id" "$host_path" <<'PY'
import json, pathlib, sys
extension_id, executable = sys.argv[1:]
manifest = {"name": "dev.newtv1.browser", "description": "Newtv1 local page preview receiver", "path": executable, "type": "stdio", "allowed_origins": [f"chrome-extension://{extension_id}/"]}
for browser in ["Google/Chrome", "Google/Chrome Beta", "Microsoft Edge", "BraveSoftware/Brave-Browser", "Arc/User Data", "Vivaldi", "Chromium"]:
    root = pathlib.Path.home() / "Library/Application Support" / browser
    if not root.exists():
        continue
    directory = root / "NativeMessagingHosts"
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / "dev.newtv1.browser.json"
    target.write_text(json.dumps(manifest, indent=2))
    target.chmod(0o600)
    print(f"Installed {target}")
PY
