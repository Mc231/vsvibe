#!/bin/bash
# Strict lint: every SwiftLint rule (.swiftlint.yml), warnings are errors.
#
#   tools/lint.sh            # lint only
#   tools/lint.sh --analyze  # also `swiftlint analyze` (needs build/ci/xcodebuild.log
#                            # from a clean build: run tools/test.sh first)
set -euo pipefail
cd "$(dirname "$0")/.."

swiftlint lint --strict --quiet

if [[ "${1:-}" == "--analyze" ]]; then
  LOG="build/ci/xcodebuild.log"
  [[ -f "$LOG" ]] || { echo "error: $LOG missing; run tools/test.sh first" >&2; exit 1; }
  swiftlint analyze --strict --quiet --compiler-log-path "$LOG"
fi
echo "lint: OK"
