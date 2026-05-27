# Setup Mac
# WORK IN PROGRESS

# Install Homebrew
which -s brew
if [[ $? != 0 ]] ; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    PATH=$PATH:/opt/homebrew/bin
else
    brew update
    echo "HOMEBREW updated!"
fi

brew upgrade
# Method for installing or upgrade brew packages.
InstallOrUpdate() {
    echo "Checking if $1 is installed. (Is a cask: $2)"
    installed=$(brew ls $1)
    if [[ -z "$installed"  ]] ; then
        echo "Installing $1"
        brew install $2 $1
        echo "Installed $1"
    else 
        echo "$1 is already installed"
    fi
}

# Packages to install
InstallOrUpdate rider --cask
InstallOrUpdate datagrip --cask
InstallOrUpdate visual-studio-code --cask
InstallOrUpdate ghostty --cask

# Fonts: Monaspace Neon for editors, Monaspice Neon Nerd Font for terminals
InstallOrUpdate font-monaspace --cask
InstallOrUpdate font-monaspace-nerd-font --cask
InstallOrUpdate zsh
InstallOrUpdate zsh-syntax-highlighting
InstallOrUpdate zsh-autosuggestions
InstallOrUpdate terraform
InstallOrUpdate azure-cli
InstallOrUpdate jandedobbeleer/oh-my-posh/oh-my-posh
InstallOrUpdate fork --cask
InstallOrUpdate commander-one --cask
InstallOrUpdate rectangle-pro --cask
InstallOrUpdate git
InstallOrUpdate alt-tab --cask
InstallOrUpdate eza
# CLI tools: shell (.zshrc) uses bat/fzf/fd/zoxide; Neovim/LazyVim needs neovim/ripgrep/fd; yazi is a terminal file manager
InstallOrUpdate bat
InstallOrUpdate fzf
InstallOrUpdate fd
InstallOrUpdate zoxide
InstallOrUpdate ripgrep
InstallOrUpdate neovim
InstallOrUpdate yazi
InstallOrUpdate bartender --cask

brew tap azure/functions
InstallOrUpdate azure-functions-core-tools@4
# if upgrading on a machine that has 2.x or 3.x installed:
brew link --overwrite azure-functions-core-tools@4

# Install Azure Developer CLI
brew tap azure/azd
InstallOrUpdate azd

# Install bicep CLI
brew tap azure/bicep
InstallOrUpdate bicep

# Install DotNet SDK
# curl -sSL https://dot.net/v1/dotnet-install.sh | sh -s -- --channel LTS

# Fonts are installed via Homebrew casks above (font-monaspace, font-monaspace-nerd-font).
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
