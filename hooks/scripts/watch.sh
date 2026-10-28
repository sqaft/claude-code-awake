#!/bin/bash
# Watcher for one Claude Code process: watch.sh <claude pid>. Started by
# hook.sh, runs until that process exits, then removes its state.
#
# Every 15 seconds it repairs the hold and, in interactive sessions, reads
# Claude Code's session status file (sessions/<pid>.json) to catch what no
# hook reports:
#   - a turn interrupted with Esc or ended by rejecting a prompt (no Stop)
#   - a prompt answered while its tool still runs (no PostToolUse yet)
#   - background shells started in a turn that never reached Stop
# The status there is "busy" (main agent or delegated agents working),
# "waiting" (a prompt is shown), "shell" (only background shells run) or
# "idle".

source "$(dirname "$0")/common.sh"

CPID="$1"
SD="$(state_dir "$CPID")"
STATUS_FILE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions/$CPID.json"

# clear_flags_before <epoch> <file>...: removes flags written before <epoch>.
clear_flags_before() {
	local at="$1" flag
	shift

	for flag in "$@"; do
		[ -e "$flag" ] || continue
		[ "$(flag_time "$flag")" -lt "$at" ] && rm -f "$flag"
	done
}

# keep_tasks <awk condition>: keeps the task lines matching the condition
# ($1 id, $2 type, $3 since).
keep_tasks() {
	[ -e "$SD/tasks" ] || return 0
	awk "$1" "$SD/tasks" >"$SD/tasks.new" && mv -f "$SD/tasks.new" "$SD/tasks"
}

apply_session_status() {
	local line="" status at re

	IFS= read -r line 2>/dev/null <"$STATUS_FILE"

	re='"kind"[[:space:]]*:[[:space:]]*"interactive"'
	[[ $line =~ $re ]] || return 0

	re='"status"[[:space:]]*:[[:space:]]*"([a-z]+)"'
	[[ $line =~ $re ]] || return 0
	status="${BASH_REMATCH[1]}"

	re='"statusUpdatedAt"[[:space:]]*:[[:space:]]*([0-9]+)'
	[[ $line =~ $re ]] || return 0
	at=$((BASH_REMATCH[1] / 1000))

	case "$status" in
		idle | shell)
			# No turn, delegated agent or prompt is active since <at>.
			clear_flags_before "$at" "$SD/turn" "$SD"/waiting/* "$SD"/agents/*
			if [ "$status" = idle ]; then
				# No background shell either.
				keep_tasks "!(\$2 == \"shell\" && \$3 < $at)"
			elif ! grep -q ' shell ' "$SD/tasks" 2>/dev/null; then
				printf 'status shell %s\n' "$at" >>"$SD/tasks"
			fi
			;;
		busy)
			# Every prompt shown before <at> has been answered.
			clear_flags_before "$at" "$SD"/waiting/*
			;;
	esac
}

while sleep 15; do
	if ! native_alive "$CPID"; then
		end_session_state keep-watcher
		exit 0
	fi

	[ -d "$SD" ] || exit 0

	NOW="$(date +%s)"
	lock_dir "$SD" || continue
	apply_session_status
	reconcile
	unlock_dir "$SD"
done
