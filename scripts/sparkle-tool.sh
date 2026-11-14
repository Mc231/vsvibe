#!/usr/bin/env bash
#
# Print the path of a Sparkle command-line tool (sign_update, generate_keys,
# generate_appcast, ...) from the Sparkle SPM artifact bundle that Xcode
# downloads into derived data (SourcePackages/artifacts/sparkle/Sparkle/bin).
#
#   scripts/sparkle-tool.sh sign_update [DERIVED_DATA...]
#
# Searches the given derived-data directories, else build/dd-release
# (scripts/build-dmg.sh), build/ci/dd (tools/test.sh) and Xcode's default
# DerivedData. Skips the legacy bin/old_dsa_scripts copies.
# Exit codes: 0 found, 1 not found, 2 bad arguments.
set -euo pipefail

cd "$(dirname "$0")/.."

tool="${1:-}"
if [[ -z "$tool" || "$tool" == */* ]]; then
  echo "usage: $0 TOOL [DERIVED_DATA...]" >&2
  exit 2
fi
shift

if [[ $# -gt 0 ]]; then
  roots=("$@")
else
  roots=(build/dd-release build/ci/dd "$HOME/Library/Developer/Xcode/DerivedData")
fi

for root in "${roots[@]}"; do
  [[ -d "$root" ]] || continue
  found="$(find "$root" -type f -perm -u+x -path "*/artifacts/*/Sparkle/bin/$tool" \
    -not -path '*/old_dsa_scripts/*' 2>/dev/null | head -1)"
  if [[ -n "$found" ]]; then
    echo "$found"
    exit 0
  fi
done

echo "error: Sparkle tool '$tool' not found (resolve packages / build first)" >&2
exit 1
