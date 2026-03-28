# Claude Code Awake

A plugin that prevents your computer from sleeping during Claude Code sessions.

## Problem

During long-running operations with Claude Code (code analysis, running tests, etc.), when the screen turns off, the computer goes to sleep and Claude Code stops working. This plugin solves this problem using macOS's `caffeinate` command.

## How It Works

The plugin integrates with Claude Code's hook system:

1. **When a message is sent**: The `caffeinate` command starts and keeps the computer awake
2. **When the agent finishes responding**: `caffeinate` is stopped
3. **When the session ends**: Cleanup is performed and `caffeinate` is terminated

Each session manages its own `caffeinate` process, so there are no issues with multiple sessions.

## Platform Support

- ✅ macOS (caffeinate)
- ❌ Linux (could be added in the future with `systemd-inhibit`)
- ❌ Windows (could be added in the future with `powercfg`)

## Installation

### 1. Download the Plugin

```bash
git clone https://github.com/yakupyigit/claude-code-awake.git
cd claude-code-awake
```

### 2. Install to Claude Code

```bash
# Copy the plugin directory to Claude Code's plugin folder
cp -r . ~/.claude/plugins/claude-code-awake/
```

### 3. Activate Hooks

Inside Claude Code:

```
/hooks
```

Verify that the hooks are loaded. You should see these hooks:
- `UserPromptSubmit`: start-caffeinate.sh
- `Stop`: stop-caffeinate.sh
- `SessionEnd`: cleanup-caffeinate.sh

## Usage

The plugin works automatically, no configuration needed. When you send a message, the computer will automatically stay awake.

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

## Technical Details

### PID Management
- Unique PID file per session: `/tmp/claude-code-awake/<session_id>.pid`
- Hooks receive `session_id` from stdin
- Only the relevant session's process is terminated

### Caffeinate Parameters
```bash
caffeinate -i -m -w $PPID
```
- `-i`: Prevents idle sleep
- `-m`: Prevents disk sleep
- `-w $PPID`: Binds to Claude Code's process - automatically stops when Claude Code exits

### Safety Features
The plugin includes multiple safety layers to prevent orphaned caffeinate processes:

1. **Process Binding**: Caffeinate is bound to Claude Code's parent process using `-w $PPID`. If Claude Code crashes or exits unexpectedly, caffeinate automatically terminates.

2. **Hook-based Cleanup**: Normal shutdown triggers the stop hook, ensuring clean termination.

3. **Session-based PID Management**: Each session tracks its own caffeinate process, preventing conflicts between multiple Claude Code instances.

4. **Stale PID Detection**: The start script automatically detects and cleans up stale PID files from previous sessions.

### Hook Timeouts
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
