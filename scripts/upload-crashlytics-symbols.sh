#!/usr/bin/env bash
# Build phase: uploads the dSYM to Crashlytics, so crash reports show function names and lines. Only for builds
# that make a dSYM (Release and Staging: DEBUG_INFORMATION_FORMAT = dwarf-with-dsym) and carry
# GoogleService-Info.plist (scripts/copy-firebase-config.sh). Debug skips it.
set -euo pipefail

PLIST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/GoogleService-Info.plist"
DWARF="${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${EXECUTABLE_NAME}"

if [[ "${DEBUG_INFORMATION_FORMAT:-}" != "dwarf-with-dsym" ]]; then
  echo "No dSYM in this build (${DEBUG_INFORMATION_FORMAT:-unset}): nothing to upload."
  exit 0
fi
if [[ ! -f "$PLIST" ]]; then
  echo "No GoogleService-Info.plist in the app: nothing to upload."
  exit 0
fi

# The Crashlytics upload tool of the Firebase package (Swift Package Manager checkout).
UPLOAD="${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols"
if [[ ! -x "$UPLOAD" ]]; then
  echo "warning: Crashlytics' upload-symbols is missing ($UPLOAD): the dSYM was not uploaded."
  exit 0
fi

# The dSYM is written just after linking: wait for it rather than upload half of it.
for _ in $(seq 1 60); do
  [[ -f "$DWARF" ]] && break
  sleep 1
done
if [[ ! -f "$DWARF" ]]; then
  echo "warning: No dSYM at $DWARF: nothing uploaded."
  exit 0
fi

# In the foreground: Crashlytics' run script uploads in the background, and a command-line build can end before
# that upload does, which leaves the crashes unsymbolicated. With a clean environment: upload-symbols crashes
# (segmentation fault) on the build's own variables.
env -i PATH="$PATH" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" "$UPLOAD" -gsp "$PLIST" -p ios "${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}" \
  || echo "warning: The dSYM upload failed: upload it by hand (README) so crashes show function names."
