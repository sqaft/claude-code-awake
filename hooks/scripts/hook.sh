#!/bin/bash
# Entry point for every hook event: hook.sh <event>, payload JSON on stdin.
# Each event updates the state described in common.sh, then the hold is
# started or stopped to match it.

source "$(dirname "$0")/common.sh"

EVENT="$1"
PAYLOAD="$(cat 2>/dev/null)"
PAYLOAD_HEAD="${PAYLOAD:0:4096}"
CPID="$(claude_pid)"
SD="$(state_dir "$CPID")"
AGENT="$(payload_agent_id)"
KEY="${AGENT:-main}"

# PostToolUse runs after every tool call, so the tool events leave early
# unless they change something.
tool_event_changes_state() {
	[ -e "$SD/waiting/$KEY" ] && return 0

	if [ -n "$AGENT" ]; then
		[ -e "$SD/agents/$AGENT" ] || return 0
	elif [ "$EVENT" = PostToolUse ] || [ "$EVENT" = PostToolUseFailure ]; then
		[ -e "$SD/turn" ] || return 0
	fi

	[[ $PAYLOAD == *'"backgroundTaskId":"'* ]] && return 0
	[ -n "$CLAUDE_CODE_BRIDGE_SESSION_ID" ] && [ ! -e "$SD/rc" ] && return 0

	return 1
}

mark_agent_running() {
	[ -n "$AGENT" ] || return 0
	[ -e "$SD/agents/$AGENT" ] || set_flag "$SD/agents/$AGENT"
	rm -f "$SD/waiting/$AGENT"
}

case "$EVENT" in
	PostToolUse | PostToolUseFailure | PermissionDenied | ElicitationResult)
		tool_event_changes_state || exit 0
		;;
esac

init_state
lock_dir "$SD" || exit 0

case "$EVENT" in
	SessionStart)
		ensure_watcher
		;;

	UserPromptSubmit)
		if [ -n "$AGENT" ]; then
			mark_agent_running
		else
			set_flag "$SD/turn"
			rm -f "$SD/waiting/main" "$SD/ratelimit"
		fi
		ensure_watcher
		;;

	PermissionRequest | Elicitation)
		# A prompt is shown (tool approval, AskUserQuestion, plan approval,
		# MCP input): this agent waits for the user.
		set_flag "$SD/waiting/$KEY"
		;;

	PostToolUse | PostToolUseFailure | PermissionDenied | ElicitationResult)
		rm -f "$SD/waiting/$KEY"
		if [ -n "$AGENT" ]; then
			mark_agent_running
		elif [ "$EVENT" = PostToolUse ] || [ "$EVENT" = PostToolUseFailure ]; then
			[ -e "$SD/turn" ] || set_flag "$SD/turn"
		fi
		[ "$EVENT" = PostToolUse ] && record_background_launch
		;;

	SubagentStart)
		mark_agent_running
		;;

	SubagentStop)
		if [ -n "$AGENT" ]; then
			rm -f "$SD/agents/$AGENT" "$SD/waiting/$AGENT"
		fi
		record_tasks "$AGENT"
		;;

	TeammateIdle)
		# An idle teammate waits for a message; its next hook marks it
		# running again.
		if [ -n "$AGENT" ]; then
			[ -e "$SD/agents/$AGENT" ] || set_flag "$SD/agents/$AGENT"
			set_flag "$SD/waiting/$AGENT"
		fi
		;;

	Stop)
		rm -f "$SD/turn" "$SD/waiting/main" "$SD/ratelimit"
		record_tasks
		;;

	StopFailure)
		rm -f "$SD/turn" "$SD/waiting/main"
		# A turn stopped by the usage limit continues by itself once the
		# limit resets.
		[ "$(payload_field error)" = rate_limit ] && set_flag "$SD/ratelimit"
		;;

	SessionEnd)
		case "$(payload_field reason)" in
			clear | resume)
				# The process goes on with another session.
				rm -f "$SD/turn" "$SD/ratelimit" "$SD/always" "$SD"/waiting/*
				;;
			*)
				end_session_state
				exit 0
				;;
		esac
		;;
esac

mark_remote_control_from_env
reconcile
unlock_dir "$SD"

# Looking up the process tree is slow on Windows, so it runs after the hook
# has answered.
if [ "$EVENT" = SessionStart ]; then
	(
		detect_remote_control
		if lock_dir "$SD"; then
			reconcile
			unlock_dir "$SD"
		fi
		sweep_stale_state
	) </dev/null >/dev/null 2>&1 &
fi

exit 0
