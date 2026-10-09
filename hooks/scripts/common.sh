#!/bin/bash
# Shared helpers for claude-code-awake hook scripts.
# Sourced by session-start.sh, caffeinate-start.sh, caffeinate-stop.sh,
# caffeinate-cleanup.sh and always-awake.sh.
#
# Three independent kinds of caffeinate process are managed:
#   - turn:    `caffeinate -i -m`, lives while the agent is responding
#              ($PID_DIR/<session_id>.pid)
#   - persist: `caffeinate -s`, lives for the whole session when remote
#              control or /always-awake is on ($PID_DIR/persist-<claude>.pid)
#   - rc:      `caffeinate -s`, bound to a `claude rc` server process and
#              only stops when that server exits ($PID_DIR/rc-<server>.pid)

readonly PID_DIR="/tmp/claude-code-awake"
readonly DEFAULT_SESSION_ID="global"

# Reads the Claude Code hook JSON payload from stdin and extracts
# `.session_id`. Falls back to DEFAULT_SESSION_ID if stdin is empty,
# unparsable, or the field is missing (keeps the plugin working even
# if Claude Code's hook payload shape changes).
read_session_id() {
	local input raw_id sanitized

	input="$(cat 2>/dev/null)"

	if [ -z "$input" ]; then
		echo "$DEFAULT_SESSION_ID"
		return
	fi

	if command -v jq >/dev/null 2>&1; then
		raw_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
	else
		raw_id="$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
	fi

	if [ -z "$raw_id" ]; then
		echo "$DEFAULT_SESSION_ID"
		return
	fi

	# Sanitize: only allow safe filename characters to avoid path
	# traversal or breaking out of PID_DIR via a crafted session_id.
	sanitized="$(printf '%s' "$raw_id" | tr -cd 'A-Za-z0-9._-')"

	if [ -z "$sanitized" ]; then
		echo "$DEFAULT_SESSION_ID"
		return
	fi

	echo "$sanitized"
}

pid_file_for() {
	echo "$PID_DIR/$1.pid"
}

persist_pid_file_for() {
	echo "$PID_DIR/persist-$1.pid"
}

rc_pid_file_for() {
	echo "$PID_DIR/rc-$1.pid"
}

always_flag_for() {
	echo "$PID_DIR/always-$1.flag"
}

is_alive() {
	[ -n "$1" ] && kill -0 "$1" 2>/dev/null
}

proc_args() {
	ps -p "$1" -o args= 2>/dev/null
}

proc_ppid() {
	ps -p "$1" -o ppid= 2>/dev/null | tr -d ' '
}

# Returns success if $1 is a live PID AND its command name looks like
# caffeinate. Guards against PID reuse causing us to treat an unrelated
# process as "already running" or, worse, kill it.
is_our_caffeinate() {
	local pid="$1"

	if ! is_alive "$pid"; then
		return 1
	fi

	ps -p "$pid" -o comm= 2>/dev/null | grep -q caffeinate
}

# Prints the PID of the Claude Code process this script belongs to.
# Prefers $CLAUDE_PID (set by Claude Code for hooks), then walks up the
# process tree looking for a `claude` executable, then falls back to $PPID.
claude_pid() {
	local pid comm

	if is_alive "$CLAUDE_PID"; then
		echo "$CLAUDE_PID"
		return
	fi

	pid="$PPID"
	for _ in 1 2 3 4 5 6; do
		if [ -z "$pid" ] || [ "$pid" -le 1 ] 2>/dev/null; then
			break
		fi
		comm="$(ps -p "$pid" -o comm= 2>/dev/null)"
		if [ "${comm##*/}" = "claude" ]; then
			echo "$pid"
			return
		fi
		pid="$(proc_ppid "$pid")"
	done

	echo "$PPID"
}

# Prints the PID of the `claude rc` / `claude remote-control` server that
# spawned this session, if any. `claude rc` starts each session as a child
# process, so the server is the parent of the session's claude process.
rc_server_pid() {
	local parent args
	local pattern='(^|/)claude[[:space:]]+(rc|remote-control)([[:space:]]|$)'

	parent="$(proc_ppid "$1")"
	if ! is_alive "$parent"; then
		return 1
	fi

	args="$(proc_args "$parent")"
	if [[ "$args" =~ $pattern ]]; then
		echo "$parent"
		return 0
	fi

	return 1
}

# Returns success if the session was started with --remote-control, or if
# remote control was turned on inside the session (/remote-control), which
# Claude Code signals to hooks via CLAUDE_CODE_BRIDGE_SESSION_ID.
is_remote_control_session() {
	local pattern='[[:space:]]--remote-control([[:space:]=]|$)'

	if [ -n "$CLAUDE_CODE_BRIDGE_SESSION_ID" ]; then
		return 0
	fi

	[[ "$(proc_args "$1")" =~ $pattern ]]
}

on_ac_power() {
	pmset -g batt 2>/dev/null | grep -q "AC Power"
}

# ensure_caffeinate <pid_file> <watch_pid> <caffeinate flags...>
# Starts caffeinate bound to <watch_pid> (-w) unless the one recorded in
# <pid_file> is still running. Returns 1 if caffeinate is unavailable.
ensure_caffeinate() {
	local pid_file="$1" watch_pid="$2" pid
	shift 2

	if ! command -v caffeinate >/dev/null 2>&1; then
		return 1
	fi

	mkdir -p "$PID_DIR" 2>/dev/null

	if [ -f "$pid_file" ]; then
		pid=$(cat "$pid_file" 2>/dev/null)
		if is_our_caffeinate "$pid"; then
			return 0
		fi
		rm -f "$pid_file" 2>/dev/null
	fi

	# -w: caffeinate exits on its own when the watched process exits
	caffeinate "$@" -w "$watch_pid" >/dev/null 2>&1 &
	echo "$!" > "$pid_file" 2>/dev/null

	return 0
}

# kill_caffeinate <pid_file>
# Stops the caffeinate recorded in <pid_file> (if it is really ours) and
# removes the file. Returns success only if a process was stopped.
kill_caffeinate() {
	local pid_file="$1" pid killed=1

	if [ ! -f "$pid_file" ]; then
		return 1
	fi

	pid=$(cat "$pid_file" 2>/dev/null)
	if is_our_caffeinate "$pid"; then
		kill "$pid" 2>/dev/null
		killed=0
	fi

	rm -f "$pid_file" 2>/dev/null

	return $killed
}

# Keeps the session-wide `caffeinate -s` running if remote control or
# /always-awake is active for this session.
ensure_persist_if_needed() {
	local cpid="$1"

	if is_remote_control_session "$cpid" || [ -f "$(always_flag_for "$cpid")" ]; then
		ensure_caffeinate "$(persist_pid_file_for "$cpid")" "$cpid" -s
	fi
}

# Shows a macOS notification, but only in local development (when the
# plugin is not running from an installed ~/.claude/... location). This
# is intentional: end users installing via the marketplace should not
# see these notifications, only the plugin author while testing.
notify() {
	local message="$1"

	if [[ "$CLAUDE_PLUGIN_ROOT" != *"/.claude/"* ]]; then
		osascript -e "display notification \"$message\" with title \"Claude Code Awake\"" >/dev/null 2>&1 &
	fi
}
