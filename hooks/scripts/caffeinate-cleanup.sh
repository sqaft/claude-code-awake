#!/bin/bash

source "$(dirname "$0")/common.sh"

SESSION_ID="$(read_session_id)"
CLAUDE=$(claude_pid)

# Run cleanup in background
(
	stopped=1
	kill_caffeinate "$(pid_file_for "$SESSION_ID")" && stopped=0
	kill_caffeinate "$(persist_pid_file_for "$CLAUDE")" && stopped=0
	rm -f "$(always_flag_for "$CLAUDE")" 2>/dev/null

	# rc-*.pid is left alone on purpose: it belongs to the `claude rc`
	# server and stops by itself (caffeinate -w) when the server exits.

	[ "$stopped" -eq 0 ] && notify "Oturum sonlandı!"

	# Sweep stale files left behind by other sessions whose caffeinate
	# process (or the session itself) has already died, so
	# /tmp/claude-code-awake doesn't accumulate dead entries.
	if [ -d "$PID_DIR" ]; then
		for stale_file in "$PID_DIR"/*.pid; do
			[ -e "$stale_file" ] || continue
			stale_pid=$(cat "$stale_file" 2>/dev/null)
			if ! is_our_caffeinate "$stale_pid"; then
				rm -f "$stale_file" 2>/dev/null
			fi
		done

		for flag_file in "$PID_DIR"/always-*.flag; do
			[ -e "$flag_file" ] || continue
			flag_pid="${flag_file##*/always-}"
			flag_pid="${flag_pid%.flag}"
			if ! is_alive "$flag_pid"; then
				rm -f "$flag_file" 2>/dev/null
			fi
		done
	fi
) >/dev/null 2>&1 &

exit 0
