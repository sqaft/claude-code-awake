# claude-code-awake

**Durum:** Yayında  
**Tür:** Bağımsız kütüphane / ürün

A Claude Code plugin that keeps the computer awake while Claude Code agents are working (main agent, subagents, teammates, workflows, background tasks) and for as long as Remote Control is on. Supports macOS, Linux, Windows (Git Bash) and WSL. Distributed through the `sqaft/claude-code-marketplace` repo. Details: `README.md`; design decisions and Claude Code behavior it relies on: `LEARNINGS.md`.

## Layout

- `hooks/hooks.json` — every hook event runs `bash hooks/scripts/hook.sh <event>; exit 0`
- `hooks/scripts/common.sh` — state and the decision whether to hold
- `hooks/scripts/platform.sh` — process inspection and the inhibitor backends per platform
- `hooks/scripts/watch.sh` — per-process watcher (session status file, cleanup)
- `hooks/scripts/windows/*.ps1` — PowerShell run through `-EncodedCommand`
- `commands/always-awake.md` + `hooks/scripts/always-awake.sh` — the `/always-awake` command

## Testing

There is no automated test suite. Scripts must run on macOS's bash 3.2 (no bash 4 features) and avoid `jq`, `ps` options missing on Linux, and anything Git Bash lacks. Test changes by running `hook.sh` with crafted payloads against a fake `CLAUDE_PID`, and end to end with `claude --plugin-dir <this repo>` while the installed copy is disabled (`--settings '{"enabledPlugins":{"claude-code-awake@sqaft-claude-marketplace":false}}'`). With `--plugin-dir` the plugin shows desktop notifications for every hold change (see `notify` in `platform.sh`).

## Releases

The plugin is versioned in `.claude-plugin/plugin.json`. To release, bump `version` there, commit and push, then update the marketplace (below) and push it.

## Update Together

- `sqaft/claude-code-marketplace` (`../claude-code-marketplace`): in `.claude-plugin/marketplace.json`, the plugin entry's `version` must match `plugin.json` and `metadata.version` is bumped with every plugin release; the plugin's description lives there and in the plugin table of `README.md`.

## Notes

- All code, comments, docs and messages are in English, except the development-only notifications.
- The plugin relies on undocumented Claude Code behavior (`background_tasks` in `Stop`/`SubagentStop` payloads, `~/.claude/sessions/<pid>.json`). When Claude Code changes, check these first; see `LEARNINGS.md`.
