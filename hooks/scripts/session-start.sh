#!/bin/bash

source "$(dirname "$0")/common.sh"

# Drain the hook payload; it isn't needed here.
cat >/dev/null 2>&1

CLAUDE=$(claude_pid)

# Session spawned by `claude rc`: keep the Mac awake for as long as the
# rc server itself runs, not just this session.
if RC_PID=$(rc_server_pid "$CLAUDE"); then
	ensure_caffeinate "$(rc_pid_file_for "$RC_PID")" "$RC_PID" -s &&
		notify "Remote control sunucusu için caffeinate başlatıldı!"
	exit 0
fi

# `claude --remote-control`: keep awake for the whole session.
if is_remote_control_session "$CLAUDE"; then
	ensure_caffeinate "$(persist_pid_file_for "$CLAUDE")" "$CLAUDE" -s &&
		notify "Remote control oturumu için caffeinate başlatıldı!"
fi

exit 0
