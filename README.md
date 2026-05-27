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

This installs the Homebrew formulae, casks and fonts; sets up the language runtimes (Node via
nvm/LTS, a uv-managed Python, the .NET Aspire CLI); copies the zsh / Oh My Posh / Ghostty /
VS Code / Claude Code configs into place (backing up any existing `~/.zshrc` and
`~/.claude/settings.json` first); and bootstraps LazyVim into `~/.config/nvim`. The .NET SDK is a
manual step (see **.NET / C#** below). Finish by setting the Rider fonts manually
(see [Rider](#rider-manual)).

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

### macOS
Installed automatically by the setup script via Homebrew casks:

```sh
brew install --cask font-monaspace font-monaspace-nerd-font
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
- **Neovim:** the script installs Neovim + ripgrep and bootstraps the official
  [LazyVim](https://www.lazyvim.org/) starter into `~/.config/nvim` (only if no config exists yet).
- **Claude Code:** my `~/.claude` customizations (settings + statusline footer) are captured in
  `ClaudeCode/` for restore after a reinstall — see `ClaudeCode/README.md`.

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

### .NET / C#

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
