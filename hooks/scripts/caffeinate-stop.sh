#!/bin/bash

source "$(dirname "$0")/common.sh"

SESSION_ID="$(read_session_id)"
PID_FILE="$(pid_file_for "$SESSION_ID")"

# Check if PID file exists
if [ ! -f "$PID_FILE" ]; then
	exit 0
fi

# Read PID
PID=$(cat "$PID_FILE" 2>/dev/null)

# Kill process if it's running and it's actually our caffeinate
if is_our_caffeinate "$PID"; then
	kill "$PID" 2>/dev/null

	notify "Caffeinate durduruldu!"
fi

# Remove PID file
rm -f "$PID_FILE" 2>/dev/null

exit 0
