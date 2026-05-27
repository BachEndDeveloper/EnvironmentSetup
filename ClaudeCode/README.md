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

## Manual steps to finish the restore
1. **Install Claude Code**, then run the Mac setup script (copies the files above).
2. **Reinstall the GSD setup** ("get-shit-done"). `settings.json` wires up several GSD hooks that
   are NOT vendored here (they belong to GSD): `gsd-check-update.js`, `gsd-session-state.sh`,
   `gsd-context-monitor.js`, `gsd-read-injection-scanner.js`, `gsd-phase-boundary.sh`,
   `gsd-prompt-guard.js`, `gsd-read-guard.js`, `gsd-workflow-guard.js`, `gsd-validate-commit.sh`.
   Reinstalling GSD restores these into `~/.claude/hooks/`.
3. **Fix the node path.** The hook commands in `settings.json` use an absolute nvm path
   (`/Users/bach/.nvm/versions/node/vXX.X.X/bin/node`). Update the version to the node you
   installed, or replace the absolute path with `node` (relying on PATH).
4. **Re-enable plugins** (already listed in `settings.json` → `enabledPlugins`):
   - `github@claude-plugins-official`
   - `agent-sdk-dev@claude-plugins-official`

## Security
No tokens or API keys are stored here. If you ever add secrets to `~/.claude/settings.json`
(e.g. under `env`), do **not** copy them into this public repo — template them out first.
