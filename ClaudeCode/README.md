# Claude Code customizations

Backup of my Claude Code (`~/.claude`) customizations so they can be restored after a reinstall.

## Files

- `settings.json` — my Claude Code config: model (`opus[1m]`), `effortLevel`, enabled plugins, and
  an experimental feature flag in `env`. Contains **no secrets** and **no machine-specific paths**.

## What the Mac setup script does

`01 - Setup Mac Environment.sh` backs up any existing `~/.claude/settings.json` to
`settings.json.backup`, then copies `settings.json` into `~/.claude`.

## No hooks are configured

This config deliberately wires up **no hooks and no statusline**. It previously drove the GSD
("get-shit-done") setup — nine hooks across `SessionStart`, `PreToolUse` and `PostToolUse`, plus a
`gsd-statusline.js` footer. GSD has been removed, so all of that is gone.

If you add a hook later, **vendor the script it calls into this folder and have the setup script
copy it**. The GSD wiring was a standing example of the failure mode: `settings.json` referenced
nine scripts that were never vendored here, so on any fresh machine Claude Code loaded a config
pointing at files that did not exist. Hook failures aren't surfaced prominently, so it looked
configured while doing nothing.

Use `$HOME`-relative paths and a `PATH` lookup for the interpreter (`node`, `bash`), never absolute
paths — Claude Code runs a `command` hook in *shell form* when the entry has no `args` key, so
`/bin/sh` expands `$HOME` at run time.

## Manual steps to finish the restore

1. **Install Claude Code**, then run the Mac setup script (copies the file above).
2. **Re-enable plugins** (already listed in `settings.json` → `enabledPlugins`):
   - `github@claude-plugins-official`
   - `agent-sdk-dev@claude-plugins-official`

## Security

No tokens or API keys are stored here. If you ever add secrets to `~/.claude/settings.json`
(e.g. under `env`), do **not** copy them into this public repo — template them out first. The same
goes for machine-specific paths: use `$HOME` or a `PATH` lookup, never `/Users/<name>/...`.

## Note: this snapshot has drifted

The live `~/.claude/settings.json` on this machine no longer matches what is vendored here — it has
moved on to a different plugin set (the `dotnet-agent-skills` marketplace), a `theme`, and
Supacode's surface-tracking hooks, and it dropped `effortLevel`, `env` and the statusline. Re-capture
this file from a working machine when you next touch it, minus any secrets.
