#!/usr/bin/env bash
# Run on a Mac with Xcode 16.2 or newer. No signing is required for Simulator checks.
set -euo pipefail
HQ_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HQ_PROJECT="$HQ_REPO_ROOT/ios/HeadQuarter/HeadQuarter.xcodeproj"
HQ_RESULTS="${HQ_RESULTS_DIR:-$HQ_REPO_ROOT/ios/HeadQuarter/DerivedData}"
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo 'xcodebuild is unavailable. Install Xcode on macOS and select it with xcode-select.' >&2
  exit 127
fi
xcodebuild -version
xcodebuild -project "$HQ_PROJECT" -scheme HeadQuarter \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$HQ_RESULTS" \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project "$HQ_PROJECT" -scheme HeadQuarterWidgets \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$HQ_RESULTS" \
  CODE_SIGNING_ALLOWED=NO build
if [[ -z "${HQ_SIMULATOR_UDID:-}" ]]; then
  HQ_SIMULATOR_UDID="$(xcrun simctl list devices available --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(v["udid"] for devices in d["devices"].values() for v in devices if v["name"].startswith("iPhone")))')"
fi
xcodebuild -project "$HQ_PROJECT" -scheme HeadQuarter \
  -destination "platform=iOS Simulator,id=$HQ_SIMULATOR_UDID" -derivedDataPath "$HQ_RESULTS" \
  CODE_SIGNING_ALLOWED=NO test
