#!/bin/bash

# Constants
readonly PID_DIR="/tmp/claude-code-awake"
readonly SESSION_ID="global"
readonly PID_FILE="$PID_DIR/$SESSION_ID.pid"

# Create PID directory
mkdir -p "$PID_DIR" 2>/dev/null

# Check if caffeinate is already running
if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE" 2>/dev/null)
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    exit 0
  fi
  rm -f "$PID_FILE" 2>/dev/null
fi

# Start caffeinate in background with output redirected
# -w $PPID: Claude Code process sonlanınca caffeinate de otomatik durur
caffeinate -i -m -w $PPID >/dev/null 2>&1 &
CAFFEINATE_PID=$!

# Save PID to file
echo "$CAFFEINATE_PID" > "$PID_FILE" 2>/dev/null

# Show success notification only in local development mode (no .claude in path)
if [[ "$CLAUDE_PLUGIN_ROOT" != *"/.claude/"* ]]; then
  osascript -e 'display notification "Caffeinate başlatıldı!" with title "Claude Code Awake"' >/dev/null 2>&1 &
fi

exit 0
