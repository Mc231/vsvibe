/// The bash script `HookInstaller` writes to `~/.vsvibe/hooks/claude-notify.sh`.
/// Claude runs it for every registered hook event with the event name as `$1`
/// and the hook's JSON payload on stdin; it appends one `HookEvent` line to
/// `~/.vsvibe/events.jsonl`. Runs under macOS `/bin/bash` 3.2; `python3` is
/// optional (without it, `message` and `sessionId` are empty).
///
/// Version history (the installed copy is outdated when it differs from
/// `contents`, see `HookInstaller.isScriptCurrent(at:)`):
/// - v1: `event`, `projectDir`, `ts`, `message`.
/// - v2: adds `paneId` (`VSVIBE_PANE_ID`) and `sessionId` (payload `session_id`).
internal enum HookScript {
    internal static let version = 2

    internal static let contents: String = #"""
#!/usr/bin/env bash
# Installed by VSVibe — appends a JSON line per Claude hook event.
# id: vsvibe:claude-notify
# version: 2
set -uo pipefail

EVENT="${1:-Unknown}"
EVENTS_FILE="${HOME}/.vsvibe/events.jsonl"
mkdir -p "$(dirname "$EVENTS_FILE")"

TS=$(date +%s)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${PWD}}"
PANE_ID="${VSVIBE_PANE_ID:-}"
PAYLOAD=$(cat 2>/dev/null || true)

esc() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e ':a;N;$!ba;s/\n/\\n/g' -e 's/\t/\\t/g' -e 's/\r/\\r/g'
}

# JSON string literals for the payload's message and session_id; "" when
# python3 is missing or the payload is not a JSON object.
MSG_JSON='""'
SESSION_JSON='""'
if [ -n "$PAYLOAD" ] && command -v python3 >/dev/null 2>&1; then
  PARSED=$(printf '%s' "$PAYLOAD" | python3 -c 'import sys,json
try:
  d=json.loads(sys.stdin.read())
  print(json.dumps(str(d.get("message") or "")))
  print(json.dumps(str(d.get("session_id") or "")))
except Exception:
  pass' 2>/dev/null || true)
  FIRST=$(printf '%s\n' "$PARSED" | sed -n 1p)
  SECOND=$(printf '%s\n' "$PARSED" | sed -n 2p)
  case "$FIRST" in \"*\") MSG_JSON="$FIRST" ;; esac
  case "$SECOND" in \"*\") SESSION_JSON="$SECOND" ;; esac
fi

ESC_PROJECT=$(esc "$PROJECT_DIR")
ESC_PANE=$(esc "$PANE_ID")

LINE="{\"event\":\"${EVENT}\",\"projectDir\":\"${ESC_PROJECT}\",\"ts\":${TS},\"message\":${MSG_JSON}"
LINE="${LINE},\"paneId\":\"${ESC_PANE}\",\"sessionId\":${SESSION_JSON}}"
printf '%s\n' "$LINE" >> "$EVENTS_FILE"

exit 0
"""#
}
