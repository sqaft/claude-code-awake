#!/bin/bash

source "$(dirname "$0")/common.sh"

SESSION_ID="$(read_session_id)"
PID_FILE="$(pid_file_for "$SESSION_ID")"

# Create PID directory
mkdir -p "$PID_DIR" 2>/dev/null

# Check if caffeinate is already running for this session
if [ -f "$PID_FILE" ]; then
	PID=$(cat "$PID_FILE" 2>/dev/null)
	if is_our_caffeinate "$PID"; then
		exit 0
	fi
	rm -f "$PID_FILE" 2>/dev/null
fi

# Start caffeinate in background with output redirected
# -w $PPID: Claude Code process sonlanınca caffeinate de otomatik durur
caffeinate -i -m -w $PPID >/dev/null 2>&1 &
CAFFEINATE_PID=$!

# Save PID to file
echo "$CAFFEINATE_PID" > "$PID_FILE" 2>/dev/null

notify "Caffeinate başlatıldı!"

exit 0
