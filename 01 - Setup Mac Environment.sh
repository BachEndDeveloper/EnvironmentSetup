# Setup Mac

# Install Homebrew
which -s brew
if [[ $? != 0 ]] ; then
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

# Fonts are installed via the Brewfile (font-monaspace, font-monaspace-nerd-font).
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

# Bootstrap LazyVim (official starter) - only if no Neovim config exists yet
if [ ! -d "$HOME/.config/nvim" ]; then
    echo "Installing LazyVim starter into ~/.config/nvim"
    git clone https://github.com/LazyVim/starter "$HOME/.config/nvim"
    rm -rf "$HOME/.config/nvim/.git"
else
    echo "~/.config/nvim already exists - skipping LazyVim bootstrap"
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

echo "Done. In Rider: set editor font to 'Monaspace Neon' (ligatures on) and terminal font to 'MonaspiceNe Nerd Font'."
