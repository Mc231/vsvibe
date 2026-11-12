#!/bin/bash
# =============================================================================
# tools/sonar_scan.sh: scan SonarQube project `vsvibe` and wait for the
# "VSVibe strict" quality gate.
#
#   tools/sonar_scan.sh
#
# Needs build/ci/result.xcresult and build/ci/dd (run tools/test.sh first).
#
# * Fails closed: with SONAR_REQUIRED=1 (the default) an unreachable server or a
#   missing token fails the run. SONAR_REQUIRED=0 skips with a warning instead.
# * One retry on a scanner/server infrastructure error (HTTP 5xx, timeout,
#   cancelled background task). A failed gate is never retried.
#
# Environment:
#   SONAR_HOST_URL   default http://localhost:9000
#   SONAR_TOKEN      analysis token; else `shared.sonar_token` from
#                    .secrets/sonar.local.json (written by sonar_setup.py)
#   SONAR_REQUIRED   1 (default) fail closed, 0 skip when Sonar is unavailable
#   SONAR_SCANNER    scanner executable (default: sonar-scanner)
#
# Exit codes: 0 gate passed (or skipped), 1 gate/scan failed, 2 bad arguments.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_URL="${SONAR_HOST_URL:-http://localhost:9000}"
REQUIRED="${SONAR_REQUIRED:-1}"
SCANNER="${SONAR_SCANNER:-sonar-scanner}"
PROJECT="vsvibe"

case "${1:-}" in
  "") ;;
  -h | --help)
    sed -n '3,23p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "error: unexpected argument '$1'" >&2
    exit 2
    ;;
esac

summary() {
  echo "sonar $PROJECT: $1"
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    echo "- sonar $PROJECT: $1" >>"$GITHUB_STEP_SUMMARY"
  fi
}

unavailable() {
  if [[ "$REQUIRED" == "0" ]]; then
    summary "skipped: $1 (SONAR_REQUIRED=0)"
    exit 0
  fi
  summary "FAILED: $1 (SONAR_REQUIRED=1, fail closed)"
  exit 1
}

if [[ -z "${SONAR_TOKEN:-}" && -f "$ROOT/.secrets/sonar.local.json" ]]; then
  SONAR_TOKEN="$(python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1]))["shared"]["sonar_token"],end="")' "$ROOT/.secrets/sonar.local.json")"
fi
[[ -n "${SONAR_TOKEN:-}" ]] || unavailable "no SONAR_TOKEN"
export SONAR_TOKEN

status="$(curl -s -m 5 "$HOST_URL/api/system/status" || true)"
grep -Eq '"status"[[:space:]]*:[[:space:]]*"UP"' <<<"$status" || unavailable "SonarQube unreachable or not UP at $HOST_URL"

[[ -d "$ROOT/build/ci/result.xcresult" ]] || { summary "FAILED: build/ci/result.xcresult missing (run tools/test.sh)"; exit 1; }

VERSION="$(sed -n 's/.*CFBundleShortVersionString: *"\(.*\)".*/\1/p' "$ROOT/project.yml" | head -1)"

WORK="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/sonar_scan.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# classify <log> <exit>: pass | gate | infra | error
classify() {
  if [[ "$2" == "0" ]]; then
    echo pass
  elif grep -q 'QUALITY GATE STATUS: FAILED' "$1"; then
    echo gate
  elif grep -Eqi 'HTTP[^0-9]*5[0-9]{2}|status(code)?[^0-9]*5[0-9]{2}|timed out|timeout|SocketTimeoutException|CANCELL?ED|Connection (refused|reset)' "$1"; then
    echo infra
  else
    echo error
  fi
}

run_scan() {
  (cd "$ROOT" && "$SCANNER" \
    -Dsonar.host.url="$HOST_URL" \
    -Dsonar.projectVersion="${VERSION:-0}" \
    -Dsonar.scm.revision="$(git rev-parse HEAD)" \
    -Dsonar.qualitygate.wait=true) >"$1" 2>&1
}

for attempt in 1 2; do
  log="$WORK/scan.$attempt.log"
  echo "→ sonar $PROJECT: scan (attempt $attempt)…"
  code=0
  run_scan "$log" || code=$?
  cat "$log"
  outcome="$(classify "$log" "$code")"
  case "$outcome" in
    pass)
      summary "quality gate passed"
      exit 0
      ;;
    gate)
      summary "FAILED: quality gate ERROR (not retried)"
      exit 1
      ;;
    error)
      summary "FAILED: scanner error (exit $code; not retried)"
      exit 1
      ;;
    infra)
      [[ "$attempt" == "1" ]] && echo "→ sonar $PROJECT: infrastructure error, retrying once"
      ;;
  esac
done
summary "FAILED: infrastructure error twice"
exit 1
