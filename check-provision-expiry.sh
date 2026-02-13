#!/bin/bash
set -eo pipefail

# Check if the SparkleShare provisioning profile is about to expire
# and send a macOS notification if it expires within WARN_DAYS.

WARN_DAYS=1
BUNDLE_ID="com.sb.SparkleShare"
PROFILES_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"

# Find the profile matching our bundle ID with the latest expiry
BEST_PROFILE=""
BEST_EXPIRY_EPOCH=0
for p in "$PROFILES_DIR"/*.mobileprovision; do
  [ -f "$p" ] || continue
  APP_ID=$(security cms -D -i "$p" 2>/dev/null | plutil -extract Entitlements.application-identifier raw -o - - 2>/dev/null)
  if [[ "$APP_ID" == *"$BUNDLE_ID" ]]; then
    P_EXPIRY=$(security cms -D -i "$p" 2>/dev/null | plutil -extract ExpirationDate raw -o - -)
    P_EPOCH=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$P_EXPIRY" +%s 2>/dev/null)
    if [ -n "$P_EPOCH" ] && [ "$P_EPOCH" -gt "$BEST_EXPIRY_EPOCH" ]; then
      BEST_EXPIRY_EPOCH=$P_EPOCH
      BEST_PROFILE="$p"
    fi
  fi
done

if [ -z "$BEST_PROFILE" ]; then
  echo "No provisioning profile found for $BUNDLE_ID"
  exit 1
fi

EXPIRY_EPOCH=$BEST_EXPIRY_EPOCH
NOW_EPOCH=$(date +%s)
SECONDS_LEFT=$(( EXPIRY_EPOCH - NOW_EPOCH ))
DAYS_LEFT=$(( SECONDS_LEFT / 86400 ))

# Machine-readable output for the Mac app
echo "SECONDS_LEFT=$SECONDS_LEFT"
