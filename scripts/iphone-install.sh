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
derived_path="${PHONE_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/TrainingLogPhone}"
project_path="$repo_dir/apps/watch/TrainingLogWatch.xcodeproj"
case "${1:-check}" in
  check) xcodebuild -project "$project_path" -scheme TrainingLogiPhone -showdestinations ;;
  simulator-build)
    xcodebuild -project "$project_path" -scheme TrainingLogiPhone -configuration Debug \
      -destination 'generic/platform=iOS Simulator' -derivedDataPath "$derived_path" CODE_SIGNING_ALLOWED=NO build ;;
  device-build|device-install)
    [[ -n "${2:-}" ]] || { echo 'Pass the physical iPhone destination ID.' >&2; exit 2; }
    xcodebuild -project "$project_path" -scheme TrainingLogiPhone -configuration Debug \
      -destination "id=$2" -derivedDataPath "$derived_path" \
      -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
    bash "$repo_dir/scripts/verify-native-signing.sh" "$derived_path/Build/Products/Debug-iphoneos/TrainingLogWatch.app"
    if [[ "$1" == device-install ]]; then
      xcrun devicectl device install app --timeout 60 --device "$2" "$derived_path/Build/Products/Debug-iphoneos/TrainingLogWatch.app"
      if [[ -n "${3:-}" ]]; then
        xcrun devicectl device install app --timeout 60 --device "$3" "$derived_path/Build/Products/Debug-iphoneos/TrainingLogWatch.app/Watch/TrainingLogWatch Watch App.app"
      fi
      xcrun devicectl device process launch --timeout 30 --device "$2" --terminate-existing ru.dcharsov.TrainingLogWatch
    fi ;;
  *) echo 'Usage: bash scripts/iphone-install.sh [check|simulator-build|device-build IPHONE_ID|device-install IPHONE_ID [WATCH_ID]]' >&2; exit 2 ;;
esac
