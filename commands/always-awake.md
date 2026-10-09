---
description: Keep this Mac awake for the rest of the session (enable, disable, or toggle)
argument-hint: "[enable|disable]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/hooks/scripts/always-awake.sh:*)
disable-model-invocation: true
---

!`"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/always-awake.sh" $ARGUMENTS`

Relay the line above to the user as-is, without adding anything else.
