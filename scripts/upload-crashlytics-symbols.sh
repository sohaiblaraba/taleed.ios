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

# Detached, so the build never waits on it: inside an archive, upload-symbols can hang with no network activity
# and block Xcode for good, while the same command finishes in seconds outside the build. Its own copy of the
# dSYM, so a clean or a rebuild cannot remove it mid-upload. A clean environment, because upload-symbols crashes
# (segmentation fault) on the build's own variables. Five minutes at most, then it gives up.
LOG_DIR="$HOME/Library/Logs/Taleed"
mkdir -p "$LOG_DIR"
COPY="$(mktemp -d "${TMPDIR:-/tmp}/taleed-dsym.XXXXXX")"
cp -R "${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}" "$COPY/"
cp "$PLIST" "$COPY/GoogleService-Info.plist"
nohup env -i PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" \
  perl -e 'alarm 300; exec @ARGV' "$UPLOAD" -gsp "$COPY/GoogleService-Info.plist" -p ios "$COPY/${DWARF_DSYM_FILE_NAME}" \
  </dev/null >>"$LOG_DIR/dsym-upload.log" 2>&1 &
echo "The dSYM upload runs in the background. Result: $LOG_DIR/dsym-upload.log (or upload it by hand, README)."
