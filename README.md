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

This installs the Homebrew formulae, casks and fonts; copies the zsh / Oh My Posh / Ghostty /
VS Code / Claude Code configs into place (backing up any existing `~/.zshrc` and
`~/.claude/settings.json` first); and bootstraps LazyVim into `~/.config/nvim`. Finish by setting
the Rider fonts manually (see [Rider](#rider-manual)).

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

## Rider (manual)
Rider settings aren't portable, so set these by hand after install:
enable the new UI, set the **editor font to `Monaspace Neon`** (ligatures on), set the
**terminal font to `MonaspiceNe Nerd Font`**, theme Rider Night, and install the Azure Toolkit +
Rainbow Brackets plugins.
