#!/bin/bash
set -eo pipefail

# Check if the SparkleShare provisioning profile is about to expire
# and send a macOS notification if it expires within WARN_DAYS.

WARN_DAYS=1
BUNDLE_ID="com.sb.SparkleShare"
PROFILES_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"

# Find the profile matching our bundle ID
PROFILE=""
for p in "$PROFILES_DIR"/*.mobileprovision; do
  [ -f "$p" ] || continue
  APP_ID=$(security cms -D -i "$p" 2>/dev/null | plutil -extract Entitlements.application-identifier raw -o - - 2>/dev/null)
  if [[ "$APP_ID" == *"$BUNDLE_ID" ]]; then
    PROFILE="$p"
    break
  fi
done

if [ -z "$PROFILE" ]; then
  echo "No provisioning profile found for $BUNDLE_ID"
  exit 1
fi

# Extract expiration date from profile
EXPIRY=$(security cms -D -i "$PROFILE" 2>/dev/null | plutil -extract ExpirationDate raw -o - -)

if [ -z "$EXPIRY" ]; then
  echo "Could not read expiry date from profile"
  exit 1
fi

EXPIRY_EPOCH=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$EXPIRY" +%s 2>/dev/null)
NOW_EPOCH=$(date +%s)
SECONDS_LEFT=$(( EXPIRY_EPOCH - NOW_EPOCH ))
DAYS_LEFT=$(( SECONDS_LEFT / 86400 ))

# Machine-readable output for the Mac app
echo "SECONDS_LEFT=$SECONDS_LEFT"
