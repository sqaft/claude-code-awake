#!/bin/bash
# Platform layer for the claude-code-awake scripts: process inspection and
# the sleep inhibitor backends. Sourced by common.sh.
#
# Every inhibitor is bound to a watched process and stops by itself when
# that process exits:
#   macos    caffeinate -i -m -s -w <pid>
#            (-i idle sleep on battery and AC, -s system sleep on AC)
#   linux    systemd-inhibit --what=sleep:idle:handle-lid-switch
#   windows  PowerShell holding SetThreadExecutionState(ES_SYSTEM_REQUIRED)
#   wsl      the Windows backend through powershell.exe, since the Windows
#            host is what sleeps

case "$OSTYPE" in
	darwin*) PLATFORM=macos ;;
	msys* | cygwin* | win32*) PLATFORM=windows ;;
	linux*)
		PLATFORM=linux
		if IFS= read -r _kernel 2>/dev/null </proc/version && [[ "$_kernel" == *[Mm]icrosoft* ]]; then
			PLATFORM=wsl
		fi
		;;
	*) PLATFORM=unknown ;;
esac

WIN_SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")/windows"

# Runs a Windows program without MSYS rewriting its /-style arguments.
win_run() {
	MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' "$@"
}

# powershell_script <file>: runs a PowerShell script through
# -EncodedCommand, which needs no path translation and is not subject to
# the execution policy. Scripts read their parameters from the environment.
powershell_script() {
	local encoded

	command -v powershell.exe >/dev/null 2>&1 || return 1
	encoded="$(iconv -f UTF-8 -t UTF-16LE <"$1" 2>/dev/null | base64 | tr -d '\r\n')"
	[ -n "$encoded" ] || return 1

	win_run powershell.exe -NoProfile -NonInteractive -EncodedCommand "$encoded"
}

# native_alive <pid>: whether a process this shell did not start (Claude
# Code, a `claude rc` server) is running. On Windows these are Windows PIDs.
native_alive() {
	case "$1" in '' | *[!0-9]*) return 1 ;; esac

	if [ "$PLATFORM" = windows ]; then
		win_run tasklist /FI "PID eq $1" /NH 2>/dev/null | grep -q "[[:space:]]$1[[:space:]]"
	else
		kill -0 "$1" 2>/dev/null
	fi
}

# proc_name, proc_ppid and proc_cmdline work on macOS, Linux and WSL.
# Windows uses windows_proc_info instead.
proc_name() {
	local name=""

	case "$PLATFORM" in
		macos) name="$(ps -p "$1" -o comm= 2>/dev/null)" ;;
		linux | wsl) IFS= read -r name 2>/dev/null <"/proc/$1/comm" ;;
	esac

	printf '%s' "${name##*/}"
}

proc_ppid() {
	local stat

	case "$PLATFORM" in
		macos) ps -p "$1" -o ppid= 2>/dev/null | tr -d ' ' ;;
		linux | wsl)
			IFS= read -r stat 2>/dev/null <"/proc/$1/stat" || return 1
			# Fields after "(comm)" start with the state, then the parent PID.
			set -- ${stat##*\) }
			printf '%s' "$2"
			;;
	esac
}

proc_cmdline() {
	case "$PLATFORM" in
		macos) ps -p "$1" -o args= 2>/dev/null ;;
		linux | wsl) tr '\0' ' ' 2>/dev/null <"/proc/$1/cmdline" ;;
	esac
}

# windows_proc_info <pid>: prints "<parent pid>\t<command line>\t<parent
# command line>" for a Windows process.
windows_proc_info() {
	(
		export CLAUDE_CODE_AWAKE_PID="$1"
		powershell_script "$WIN_SCRIPT_DIR/proc-info.ps1"
	) | tr -d '\r'
}

# start_inhibitor <pid_file> <watched pid>: starts an inhibitor bound to the
# watched process and records it in <pid_file> as "<pid> <run file|->".
# Returns 1 when this platform has no usable backend.
start_inhibitor() {
	case "$PLATFORM" in
		macos) start_caffeinate "$@" ;;
		linux) start_systemd_inhibit "$@" ;;
		windows | wsl) start_powershell_hold "$@" ;;
		*) return 1 ;;
	esac
}

start_caffeinate() {
	command -v caffeinate >/dev/null 2>&1 || return 1

	caffeinate -i -m -s -w "$2" </dev/null >/dev/null 2>&1 &
	printf '%s -\n' "$!" >"$1"
}

# The Linux and Windows backends keep running only while their run file
# exists, so stopping one never leaves a helper process behind.
new_run_file() {
	local run="$1.$$.$RANDOM.run"

	: >"$run" 2>/dev/null && printf '%s' "$run"
}

start_systemd_inhibit() {
	local run

	command -v systemd-inhibit >/dev/null 2>&1 || return 1
	run="$(new_run_file "$1")" || return 1

	systemd-inhibit --what=sleep:idle:handle-lid-switch --mode=block \
		--who="Claude Code Awake" --why="Claude Code is working" \
		/bin/sh -c 'while [ -e "$1" ] && kill -0 "$2" 2>/dev/null; do sleep 2; done; rm -f "$1"' \
		sh "$run" "$2" </dev/null >/dev/null 2>&1 &
	printf '%s %s\n' "$!" "$run" >"$1"
}

start_powershell_hold() {
	local run ps_watch=0 local_watch=""

	command -v powershell.exe >/dev/null 2>&1 || return 1
	run="$(new_run_file "$1")" || return 1

	# On Windows PowerShell watches the (Windows) PID itself. Under WSL the
	# PID is a Linux one, so the feeding loop watches it.
	if [ "$PLATFORM" = windows ]; then
		ps_watch="$2"
	else
		local_watch="$2"
	fi

	{
		# The heartbeat makes the loop die of SIGPIPE once PowerShell exits;
		# when the loop ends, PowerShell sees its stdin close and exits.
		while [ -e "$run" ] && { [ -z "$local_watch" ] || kill -0 "$local_watch" 2>/dev/null; }; do
			echo
			sleep 1
		done | (
			export CLAUDE_CODE_AWAKE_WATCH_PID="$ps_watch"
			powershell_script "$WIN_SCRIPT_DIR/hold.ps1"
		)
		rm -f "$run"
	} </dev/null >/dev/null 2>&1 &
	printf '%s %s\n' "$!" "$run" >"$1"
}

# inhibitor_alive <pid_file>
inhibitor_alive() {
	local pid run

	read -r pid run 2>/dev/null <"$1" || return 1
	kill -0 "$pid" 2>/dev/null || return 1

	case "$PLATFORM" in
		macos) [ "$(proc_name "$pid")" = caffeinate ] ;;
		*) [ -e "$run" ] ;;
	esac
}

# stop_inhibitor <pid_file>: stops the inhibitor and removes <pid_file>.
# Returns success only if an inhibitor was running.
stop_inhibitor() {
	local pid run running=1

	read -r pid run 2>/dev/null <"$1" || return 1
	inhibitor_alive "$1" && running=0

	case "$PLATFORM" in
		macos)
			[ "$running" -eq 0 ] && kill "$pid" 2>/dev/null
			;;
		linux)
			rm -f "$run"
			[ "$running" -eq 0 ] && [ "$(proc_name "$pid")" = systemd-inhibit ] && kill "$pid" 2>/dev/null
			;;
		*)
			rm -f "$run"
			;;
	esac

	rm -f "$1"
	return $running
}

# Shows a desktop notification, but only in local development (when the
# plugin is not running from an installed ~/.claude/... location). This is
# intentional: end users installing via the marketplace should not see
# these notifications, only the plugin author while testing.
notify() {
	case "$CLAUDE_PLUGIN_ROOT" in
		*/.claude/* | *\\.claude\\*) return 0 ;;
	esac

	case "$PLATFORM" in
		macos)
			osascript -e "display notification \"$1\" with title \"Claude Code Awake\"" </dev/null >/dev/null 2>&1 &
			;;
		linux)
			if command -v notify-send >/dev/null 2>&1; then
				notify-send "Claude Code Awake" "$1" </dev/null >/dev/null 2>&1 &
			fi
			;;
	esac
}
