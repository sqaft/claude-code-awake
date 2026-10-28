# Claude Code Awake

A plugin that keeps your computer awake while Claude Code agents are working, and for as long as Remote Control is on. Works on macOS, Linux, Windows and WSL.

## Problem

When the screen turns off, the computer goes to sleep and Claude Code stops working. Much of that work goes on after Claude has replied: background subagents, agent teammates, workflows, background shell commands and monitors keep running while the session looks idle.

Remote Control has the same problem: a session that waits for a message from your phone does nothing, so the computer goes to sleep and the connection drops.

## When the Computer Stays Awake

| Situation | Awake |
|---|---|
| The main agent is working on your message | Yes |
| Subagents, agent teammates, workflows, background shell commands, monitors or other background tasks are running, even after Claude has replied | Yes |
| An agent waits for your answer (permission prompt, question, plan approval, MCP input) and nothing else is running | No |
| An agent waits for your answer while another agent or background task keeps working | Yes |
| The usage limit paused a turn that continues by itself when the limit resets | Yes |
| Claude is idle, waiting for your next message | No |
| Remote Control is on | Always |
| `/always-awake` is enabled | Until the session ends |

The computer is kept awake on battery and on AC power alike. See [Platform Support](#platform-support) for what each platform can and cannot prevent.

Each Claude Code process is handled on its own, so several sessions can run side by side.

## Compared with Claude Code's Own Sleep Prevention

Claude Code prevents some sleep by itself: on macOS, an interactive session runs `caffeinate -i` while it is busy and releases it 30 seconds after a prompt starts waiting for an answer, even if other agents are still working. Sessions spawned by `claude rc` are kept awake only while they work, at most one hour at a time. This behavior is undocumented; the table reflects Claude Code 2.1.312. The plugin runs alongside it and does not turn it off.

| Situation | Claude Code | This plugin |
|---|---|---|
| **Interactive session** | | |
| The main agent is working | Yes | Yes |
| An agent waits for your answer and nothing else is running | No | No |
| The main agent has replied, background subagents, teammates or workflows are running | Yes | Yes |
| An agent waits for your answer while another agent or background task keeps working | No | Yes |
| Only background shell commands are running | No | Yes |
| A Monitor or an MCP background task is running | No | Yes |
| The usage limit paused a turn that continues by itself | No | Yes |
| Between the runs of `/loop`, a cron or a scheduled wakeup | No | No (use `/always-awake`) |
| Idle, waiting for your next message | No | No |
| `/always-awake` is enabled | — | Yes |
| **Remote Control** | | |
| A `--remote-control` or `/remote-control` session waits for a message | No | Yes |
| `/remote-control` is on, no message sent since | No | No, until the next hook |
| A `claude rc` server runs with no session open | No | Yes, once the server has started a session |
| A `claude rc` session is working | Yes, at most one hour at a time | Yes |
| **`claude -p` and the Agent SDK** | | |
| The agent is working | No | Yes |
| The turn has ended, background tasks are running | No | Yes |
| **Power and platform** | | |
| On battery | Yes | Yes |
| Lid closed, power adapter connected (macOS) | No | Yes |
| Lid closed, on battery (macOS) | No | No |
| Linux | No | Yes |
| Windows and WSL | No | Yes |

## Remote Control

The plugin detects [Remote Control](https://code.claude.com/docs/en/remote-control) automatically, however you start it, and keeps the computer awake for as long as it is on:

| How you start it | What happens |
|---|---|
| `claude rc` (`claude remote-control`) | Keeps the computer awake for as long as the server runs, even when no session is open. |
| `claude --remote-control` | Keeps the computer awake for the whole session, from the moment it starts. |
| `/remote-control` inside a session | Keeps the computer awake from the next hook on, which is usually your next message. Slash commands don't trigger hooks, so run `/always-awake enable` as well if you won't send a message first. |

`claude rc` is detected when the server starts its first session. By default the server creates one at startup; with `--no-create-session-in-dir` nothing is held until the first session starts.

## `/always-awake`

Keeps the computer awake for the current session only, until the session ends or you turn it off.

```
/always-awake          # toggle
/always-awake enable
/always-awake disable
```

## Platform Support

| Platform | How | Notes |
|---|---|---|
| macOS | `caffeinate -i -m -s` | `-i` prevents idle sleep on battery and AC. `-s` prevents system sleep, which macOS honors only on AC power; with the power adapter connected this also keeps the Mac awake with the lid closed. On battery, closing the lid always sleeps the Mac. |
| Linux | `systemd-inhibit --what=sleep:idle:handle-lid-switch` | Blocks suspend, idle and the lid switch. Needs systemd-logind and permission to take block inhibitors (granted to active local sessions by default). Without `systemd-inhibit` nothing is held. |
| Windows | PowerShell calling `SetThreadExecutionState(ES_SYSTEM_REQUIRED)` | Prevents sleep on battery and AC. Closing the lid still follows the power plan's lid action. The hooks run in Git Bash, which Claude Code uses on Windows; without Git Bash the plugin does nothing. |
| WSL | The Windows method through `powershell.exe` | Keeps the Windows host awake. Needs Windows interop (`powershell.exe` on the `PATH`). |

The plugin does not use `pmset disablesleep` or change power plans: these need administrator rights, and if cleanup ever failed the computer would never sleep again.

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

You should see `hook.sh` on these events: `SessionStart`, `UserPromptSubmit`, `PermissionRequest`, `Elicitation`, `PostToolUse`, `PostToolUseFailure`, `PermissionDenied`, `ElicitationResult`, `SubagentStart`, `SubagentStop`, `TeammateIdle`, `Stop`, `StopFailure` and `SessionEnd`, and the `/always-awake` command.

## Usage

The plugin works automatically, no configuration needed. Use `/always-awake` to keep a single session awake while it is idle.

## How It Works

Every Claude Code process gets one sleep inhibitor, its *hold*, while it has work running, while Remote Control is on, or while `/always-awake` is enabled. A `claude rc` server gets a hold of its own.

### Hook Events

All hooks run `hooks/scripts/hook.sh`, which records what the event says and then starts or stops the hold to match:

| Event | Records |
|---|---|
| `UserPromptSubmit` | The main agent started a turn |
| `PermissionRequest`, `Elicitation` | The main agent or a subagent waits for the user |
| `PostToolUse`, `PostToolUseFailure`, `PermissionDenied`, `ElicitationResult` | The agent got its answer and is working; a background Bash command started |
| `SubagentStart`, `SubagentStop` | A subagent or teammate started or finished |
| `TeammateIdle` | A teammate waits for a message |
| `Stop` | The turn ended; the background tasks still running, from the `background_tasks` field of the payload |
| `StopFailure` | The turn ended with an error; a `rate_limit` error means it continues by itself |
| `SessionStart` | Starts the watcher; detects `--remote-control` and `claude rc` |
| `SessionEnd` | Releases everything (except after `/clear`, when the process goes on) |

Remote Control turned on with `/remote-control` is detected from `CLAUDE_CODE_BRIDGE_SESSION_ID` in the environment of every hook.

### Watcher

Some changes reach no hook: a turn interrupted with Esc or ended by rejecting a prompt has no `Stop`, and a tool approved after a prompt reports `PostToolUse` only when it finishes. A watcher (`hooks/scripts/watch.sh`) runs next to each Claude Code process and, every 15 seconds, reads Claude Code's session status file (`~/.claude/sessions/<pid>.json`, interactive sessions only) to correct the state, repairs the hold if it died, and removes everything once Claude Code exits.

### State

State lives in `/tmp/claude-code-awake-<uid>/` (Git Bash's `/tmp` on Windows):

- `<claude pid>/`: the state of one Claude Code process (`turn`, `agents/`, `waiting/`, `tasks`, `rc`, `always`), its hold (`hold.pid`) and its watcher (`watch.pid`)
- `rc-<server pid>.pid`: the hold of a `claude rc` server

### Safety Features

1. **Process binding**: every hold is bound to the Claude Code process (or the `claude rc` server) and ends by itself when that process exits, even if Claude Code crashes.
2. **No leftover helpers**: the Linux and Windows holds run only while their run file exists, so stopping one never leaves a helper process behind.
3. **PID reuse protection**: before treating a PID as one of its holds, the plugin checks the process (and its run file), not just that the PID is alive.
4. **Stale state cleanup**: the watcher removes a process's state when it exits, and `SessionStart` sweeps state left by processes that are gone.
5. **Never blocks Claude Code**: hook commands end with `exit 0`, so a failing hook can't block a prompt or deny a permission.

### Hook Timeouts

- `SessionEnd`: 2 seconds
- All other events: 5 seconds (process lookups that are slow on Windows run in the background)

## Troubleshooting

### See what keeps the computer awake

```bash
# macOS
pmset -g assertions | grep caffeinate

# Linux
systemd-inhibit --list

# Windows (administrator PowerShell)
powercfg /requests
```

### Inspect the plugin's state

```bash
ls -R /tmp/claude-code-awake-$UID/
```

### Hooks not working

```
/hooks          # check that the hooks are loaded
Ctrl+O          # verbose mode shows hook output
```

### Stop everything manually

```bash
# macOS
pkill -f "caffeinate -i -m -s"

# all platforms: removing the state also stops the Linux and Windows holds
rm -rf /tmp/claude-code-awake-$UID/
```

## Test Scenarios

### 1. Working and idle
```
1. Send a message and check that a hold exists while Claude works (see Troubleshooting)
2. Let Claude finish and check that the hold is gone
```

### 2. Background work
```
1. Ask Claude to start a background subagent or a background shell command that runs for a few minutes
2. After Claude replies, check that the hold is still there
3. When the background work finishes, check that the hold is gone
```

### 3. Waiting for the user
```
1. In manual permission mode, ask Claude to run a command that needs approval
2. While the prompt is shown, check that the hold is gone
3. Approve it and check that the hold is back within about 15 seconds
```

### 4. Interrupt
```
1. Ask Claude to run a long command and press Esc while it runs
2. Check that the hold is gone within about 15 seconds
```

### 5. Remote Control
```
1. Run `claude rc`, `claude --remote-control`, or `/remote-control` and send a message
2. Let Claude finish and check that the hold stays
3. Exit; check that the hold is gone
```

### 6. /always-awake
```
1. Run `/always-awake` in a plain session and check that the hold stays while idle
2. Run `/always-awake` again (or `disable`) and check that it stops
```

## License

MIT

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## Author

Yakup Yigit
