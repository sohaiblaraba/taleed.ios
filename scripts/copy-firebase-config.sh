#!/usr/bin/env bash
# Build phase: copies this build's GoogleService-Info.plist into the app from TALEED_FIREBASE_CONFIG_DIR
# (Config/Base.xcconfig, or Config/Local.xcconfig). The file is never in the repository. Without it the app
# builds and runs with push and crash reporting off.
set -euo pipefail

SOURCE="${TALEED_FIREBASE_CONFIG_DIR:-}/GoogleService-Info.plist"
DESTINATION="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/GoogleService-Info.plist"

if [[ -n "${TALEED_FIREBASE_CONFIG_DIR:-}" && -f "$SOURCE" ]]; then
  bundle_id=$(/usr/libexec/PlistBuddy -c "Print :BUNDLE_ID" "$SOURCE" 2>/dev/null || true)
  if [[ "$bundle_id" != "$PRODUCT_BUNDLE_IDENTIFIER" ]]; then
    echo "error: $SOURCE is for the bundle ID '$bundle_id', not '$PRODUCT_BUNDLE_IDENTIFIER'."
    exit 1
  fi
  cp "$SOURCE" "$DESTINATION"
  echo "Copied $SOURCE"
else
  # A copy from an earlier build must not stay behind.
  rm -f "$DESTINATION"
  echo "warning: No GoogleService-Info.plist in TALEED_FIREBASE_CONFIG_DIR ('${TALEED_FIREBASE_CONFIG_DIR:-}'): push and crash reporting are off in this build."
fi
