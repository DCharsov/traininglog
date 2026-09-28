#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  if [[ -d /Applications/Xcode-26.3.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-26.3.app/Contents/Developer
  else
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  fi
fi
project_path="$repo_dir/apps/watch/TrainingLogWatch.xcodeproj"
# Keep signing products outside iCloud/Documents: File Provider may add
# com.apple.FinderInfo, which codesign rejects on application bundles.
derived_path="${WATCH_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/TrainingLogWatch}"

if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
  echo 'Full Xcode is required. Set DEVELOPER_DIR to its Contents/Developer directory.' >&2
  exit 1
fi

case "${1:-check}" in
  check)
    xcodebuild -version
    xcodebuild -showsdks
    xcodebuild -project "$project_path" -scheme TrainingLogWatch -showdestinations
    ;;
  simulator-build)
    xcodebuild -project "$project_path" -scheme TrainingLogWatch -configuration Debug \
      -destination 'generic/platform=watchOS Simulator' -derivedDataPath "$derived_path" \
      CODE_SIGNING_ALLOWED=NO build
    ;;
  device-build|device-install)
    if [[ -z "${2:-}" ]]; then
      echo 'Pass an actual watch destination ID from the check command.' >&2
      exit 2
    fi
    xcodebuild -project "$project_path" -scheme TrainingLogWatch -configuration Debug \
      -destination "id=$2" -derivedDataPath "$derived_path" \
      -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
    if [[ "$1" == device-install ]]; then
      xcrun devicectl --timeout 120 device install app --device "$2" \
        "$derived_path/Build/Products/Debug-watchos/TrainingLogWatch Watch App.app"
      xcrun devicectl --timeout 30 device process launch --device "$2" \
        --terminate-existing ru.dcharsov.TrainingLogWatch.watchkitapp
    fi
    ;;
  *)
    echo 'Usage: bash scripts/watch-install.sh [check|simulator-build|device-build WATCH_DESTINATION_ID|device-install WATCH_DESTINATION_ID]' >&2
    exit 2
    ;;
esac

# devicectl install + launch verified with Xcode 26.3 / Series 8 / watchOS 26.6.
# Retention across reinstall is a separate stage-0 check, not implied by build.
