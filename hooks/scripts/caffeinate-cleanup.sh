#!/bin/bash

source "$(dirname "$0")/common.sh"

SESSION_ID="$(read_session_id)"
PID_FILE="$(pid_file_for "$SESSION_ID")"

# Run cleanup in background
(
	if [ -f "$PID_FILE" ]; then
		PID=$(cat "$PID_FILE" 2>/dev/null)

		if is_our_caffeinate "$PID"; then
			kill "$PID" 2>/dev/null

			notify "Oturum sonlandı!"
		fi

		rm -f "$PID_FILE" 2>/dev/null
	fi

	# Sweep stale PID files left behind by other sessions whose
	# caffeinate process (or the session itself) has already died,
	# so /tmp/claude-code-awake doesn't accumulate dead entries.
	if [ -d "$PID_DIR" ]; then
		for stale_file in "$PID_DIR"/*.pid; do
			[ -e "$stale_file" ] || continue
			stale_pid=$(cat "$stale_file" 2>/dev/null)
			if ! is_our_caffeinate "$stale_pid"; then
				rm -f "$stale_file" 2>/dev/null
			fi
		done
	fi
) >/dev/null 2>&1 &

exit 0
