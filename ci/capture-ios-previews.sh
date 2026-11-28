#!/usr/bin/env bash
# Optional, bounded by its CI step timeout. Capture the simulator already used by tests.
set -euo pipefail
HQ_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HQ_RESULTS="${HQ_RESULTS_DIR:-$HQ_REPO_ROOT/ios/HeadQuarter/DerivedData}"
HQ_APP_BUNDLE="$HQ_RESULTS/Build/Products/Debug-iphonesimulator/HeadQuarter.app"
HQ_APP_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$HQ_APP_BUNDLE/Info.plist")"
if [[ -z "${HQ_SIMULATOR_UDID:-}" ]]; then
  HQ_SIMULATOR_UDID="$(xcrun simctl list devices available --json | python3 -c 'import json,sys; d=json.load(sys.stdin); phones=[v for a in d["devices"].values() for v in a if "iPhone" in v["name"]]; print(next((v["udid"] for v in phones if v["state"]=="Booted"), phones[0]["udid"]))')"
fi
mkdir -p "$HQ_RESULTS/previews"
echo "Capturing actual app on Simulator $HQ_SIMULATOR_UDID"
xcrun simctl bootstatus "$HQ_SIMULATOR_UDID" -b
xcrun simctl install "$HQ_SIMULATOR_UDID" "$HQ_APP_BUNDLE"
xcrun simctl ui "$HQ_SIMULATOR_UDID" appearance light
xcrun simctl launch "$HQ_SIMULATOR_UDID" "$HQ_APP_IDENTIFIER"
sleep 3
xcrun simctl io "$HQ_SIMULATOR_UDID" screenshot "$HQ_RESULTS/previews/overview-light.png"
xcrun simctl ui "$HQ_SIMULATOR_UDID" appearance dark
sleep 2
xcrun simctl io "$HQ_SIMULATOR_UDID" screenshot "$HQ_RESULTS/previews/overview-dark.png"
