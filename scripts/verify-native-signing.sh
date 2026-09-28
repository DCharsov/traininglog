#!/bin/bash
# Read-only release gate. Never print provisioning profiles or identity material.
set -euo pipefail
[[ -n "${1:-}" ]] || { echo 'Pass the signed iPhone .app bundle.' >&2; exit 2; }
phone_app="$1"
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
expected_team=$(sed -n -E 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*([A-Za-z0-9]+).*/\1/p' "$repo_dir/apps/watch/Config/Signing.local.xcconfig")
[[ -n "$expected_team" && "$expected_team" != *$'\n'* ]] || { echo 'Cannot determine the configured development team.' >&2; exit 1; }
watch_app="$phone_app/Watch/TrainingLogWatch Watch App.app"
expected_phone='ru.dcharsov.TrainingLogWatch'
expected_watch='ru.dcharsov.TrainingLogWatch.watchkitapp'
phone_identity=''
for target_app in "$phone_app" "$watch_app"; do
  [[ -d "$target_app" ]] || { echo 'Missing native application bundle.' >&2; exit 1; }
  codesign --verify --strict "$target_app"
  bundle_id=$(plutil -extract CFBundleIdentifier raw -o - "$target_app/Info.plist")
  expected_id="$expected_watch"
  [[ "$target_app" != "$phone_app" ]] || expected_id="$expected_phone"
  [[ "$bundle_id" == "$expected_id" ]] || { echo 'Bundle ID changed; refusing replacement install.' >&2; exit 1; }
  entitlements=$(codesign -d --entitlements :- "$target_app" 2>/dev/null)
  team=$(plutil -extract 'com\.apple\.developer\.team-identifier' raw -o - - <<< "$entitlements")
  [[ "$team" == "$expected_team" ]] || { echo 'Signing team differs from the configured Personal Team.' >&2; exit 1; }
  [[ -f "$target_app/embedded.mobileprovision" ]] || { echo 'Missing provisioning profile.' >&2; exit 1; }
  profile=$(security cms -D -i "$target_app/embedded.mobileprovision" 2>/dev/null)
  profile_team=$(plutil -extract TeamIdentifier.0 raw -o - - <<< "$profile")
  [[ "$profile_team" == "$expected_team" ]] || { echo 'Provisioning profile belongs to a different team.' >&2; exit 1; }
  expires=$(plutil -extract ExpirationDate raw -o - - <<< "$profile")
  expires_epoch=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$expires" +%s)
  [[ "$expires_epoch" -gt "$(date +%s)" ]] || { echo 'Provisioning profile has expired; rebuild before updating.' >&2; exit 1; }
  health_enabled=$(plutil -extract 'com\.apple\.developer\.healthkit' raw -o - - <<< "$entitlements")
  [[ "$health_enabled" == 'true' ]] || { echo 'HealthKit signing entitlement is missing.' >&2; exit 1; }
  identity=$(plutil -extract application-identifier raw -o - - <<< "$entitlements")
  if [[ "$target_app" == "$phone_app" ]]; then
    phone_identity="$identity"
  else
    [[ "$identity" == "$phone_identity.watchkitapp" ]] || { echo 'Phone/watch signing identities do not match.' >&2; exit 1; }
    companion=$(plutil -extract WKCompanionAppBundleIdentifier raw -o - "$target_app/Info.plist")
    [[ "$companion" == "$expected_phone" ]] || { echo 'Watch companion does not match iPhone.' >&2; exit 1; }
  fi
done
echo 'Native signing verified: configured team, valid profile dates, existing bundle IDs, matching companion and HealthKit.'
