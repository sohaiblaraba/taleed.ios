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

# Handed to launchd and run after the build, never during it. In an archive this script runs before Xcode writes
# the dSYM: the file is still an empty placeholder, and upload-symbols hangs on it, which blocked the archive for
# good. So the job waits (ten minutes at most) until the dSYM is a valid object file whose size stopped changing,
# copies it (a clean or a rebuild cannot remove it mid-upload), then uploads it with a clean environment
# (upload-symbols crashes on the build's own variables) and a five-minute limit. The build never waits on it. The
# job removes itself at the end; launchd would otherwise start a submitted job again.
LOG_DIR="$HOME/Library/Logs/Taleed"
mkdir -p "$LOG_DIR"
COPY="$(mktemp -d "/tmp/taleed-dsym.XXXXXX")"
cp "$PLIST" "$COPY/GoogleService-Info.plist"
LABEL="app.taleed.dsym-upload.$(basename "$COPY")"
JOB="$COPY/upload.sh"
cat >"$JOB" <<EOF
#!/bin/bash
echo "\$(date '+%F %T') ${DWARF_DSYM_FILE_NAME} (${CONFIGURATION})"
ready=no last=-1
for _ in \$(seq 1 120); do
  if /usr/bin/dwarfdump --uuid "$DWARF" >/dev/null 2>&1; then
    size=\$(/usr/bin/stat -f %z "$DWARF")
    [[ "\$size" == "\$last" ]] && { ready=yes; break; }
    last=\$size
  fi
  sleep 5
done
if [[ \$ready == yes ]]; then
  /bin/cp -R "${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}" "$COPY/"
  /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$HOME" /usr/bin/perl -e 'alarm 300; exec @ARGV' \\
    "$UPLOAD" -gsp "$COPY/GoogleService-Info.plist" -p ios "$COPY/${DWARF_DSYM_FILE_NAME}" </dev/null
  echo "exit \$?"
else
  echo "exit 1: no complete dSYM at $DWARF after ten minutes"
fi
rm -rf "$COPY"
/bin/launchctl remove "$LABEL"
EOF
chmod +x "$JOB"
/bin/launchctl submit -l "$LABEL" -o "$LOG_DIR/dsym-upload.log" -e "$LOG_DIR/dsym-upload.log" -- "$JOB"
echo "The dSYM upload runs in the background ($LABEL). Result: $LOG_DIR/dsym-upload.log (or upload it by hand, README)."
