#!/bin/bash
# Build + unit-test with coverage, then run the core coverage gate.
#
#   tools/test.sh
#
# Writes build/ci/result.xcresult (tests, coverage, compiler warnings),
# build/ci/dd (derived data incl. the index store Periphery/Sonar read) and
# build/ci/xcodebuild.log (the compiler log `swiftlint analyze` reads).
# Env: COVERAGE_MIN (default 90).
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="build/ci"
rm -rf "$OUT/result.xcresult"
mkdir -p "$OUT"

xcodegen generate

# Clean build so the log contains every compile command (swiftlint analyze).
# Compiler warnings are errors for our targets (project.yml), because the Sonar
# profile imports them as issues.
xcodebuild \
  -project VSVibe.xcodeproj \
  -scheme VSVibe \
  -configuration Debug \
  -derivedDataPath "$OUT/dd" \
  -resultBundlePath "$OUT/result.xcresult" \
  -enableCodeCoverage YES \
  clean test 2>&1 | tee "$OUT/xcodebuild.log" | grep -E '(error|warning):|Test Suite .* (passed|failed)|Executed [0-9]+ tests|\*\* (TEST|BUILD) ' || true

# tee/grep hide xcodebuild's status; the result bundle records it.
if ! grep -q '\*\* TEST SUCCEEDED \*\*' "$OUT/xcodebuild.log"; then
  echo "error: xcodebuild test failed (see $OUT/xcodebuild.log)" >&2
  exit 1
fi

python3 -I tools/check_coverage.py "$OUT/result.xcresult" --min "${COVERAGE_MIN:-90}"
