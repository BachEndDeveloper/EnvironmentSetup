# Homebrew (must be early so $HOMEBREW_PREFIX is set)
eval "$(/opt/homebrew/bin/brew shellenv)"

# NVM
export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# PATH additions
export PATH="$HOME/.local/bin:$PATH"   # Copilot CLI + Claude Code (native installers)
export PATH="$HOME/.dotnet/tools:$PATH"
export PATH="$HOME/.aspire/bin:$PATH"
export DOTNET_ROOT="/usr/local/share/dotnet"

# History
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY

# Completions (fpath must be set before compinit)
fpath=($HOME/.docker/completions $fpath)
autoload -Uz compinit
compinit

# Prompt
eval "$(oh-my-posh init zsh --config $HOME/custom-theme-oh-my-posh.json)"

# Aliases
alias fork="open -a /Applications/Fork.app"
alias code="open -a /Applications/Visual\ Studio\ Code.app"
alias rider="open -a /Applications/Rider.app"
alias ls='eza --icons --group-directories-first'
alias ll='eza -l --icons --no-user --group-directories-first --time-style long-iso'
alias la='eza -la --icons --no-user --group-directories-first --time-style long-iso'
alias cat='bat --paging=never'

# Shell options
setopt list_ambiguous
setopt auto_list

# Plugins
source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh

# fzf
source <(fzf --zsh)
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'

# zoxide
eval "$(zoxide init zsh)"

# .NET CLI completions
_dotnet_zsh_complete() {
  local completions=("$(dotnet complete "$words")")
  if [ -z "$completions" ]; then
    _arguments '*::arguments: _normal'
    return
  fi
  _values = "${(ps:\n:)completions}"
}
compdef _dotnet_zsh_complete dotnet

# Syntax highlighting (must be sourced last, after all widgets/keybindings)
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
