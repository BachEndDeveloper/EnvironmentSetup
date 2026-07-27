# Claude Code customizations

Backup of my Claude Code (`~/.claude`) customizations so they can be restored after a reinstall.

## Files

- `settings.json` — my Claude Code config: model (`opus[1m]`), `effortLevel`, the
  `dotnet-agent-skills` plugin marketplace, the plugins enabled from it, and an experimental
  feature flag in `env`. Contains **no secrets** and **no machine-specific paths**.

## What the Mac setup script does

`01 - Setup Mac Environment.sh` backs up any existing `~/.claude/settings.json` to
`settings.json.backup`, then copies `settings.json` into `~/.claude`. Claude Code resolves the
declared marketplace and plugins itself on next launch — the same pattern as Pi's declared packages.

## Skills and plugins come from upstream, not from here

Nothing in this folder vendors skill or plugin *content*. Three separate sources feed Claude Code,
and each is owned elsewhere:

| Source | Reaches Claude Code via | Also used by |
| --- | --- | --- |
| [`dotnet/skills`](https://github.com/dotnet/skills) | the `dotnet-agent-skills` marketplace declared in `settings.json` (Claude Code clones it into `~/.claude/plugins/marketplaces/`) | **Pi** — the setup script clones the *same repo* to `~/pi-skills/dotnet-skills` |
| Supacode | Supacode installs its own skills and its surface-tracking hooks when it is installed (Homebrew cask, root `Brewfile`) | — |
| [AI-Skills](https://github.com/BachEndDeveloper/AI-Skills) (private) | `scripts/install-local.sh`, run by the setup script | Pi |

Two consequences worth remembering:

- **`dotnet/skills` is cloned twice on this machine**, once by the setup script for Pi and once by
  Claude Code for the marketplace. They are independent copies at independent commits. That is
  expected, not a bug — but if you change how one is pinned, the other does not follow.
- **Supacode's hooks are deliberately not vendored here.** The live `~/.claude/settings.json` has
  eight `SUPACODE_SURFACE_ID` hooks that Supacode writes itself. Copying them into this repo would
  fight with Supacode on every launch.

## No hooks are configured here

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
2. **Launch Claude Code once** so it fetches the `dotnet-agent-skills` marketplace and installs the
   enabled plugins. Verify with `/plugin`.

## Not captured here, on purpose

The live `~/.claude/settings.json` also carries `theme`, `skipDangerousModePermissionPrompt` and
Supacode's hooks. `theme` is cosmetic, the permission-prompt setting is security-relevant enough to
be an explicit per-machine choice rather than something a setup script turns on silently, and the
hooks belong to Supacode. Add them deliberately if you decide you want them everywhere.

## Security

No tokens or API keys are stored here. If you ever add secrets to `~/.claude/settings.json`
(e.g. under `env`), do **not** copy them into this public repo — template them out first. The same
goes for machine-specific paths: use `$HOME` or a `PATH` lookup, never `/Users/<name>/...`.
