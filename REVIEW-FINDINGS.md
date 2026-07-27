# EnvironmentSetup — review findings and resolution plan

Review of `~/source/EnvironmentSetup` carried out 2026-07-27, prompted by work
on a portable MCP server setup. Findings are ordered by severity.

**State at the time of the review:** branch `main`, clean tree, `c5532cd` at HEAD.
Nothing had been changed at that point — the findings below describe that state.
All line counts and citations in this document are taken at `c5532cd`.

**State now:** HEAD is still `c5532cd`. Phase A (error handling) has been implemented
and is sitting **uncommitted in the working tree**, together with the round-1 and
round-2 review fixes — see the [Progress log](#progress-log) at the end. Finding 5 is
closed in the worktree but not yet in history; finding 2 is closed for macOS/Windows
only, since the Ubuntu/WSL script is untouched. Phases B–F are still open, and B/E are
blocked on a support-level decision.

---

## Summary

| # | Severity | Finding |
| --- | --- | --- |
| 1 | **Critical** | Ubuntu/WSL script has a syntax error and cannot run at all |
| 2 | **High** | No script sets `-e`; failures are silent and leave a half-configured machine |
| 3 | **High** | `ClaudeCode/settings.json` hardcodes another machine's user and Node version |
| 4 | Medium | 9 of 10 hooks referenced by `settings.json` are not vendored |
| 5 | Medium | README pins `v0.2.1`; the script pins `v0.3.0` |
| 6 | Medium | Windows provisions no AI tooling — no Pi, Claude Code, Copilot or skills |
| 7 | Medium | Ubuntu/WSL is a stub with an unfinished `TODO` |
| 8 | Low | No MCP server provisioning exists yet |
| 9 | Low | Pinned versions are scattered with no single inventory |

---

## 1. Ubuntu/WSL script cannot execute — CRITICAL

`bash -n "01 - Setup Ubuntu Environment WSL.sh"` fails:

```
line 13: syntax error near unexpected token `else'
```

The cause is line 4, missing a separator before `then`:

```bash
if ! command -v brew &> /dev/null then      # needs `;` or newline before `then`
```

The script has never run successfully in this state. Three further defects sit
behind it:

- **macOS paths on Linux.** It copies fonts to `/Library/Fonts` and
  `~/Library/Fonts`, which do not exist on Ubuntu. Should be
  `/usr/share/fonts` or `~/.local/share/fonts`.
- **Typo:** `cp Font/CascadiaCodeNF/*` — the directory is `Fonts/`.
- **Failures masked by `| echo`.** The pattern
  `brew install $1 | echo "Installed $1"` pipes output into `echo`, which
  ignores stdin and prints unconditionally. Every step reports success whether
  or not it worked.

**Fix:** repair the syntax, correct the font paths for Linux, remove the
`| echo` pattern, and re-check with `bash -n`. Alternatively delete the script
if WSL is no longer a target — a broken script is worse than an absent one,
because it implies coverage that does not exist.

## 2. No error handling in any script — HIGH

As of 2026-07-27 (before Phase A), none of the three setup scripts set `-e`, `-u`,
or `-o pipefail`:

```
grep -n 'set -' "01 - Setup Mac Environment.sh" \
                "01 - Setup Windows environment.ps1" \
                "01 - Setup Ubuntu Environment WSL.sh"
→ no matches
```

A failing step therefore does not stop the run. On a fresh machine — the exact
case these scripts exist for — a failed clone, a failed `brew bundle`, or a
missing SSH key produces a script that runs to completion and appears to
succeed, leaving a partially configured environment whose gaps surface later as
unrelated-looking breakage.

**Fix:** add `set -euo pipefail` to the bash scripts and
`$ErrorActionPreference = 'Stop'` to the PowerShell one. Then walk each script
for steps that are *expected* to fail benignly and guard those explicitly with
`|| true`, so the intent is visible rather than global.

Do this **after** finding 1, since enabling `-e` on a script that currently
tolerates failures will surface latent breakage — which is the point, but it is
easier to interpret one script at a time.

## 3. Hardcoded foreign user and Node version — HIGH ✅ fixed 2026-07-27

**Fixed.** `settings.json` now uses `node` from `PATH` and
`"$HOME/.claude/hooks/<name>"`; there are zero machine-specific paths left. See
Phase C. The description below is the state at the time of the review.

`ClaudeCode/settings.json` contains 16 absolute-path references belonging to a
different machine, spread across 10 distinct hook scripts (9 hook command entries
plus the statusline):

```
"/Users/bach/.nvm/versions/node/v25.9.0/bin/node" "/Users/bach/.claude/hooks/gsd-check-update.js"
```

This machine is `/Users/martinbach` running Node **v24.16.0**. Both the
username and the Node version are wrong, so every hook wired through that path
fails. Claude Code hook failures are not surfaced prominently, so the setup
looks complete while `SessionStart`, `PostToolUse`, `PreToolUse` and the commit
validation hooks silently do nothing.

`ClaudeCode/README.md` step 3 documents this as a manual fix, so it is known
rather than accidental. But a documented manual step that is easy to forget and
silent when skipped is a poor guard for something restored on every new machine.

**Fix (applied):** replaced the absolute node path with plain `node` (relying on
`PATH`, which the setup script already configures via nvm), and `/Users/bach`
with `$HOME`. A setup-time template (`sed "s|__HOME__|$HOME|g"`, the way
`models.json` templates `YOUR-FOUNDRY-RESOURCE`) turned out to be unnecessary:
Claude Code runs a `command` hook in *shell form* when the entry has no `args`
key, so `/bin/sh` expands `$HOME` at run time. Using `$HOME` keeps the vendored
file and the installed file identical, which is simpler than templating.

## 4. Referenced hooks are not vendored — MEDIUM ✅ resolved 2026-07-27 by removing GSD

**Resolved by deletion, not by fixing.** GSD was removed entirely: `settings.json`
no longer declares any hooks or a statusline, `ClaudeCode/hooks/gsd-statusline.js`
is deleted, and the setup script no longer copies a hooks directory. There is
nothing left to reference, so the silent-gap class is gone rather than guarded.
The machine had already moved on — `~/.claude/hooks/` did not exist and the live
`~/.claude/settings.json` contained no GSD references. The description below is
the state at the time of the review.

`settings.json` references 10 hooks; only `gsd-statusline.js` exists in
`ClaudeCode/hooks/`. The other nine belong to the external GSD setup:

```
gsd-check-update.js       gsd-prompt-guard.js       gsd-session-state.sh
gsd-context-monitor.js    gsd-read-guard.js         gsd-validate-commit.sh
gsd-phase-boundary.sh     gsd-read-injection-scanner.js
gsd-workflow-guard.js
```

This is documented (`ClaudeCode/README.md` step 2: reinstall GSD). The risk is
the combination with findings 2 and 3: settings are restored unconditionally,
the hooks they point at may not exist, nothing fails loudly, and the result is
a Claude Code that appears configured but has no working hooks.

**Fix (superseded):** the plan was to vendor the hooks or add a post-restore
check warning about missing ones. A check was briefly added, then removed along
with GSD itself — deleting the dependency beat guarding it. `ClaudeCode/README.md`
now records the rule that any future hook must have its script vendored here.

## 5. Documentation drift on the pinned tag — MEDIUM

```
README.md, "Personal AI skills"                … checks out its pinned `v0.2.1` release …
01 - Setup Mac Environment.sh, AI_SKILLS_REF   AI_SKILLS_REF="v0.3.0"
```

The script is authoritative; the README is one release behind. Worth noting the
practical cost: reading the README during this review produced a wrong statement
about which release is pinned, which then had to be corrected. Stale
documentation does not merely fail to help — it actively misleads.

**Fix:** stop repeating the value. Have the README point at the variable
(*"pinned in `01 - Setup Mac Environment.sh` — see `AI_SKILLS_REF`"*) rather
than restating it, so there is one source of truth.

## 6. Windows provisions no AI tooling — MEDIUM

```
grep -niE 'pi-coding|claude|copilot|skill|nvm|node' "01 - Setup Windows environment.ps1"
→ no matches
```

The Windows script installs winget packages, fonts, terminal and editor configs.
It does not install Pi, Claude Code, GitHub Copilot CLI, Node/nvm, or any
skills. A Windows machine set up from this repository has the terminal
environment but none of the AI tooling.

**Fix:** decide explicitly whether Windows is a supported target for AI tooling.
If yes, port the agent-installation and skills-bootstrap blocks. If no, say so
in the README so the gap is a documented choice rather than an apparent
oversight.

## 7. Ubuntu/WSL is a stub — MEDIUM

50 lines against 178 for Windows and 157 for macOS (counts at `c5532cd`),
containing an unfinished `## TODO copy the fonts`. It installs eight brew packages
and copies a `.zshrc`. No AI tooling, no Neovim, no VS Code config, no skills.

**Fix:** same decision as finding 6 — bring it up to parity, or retire it and
note that WSL is unsupported. Combined with finding 1, retiring is the lower
effort path unless WSL is actively used.

## 8. No MCP server provisioning — LOW, forward-looking

The only match for "mcp" anywhere is `npm:pi-mcp-adapter` in
`Pi/settings.json`. No MCP server is installed or configured by any script.

This becomes relevant shortly: `m365-personal-productivity-mcp` is intended to
be cloned at a pinned tag and registered with Pi, Claude Code and Claude
Desktop, following the AI-Skills pattern. It will be the first MCP server this
repository provisions, so the pattern is being invented rather than followed.

**Fix:** when adding it, design for the second and third server. A per-host
`MCP/` directory with one config fragment per server is likely to age better
than appending entries into each host's settings file.

### Survey of the live wiring (2026-07-27)

Inspected before designing anything. All three of these are machine-local and
captured nowhere in this repository:

| Host | File | State |
| --- | --- | --- |
| Pi | `~/.pi/agent/mcp.json` | `{"imports": ["claude-code", "claude-desktop"], "mcpServers": {}}` |
| Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` | declares `m365-personal-productivity` |
| Claude Code | `~/.claude.json` | identical entry at top level |

Three findings that shape the design:

1. **Pi imports rather than declares.** It pulls MCP servers from the Claude Code
   and Claude Desktop configs, so provisioning only has to write those two and
   Pi follows. That is a good existing pattern - keep it, do not add a third
   declaration for Pi.
2. **The same absolute-path bug this repo just fixed in `ClaudeCode/settings.json`
   is present here, untouched.** Both host configs invoke the server as:

   ```
   command: /Users/martinbach/.nvm/versions/node/v24.16.0/bin/node
   args:    [/Users/martinbach/source/m365-personal-productivity-mcp/dist/index.js]
   ```

   A pinned Node version and a hardcoded home directory - it breaks on any other
   machine and on the next `nvm install --lts`. Whatever provisioning is written
   must emit `node` from `PATH` and a `$HOME`-relative path.
3. **There is org-specific config to template.** Both entries carry a `TENANT_ID`
   env value. This repository is public, so it must be templated the way
   `Pi/models.json` templates `YOUR-FOUNDRY-RESOURCE` - never vendored verbatim.

The server itself is `github.com/BachEndDeveloper/m365-mcp` (tag `v0.1.0`
exists), checked out at `~/source/m365-personal-productivity-mcp`, npm name
`m365-mcp`, `bin: m365-mcp -> dist/index.js`, scripts `build` / `auth` /
`doctor` / `dev` / `start`. Its `.env` is correctly git-ignored.

**Risk to weigh before implementing:** `~/.claude.json` is ~73 KB and holds far
more than MCP config (project history and session state). Provisioning must do a
surgical merge of the `mcpServers` key and preserve everything else - a
write-whole-file approach would destroy live state. Claude Desktop's config is
small and safe by comparison.

## 9. Pinned versions have no inventory — LOW

Pins are scattered across files:

- `nvm` installer — `v0.40.3` (`01 - Setup Mac Environment.sh`, the nvm install block)
- `AI_SKILLS_REF` — `v0.3.0` (`01 - Setup Mac Environment.sh`, `AI_SKILLS_REF`)
- Node — "latest LTS", unpinned
- LazyVim and plugins — deliberately unpinned
- Homebrew packages — `Brewfile`, unpinned
- npm globals — `@earendil-works/pi-coding-agent`, `hunkdiff`
  (`01 - Setup Mac Environment.sh`, the AI coding agents block); deliberately
  floating, always installed at latest
- QMK MSYS — `1.7.2` (`01 - Setup Windows environment.ps1`, `$qmkMsysVersion`)

The mix of pinned and floating is intentional and documented in places, but
there is no single view of what is pinned and where, so updating a pin means
knowing it exists.

**Fix:** a short table in the README listing each pinned item, its current
value, its location, and whether it is deliberately floating.

---

## Resolution plan

Sequenced so that each phase makes the next one easier to interpret. Suggested
as one branch per phase, following the small-commits workflow.

### Phase A — Make failures visible 🟡 implemented 2026-07-27, verification incomplete

- [x] Add `set -euo pipefail` to `01 - Setup Mac Environment.sh`
- [x] Add `$ErrorActionPreference = 'Stop'` to the Windows script
      — *round 2 parsed it with a real PowerShell 7.6.4 parser and ran it in a
      mocked-Windows harness; a 5.1 parse and a real elevated run are still owed*
- [x] Audit the intentionally-tolerant steps and confirm each is explicitly
      guarded — *no new guards were needed for the pre-existing five
      `|| true` / `|| echo WARNING` steps; they were reviewed and kept. Round-1
      fixes then added guards around `brew bundle` and the AI-Skills bootstrap.*
- [ ] Re-run the macOS script on a working machine; confirm it still completes
      — *only a stubbed dry run was done (see Progress log); a real end-to-end
      run on this machine is still outstanding*
- [ ] Commit separately from any behavioural change
      — *nothing is committed yet; the Phase A hardening and the round-1 fixes
      are one undifferentiated working-tree change and still need splitting*

### Phase B — Ubuntu/WSL: deferred 2026-07-27 — stale, revive later

**Decision:** neither fixed nor deleted for now. Windows/WSL is not a day-to-day
machine, so the script stays in the repo as a starting point, clearly marked
broken. It has **never executed successfully** — do not run it expecting results.

What has to be fixed to revive it (each verified against the current file):

- [ ] **Syntax error, line 4** — `if ! command -v brew &> /dev/null then` is
      missing a `;` or newline before `then`. This alone makes the whole file
      unparseable (`bash -n` → rc 2), so nothing below has ever run.
- [ ] **macOS paths on Linux** — it copies fonts to `/Library/Fonts` and
      `~/Library/Fonts`, which do not exist on Ubuntu. Use
      `/usr/share/fonts` or `~/.local/share/fonts`, and run `fc-cache -f`.
- [ ] **Typo** — `cp Font/CascadiaCodeNF/*`; the directory is `Fonts/`.
- [ ] **Remove every `| echo`** — `brew install $1 | echo "Installed $1"` pipes
      output *into* `echo`, which ignores stdin and prints unconditionally, so
      every step reports success whether or not it worked. There are 4 of these.
- [ ] **Add `set -euo pipefail`** — finding 2 is only closed for macOS/Windows
      until this is done.
- [ ] **Decide on Homebrew-on-Linux at all.** The script installs Linuxbrew and
      then installs `zsh`, `git`, `terraform`, `azure-cli`, `exa` through it.
      On Ubuntu, `apt` + the vendors' own repos is the lower-friction path, and
      `exa` is unmaintained (use `eza`, as the macOS Brewfile already does).
- [ ] **Bring it to parity, or scope it down explicitly.** It currently has no
      AI tooling, no Neovim, no VS Code config and no skills bootstrap. Either
      port the macOS blocks or state in the README that WSL is shell-only.
- [ ] **Back up before overwriting** — it does `cp Zsh/.zshrc $HOME` with no
      backup, unlike the macOS script.
- [ ] Gate on `bash -n` passing, then run it once in a throwaway container.

If it is still untouched next time this list is reviewed, retire it instead — a
broken script implies coverage that does not exist.

### Phase C — De-hardcode the Claude Code config ✅ done 2026-07-27

- [x] Replace absolute node paths with `node`
      — all 9 hook commands now call `node` from `PATH`, matching what
      `statusLine` already did. No Node version is pinned anywhere.
- [x] Replace `/Users/bach` with `$HOME`, or template it during setup as
      `models.json` already does
      — used `$HOME` directly rather than a setup-time template: Claude Code runs
      a `command` hook in *shell form* when the entry has no `args` key, so
      `/bin/sh` expands `$HOME` at run time. Verified the expansion resolves to
      this machine's home. Zero `/Users/bach` references remain and the file is
      still valid JSON.
- [x] Add a post-restore check that warns about missing GSD hooks
      — the macOS script now checks all 10 referenced hooks after the copy and
      lists the missing ones on stderr, plus a warning if `node` is absent.
      Exercised against a hooks directory containing only the vendored
      statusline: it correctly reported the 9 GSD hooks as missing.
- [x] Verify on this machine that hooks actually fire after the change
      — **moot**: GSD was removed on 2026-07-27, so `settings.json` declares no
      hooks and no statusline at all. Nothing to fire. If a hook is ever added
      back, its script must be vendored in `ClaudeCode/` and copied by the setup
      script — see finding 4 and `ClaudeCode/README.md`.

### Phase D — Documentation consistency 🟡 partly done

- [x] Remove the duplicated `v0.2.1` from the README; reference `AI_SKILLS_REF`
      — *done in the round-1 review fixes; finding 5 is closed in the worktree,
      though not yet in history*
- [ ] Add the pinned-versions inventory table
      — *the inventory in finding 9 above is current, but it has not been moved
      into the README as a table*
- [ ] State the support level of Windows and WSL explicitly
      — *Windows: done (2026-07-27). The README now marks it stale and
      unmaintained, lists what is known outdated (no AI tooling, .NET SDK 6/7 out
      of support, never run on real Windows), in both the repo layout list and the
      Windows setup section. WSL is still pending the Phase B decision.*

### Phase E — Cross-OS parity decision ✅ decided 2026-07-27: no

- [x] Decide whether Windows gets the AI tooling blocks
      — **No.** I no longer work on Windows machines, so Windows is explicitly
      out of scope rather than an unfinished port.
- [x] If yes, port agents + skills bootstrap; if no, document the boundary
      — boundary documented in the README (stale-script callouts). The Windows
      hardening from Phase A stays in place, but nobody should assume it has been
      exercised on real Windows.

### Phase F — MCP provisioning pattern 🟡 surveyed, not implemented

The live wiring has been surveyed - see the table and the three findings under
finding 8. Remaining work, in order:

- [ ] Choose where MCP config lives, designed for several servers.
      Proposal: an `MCP/` directory holding one declarative entry per server
      (repo URL, pinned tag, build command, env template), with the setup script
      materialising the two host configs from it. Pi needs nothing - it imports
      from those two.
- [ ] Add `m365-personal-productivity-mcp` as the first, mirroring the
      AI-Skills clone-at-pinned-tag block
      (`github.com/BachEndDeveloper/m365-mcp`, tag `v0.1.0`), including
      `npm ci && npm run build` after checkout.
- [ ] Emit `node` from `PATH` and `$HOME`-relative paths, **not** the pinned
      `/Users/martinbach/.nvm/versions/node/v24.16.0/bin/node` currently in both
      host configs - same bug class as finding 3.
- [ ] Template `TENANT_ID`; never vendor the real value into this public repo.
- [ ] Merge surgically into `~/.claude.json` (73 KB of live session state) -
      only the `mcpServers` key, preserving everything else. Back it up first.
- [ ] Document `npm run auth` alongside the existing per-provider `/login` steps,
      and `npm run doctor` for diagnosis.

---

## Verification

Before considering any phase done:

- [ ] `bash -n` passes on every shell script
      — *passes on the macOS script; the Ubuntu/WSL script still fails with a
      syntax error (finding 1), so this stays unchecked*
- [ ] The macOS script completes on a machine that already has everything
      (idempotency)
      — *never run for real end-to-end; only stubbed/isolated fragments*
- [x] A deliberately broken step causes a visible failure rather than a silent
      continue
      — *exercised by execution on both scripts: a forced mid-script failure
      aborts the macOS run, and the Windows script aborts at its precondition
      check. Note the deliberate exception: native-command failures on Windows
      (`winget`, `git config`) are still silent by design*
- [ ] Claude Code hooks demonstrably fire — check the statusline renders and a
      `PostToolUse` hook produces its side effect
- [ ] No `/Users/<someone>` remains outside documentation examples

A note on what "verified" has meant so far: treat only the bullets under a
**Verification** heading as executed or parsed. The change bullets above them are
descriptions, and several were reasoned about but never run — the `brew update`
tolerance, the `curl -f` behaviour, the stderr redirections, the `pwd -P` comment
rewrite, and the `nvm`-callable check. The recurring failure mode across rounds 1
and 2 was verifying *part* of a block and writing it up as if the whole block were
covered — round 1's AI-Skills check exercised the checkout but not the clone, and
the clone was the fatal path.

## Progress log

### 2026-07-27 — Decisions taken

- **Brewfile rot — fixed rather than tolerated.** `tap "azure/functions"` and
  `brew "azure-functions-core-tools@4"` were removed (Homebrew refuses to load
  formulae from untrusted third-party taps, which made `brew bundle` fail
  outright), and `font-monaspace-nerd-font` was renamed to the current upstream
  cask `font-monaspice-nerd-font`. The `brew link azure-functions-core-tools@4`
  line in the macOS script went with it. `brew bundle check --file=Brewfile` now
  evaluates the file successfully.
  **Machine-state caveat:** this repo change does not untap anything already on a
  given machine. Until `brew untap azure/functions` (and, if wanted,
  `brew uninstall azure-functions-core-tools@4`) is run locally, `brew bundle`
  will still print the untrusted-tap error — it now warns and continues instead of
  aborting the run.
- **The `brew bundle` guard stays.** Even with the Brewfile fixed, one failing
  package must not abort a machine setup; the warning plus the EXIT-trap reminder
  is the intended behaviour, not a workaround for the tap problem.
- **Windows is out of scope** (Phase E above).
- **This document is committed** so the history exists; delete it once the phases
  are closed.

### 2026-07-27 — Phase A implemented

**`01 - Setup Mac Environment.sh`**

- Added a `#!/usr/bin/env bash` shebang and `set -euo pipefail`.
- Added `cd "$(dirname "${BASH_SOURCE[0]}")"` so the repo-relative `cp` and
  `brew bundle --file="Brewfile"` calls no longer depend on the caller's cwd.
- Replaced the `which -s brew` / `if [[ $? != 0 ]]` idiom with
  `if ! command -v brew`: under `set -e` the old form exits the script *before*
  reaching the `if`, so the Homebrew install branch was unreachable.
- Converted every `[ -f … ] && cp …` backup line to a full `if` block. As a
  top-level command, `false && cmd` returns non-zero and aborts under `set -e`,
  which would have made a *missing* `~/.zshrc` fatal.
- Wrapped the `. "$NVM_DIR/nvm.sh"` source in `set +eu` / `set -eu`; nvm is not
  written to run under `-e`/`-u`.
- Changed the Homebrew-install branch from a bare `PATH=...` assignment to an
  explicit `export PATH=...` (replaced by `brew shellenv` in round 1).
- Reindented the AI-Skills block from spaces to tabs to match the rest of the
  file (whitespace only, no behaviour change).
- Left the five existing `|| true` / `|| echo WARNING` guards in place — they are
  now the only tolerated failures, and each is visible at its call site. They
  guard: the `brew link` of azure-functions-core-tools@4, the headless `Lazy
  sync`, the `cp` of the ClaudeCode hooks, and the two upstream skills clones
  (dotnet/skills and microsoft/aspire-skills).

**`01 - Setup Windows environment.ps1`**

- Added `$ErrorActionPreference = 'Stop'` plus a header note that this does *not*
  cover native exit codes (`winget upgrade` returns non-zero when already current,
  which must stay tolerated).
- Added an elevation pre-check that throws immediately — the font install writes to
  `C:\Windows\Fonts` and HKLM, so a non-elevated run previously failed half-way.
- Fixed a latent bug in `InstallFont`: it copied `$Font` (the *caller's* loop
  variable) instead of its own `$fontToInstall` parameter. It happened to work only
  because every call site used that variable name.
- Added `-Force` to the font registry `New-ItemProperty` so re-runs are idempotent.
- Guarded the Windows Terminal and VS Code settings copies with `Test-Path` and a
  `Write-Warning`; both destinations only exist after the app's first launch, and
  under `Stop` a missing folder would abort the remaining setup.
- Created the `$PROFILE` parent directory before copying into it.

**Verification performed**

- `bash -n` passes on the macOS script.
- Stubbed dry run of the macOS script (all external commands stubbed, `HOME`
  redirected to a temp dir, `env -i`):
  - all steps succeeding → script runs to completion, exit 0;
  - one step (`uv`) forced to exit 1 → script aborts at that step with exit 1 and
    executes nothing after it. This is the behaviour finding 2 asked for.

  The harness was ad-hoc and was **not kept**, so this result is not reproducible
  as written — it would have to be rebuilt to re-check.

**Not verified / carried forward**

- The PowerShell script could not be parsed or run: neither `pwsh` nor Docker is
  available on this machine. Needs a syntax check on a Windows box before trusting.
- The macOS script has not been run for real end-to-end since the change.
- `shellcheck` is not installed here; adding it to the `Brewfile` would make this
  class of bug catchable automatically.

### 2026-07-27 — Round 1 review fixes

A fresh-context review of the Phase A diff found that the hardening had, in
several places, converted "silently continues" into "aborts the whole setup on a
routine condition". This pass fixes that.

**`01 - Setup Mac Environment.sh`**

- `brew bundle` now records failure in `BREW_BUNDLE_FAILED` and continues, with a
  reminder printed at the end. It exits non-zero if *any* single package fails,
  and it does fail on this machine today (untrusted `azure/functions` tap), which
  under `set -e` aborted everything after it.
- The `cd "$(dirname ...)"` line was replaced with a `pwd -P` form plus a
  `Brewfile` existence check. The old form silently no-opped when the script was
  piped on stdin, and resolved wrongly through a symlink.
- The Homebrew installer is now assigned to a variable before being run:
  `bash -c "$(curl ...)"` silently succeeds when curl fails, because the empty
  substitution becomes `bash -c ""`. Neither `-e` nor `pipefail` catches that.
- That branch now uses `eval "$(/opt/homebrew/bin/brew shellenv)"` instead of
  appending to `PATH` by hand.
- The AI-Skills `fetch` is tolerated with a warning, and `checkout` +
  `install-local.sh` run in a guarded subshell. A new machine without a GitHub SSH
  key is the documented normal case, and it was aborting before the two upstream
  skills clones and the final Rider reminder.
  The first attempt at that subshell was wrong: `set -e` is **ignored inside a
  subshell used as an `if` condition**, so `install-local.sh` would still have run
  after a failed `checkout`. Caught by executing the construct rather than trusting
  `bash -n`; each step now carries an explicit `|| exit 1`.
  **This pass did not finish the job:** the initial `git clone` in the `else` branch
  was left unguarded, so the SSH-key case was still fatal. Round 2 caught it — see
  below.
- Added an explicit check that `nvm` is callable after sourcing `nvm.sh`.

**`01 - Setup Windows environment.ps1`**

- Set `$PSNativeCommandUseErrorActionPreference = $false`. PowerShell 7.4 defaults
  it to `$true`, which makes non-zero *native* exit codes terminating — so
  `winget upgrade` on an already-current package would have been fatal. The header
  comment previously asserted the opposite.
- `Set-ExecutionPolicy` is now wrapped in try/catch. It emits a non-terminating
  `ExecutionPolicyOverride` error whenever a more specific scope is set — which the
  README's own `-Scope Process` instruction causes, and which is normal on
  GPO-managed machines.
- The three `Install-Module` calls are individually wrapped in try/catch, and TLS
  1.2 is enabled first on PowerShell 5.1 (the Gallery refuses the stock defaults).
- `InstallFont` copies with `-Force` to `$env:SystemRoot\Fonts` rather than a
  hard-coded `C:\Windows\Fonts`, wrapped in try/catch. Fonts that ship with
  Windows Terminal / VS are usually already present, which would otherwise throw.
- The `$PROFILE` handling backs up to `$PROFILE.bak` instead of deleting, and the
  copy uses `-Force`.
- Added a non-Windows guard, because
  `[Security.Principal.WindowsIdentity]::GetCurrent()` throws an opaque
  `PlatformNotSupportedException` on PowerShell 7 for macOS/Linux.

**`README.md`** — corrected the run-location and idempotency claims, documented the
new fail-fast behaviour and the elevation requirement (including the
wrong-admin-account trap), replaced the stale `v0.2.1` with a pointer to
`AI_SKILLS_REF`, and added a clarifying sentence about which CLIs come from where
(the count of three was already correct and was not changed).

**This document** — corrected the stale "nothing has been changed" header, the
Phase A checkboxes that claimed unfinished work was done, the guard count, the
stale line-number citations, and finding 2's now-false evidence block.

**Verification**

- `bash -n` passes on the macOS script.
- The four behavioural changes to the macOS script were executed in isolation to
  confirm they do what they claim: a failing `brew bundle` warns, continues, and
  fires the end-of-run reminder; a failed `curl` of the Homebrew installer is now
  fatal instead of silently succeeding; a failed AI-Skills bootstrap warns and
  lets the rest of the script finish; and a wrong working directory exits 1 with a
  clear message. This is what caught the `set -e`-in-subshell bug above.
  **Caveat found in round 2:** the "failed AI-Skills bootstrap warns" check
  exercised only the `checkout`/`install-local.sh` subshell. The `git clone` path
  was never executed, and it was still fatal. Do not read that bullet as covering
  the whole block.
- The PowerShell script is still unparsed — no `pwsh` on this machine. Brace
  balance and try/catch pairing were checked textually only, which is not a
  substitute for a real parse. *(Superseded in round 2: a real parser was obtained.)*

### 2026-07-27 — Round 2 review fixes

A second fresh-context review, this time with a working PowerShell runtime, found
that the earlier passes had **introduced three regressions of their own** — round 1's
unguarded AI-Skills `git clone`, round 1's `$PROFILE.bak` clobber on the second run,
and Phase A's `'Stop'`-induced abort when run from the wrong directory — and had left
several documentation claims ahead of the code.

**`01 - Setup Mac Environment.sh`**

- **Blocker introduced by round 1:** the initial `git clone "$AI_SKILLS_REPO"` was
  never guarded, only the `fetch` and the `checkout`/`install` pair. Reproduced with
  a real SSH failure: `Permission denied (publickey)` → exit 128, skipping both
  upstream skills clones and the final Rider reminder — exactly the fresh-machine
  case the README promises degrades gracefully. Now warns and continues.
- `eval "$(/opt/homebrew/bin/brew shellenv)"` had the same shape as the
  `bash -c "$(curl ...)"` trap fixed in round 1: a failing command substitution
  collapses to `eval ""` (rc 0). Combined with the now-tolerated `brew bundle`, a
  Homebrew install landing elsewhere (Intel `/usr/local`) meant the entire Brewfile
  was silently skipped while the run reported success. Now checks the binary exists
  and assigns before `eval`.
- `brew update` was fatal while an actual package failure was tolerated — inconsistent
  with the policy stated in the file header. It now warns and continues.
- The end-of-run `BREW_BUNDLE_FAILED` reminder was lost whenever a later step aborted
  (verified: a `uv` failure exited 1 with no reminder). It is now an `EXIT` trap set
  immediately after the flag is initialised.
- The comment claiming `pwd -P` resolves a symlinked entry point was false — `pwd -P`
  resolves symlinks in the *directory path*, not a symlinked script file. Reworded to
  state the real guarantee: the `Brewfile` check is what catches misinvocation.
- Added `-f` to the nvm and Aspire `curl` installers (without it curl writes an HTML
  error body into the shell), and sent the two upstream-skills warnings to stderr.

**`01 - Setup Windows environment.ps1`**

- **Data loss, empirically proven:** `Copy-Item $PROFILE "$PROFILE.bak" -Force`
  clobbered the good backup on the *second* run — run 1 saved the user's real profile,
  run 2 saved the repo profile over it, irrecoverably. The backup is now kept and a
  timestamped name is used for subsequent runs.
- `$ErrorActionPreference = 'Stop'` had made the four repo-relative `Get-Item -Path
  $FontFolder` calls fatal. Proven: running from the wrong directory aborted *after*
  ~21 winget installs and *before* any personalisation, with a message that never
  mentioned the working directory. A precondition check now validates the eight
  required folders up front.
- try/catch survives an `Install-Module` failure but cannot answer a ShouldContinue
  **prompt**, which would block the run waiting on input. `-Scope CurrentUser -Force`
  added to the Terminal-Icons and PSReadLine installs (posh-git already had it), and
  the comment corrected to say the prompts are suppressed rather than merely survived.

**Documentation** — corrected the README's "all three are idempotent" (the WSL script
cannot even parse), narrowed "stop at the first failing step" to "first failing
cmdlet/command" with an explicit native-executable exception, described the post-fix
AI-Skills degradation accurately, and added a note that `.backup` files are overwritten
on every run. In this document: corrected the review baseline to `c5532cd`, the Ubuntu
syntax-error line (4, not 3), the macOS line count (157, not ~175), the
`ClaudeCode/settings.json` path count (16 references across 10 hook scripts, not 10
paths), added QMK MSYS `1.7.2` to the pinned inventory, reconciled the two conflicting
statements about finding 5, and corrected a round-1 claim that a README CLI count had
been fixed when it had not.

**Verification**

Exercised by execution:

- `bash -n` passes on the macOS script.
- The unguarded-clone blocker was reproduced with a real failing SSH clone (exit 128)
  and confirmed fixed: the guarded form warns and reaches the subsequent steps.
- The `eval "$(... shellenv)"` trap was demonstrated both ways — the old form continues
  at rc 0 after a failed substitution, the new form exits 1.
- The `EXIT` trap was tested in three scenarios: clean run (silent), flag set with a
  normal exit (fires), and flag set with a later step aborting the run (fires, rc 1).
- **The PowerShell script now parses cleanly** — zero syntax errors, 1115 tokens, 71
  top-level statements — using a real PowerShell **7.6.4** parser installed as a
  dotnet local tool. It was also executed end-to-end in a mocked-Windows harness,
  which is how the profile-backup data loss and the wrong-directory abort were proven
  and then confirmed fixed (the original profile now survives repeated runs; a wrong
  CWD aborts at the precondition check naming the missing folder).

Still **not** verified:

- No PowerShell **5.1** parse. 7.6.4 accepts the syntax, but 5.1 is the version on a
  stock Windows box and has not been exercised.
- No real elevated run on Windows: winget, the HKLM font registry writes, and
  `Install-Module` were all mocked.
- The macOS script has still never been run end-to-end for real.
- `shellcheck` is still not installed here; adding it to the `Brewfile` would make
  this class of bug catchable automatically.

---

## Notes

The repository's core design is sound: idempotent guards on the AI-Skills
clone, backup-before-overwrite for configs, a stated no-secrets policy, and
`Brewfile` as a single source of truth for packages. Findings 1–3 are the ones
worth acting on soon; the rest are hygiene.

The recurring theme across findings 1, 2, 3 and 5 is the same: **steps that fail
or drift without announcing it.** A syntax error in a script nobody runs, hooks
that point nowhere, a version documented in two places. Each is individually
minor and collectively means the setup cannot be trusted to have worked without
manual inspection — which is precisely what a bootstrap repository exists to
avoid.
