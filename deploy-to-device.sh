#!/bin/bash

set -eo pipefail

DEVICE_ID="00008110-001249961E46801E"
BUILD_DIR="$(pwd)/build"
BUNDLE_ID="com.sb.SparkleShare"
PROFILES_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"

# Clean build only if requested: ./deploy-to-device.sh clean
if [ "$1" = "clean" ]; then
  echo "Cleaning build directory..."
  rm -rf "$BUILD_DIR"
fi

# Remove existing provisioning profiles for this app so Xcode generates a fresh one
for p in "$PROFILES_DIR"/*.mobileprovision; do
  [ -f "$p" ] || continue
  APP_ID=$(security cms -D -i "$p" 2>/dev/null | plutil -extract Entitlements.application-identifier raw -o - - 2>/dev/null)
  if [[ "$APP_ID" == *"$BUNDLE_ID" ]]; then
    echo "Removing old profile: $p"
    rm "$p"
  fi
done

# Build for device (incremental)
xcodebuild build \
  -scheme SparkleShare \
  -configuration Debug \
  -destination "platform=iOS,id=$DEVICE_ID" \
  -workspace SparkleShare.xcworkspace \
  -derivedDataPath "$BUILD_DIR" \
  -allowProvisioningUpdates

# Find and deploy the .app bundle
APP_PATH=$(find "$BUILD_DIR" -name "SparkleShare.app" -type d | head -1)

if [ -z "$APP_PATH" ]; then
  echo "Error: SparkleShare.app not found in build output"
  exit 1
fi

echo "Deploying $APP_PATH..."
ios-deploy --bundle "$APP_PATH" --id "$DEVICE_ID"

echo ""
echo "If the app won't launch, trust the certificate on your iPhone:"
echo "  Settings > General > VPN & Device Management > Developer App"
