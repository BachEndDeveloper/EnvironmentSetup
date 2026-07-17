# EnvironmentSetup

Scripts, fonts and profiles for setting up a new machine to my specs.

- macOS: `01 - Setup Mac Environment.sh` (Homebrew-based)
- Windows: `01 - Setup Windows environment.ps1` (winget-based)
- WSL/Ubuntu: `01 - Setup Ubuntu Environment WSL.sh`

## Running the setup

Run the script **from the repo root** — it copies config files using relative paths. Both scripts
are idempotent: re-running updates installed packages and skips what's already present.

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
CLI); installs the AI coding-agent CLIs (GitHub Copilot CLI, Claude Code, Pi); copies the zsh /
Oh My Posh / Ghostty / VS Code / Claude Code / Pi configs into place (backing up
any existing `~/.zshrc`, `~/.claude/settings.json` and `~/.pi/agent/*.json` first); restores my
full LazyVim config into `~/.config/nvim` (plugins, extras and Mason LSPs); and restores my
user-managed Agent Skills into `~/.agents/skills`. The .NET SDK is a manual step (see **.NET / C#**
below). Finish by setting the Rider fonts manually (see [Rider](#rider-manual)).

Homebrew packages are declared in the [`Brewfile`](Brewfile) (the source of truth). Add/remove
entries there; regenerate it from a machine with `brew bundle dump --force --file=Brewfile`, or list
undeclared installs with `brew bundle cleanup --file=Brewfile`.

### Windows

Requires [winget](https://learn.microsoft.com/windows/package-manager/winget/) (App Installer) and
Git. Run from an **elevated (Administrator) PowerShell** — installing fonts writes to the system
fonts folder and registry.

```powershell
git clone https://github.com/BachEndDeveloper/EnvironmentSetup.git
cd EnvironmentSetup
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& ".\01 - Setup Windows environment.ps1"
```

This installs the winget packages and bundled fonts, copies the Windows Terminal / PowerShell /
VS Code configs, and prompts for your Git username/email and optional QMK tooling. Afterwards, open
JetBrains Toolbox to install Rider/DataGrip, then set the Rider fonts manually.

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
brew install --cask font-monaspace font-monaspace-nerd-font font-monaspace-frozen
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
- **Claude Code:** my `~/.claude` customizations (settings + statusline footer) are captured in
  `ClaudeCode/` for restore after a reinstall — see `ClaudeCode/README.md`.
- **Pi and shared Agent Skills:** my `~/.pi/agent` config (settings, custom provider/model
  catalog, and Pi-local extensions/skills) and my user-managed `~/.agents/skills` collection are
  captured in `Pi/` and restored by the setup script. The dotnet and Aspire skills remain
  upstream-managed repositories cloned into `~/pi-skills/`. Declared packages install on first
  `pi` launch; no secrets are vendored (`/login` per provider afterwards). See `Pi/README.md`.
- **AI coding agents:** the script installs three terminal CLIs — **GitHub Copilot CLI**
  (`gh.io/copilot-install`) and **Claude Code** (`claude.ai/install.sh`) as standalone binaries in
  `~/.local/bin`, and **Pi** (`@earendil-works/pi-coding-agent`) as an npm global. Each needs a
  one-time `/login` on first run. `~/.local/bin` is added to `PATH` in `Zsh/.zshrc`.

### Personal AI skills (optional)

Personal skills live in their own private repository rather than in this machine-setup repository.
To clone that repository and register it as a local Pi package during macOS setup, set its Git URL
before running the setup script:

```sh
export AI_SKILLS_REPO='git@github.com:BachEndDeveloper/AI-Skills.git'
# Optional: use a release tag or commit rather than the repository default branch.
export AI_SKILLS_REF='v0.2.0'
bash "01 - Setup Mac Environment.sh"
```

The setup script clones the checkout to `~/source/AI-Skills` (or `AI_SKILLS_DIR`), updates it, then
runs its `scripts/install-local.sh`. On a new or shared machine, prefer a private remote and pin
`AI_SKILLS_REF` to a reviewed tag or commit. If `AI_SKILLS_REPO` is unset, the setup script skips
this optional step.

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
