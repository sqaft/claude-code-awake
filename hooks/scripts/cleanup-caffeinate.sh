#!/bin/bash

# Constants
readonly PID_DIR="/tmp/claude-code-awake"
readonly SESSION_ID="global"
readonly PID_FILE="$PID_DIR/$SESSION_ID.pid"

# Run cleanup in background
(
  if [ ! -f "$PID_FILE" ]; then
    exit 0
  fi

  PID=$(cat "$PID_FILE" 2>/dev/null)

  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null
    # Show success notification only in local development mode (no .claude in path)
    if [[ "$CLAUDE_PLUGIN_ROOT" != *"/.claude/"* ]]; then
      osascript -e 'display notification "Oturum sonlandı!" with title "Claude Code Awake"' >/dev/null 2>&1 &
    fi
  fi

  rm -f "$PID_FILE" 2>/dev/null
) >/dev/null 2>&1 &

exit 0
