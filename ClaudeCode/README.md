# Claude Code customizations

Backup of my Claude Code (`~/.claude`) customizations so they can be restored after a reinstall.

## Files

- `settings.json` — my Claude Code config: model (`opus[1m]`), `effortLevel`, the **statusline
  footer**, the hook wiring, enabled plugins, and an experimental feature flag in `env`.
  Contains **no secrets**.
- `hooks/gsd-statusline.js` — the custom statusline **footer** script referenced by
  `settings.json` (`statusLine.command`).

## What the Mac setup script does

`01 - Setup Mac Environment.sh` backs up any existing `~/.claude/settings.json` to
`settings.json.backup`, then copies `settings.json` and `hooks/gsd-statusline.js` into `~/.claude`.
Afterwards it checks that every hook `settings.json` references actually exists in
`~/.claude/hooks/` and prints a `WARNING` listing any that are missing, plus a warning if `node`
isn't on `PATH`. A missing hook otherwise fails silently at runtime, which is how this config
spent a long time doing nothing at all.

## Paths are deliberately generic

`settings.json` contains **no machine-specific paths**. Hook commands invoke `node` / `bash` from
`PATH` and reference scripts as `"$HOME/.claude/hooks/<name>"`. Claude Code runs a `command` hook
in *shell form* when the entry has no `args` key, so `$HOME` is expanded by `/bin/sh` at run time.
That makes the file portable across machines, users and Node versions.

It previously hardcoded `/Users/bach/...` and a pinned `.nvm/versions/node/v25.9.0/bin/node`, so
every hook silently failed on any other machine or after any Node upgrade. **Don't reintroduce
absolute paths** when refreshing this file from a working machine — re-template them.

## Manual steps to finish the restore

1. **Install Claude Code**, then run the Mac setup script (copies the files above).
2. **Reinstall the GSD setup** ("get-shit-done"). `settings.json` wires up several GSD hooks that
   are NOT vendored here (they belong to GSD): `gsd-check-update.js`, `gsd-session-state.sh`,
   `gsd-context-monitor.js`, `gsd-read-injection-scanner.js`, `gsd-phase-boundary.sh`,
   `gsd-prompt-guard.js`, `gsd-read-guard.js`, `gsd-workflow-guard.js`, `gsd-validate-commit.sh`.
   Reinstalling GSD restores these into `~/.claude/hooks/`. The setup script tells you exactly
   which ones are missing.
3. **Re-enable plugins** (already listed in `settings.json` → `enabledPlugins`):
   - `github@claude-plugins-official`
   - `agent-sdk-dev@claude-plugins-official`

## Security

No tokens or API keys are stored here. If you ever add secrets to `~/.claude/settings.json`
(e.g. under `env`), do **not** copy them into this public repo — template them out first. The same
goes for machine-specific paths: use `$HOME` or a `PATH` lookup, never `/Users/<name>/...`.
