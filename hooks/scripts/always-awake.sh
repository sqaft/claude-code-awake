#!/bin/bash
# Backs the /always-awake slash command.
# Usage: always-awake.sh [enable|disable]   (no argument toggles)
# Keeps the Mac awake (caffeinate -s, on AC power) for the current
# session until it ends or the command is disabled.

source "$(dirname "$0")/common.sh"

ACTION="${1:-toggle}"
CLAUDE=$(claude_pid)
FLAG_FILE="$(always_flag_for "$CLAUDE")"
PERSIST_FILE="$(persist_pid_file_for "$CLAUDE")"

if ! command -v caffeinate >/dev/null 2>&1; then
	echo "always-awake: caffeinate not found. This plugin only supports macOS."
	exit 1
fi

case "$ACTION" in
	enable | disable) ;;
	toggle)
		if [ -f "$FLAG_FILE" ]; then
			ACTION=disable
		else
			ACTION=enable
		fi
		;;
	*)
		echo "Usage: /always-awake [enable|disable]  (no argument toggles)"
		exit 1
		;;
esac

mkdir -p "$PID_DIR" 2>/dev/null

if [ "$ACTION" = "enable" ]; then
	touch "$FLAG_FILE"
	ensure_caffeinate "$PERSIST_FILE" "$CLAUDE" -s
	message="Always-awake enabled: this Mac stays awake until the session ends."
	if ! on_ac_power; then
		message="$message Note: running on battery, so it has no effect until the power adapter is connected."
	fi
	echo "$message"
	exit 0
fi

rm -f "$FLAG_FILE" 2>/dev/null

if is_remote_control_session "$CLAUDE"; then
	echo "Always-awake disabled. Remote control is active, so this session still keeps the Mac awake."
elif rc_server_pid "$CLAUDE" >/dev/null; then
	kill_caffeinate "$PERSIST_FILE"
	echo "Always-awake disabled. The claude rc server still keeps the Mac awake while it runs."
else
	kill_caffeinate "$PERSIST_FILE"
	echo "Always-awake disabled."
fi

exit 0
