# Fig pre block. Keep at the top of this file.
[[ -f "$HOME/.fig/shell/zshrc.pre.zsh" ]] && builtin source "$HOME/.fig/shell/zshrc.pre.zsh"
# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

export DOTNET_ROOT=$HOME/.dotnet
export PATH=$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools
export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm

export PATH=$HOME/homebrew/bin:$PATH

alias code="open -a /Applications/Visual\ Studio\ Code.app"\
alias code="o -a /Applications/Visual\ Studio\ Code.app"\

export TERRAFORM_ROOT=$HOME/.terraform
export PATH=$PATH:$TERRAFORM_ROOT

alias ls='exa --icons --group-directories-first'
alias ll='exa -l --icons --no-user --group-directories-first  --time-style long-iso'
alias la='exa -la --icons --no-user --group-directories-first  --time-style long-iso'

eval "$(oh-my-posh init zsh --config $HOME/custom-theme-oh-my-posh.rev2.json)"

#setopt menu_complete
setopt list_ambiguous
setopt auto_list

# Fig post block. Keep at the bottom of this file.
[[ -f "$HOME/.fig/shell/zshrc.post.zsh" ]] && builtin source "$HOME/.fig/shell/zshrc.post.zsh"

source /Users/e144259/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /Users/e144259/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh