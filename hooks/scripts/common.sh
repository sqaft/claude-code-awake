#!/bin/bash
# Shared helpers for claude-code-awake hook scripts.
# Sourced by caffeinate-start.sh, caffeinate-stop.sh, caffeinate-cleanup.sh.

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

# Returns success if $1 is a live PID AND its command name looks like
# caffeinate. Guards against PID reuse causing us to treat an unrelated
# process as "already running" or, worse, kill it.
is_our_caffeinate() {
	local pid="$1"

	if [ -z "$pid" ]; then
		return 1
	fi

	if ! kill -0 "$pid" 2>/dev/null; then
		return 1
	fi

	ps -p "$pid" -o comm= 2>/dev/null | grep -q caffeinate
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
