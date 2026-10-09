#!/bin/bash

source "$(dirname "$0")/common.sh"

SESSION_ID="$(read_session_id)"
CLAUDE=$(claude_pid)

# Covers remote control turned on via /remote-control, whose first
# visible signal is this hook's environment.
ensure_persist_if_needed "$CLAUDE"

PID_FILE="$(pid_file_for "$SESSION_ID")"
if [ -f "$PID_FILE" ] && is_our_caffeinate "$(cat "$PID_FILE" 2>/dev/null)"; then
	exit 0
fi

# -w: caffeinate stops automatically when the Claude Code process exits
ensure_caffeinate "$PID_FILE" "$CLAUDE" -i -m &&
	notify "Caffeinate başlatıldı!"

exit 0
