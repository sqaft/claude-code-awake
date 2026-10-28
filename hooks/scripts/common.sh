#!/bin/bash
# Shared state and decisions for the claude-code-awake scripts. Sourced by
# hook.sh, watch.sh and always-awake.sh.
#
# Each Claude Code process gets one sleep inhibitor, its "hold", for as long
# as any of these is true:
#   - the main agent is running a turn and is not waiting for the user
#   - a subagent or teammate is running and is not waiting for the user
#   - a background task (shell, monitor, workflow, ...) is running
#   - the usage limit paused a turn that will continue on its own
#   - Remote Control is on for the session, or /always-awake is enabled
# A `claude rc` server gets a hold of its own for as long as it runs.
#
# State of one Claude Code process, in $STATE_ROOT/<claude pid>/:
#   turn           the main agent is running a turn
#   ratelimit      the usage limit paused a turn
#   agents/<id>    subagent or teammate <id> is running
#   waiting/<key>  "main" or agent <id> waits for the user to answer
#   tasks          background tasks, one "<id> <type> <since>" per line
#   rc, always     Remote Control is on / /always-awake is enabled
#   hold.pid       the inhibitor (see platform.sh)
#   watch.pid      the watcher (see watch.sh)
# Flag files contain the epoch second they were written.
#
# Callers set CPID (the Claude Code PID) and SD (its state directory), and
# PAYLOAD / PAYLOAD_HEAD when handling a hook payload.

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/platform.sh"

STATE_ROOT="/tmp/claude-code-awake-${UID:-0}"
NOW="$(date +%s)"

# A `claude rc` / `claude remote-control` server command line, and the
# --remote-control flag of an interactive session.
RC_SERVER_PATTERN='(^|[/\\ "])claude(\.exe)?"?[[:space:]]+(rc|remote-control)([[:space:]]|$)'
RC_FLAG_PATTERN='[[:space:]]--remote-control([[:space:]=]|$)'

valid_id() {
	[[ $1 =~ ^[A-Za-z0-9._-]+$ ]]
}

# payload_field <name>: a string field from the start of the payload, where
# the common fields, hook_event_name, tool_name, error, reason and source are.
payload_field() {
	local re="\"$1\":\"([^\"]*)\""

	[[ $PAYLOAD_HEAD =~ $re ]] && printf '%s' "${BASH_REMATCH[1]}"
}

# payload_agent_id: the subagent or teammate the event belongs to, empty
# for the main agent. Read only among the common fields, which come before
# hook_event_name, so a key inside tool_input cannot match.
payload_agent_id() {
	local head="${PAYLOAD_HEAD%%\"hook_event_name\"*}"
	local re='"agent_id":"([A-Za-z0-9._-]+)"'

	[[ $head =~ $re ]] && printf '%s' "${BASH_REMATCH[1]}"
}

# payload_tasks: "<id> <type>" for each running or pending entry of the
# background_tasks field of a Stop or SubagentStop payload.
payload_tasks() {
	local rest="${PAYLOAD#*\"background_tasks\":\[}"
	local re='\{"id":"([^"]*)","type":"([^"]*)","status":"(running|pending)"'

	[ "$rest" != "$PAYLOAD" ] || return 1
	rest="${rest%%\"session_crons\":*}"

	while [[ $rest =~ $re ]]; do
		printf '%s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
		rest="${rest#*"${BASH_REMATCH[0]}"}"
	done
}

# Prints the PID of the Claude Code process this script belongs to.
# Prefers $CLAUDE_PID (set by Claude Code for hooks and commands; a Windows
# PID on Windows), then walks up the process tree looking for a `claude`
# executable, then falls back to $PPID.
claude_pid() {
	local pid="$CLAUDE_PID" name

	case "$pid" in
		'' | *[!0-9]*) ;;
		*)
			printf '%s' "$pid"
			return
			;;
	esac

	pid="$PPID"
	for _ in 1 2 3 4 5 6; do
		case "$pid" in '' | 0 | 1 | *[!0-9]*) break ;; esac
		name="$(proc_name "$pid")"
		if [ "$name" = claude ] || [ "$name" = claude.exe ]; then
			printf '%s' "$pid"
			return
		fi
		pid="$(proc_ppid "$pid")"
	done

	printf '%s' "$PPID"
}

state_dir() {
	printf '%s/%s' "$STATE_ROOT" "$1"
}

init_state() {
	mkdir -p "$SD/agents" "$SD/waiting" 2>/dev/null
}

set_flag() {
	printf '%s\n' "$NOW" >"$1"
}

# flag_time <file>: the epoch second stored in a flag file, 0 if unreadable.
flag_time() {
	local t=0

	read -r t 2>/dev/null <"$1"
	case "$t" in '' | *[!0-9]*) t=0 ;; esac
	printf '%s' "$t"
}

# lock_dir <dir> / unlock_dir <dir>: serialize state changes between hooks
# and the watcher. A lock left behind by a killed process is taken over
# after 3 seconds.
lock_dir() {
	local tries=0

	until mkdir "$1/.lock" 2>/dev/null; do
		tries=$((tries + 1))
		[ "$tries" -eq 30 ] && rm -rf "$1/.lock"
		[ "$tries" -ge 50 ] && return 1
		sleep 0.1
	done
}

unlock_dir() {
	rmdir "$1/.lock" 2>/dev/null
}

work_needed() {
	local agent

	if [ -e "$SD/rc" ] || [ -e "$SD/always" ] || [ -e "$SD/ratelimit" ]; then
		return 0
	fi

	if [ -e "$SD/turn" ] && [ ! -e "$SD/waiting/main" ]; then
		return 0
	fi

	for agent in "$SD"/agents/*; do
		[ -e "$agent" ] || continue
		[ -e "$SD/waiting/${agent##*/}" ] || return 0
	done

	[ -s "$SD/tasks" ]
}

# Starts or stops the hold so that it matches the state.
reconcile() {
	if work_needed; then
		inhibitor_alive "$SD/hold.pid" && return 0
		stop_inhibitor "$SD/hold.pid"
		start_inhibitor "$SD/hold.pid" "$CPID" && notify "Uyku engellendi."
	elif stop_inhibitor "$SD/hold.pid"; then
		notify "Uyku engeli kaldırıldı."
	fi
}

watcher_alive() {
	local pid

	read -r pid 2>/dev/null <"$SD/watch.pid" || return 1
	kill -0 "$pid" 2>/dev/null || return 1

	case "$PLATFORM" in
		macos | linux | wsl) [[ "$(proc_cmdline "$pid")" == *watch.sh* ]] ;;
	esac
}

ensure_watcher() {
	watcher_alive && return 0

	bash "$SCRIPT_DIR/watch.sh" "$CPID" </dev/null >/dev/null 2>&1 &
	printf '%s\n' "$!" >"$SD/watch.pid"
}

# record_tasks [stopping agent id]: replaces the task list with the
# background_tasks of a Stop or SubagentStop payload. Subagents are kept
# under agents/ instead, and teammates are followed through their own hooks.
# Without background_tasks in the payload the list ends up empty.
record_tasks() {
	local exclude="$1" list id type

	list="$(payload_tasks)"
	: >"$SD/tasks.new"

	while read -r id type; do
		valid_id "$id" && [ "$id" != "$exclude" ] || continue
		case "$type" in
			subagent) [ -e "$SD/agents/$id" ] || set_flag "$SD/agents/$id" ;;
			teammate) ;;
			*) printf '%s %s %s\n' "$id" "${type// /_}" "$NOW" >>"$SD/tasks.new" ;;
		esac
	done <<EOF
$list
EOF

	mv -f "$SD/tasks.new" "$SD/tasks"
}

# A background Bash command appears in its PostToolUse right away, so it is
# followed even when the turn ends without a Stop (Esc).
record_background_launch() {
	local re='"backgroundTaskId":"([A-Za-z0-9._-]+)"' id

	[ "$(payload_field tool_name)" = Bash ] || return 0
	[[ $PAYLOAD =~ $re ]] || return 0
	id="${BASH_REMATCH[1]}"

	grep -q "^$id " "$SD/tasks" 2>/dev/null && return 0
	printf '%s shell %s\n' "$id" "$NOW" >>"$SD/tasks"
}

# Remote Control turned on inside the session (/remote-control) shows up in
# the environment of the hooks that run after it.
mark_remote_control_from_env() {
	if [ -n "$CLAUDE_CODE_BRIDGE_SESSION_ID" ] && [ ! -e "$SD/rc" ]; then
		set_flag "$SD/rc"
	fi
}

# Run at SessionStart. Marks sessions started with --remote-control, and
# gives the `claude rc` server that spawned this session a hold of its own
# for as long as the server runs. Slow on Windows (PowerShell), so it is run
# in the background.
detect_remote_control() {
	local info rest parent_pid own parent

	if [ "$PLATFORM" = windows ]; then
		info="$(windows_proc_info "$CPID")"
		parent_pid="${info%%$'\t'*}"
		rest="${info#*$'\t'}"
		own="${rest%%$'\t'*}"
		parent="${rest#*$'\t'}"
	else
		parent_pid="$(proc_ppid "$CPID")"
		own="$(proc_cmdline "$CPID")"
		parent="$(proc_cmdline "$parent_pid")"
	fi

	if [[ $own =~ $RC_FLAG_PATTERN ]] || [ -n "$CLAUDE_CODE_BRIDGE_SESSION_ID" ]; then
		set_flag "$SD/rc"
	fi

	if [[ $parent =~ $RC_SERVER_PATTERN ]]; then
		ensure_rc_server_hold "$parent_pid"
	elif [ "$CLAUDE_CODE_ENVIRONMENT_KIND" = bridge ]; then
		# Spawned by a Remote Control server that could not be identified:
		# keep at least this session awake.
		set_flag "$SD/rc"
	fi
}

ensure_rc_server_hold() {
	local pid_file="$STATE_ROOT/rc-$1.pid"

	case "$1" in '' | *[!0-9]*) return 1 ;; esac
	lock_dir "$STATE_ROOT" || return 1

	if ! inhibitor_alive "$pid_file"; then
		stop_inhibitor "$pid_file"
		start_inhibitor "$pid_file" "$1" &&
			notify "Remote Control sunucusu için uyku engellendi."
	fi

	unlock_dir "$STATE_ROOT"
}

# end_session_state [keep-watcher]: stops the hold and the watcher of this
# Claude Code process and removes its state. A `claude rc` server hold is
# left alone: it stops by itself when the server exits.
end_session_state() {
	local pid

	stop_inhibitor "$SD/hold.pid" && notify "Uyku engeli kaldırıldı."

	if [ "$1" != keep-watcher ] && watcher_alive; then
		read -r pid <"$SD/watch.pid"
		kill "$pid" 2>/dev/null
	fi

	rm -rf "$SD"
}

# Removes the state of Claude Code processes that are gone, and the records
# of `claude rc` server holds that have stopped.
sweep_stale_state() {
	local dir pid pid_file

	for dir in "$STATE_ROOT"/*/; do
		dir="${dir%/}"
		pid="${dir##*/}"
		case "$pid" in '' | *[!0-9]*) continue ;; esac
		[ "$pid" = "$CPID" ] && continue
		native_alive "$pid" && continue
		stop_inhibitor "$dir/hold.pid"
		rm -rf "$dir"
	done

	lock_dir "$STATE_ROOT" || return
	for pid_file in "$STATE_ROOT"/rc-*.pid; do
		[ -e "$pid_file" ] || continue
		inhibitor_alive "$pid_file" || stop_inhibitor "$pid_file"
	done
	unlock_dir "$STATE_ROOT"
}
