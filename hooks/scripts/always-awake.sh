#!/bin/bash
# Backs the /always-awake slash command.
# Usage: always-awake.sh [enable|disable]   (no argument toggles)
# Keeps this computer awake for the current session until it ends or the
# command is disabled.

source "$(dirname "$0")/common.sh"

ACTION="${1:-toggle}"
CPID="$(claude_pid)"
SD="$(state_dir "$CPID")"

case "$ACTION" in
	enable | disable) ;;
	toggle)
		if [ -e "$SD/always" ]; then
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

init_state
if ! lock_dir "$SD"; then
	echo "always-awake: the plugin state is locked, try again."
	exit 1
fi

if [ "$ACTION" = "enable" ]; then
	set_flag "$SD/always"
	reconcile
	ensure_watcher

	if ! inhibitor_alive "$SD/hold.pid"; then
		rm -f "$SD/always"
		unlock_dir "$SD"
		echo "always-awake: no way to keep this computer awake was found. It needs caffeinate (macOS), systemd-inhibit (Linux) or powershell.exe (Windows, WSL)."
		exit 1
	fi
	unlock_dir "$SD"

	message="Always-awake enabled: this computer stays awake until the session ends."
	if [ "$PLATFORM" = macos ] && ! pmset -g batt 2>/dev/null | grep -q "AC Power"; then
		message="$message On battery, closing the lid still puts the Mac to sleep."
	fi
	echo "$message"
	exit 0
fi

rm -f "$SD/always"
reconcile
unlock_dir "$SD"

if [ -e "$SD/rc" ]; then
	echo "Always-awake disabled. Remote Control is on, so this session still keeps the computer awake."
elif [ "$PLATFORM" != windows ] && inhibitor_alive "$STATE_ROOT/rc-$(proc_ppid "$CPID").pid"; then
	echo "Always-awake disabled. The claude rc server still keeps the computer awake while it runs."
elif inhibitor_alive "$SD/hold.pid"; then
	echo "Always-awake disabled. The computer stays awake until the running work finishes."
else
	echo "Always-awake disabled."
fi

exit 0
