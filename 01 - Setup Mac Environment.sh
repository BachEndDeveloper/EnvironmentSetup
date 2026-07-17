# Setup Mac

# Install Homebrew
which -s brew
if [[ $? != 0 ]]; then
	/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	PATH=$PATH:/opt/homebrew/bin
else
	brew update
	echo "HOMEBREW updated!"
fi

# Install / upgrade all declared Homebrew taps, formulae, casks and fonts (see Brewfile).
# brew bundle is idempotent and reports failures loudly; --upgrade also updates what's installed.
brew bundle --upgrade --file="Brewfile"

# azure-functions-core-tools@4: ensure it's linked even when upgrading from an older major.
brew link --overwrite --quiet azure-functions-core-tools@4 2>/dev/null || true

# --- Languages & runtimes ---

# Node via nvm, defaulting to LTS (.zshrc loads nvm; install nvm here if missing).
export NVM_DIR="$HOME/.nvm"
if [ ! -s "$NVM_DIR/nvm.sh" ]; then
	echo "Installing nvm"
	curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
fi
. "$NVM_DIR/nvm.sh"
nvm install --lts
nvm alias default 'lts/*'

# --- AI coding agents ---

# GitHub Copilot CLI — standalone binary to ~/.local/bin (no Node required).
curl -fsSL https://gh.io/copilot-install | bash

# Claude Code CLI — native installer; auto-updates in the background (no Node required).
curl -fsSL https://claude.ai/install.sh | sh

# Pi coding agent CLI — npm-only (nvm/Node installed above; --ignore-scripts per pi.dev docs).
npm install -g --ignore-scripts @earendil-works/pi-coding-agent

# Python managed by uv (uv installed via the Brewfile above). Installs the latest stable CPython.
uv python install

# .NET SDK is installed manually via the official installer (not Homebrew) - see README "## .NET / C#".
# The Aspire CLI needs the .NET SDK, so only install it once dotnet is on PATH.
if command -v dotnet >/dev/null 2>&1; then
	# .NET Aspire CLI -> installs to ~/.aspire/bin (already on PATH via .zshrc).
	curl -sSL https://aspire.dev/install.sh | bash
else
	echo "WARNING: .NET SDK not found - skipping Aspire CLI."
	echo "         Install .NET (see README '## .NET / C#'), then re-run this script."
fi

# Fonts are installed via the Brewfile (font-monaspace, font-monaspace-nerd-font, font-monaspace-frozen).
# Editor font: "Monaspace Neon"  |  Terminal font: "MonaspiceNe Nerd Font"

# Copy Oh My Posh theme and zsh config (back up any existing .zshrc first)
cp OhMyPosh/custom-theme-oh-my-posh.json "$HOME/"
[ -f "$HOME/.zshrc" ] && cp "$HOME/.zshrc" "$HOME/.zshrc.backup"
cp Zsh/.zshrc "$HOME/.zshrc"

# Copy VS Code settings (correct macOS path)
VSCODE_USER="$HOME/Library/Application Support/Code/User"
mkdir -p "$VSCODE_USER"
cp VSCode/settings.json "$VSCODE_USER/settings.json"

# Copy Ghostty terminal config (replaces the retired iTerm2 setup)
mkdir -p "$HOME/.config/ghostty"
cp ghostty/config "$HOME/.config/ghostty/config"

# Copy Yazi file manager config (preview tooling installed via Brewfile)
mkdir -p "$HOME/.config/yazi"
cp yazi/yazi.toml "$HOME/.config/yazi/yazi.toml"

# Restore my Neovim / LazyVim config (vendored in nvim/ - see nvim/README.md).
# The config declares WHAT I run - my LazyVim extras and Mason LSPs/formatters - and the
# sync below installs the LATEST LazyVim plus every plugin/extra it declares (no version
# pinning, so I get current versions at the time I run this). Needs neovim + ripgrep (Brewfile).
if [ -d "$HOME/.config/nvim" ]; then
	nvim_backup="$HOME/.config/nvim.backup-$(date +%Y%m%d%H%M%S)"
	echo "Backing up existing ~/.config/nvim to $nvim_backup"
	mv "$HOME/.config/nvim" "$nvim_backup"
fi
mkdir -p "$HOME/.config/nvim"
cp -R nvim/. "$HOME/.config/nvim/"
# Install the latest LazyVim + all declared plugins/extras (Lazy sync). Mason installs the
# LSPs/formatters listed in lua/plugins/mason-tools.lua on the first interactive 'nvim' launch.
if command -v nvim >/dev/null 2>&1; then
	echo "Installing Neovim plugins (Lazy sync, latest versions)..."
	nvim --headless "+Lazy! sync" +qa || echo "WARNING: 'Lazy sync' failed - run ':Lazy sync' inside nvim."
else
	echo "WARNING: nvim not found - skipping plugin install (the Brewfile installs neovim)."
fi

# Restore Claude Code customizations (settings + statusline footer + hooks).
# NOTE: settings.json references node via an absolute nvm path and the GSD setup;
#       re-enable the plugins listed in ClaudeCode/README.md and fix paths after install.
if [ -d "$HOME/.claude" ]; then
	[ -f "$HOME/.claude/settings.json" ] && cp "$HOME/.claude/settings.json" "$HOME/.claude/settings.json.backup"
	cp ClaudeCode/settings.json "$HOME/.claude/settings.json"
	mkdir -p "$HOME/.claude/hooks"
	cp ClaudeCode/hooks/* "$HOME/.claude/hooks/" 2>/dev/null || true
fi

# Restore Pi coding agent customizations (settings + custom provider/model catalog + local
# extensions/skills). NO secrets are vendored: run 'pi' then /login per provider, and set your
# Azure AI Foundry resource name in ~/.pi/agent/models.json (templated). See Pi/README.md.
PI_DIR="$HOME/.pi/agent"
if command -v pi >/dev/null 2>&1 || [ -d "$PI_DIR" ]; then
	mkdir -p "$PI_DIR/extensions"
	[ -f "$PI_DIR/settings.json" ] && cp "$PI_DIR/settings.json" "$PI_DIR/settings.json.backup"
	[ -f "$PI_DIR/models.json" ] && cp "$PI_DIR/models.json" "$PI_DIR/models.json.backup"
	cp Pi/settings.json "$PI_DIR/settings.json"
	cp Pi/models.json "$PI_DIR/models.json"
	cp -R Pi/extensions/. "$PI_DIR/extensions/"
	echo "Pi config restored. Declared packages install on first 'pi' launch (or 'pi update --extensions')."
	echo "         Remember: 'pi' + /login per provider, and set your Foundry resource in ~/.pi/agent/models.json."
fi

# Personal AI skills — private, version-pinned source of truth for Pi skills.
# This runs after Pi settings are restored so `pi install` records the package persistently.
# Update the repository URL or release tag here when the personal library moves or releases.
AI_SKILLS_REPO="git@github.com:BachEndDeveloper/AI-Skills.git"
AI_SKILLS_REF="v0.2.1"
AI_SKILLS_DIR="${AI_SKILLS_DIR:-$HOME/source/AI-Skills}"

if [[ -d "$AI_SKILLS_DIR/.git" ]]; then
    git -C "$AI_SKILLS_DIR" fetch --tags --prune origin
elif [[ -e "$AI_SKILLS_DIR" ]]; then
    echo "ERROR: $AI_SKILLS_DIR exists but is not a Git checkout." >&2
    exit 1
else
    mkdir -p "$(dirname "$AI_SKILLS_DIR")"
    git clone "$AI_SKILLS_REPO" "$AI_SKILLS_DIR"
fi

git -C "$AI_SKILLS_DIR" checkout --detach "$AI_SKILLS_REF"
bash "$AI_SKILLS_DIR/scripts/install-local.sh"

# External skills referenced by Pi settings.json. Keep upstream-managed skills out of the
# shared snapshot so their repositories can evolve independently.
PI_SKILLS_DIR="$HOME/pi-skills"
if [ ! -d "$PI_SKILLS_DIR/dotnet-skills" ]; then
	mkdir -p "$PI_SKILLS_DIR"
	git clone https://github.com/dotnet/skills.git "$PI_SKILLS_DIR/dotnet-skills" || echo "WARNING: failed to clone dotnet/skills."
fi
echo "Done. In Rider: set editor font to 'Monaspace Neon' (ligatures on) and terminal font to 'MonaspiceNe Nerd Font'."
