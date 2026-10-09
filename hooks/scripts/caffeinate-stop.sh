#!/bin/bash

source "$(dirname "$0")/common.sh"

SESSION_ID="$(read_session_id)"
CLAUDE=$(claude_pid)

# Stop only the per-turn caffeinate. The session-wide one (remote control,
# /always-awake) and the `claude rc` server one live in separate PID files.
if kill_caffeinate "$(pid_file_for "$SESSION_ID")"; then
	notify "Caffeinate durduruldu!"
fi

ensure_persist_if_needed "$CLAUDE"

exit 0
