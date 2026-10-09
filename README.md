# Claude Code Awake

A plugin that prevents your computer from sleeping during Claude Code sessions, including Remote Control sessions that wait for your phone.

## Problem

During long-running operations with Claude Code (code analysis, running tests, etc.), when the screen turns off, the computer goes to sleep and Claude Code stops working. This plugin solves this problem using macOS's `caffeinate` command.

The same happens with [Remote Control](https://code.claude.com/docs/en/remote-control): a session that is idle and waiting for a message from your phone does nothing, so the Mac goes to sleep and the connection drops. The plugin keeps the Mac awake for the whole life of such sessions.

## How It Works

The plugin integrates with Claude Code's hook system:

1. **When a message is sent**: The `caffeinate` command starts and keeps the computer awake
2. **When the agent finishes responding**: `caffeinate` is stopped
3. **When the session ends**: Cleanup is performed and `caffeinate` is terminated

Each session manages its own `caffeinate` process, so there are no issues with multiple sessions.

On top of that, Remote Control sessions and sessions where you ran `/always-awake` also keep the Mac awake **between** messages (see below).

## Remote Control

The plugin detects Remote Control automatically, however you start it:

| How you start it | What happens |
|---|---|
| `claude rc` (`claude remote-control`) | Starts one `caffeinate` bound to the `claude rc` server. It stays on as long as the server runs, even when no session is open. |
| `claude --remote-control` | Stays awake for the whole session, from the moment it starts. |
| `/remote-control` inside a session | Stays awake from your **next message** on. Slash commands don't trigger hooks, so run `/always-awake enable` as well if you won't send a message first. |

These use `caffeinate -s`, which only works **while the power adapter is connected**. On battery nothing is held, so a Mac you carry around still sleeps normally.

## `/always-awake`

Keeps the Mac awake for the current session only, until the session ends or you turn it off.

```
/always-awake          # toggle
/always-awake enable
/always-awake disable
```

If the Mac is on battery when you enable it, the command tells you it has no effect until the adapter is connected.

## Lid Behavior

- **Power adapter connected**: `caffeinate -s` also keeps the Mac awake with the lid closed (display off).
- **On battery**: closing the lid always sleeps the Mac. This is intentional so a laptop in a bag never stays awake.

The plugin does not use `pmset disablesleep`: it needs `sudo`, and if cleanup ever failed the Mac would never sleep again.

## Platform Support

- ✅ macOS (caffeinate)
- ❌ Linux (could be added in the future with `systemd-inhibit`)
- ❌ Windows (could be added in the future with `powercfg`)

## Installation

This plugin is available through the [Claude Code Marketplace](https://github.com/sqaft/claude-code-marketplace).

Inside Claude Code:

```
/plugin marketplace add sqaft/claude-code-marketplace
/plugin install claude-code-awake@sqaft-claude-marketplace
```

### Verify Installation

Check that the hooks are loaded:

```
/hooks
```

You should see these hooks:
- `SessionStart`: session-start.sh
- `UserPromptSubmit`: caffeinate-start.sh
- `Stop`: caffeinate-stop.sh
- `SessionEnd`: caffeinate-cleanup.sh

and the `/always-awake` command.

## Usage

The plugin works automatically, no configuration needed. When you send a message, the computer will automatically stay awake, and Remote Control sessions stay awake while they wait. Use `/always-awake` to opt a single session in manually.

### Control Commands

```bash
# Show running caffeinate processes
ps aux | grep caffeinate

# Check PID files
ls -la /tmp/claude-code-awake/

# View hook outputs (inside Claude Code)
Ctrl+O  # Verbose mode
```

## Test Scenarios

### 1. Normal Flow
```
1. Send a message in Claude Code
2. Check the process with `ps aux | grep caffeinate`
3. Let the agent finish responding
4. Verify the process has stopped
```

### 2. Multiple Sessions
```
1. Open Claude Code in two terminals
2. Send messages in both
3. Verify each session has its own caffeinate process
4. Close one session, see that the other is unaffected
```

### 3. Rapid Messages
```
1. Send several messages in quick succession
2. Verify only one caffeinate process is running
```

### 4. Remote Control
```
1. Connect the power adapter
2. Run `claude rc`, `claude --remote-control`, or `/remote-control` and send a message
3. Wait until the agent has finished responding
4. Verify with `pmset -g assertions` that caffeinate still holds PreventSystemSleep
5. Close the lid, send a message from your phone, and check that it is answered
6. Exit; verify the caffeinate process is gone
```

### 5. /always-awake
```
1. Run `/always-awake` in a plain session, send a message and let it finish
2. Verify caffeinate is still running
3. Run `/always-awake` again (or `disable`) and verify it stops
```

## Technical Details

### PID Management
Three independent kinds of `caffeinate` process, each with its own file in `/tmp/claude-code-awake/`:

| Kind | File | Started by | Stopped by |
|---|---|---|---|
| Turn | `<session_id>.pid` | `UserPromptSubmit` | `Stop`, `SessionEnd` |
| Session | `persist-<claude_pid>.pid` | Remote Control detected, `/always-awake` | `SessionEnd`, `/always-awake disable` |
| `claude rc` server | `rc-<server_pid>.pid` | `SessionStart` of a session spawned by `claude rc` | Only when the server exits |

- Hooks receive `session_id` from stdin
- Only the relevant session's process is terminated
- `/always-awake` state is a flag file, `always-<claude_pid>.flag`, so it only applies to that session

### Remote Control Detection
- `claude rc`: the session's parent process is `claude rc` / `claude remote-control`
- `claude --remote-control`: the session's command line contains `--remote-control`
- `/remote-control`: Claude Code sets `CLAUDE_CODE_BRIDGE_SESSION_ID` in the environment of later hooks

### Caffeinate Parameters
```bash
caffeinate -i -m -w <claude pid>   # per turn
caffeinate -s -w <claude pid>      # Remote Control / /always-awake
caffeinate -s -w <claude rc pid>   # claude rc server
```
- `-i`: Prevents idle sleep
- `-m`: Prevents disk sleep
- `-s`: Prevents system sleep, only while on AC power (also covers a closed lid)
- `-w <pid>`: Binds to a process - caffeinate automatically stops when it exits

### Safety Features
The plugin includes multiple safety layers to prevent orphaned caffeinate processes:

1. **Process Binding**: Caffeinate is bound to the Claude Code process (`$CLAUDE_PID`, or the nearest `claude` ancestor) using `-w`. If Claude Code crashes or exits unexpectedly, caffeinate automatically terminates.

2. **Hook-based Cleanup**: Normal shutdown triggers the stop hook, ensuring clean termination.

3. **Session-based PID Management**: The session's `session_id` is read from the hook JSON payload on stdin (see `hooks/scripts/common.sh`), so each session uses its own PID file (`/tmp/claude-code-awake/<session_id>.pid`) and only ever starts, stops, or cleans up its own caffeinate process — running multiple Claude Code sessions in parallel no longer causes one session's `Stop` hook to kill another session's caffeinate.

4. **Stale PID Detection**: The start script automatically detects and cleans up stale PID files from previous sessions. `SessionEnd` also sweeps any stale PID files left behind by other dead sessions.

5. **PID Reuse Protection**: Before treating a PID as "our caffeinate" (to skip starting a new one, or to kill it), the scripts verify via `ps` that the process is actually named `caffeinate`, not just that the PID is alive. This avoids acting on an unrelated process if the original PID was recycled by the OS.

### Hook Timeouts
- `SessionStart`: 5 seconds
- `UserPromptSubmit`: 5 seconds
- `Stop`: 5 seconds
- `SessionEnd`: 2 seconds (runs in background)

## Troubleshooting

### Hooks not working
```bash
# Check if hooks are loaded
/hooks

# See detailed output with verbose mode
Ctrl+O
```

### Caffeinate won't stop
```bash
# Stop manually
pkill caffeinate

# Clean up PID files
rm -rf /tmp/claude-code-awake/
```

### Stale PID files
The plugin automatically cleans up stale PID files. For manual cleanup:
```bash
rm -rf /tmp/claude-code-awake/
```

## License

MIT

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## Author

Yakup Yigit
