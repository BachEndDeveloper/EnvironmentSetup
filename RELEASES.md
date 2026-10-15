# Releases: the unit we run

Our released repositories (AI-Skills and the Git-deployed MCP servers) run **from a release,
never from the tip of a branch**. A release is an annotated Git tag `vMAJOR.MINOR.PATCH` on `main`.
Machines follow the
**newest release tag** by default, so shipping a change means cutting a release, not editing this
repository.

## How a machine picks a version

| Where | Setting | Meaning |
| --- | --- | --- |
| `MCP/servers.json`, each server's `ref` | `"latest"` (default) | The highest stable tag, `vX.Y.Z` with no pre-release suffix. |
| `scripts/install-ai-skills.sh`, `AI_SKILLS_REF` | `"latest"` (default) | Same rule for the AI-Skills library. |
| Either of the above | an exact tag, e.g. `"v0.6.0"` | **Hold-back pin.** That machine stays on that tag until you change it. |

`scripts/resolve-release.sh` is the only place "latest" is defined. It runs after tags are fetched
and ignores branches, `-rc`/`-beta` tags and anything not shaped `vX.Y.Z`. A repository with no
release tag is skipped with a warning, so an unreleased project cannot be installed by accident.

**Existing machines do not update themselves.** "Latest" removes the step of editing this
repository; you still re-run `bash MCP/install-mcp-servers.sh` (MCP servers) or
`bash scripts/install-ai-skills.sh` (skills for Pi and Claude Code), or
`bash "01 - Setup Mac Environment.sh"` (everything) to move to a newer release.

AI-Skills is detached in a **deployment-only copy** at `~/.local/share/ai-skills`
(`AI_SKILLS_DIR` can override it). Pi registers that path; Claude Code symlinks to its `skills/`.
Existing Pi checkout registrations are removed via `pi remove` after a successful deployed
install, and old Claude Code links are backed up/replaced. The development checkout at
`~/source/AI-Skills` remains for development only: setup never fetches, detaches or registers it.
Branched/dirty deployments are refused. The installer has a migration fallback even when
installing older skill tags. Relinking alone repairs links but does not update a release.

**External exceptions:** Confluent is a manually installed, approved npm release; Atlassian,
Datadog and Rovo are provider-controlled remote services. Their private configuration/OAuth/
restrictions remain machine-local references, not Git deployments or version pins in this public
repo. The six-server inventory and read-only prerequisite check are in `MCP/README.md`.
Upstream dotnet/Aspire skills, runtimes and third-party Pi packages retain their existing upstream
update mechanisms; this contract does not imply they have the same release-copy isolation.

**Local search exception (explicit npm pin):** qmd is installed globally as
`@tobilu/qmd@2.8.3`, with the single installer version variable in
`scripts/install-qmd.sh`; it does not follow npm latest. Node >=22 is required; Bun is not
needed for this npm distribution. Homebrew SQLite remains Homebrew-managed. Re-run the qmd
installer after a deliberate pin change, then its read-only `--check`, and re-benchmark
retrieval before accepting an upgrade. Full macOS setup now configures the `dailydriver`
named index and embeds before installing the on-demand memory runner and disabled scheduler template; the installer also works standalone.
DEC-0018 makes `$MEMORY_REPO/qmd/dailydriver.yml` canonical in private DailyDriver, with
portable path tokens and explicit model pins; Martin reviews/commits it himself. Installation
only proposes a missing config (uncommitted), then validates and renders the host copy.
It never stages/commits/pushes, mutates collections ad hoc or copies index/model caches.
See [docs/qmd.md](docs/qmd.md) for config ownership, `--rebuild`, `--check`, first-use
downloads, upgrade/re-benchmark steps and GUI PATH discovery. Changed collection names,
roots, masks or ignore globs require a guarded `--rebuild` because qmd retains orphan rows;
labels-only changes do not. The go-live install requires `--rebuild` to replace the benchmark
lane-worktree/ignore topology. Rebuild time is not yet measured (hardware-dependent); the
runbook has the measurement line for the benchmark result.

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
| AI-Skills (private) | Yes | `git diff --check`; review skills; changed scripts: `bash -n`, ShellCheck and sandbox deployment tests | AI-Skills `README.md`, "Releasing" |
| m365-mcp (private) | Yes | `npm run build && npm test && git diff --check` | m365-mcp `docs/RELEASING.md` |
| memory-mcp (private) | Yes | `pnpm verify` | memory-mcp `docs/operations.md`, section 5.2 |
| SystemOneAIMCP (private) | **Not yet.** No release tag and not installed by this setup. | `pnpm verify` | Follows this contract before it is added to `MCP/servers.json`. |
| DailyDriver (private data) | **No.** It is data, not software: it is cloned and kept current with Git, never versioned or installed. | n/a | Never public (see its README). |
| EnvironmentSetup (this repo, public) | **No.** It is the bootstrapper, so nothing pins against it; run it from `main`. Managed repositories follow the release-copy contract above; external exceptions are listed above. | `bash -n` on changed scripts, ShellCheck, `git diff --check`, temp-HOME deployment tests | Commit and push to `main`. |

## Verifying after a release

```sh
bash MCP/install-mcp-servers.sh        # prints "<server>: latest -> vX.Y.Z" for each Git deployment
claude mcp list                        # Claude Code's health view
# In interactive Pi: /mcp             # pi-mcp-adapter runtime health
bash MCP/install-mcp-servers.sh --check-machine-local  # configuration presence, not health
git -C ~/.local/share/mcp/<dir> describe --tags --exact-match HEAD
bash scripts/install-ai-skills.sh      # advances release, reconciles both hosts
git -C ~/.local/share/ai-skills describe --tags --exact-match HEAD
```

Full macOS setup installs the on-demand memory runner/status helpers and a disabled
per-user LaunchAgent template with `install-memory-daily.sh --install-disabled`.
It ignores inherited `MEMORY_DAILY_ENABLE=1` and prior opt-in for loading: **never
loads/reloads** a job. A previously loaded job is left untouched with a prominent
warning and disable command. Standalone default installation retains prior opt-in
behaviour; `--enable` is available for **future automation, not now (DEC-0029)**.
Cowork tasks are not resumed. See README's **Daily memory run** and
[the automation plan](docs/memory-automation.md) for on-demand usage, readiness gates,
status, disable, model selection, logging and future staged rollout.

## Sandbox gate (no live changes)

```sh
python3 scripts/test-deployment.py /path/to/AI-Skills
python3 scripts/test-memory-daily.py
python3 scripts/test-qmd-install.py
```

This uses a temporary HOME and mocked Git/npm/host CLIs to check latest/pinned releases,
checkout-to-deployment migration, idempotent relinking/registration, guards, all six declarations,
manual-reference preservation, remote registration, value-safe warnings, and SSH-auth-only
same-repository HTTPS clone fallback (including both-installer coverage and failed-auth guards). It never downloads,
authenticates, creates tags or starts MCP servers. Run `bash -n` and ShellCheck on changed shell
scripts and `git diff --check` in both repositories as well. Live installer/health commands above
are operator follow-ups, not sandbox gates. The daily-memory sandbox also uses temporary HOME
and mocked Pi/launchctl/osascript to cover opt-in/out, idempotent installs, overlap/stale locks,
read-only prerequisites, marker/exit failures, partial notifications, log retention, on-demand
daily/catch-up streaming and read-only status, plus full-setup never-load behaviour. It never
loads a real launchd job or invokes a real agent. The qmd sandbox uses temporary HOME,
real Ruby YAML/Node and mocked npm/qmd/brew/git/pgrep. It covers the exact pin, SQLite,
missing-config proposals without Git mutation, authoritative private-config rendering with
byte preservation, canonical/rendered safety checks before installation, read-only doctor,
installed-YAML topology-change refusal (including masks/paths/names/ignores) and labels-only
updates, idempotence, rebuild deletion scope and process/WAL/writer-lock guards, deferred embedding,
failure handling, settings precedence and GUI PATH discovery. It never installs real
packages, downloads models or stages/commits/pushes a repository.

## Holding a machine back

Set the exact tag in `MCP/servers.json` (for one server) or export `AI_SKILLS_REF=vX.Y.Z` before
running setup (for the skills), then re-run the installer. Remove the pin to return to "latest".
