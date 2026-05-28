# Brewfile — declarative list of Homebrew packages for the macOS setup.
#
# Install / upgrade everything (run from the repo root):
#   brew bundle --upgrade --file="Brewfile"
# Regenerate this file from the current machine:
#   brew bundle dump --force --file="Brewfile"
# See what's installed but NOT declared here:
#   brew bundle cleanup --file="Brewfile"

# --- Taps ---
tap "azure/functions"
tap "azure/azd"
tap "azure/bicep"
tap "jandedobbeleer/oh-my-posh"

# --- Shell & prompt ---
brew "zsh"
brew "zsh-autosuggestions"
brew "zsh-syntax-highlighting"
brew "jandedobbeleer/oh-my-posh/oh-my-posh"

# --- CLI tools ---
brew "git"
brew "eza"                # ls replacement (aliased in .zshrc)
brew "bat"                # cat replacement (aliased in .zshrc)
brew "fzf"                # fuzzy finder (.zshrc integration)
brew "fd"                 # find replacement / fzf + LazyVim
brew "ripgrep"            # grep replacement / LazyVim + fzf
brew "zoxide"             # smarter cd (.zshrc integration)
brew "yazi"               # terminal file manager
brew "poppler"            # Yazi PDF preview (pdftoppm)
brew "resvg"              # Yazi SVG preview
brew "ffmpeg"             # Yazi video preview (decoder)
brew "ffmpegthumbnailer"  # Yazi video thumbnails
brew "imagemagick"        # Yazi fallback image rasterizer
brew "sevenzip"           # Yazi archive contents preview
brew "neovim"             # editor (LazyVim)
brew "uv"                 # Python toolchain / version manager

# --- Azure / cloud ---
brew "azure-cli"
brew "azure-functions-core-tools@4", link: true
brew "azd"
brew "bicep"

# --- Apps ---
cask "visual-studio-code"
cask "rider"
cask "datagrip"
cask "ghostty"
cask "fork"
cask "commander-one"
cask "rectangle-pro"
cask "alt-tab"
cask "hiddenbar"

# --- Fonts ---
cask "font-monaspace"             # Monaspace Neon (editors)
cask "font-monaspace-nerd-font"   # MonaspiceNe Nerd Font (terminals)
