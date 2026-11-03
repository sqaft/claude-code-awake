# Learnings

## 2026-10-28 — Stop fires while background work is still running
`Stop` fires when the main agent's turn ends, even while background subagents, shells or workflows keep running; stopping the hold there let the computer sleep mid-work. The `Stop` and `SubagentStop` payloads carry a `background_tasks` list (`id`, `type`, `status`) of what is still running, and the agent is re-invoked with a fresh `Stop` when that work finishes.

## 2026-10-28 — Some turn changes reach no hook
A turn interrupted with Esc, or ended by rejecting a permission prompt, gets no `Stop`, and a tool approved after a prompt reports `PostToolUse` only when it finishes. Claude Code's session status file (`~/.claude/sessions/<pid>.json`, interactive sessions only) shows `busy`, `waiting`, `shell` or `idle` with `statusUpdatedAt`, which the watcher uses to catch these.

## 2026-10-28 — Claude Code's own sleep prevention has gaps
Claude Code runs `caffeinate -i -t 300` on macOS in interactive sessions while it is busy, but releases it whenever any prompt waits for an answer, even if other agents keep working, and not at all for background shells or in `claude -p`. A subagent's permission prompt let a Mac sleep while another subagent was mid-request.

## 2026-10-28 — Waiting for the user is visible through PermissionRequest
`PermissionRequest` fires (with `agent_id` for subagents) whenever a prompt is shown, including `AskUserQuestion` and plan approval, but not when auto mode approves a tool silently. The `agent_id` of `SubagentStart`/`SubagentStop` is the same id `background_tasks` uses.

## 2026-10-28 — caffeinate -s does nothing on battery
macOS honors `caffeinate -s` only on AC power, so on battery only `-i` keeps the Mac awake; closing the lid on battery always sleeps it without `pmset disablesleep`.

## 2026-10-28 — Console.In blocks even in its Async methods
In .NET, `[Console]::In.ReadToEndAsync()` runs synchronously, so a PowerShell loop waiting on it never checked whether the watched process had exited. Reading `[Console]::OpenStandardInput()` with `ReadAsync` does not block.

## 2026-10-28 — Hooks on Windows run in Git Bash with a Windows CLAUDE_PID
Claude Code runs hook commands in Git Bash on Windows (PowerShell when Git Bash is missing, where any exit code other than 0 or 2 blocks), and `CLAUDE_PID` is a Windows PID that `kill -0` can't see. Hook commands therefore run `bash "<script>"; exit 0`, and Windows PIDs are checked with `tasklist`.

## 2026-11-04 — A slash command's shell has no CLAUDE_PLUGIN_ROOT
`${CLAUDE_PLUGIN_ROOT}` is substituted into the text of a plugin command, but the variable is not in the environment of its `!` shell, while hooks do get it. Anything that must tell an installed copy from a development copy has to look at the script's own path.

## 2026-11-04 — Large payloads make `${var#*pattern}` quadratic
In bash, `${var#*pattern}` on a Stop payload took 2.3 seconds at 60 KB and would pass the 5 second hook timeout near 100 KB, because `background_tasks` comes after `last_assistant_message`. `[[ $var =~ $re ]]` handles the same string in milliseconds, and `[[ $var == *text* ]]` stays fast at several megabytes.

## 2026-11-04 — Nothing under a shared /tmp can be trusted until its owner is checked
A name like `/tmp/claude-code-awake-<uid>` can be created first by another user, who can then plant pid files and symlinks that the plugin follows or deletes. `mkdir -p` succeeds on such a directory, so the owner and the symlink have to be checked before the first write.
