# Releases: the unit we run

Every piece of software this setup installs is run **from a release, never from the tip of a
branch**. A release is an annotated Git tag `vMAJOR.MINOR.PATCH` on `main`. Machines follow the
**newest release tag** by default, so shipping a change means cutting a release, not editing this
repository.

## How a machine picks a version

| Where | Setting | Meaning |
| --- | --- | --- |
| `MCP/servers.json`, each server's `ref` | `"latest"` (default) | The highest stable tag, `vX.Y.Z` with no pre-release suffix. |
| `01 - Setup Mac Environment.sh`, `AI_SKILLS_REF` | `"latest"` (default) | Same rule for the AI-Skills library. |
| Either of the above | an exact tag, e.g. `"v0.6.0"` | **Hold-back pin.** That machine stays on that tag until you change it. |

`scripts/resolve-release.sh` is the only place "latest" is defined. It runs after tags are fetched
and ignores branches, `-rc`/`-beta` tags and anything not shaped `vX.Y.Z`. A repository with no
release tag is skipped with a warning, so an unreleased project cannot be installed by accident.

**Existing machines do not update themselves.** "Latest" removes the step of editing this
repository; you still re-run `bash MCP/install-mcp-servers.sh` (MCP servers) or
`bash "01 - Setup Mac Environment.sh"` (everything) to move to a newer release.

## The release contract (every released repository)

1. **Tag from `main`, annotated, `vX.Y.Z`** (`git tag -a`). The version in the package manifest
   equals the tag. Pre-releases, if ever needed, carry a suffix (`v1.0.0-rc.1`) and are never run.
2. **Checks pass first**, using that repository's own gate (listed below). A failing gate blocks the
   release; nothing waives it.
3. **Release notes** describe what changed and anything an operator must do.
4. **Settings land before the tag.** If a release needs a new setting, gate or environment value
   (a new `ALLOW_*`, a new path), put it in `MCP/servers.json` here **first**, then tag. Otherwise a
   machine that follows "latest" runs the new code without the setting it needs. Defaults must stay
   safe (gates default off).
5. **Never move or delete a published tag.** A bad release is fixed by a new patch release; a
   machine that must not take it is held back with an exact pin.
6. **Push `main` and the tag together**, only after the commit that carries the version bump has
   fully succeeded. Run the steps with `set -e`, or one at a time, so a failed edit cannot be
   followed by a commit and a tag.
7. **Verify on a machine** by re-running the installer and checking the result (commands below).

## Per repository

| Repository | Released? | Gate before tagging | How to release |
| --- | --- | --- | --- |
| AI-Skills (private) | Yes | `git diff --check`; review the skill diff | AI-Skills `README.md`, "Releasing" |
| m365-mcp (private) | Yes | `npm run build && npm test && git diff --check` | m365-mcp `docs/RELEASING.md` |
| memory-mcp (private) | Yes | `pnpm verify` | memory-mcp `docs/operations.md`, section 5.2 |
| SystemOneAIMCP (private) | **Not yet.** No release tag and not installed by this setup. | `pnpm verify` | Follows this contract before it is added to `MCP/servers.json`. |
| DailyDriver (private data) | **No.** It is data, not software: it is cloned and kept current with Git, never versioned or installed. | n/a | Never public (see its README). |
| EnvironmentSetup (this repo, public) | **No.** It is the bootstrapper, so nothing pins against it; run it from `main`. Everything it installs still follows releases. | `bash -n` on changed scripts | Commit and push to `main`. |

## Verifying after a release

```sh
bash MCP/install-mcp-servers.sh        # prints "<server>: latest -> vX.Y.Z" for each server
claude mcp list                        # Claude Code's health view
pi mcp list                            # Pi: connected and tool counts
git -C ~/.local/share/mcp/<dir> describe --tags   # the deployed tag
```

## Holding a machine back

Set the exact tag in `MCP/servers.json` (for one server) or export `AI_SKILLS_REF=vX.Y.Z` before
running setup (for the skills), then re-run the installer. Remove the pin to return to "latest".
