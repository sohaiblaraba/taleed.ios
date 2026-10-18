#!/usr/bin/env bash
# Regenerates the TaleedAPI Swift package from api/openapi.json.
#
# Usage:
#   scripts/generate-api.sh                  # generate from api/openapi.json
#   scripts/generate-api.sh --from ../taleed # copy the contract from the backend repo first
#
# Requires openapi-generator (brew install openapi-generator). Never edit the
# generated code by hand; wrap it in the app instead.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPEC="$ROOT/api/openapi.json"
OUT="$ROOT/TaleedAPI"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)
      BACKEND="${2:?--from needs the path of the backend repository}"
      cp "$BACKEND/docs/mobile/openapi.json" "$SPEC"
      echo "Copied the contract from $BACKEND/docs/mobile/openapi.json"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

command -v openapi-generator >/dev/null || {
  echo "openapi-generator is missing: brew install openapi-generator" >&2
  exit 1
}

rm -rf "$OUT"
openapi-generator generate -i "$SPEC" -g swift6 -o "$OUT" \
  --additional-properties=projectName=TaleedAPI,enumUnknownDefaultCase=true,responseAs=AsyncAwait

# The generator also writes files that the Swift package does not need.
rm -rf "$OUT/.openapi-generator-ignore" "$OUT/git_push.sh" "$OUT/.travis.yml" \
  "$OUT/Cartfile" "$OUT/TaleedAPI.podspec" "$OUT/project.yml" "$OUT/docs" "$OUT/README.md"

echo "Generated $OUT from $SPEC ($(openapi-generator version))"
