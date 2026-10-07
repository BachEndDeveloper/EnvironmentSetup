# EnvironmentSetup

Scripts, fonts and profiles for setting up a new machine to my specs.

- macOS: `01 - Setup Mac Environment.sh` (Homebrew-based) — **actively maintained**
- Windows: `01 - Setup Windows environment.ps1` (winget-based) — **stale, see below**
- WSL/Ubuntu: `01 - Setup Ubuntu Environment WSL.sh` — **broken, never run successfully**

> **Only the macOS script is actively maintained.** I no longer work on Windows machines, so the
> PowerShell script is stale: it has been hardened and statically verified, but it has not been run
> on a real Windows machine in a long time, and it provisions none of the AI tooling the macOS
> script does (no Node/nvm, no Pi, Claude Code or Copilot CLI, no skills bootstrap). It also still
> installs .NET SDK 6 and 7, both out of support. Treat it as a starting point that needs a rework
> and a real test run before trusting it. The WSL/Ubuntu script is worse — it has a syntax error on
> line 4 and has therefore never executed at all; see
> [Reviving the WSL/Ubuntu script](#reviving-the-wslubuntu-script).

## Running the setup

Run each script **from the repo root** — they copy config files using relative paths. The macOS
script `cd`s to its own directory first and verifies it found the repo, so it tolerates being
invoked from elsewhere; the Windows script checks the folders it needs and stops with a clear
message if you run it from the wrong place. The macOS and Windows scripts are idempotent:
re-running updates installed packages and skips what's already present. **The WSL/Ubuntu script
does not currently run at all** — it has a syntax error and has never executed successfully; treat
it as unmaintained until it is repaired or retired.

The macOS and Windows scripts **stop at the first failing cmdlet/command** rather than continuing
with a half-configured machine. Fix the reported problem and re-run. Steps that are expected to
fail benignly on some machines (a missing .NET SDK, an unavailable optional package, a missing
GitHub SSH key) print a `WARNING` and continue instead.

> **Exception — native executables on Windows.** The PowerShell script deliberately sets
> `$PSNativeCommandUseErrorActionPreference = $false`, because `winget upgrade` returns a non-zero
> exit code whenever a package is already current, which would otherwise abort the run. The
> consequence is that failures from `winget` and `git config` are **not** caught and pass silently —
> check their output if a package or your Git identity seems missing afterwards.

Re-running is safe, with two caveats. First, the `.backup` copies the macOS script makes (`~/.zshrc`,
`~/.claude/settings.json`, `~/.pi/agent/*.json`) are **overwritten on every run**, so after a second
run they hold the previous run's files rather than your originals. Two backups do survive re-runs:
the Neovim one (`~/.config/nvim.backup-<timestamp>`) is timestamped, and on Windows the *first*
backup is kept at `$PROFILE.bak` (your original) while later runs write `$PROFILE.<timestamp>.bak`
containing the repo profile — so restore from `$PROFILE.bak`, **not** from a timestamped file.
Second, some configs are replaced with **no backup at all**: on macOS
`~/Library/Application Support/Code/User/settings.json`, `~/.config/ghostty/config`,
`~/.config/yazi/yazi.toml` and `~/custom-theme-oh-my-posh.json`; on Windows the Windows Terminal
and VS Code `settings.json`. Keep your own copy of anything you cannot lose.

### macOS

Requires Git and the Xcode Command Line Tools (`xcode-select --install`). Homebrew is installed
automatically if it's missing.

```sh
git clone https://github.com/BachEndDeveloper/EnvironmentSetup.git
cd EnvironmentSetup
bash "01 - Setup Mac Environment.sh"
```

This runs `brew bundle` against the [`Brewfile`](Brewfile) to install/upgrade all formulae, casks
and fonts; sets up the language runtimes (Node via nvm/LTS, a uv-managed Python, the .NET Aspire
CLI); installs the AI coding-agent CLIs (GitHub Copilot CLI, Claude Code, Pi, and Supacode) plus the
hunk diff reviewer; copies the zsh / Oh My Posh / Ghostty / VS Code / Claude Code / Pi configs into
place (backing up any existing `~/.zshrc`, `~/.claude/settings.json` and `~/.pi/agent/*.json`
first); restores my full LazyVim config into `~/.config/nvim` (plugins, extras and Mason LSPs); and
clones the pinned private AI-Skills repository as Pi's source of repository-managed skills. The
.NET SDK is a manual step (see **.NET / C#** below). Finish by setting the Rider fonts manually
(see [Rider](#rider-manual)).

Homebrew packages are declared in the [`Brewfile`](Brewfile) (the source of truth). Add/remove
entries there; regenerate it from a machine with `brew bundle dump --force --file=Brewfile`, or list
undeclared installs with `brew bundle cleanup --file=Brewfile`.

### Windows

> **Stale — needs a rework before it is trusted.** Not used or tested on a real machine for a long
> time. What is known to be outdated: no AI tooling at all (the macOS script installs Node/nvm, Pi,
> Claude Code, Copilot CLI, Supacode, hunk and the skills bootstrap; this one installs none of
> them), and it still requests `Microsoft.DotNet.SDK.6` and `Microsoft.DotNet.SDK.7`, which are both
> out of support. The error handling and font/profile logic were hardened and verified against a
> real PowerShell parser, but **never executed on Windows** — expect to fix things on first run.

Requires [winget](https://learn.microsoft.com/windows/package-manager/winget/) (App Installer) and
Git. Run from an **elevated (Administrator) PowerShell** — installing fonts writes to the system
fonts folder and registry. The script refuses to run unelevated rather than failing part-way
through.

> **Elevate the *same* account you intend to use.** If you elevate with a different administrator
> account, the script silently writes the PowerShell profile, the Oh My Posh theme,
> `git config --global`, and the Windows Terminal / VS Code settings into *that* account's profile,
> not yours — the installs succeed and the personalisation lands somewhere you won't see it.

```powershell
git clone https://github.com/BachEndDeveloper/EnvironmentSetup.git
cd EnvironmentSetup
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& ".\01 - Setup Windows environment.ps1"
```

This installs the winget packages and bundled fonts, copies the Windows Terminal / PowerShell /
VS Code configs, and prompts for your Git username/email and optional QMK tooling. Afterwards, open
JetBrains Toolbox to install Rider/DataGrip, then set the Rider fonts manually.

### Reviving the WSL/Ubuntu script

`01 - Setup Ubuntu Environment WSL.sh` is **kept for reference only and must not be run as-is**. It
has a syntax error, so it has never executed successfully — `bash -n` fails on it today. It is not
deleted because WSL may come back; if it hasn't been revived by the next review, retire it instead,
because a broken script implies coverage that doesn't exist.

To bring it back, in roughly this order:

1. **Fix the syntax error on line 4** — `if ! command -v brew &> /dev/null then` needs a `;` or a
   newline before `then`. Nothing below this line has ever run. Gate on `bash -n` passing.
2. **Remove every `| echo`** — `brew install $1 | echo "Installed $1"` pipes output *into* `echo`,
   which ignores stdin and prints unconditionally, so every step reports success regardless of
   what happened. There are four of these.
3. **Fix the Linux font paths** — it copies to `/Library/Fonts` and `~/Library/Fonts`, which are
   macOS locations. Use `/usr/share/fonts` or `~/.local/share/fonts`, then `fc-cache -f`. Also fix
   the `cp Font/CascadiaCodeNF/*` typo (the directory is `Fonts/`).
4. **Add `set -euo pipefail`**, as the macOS script now has.
5. **Reconsider Homebrew on Linux** — it installs Linuxbrew just to get `zsh`, `git`, `terraform`,
   `azure-cli` and `exa`. `apt` plus the vendors' own repos is less friction, and `exa` is
   unmaintained (the macOS Brewfile already moved to `eza`).
6. **Decide the scope explicitly** — it currently has no AI tooling, no Neovim, no VS Code config
   and no skills bootstrap. Either port those blocks from the macOS script, or say here that WSL is
   deliberately shell-only.
7. **Back up before overwriting** — it copies `.zshrc` over the existing one with no backup.

The full list, with line references, is in `REVIEW-FINDINGS.md` (finding 1 and Phase B).

## Fonts

I use the [Monaspace](https://monaspace.githubnext.com/) family:

- **Editors** (VS Code, Rider): `Monaspace Neon`
- **Terminals** (Ghostty, VS Code integrated terminal, Rider terminal): `MonaspiceNe Nerd Font`
  (the Nerd-Font-patched Monaspace Neon, for icons/glyphs)
- **Frozen** (`font-monaspace-frozen`): static TTFs with all of Monaspace's stylistic sets baked
  in. Use these in editors that can't configure OpenType features / character variants per-font
  (Rider/JetBrains, Xcode) so ligatures and texture-healing render without extra config.

### macOS

Installed automatically by the setup script via Homebrew casks:

```sh
brew install --cask font-monaspace font-monaspice-nerd-font font-monaspace-frozen
```

### Windows

Font files are bundled in the `Fonts/` folder and installed by the Windows setup script
(Cascadia Code, JetBrains Mono and their Nerd Font variants). Monaspace is not yet wired into
the Windows installer — install it manually from the Monaspace releases or via the Nerd Fonts site.

## macOS specifics

- **Terminal:** Ghostty (config in `ghostty/`). The `iterm2/` folder is kept for history only and
  is no longer used.
- **VS Code:** settings copied to `~/Library/Application Support/Code/User/settings.json`.
- **Shell:** zsh config in `Zsh/`, Oh My Posh theme in `OhMyPosh/`. The `.zshrc` uses
  `bat`, `fzf`, `fd` and `zoxide`, which the setup script installs.
- **Neovim:** the script installs Neovim + ripgrep and restores my
  [LazyVim](https://www.lazyvim.org/) config from `nvim/` into `~/.config/nvim`, then runs
  `:Lazy sync` to install the **latest** LazyVim plus every plugin/extra the config declares (not
  version-pinned) — along with the Mason LSPs/formatters (auto-installed on first launch).
  Any existing config is backed up to `~/.config/nvim.backup-<timestamp>`. See `nvim/README.md`.
- **Claude Code:** my `~/.claude` customizations are captured in `ClaudeCode/` for restore after a
  reinstall — see `ClaudeCode/README.md`. `settings.json` holds the model, effort level, the
  `dotnet-agent-skills` plugin marketplace and the plugins enabled from it, plus an experimental
  flag; it carries **no hooks, no statusline, no secrets and no machine-specific paths**. The GSD
  ("get-shit-done") setup that previously supplied nine hooks and a statusline footer has been
  removed. Claude Code fetches the marketplace and installs the plugins itself on next launch.
- **Pi:** non-secret Pi settings, custom provider/model catalog, and local extensions are captured
  in `Pi/` and restored by the setup script. Repository-managed skills are instead cloned from the
  private AI-Skills repository at its pinned release; the upstream dotnet and Aspire skills are
  cloned into `~/pi-skills/`. Declared packages install on first `pi` launch; no secrets are
  vendored (`/login` per provider afterwards). See `Pi/README.md`.
- **AI coding agents:** the script installs three terminal CLIs — **GitHub Copilot CLI**
  (`gh.io/copilot-install`) and **Claude Code** (`claude.ai/install.sh`) as standalone binaries in
  `~/.local/bin`, and **Pi** (`@earendil-works/pi-coding-agent`) as an npm global. Each needs a
  one-time `/login` on first run. `~/.local/bin` is added to `PATH` in `Zsh/.zshrc`.
  **Supacode** is installed separately via the [`Brewfile`](Brewfile), and **hunk** as an npm
  global (see below).
- **hunk:** [hunk](https://github.com/modem-dev/hunk) (`hunkdiff` on npm) is a review-first terminal
  diff viewer built for reviewing agent-generated changes. Installed as an npm global
  (`npm i -g hunkdiff`, needs Node 18+). Use `hunk diff` to review the working tree (including
  untracked files), `hunk diff --watch` to auto-reload as it changes, and `hunk show [rev]` to
  review a commit. Docs: [hunk.dev](https://hunk.dev).

### Agent skills — who installs what

Skill and plugin *content* is never vendored in this repository; it is always pulled from upstream.
Three sources feed the agents, and one of them feeds two agents through different mechanisms:

| Source | Pi | Claude Code |
| --- | --- | --- |
| [`dotnet/skills`](https://github.com/dotnet/skills) | cloned by the setup script to `~/pi-skills/dotnet-skills` | the `dotnet-agent-skills` plugin marketplace declared in `ClaudeCode/settings.json`; Claude Code clones it into `~/.claude/plugins/` |
| [`microsoft/aspire-skills`](https://github.com/microsoft/aspire-skills) | cloned to `~/pi-skills/aspire-skills` | — |
| [AI-Skills](https://github.com/BachEndDeveloper/AI-Skills) (private) | registered as a local Pi package at a pinned tag | — |
| Supacode | — | Supacode installs its own skills **and** its surface-tracking hooks when it is installed via the [`Brewfile`](Brewfile) |

So `dotnet/skills` ends up cloned **twice** on a machine — once for Pi by the setup script, once for
Claude Code by Claude Code itself. They are independent checkouts at independent commits; that is
expected, but pinning one does not pin the other. Supacode's contributions are deliberately left
out of `ClaudeCode/settings.json`, since vendoring them would fight with Supacode on every launch.

### MCP servers

The [MCP](https://modelcontextprotocol.io/) servers this machine runs are declared in
[`MCP/servers.json`](MCP/servers.json) and installed by `MCP/install-mcp-servers.sh`, which the
setup script calls. Each is kept as a deployment copy at a pinned tag (under `~/.local/share/mcp/`,
never a working checkout), built, and registered with all three MCP hosts.
Adding another server is a data change in `servers.json`, not a code change.

Each host is registered through the mechanism it owns:

- **Claude Desktop** — its config is merged directly (small, configuration-only), touching only the
  `mcpServers` key and writing a `.backup` first.
- **Claude Code** — registered through its own `claude mcp add-json --scope user` CLI.
  `~/.claude.json` is **never** hand-edited: it holds ~73 KB of live project and session state, and
  a whole-file write would destroy it.
- **Pi** — registered through its own `pi mcp add`, using Pi's built-in MCP support.

Every host launches servers through `~/.local/bin/mcp-node`, which follows nvm's `default` alias, so
upgrading or removing a Node version does not break a host. See [`MCP/README.md`](MCP/README.md).

No secrets or tenant ids live here. To override the M365 tenant on a machine:

```sh
M365_TENANT_ID=<your-tenant-id> bash "01 - Setup Mac Environment.sh"
```

Each server prints its own one-time sign-in step (for m365, `npm run auth`) at the end of its
install. See [`MCP/README.md`](MCP/README.md) for the full pattern.

The m365 server's two capability gates — `ALLOW_SEND` and `ALLOW_DELETE`, both default-off — are set
in `MCP/servers.json`, never in a host's own config: the installer rebuilds each host `env` block
from that file and drops anything added by hand. See
[Capability gates](MCP/README.md#capability-gates).

### Personal AI skills

Personal skills live in the private [AI-Skills](https://github.com/BachEndDeveloper/AI-Skills)
repository rather than in this machine-setup repository. The macOS setup script always clones it to
`~/source/AI-Skills` (or `AI_SKILLS_DIR`), checks out a pinned release, and registers it as a local
Pi package.

The repository URL and the pinned release are deliberately hardcoded near the Pi installation block
in `01 - Setup Mac Environment.sh` — see `AI_SKILLS_REPO` and `AI_SKILLS_REF` there for the current
values (the tag is deliberately not repeated here, so there is one source of truth). Update those
two values when the repository moves or you want a newer reviewed skill release. Because the
repository is private, a new machine must have GitHub SSH access configured before this step runs;
if it doesn't, the clone (or, on a re-run, the fetch) prints a `WARNING`, a second one covers the
checkout and local install, the skills bootstrap is skipped, and the rest of the setup continues to
completion.

## Languages & runtimes

The macOS script installs and configures these automatically:

- **Node** — via [nvm](https://github.com/nvm-sh/nvm), defaulting to the latest **LTS**
  (`nvm install --lts`). Install a Current release on demand with `nvm install node`.
- **Python** — managed by [uv](https://docs.astral.sh/uv/) (installed as a Homebrew formula).
  `uv python install` provides the latest stable CPython. Pin per project with a `.python-version`
  file or `requires-python`; `uv run` / `uv sync` auto-download the matching version. uv replaces
  pyenv, pip, venv and pipx (use `uv tool install` for global tools).
- **.NET Aspire CLI** — installed via `aspire.dev/install.sh` into `~/.aspire/bin` (already on
  `PATH`). It needs the .NET SDK, so **install .NET first** — the setup script skips Aspire (with a
  warning) if `dotnet` isn't on `PATH`; just re-run setup after installing .NET.

### .NET / C #

Install the .NET SDK with the **official installer** (not Homebrew), so it lands at the standard
`/usr/local/share/dotnet` location:

1. Download the latest **LTS** SDK installer (`.pkg`, Arm64 for Apple Silicon) from
   <https://dotnet.microsoft.com/download/dotnet>.
2. Run the `.pkg` and follow the prompts.
3. Verify with `dotnet --version` and `dotnet --list-sdks`.

The `.zshrc` sets `DOTNET_ROOT=/usr/local/share/dotnet` (the official installer's path) and adds
`~/.dotnet/tools` to `PATH` for global tools. .NET releases on even-numbered majors (8, 10, …) are
LTS; odd-numbered (9, 11, …) are STS — prefer LTS unless you need the newer one.

Do this **before** running the setup script so the Aspire CLI step can find `dotnet` (otherwise the
script skips Aspire and you re-run setup afterwards).

## Rider (manual)

Rider settings aren't portable, so set these by hand after install:
enable the new UI, set the **editor font to `Monaspace Neon`** (ligatures on), set the
**terminal font to `MonaspiceNe Nerd Font`**, theme Rider Night, and install the Azure Toolkit +
Rainbow Brackets plugins.
