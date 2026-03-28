#!/bin/bash

# Constants
readonly PID_DIR="/tmp/claude-code-awake"
readonly SESSION_ID="global"
readonly PID_FILE="$PID_DIR/$SESSION_ID.pid"

# Check if PID file exists
if [ ! -f "$PID_FILE" ]; then
  exit 0
fi

# Read PID
PID=$(cat "$PID_FILE" 2>/dev/null)

# Kill process if it's running
if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
  kill "$PID" 2>/dev/null
  # Show success notification only in local development mode (no .claude in path)
  if [[ "$CLAUDE_PLUGIN_ROOT" != *"/.claude/"* ]]; then
    osascript -e 'display notification "Caffeinate durduruldu!" with title "Claude Code Awake"' >/dev/null 2>&1 &
  fi
fi

# Remove PID file
rm -f "$PID_FILE" 2>/dev/null

exit 0
