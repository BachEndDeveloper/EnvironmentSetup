# Fig pre block. Keep at the top of this file.
#[[ -f "$HOME/.fig/shell/zshrc.pre.zsh" ]] && builtin source "$HOME/.fig/shell/zshrc.pre.zsh"
#export PATH=$PATH:~/.fig/bin:~/.local/bin

export DOTNET_ROOT=$HOME/.dotnet
export PATH=$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools
export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm

autoload -Uz compinit
compinit

export PATH=$PATH:/usr/local/git/bin

eval $(/opt/homebrew/bin/brew shellenv)

alias fork="open -a /Applications/Fork.app"
alias code="open -a /Applications/Visual\ Studio\ Code.app"
alias rider="open -a /Applications/Rider.app"

export TERRAFORM_ROOT=$HOME/.terraform
export PATH=$PATH:$TERRAFORM_ROOT

alias ls='eza --icons --group-directories-first'
alias ll='eza -l --icons --no-user --group-directories-first  --time-style long-iso'
alias la='eza -la --icons --no-user --group-directories-first  --time-style long-iso'

eval "$(oh-my-posh init zsh --config $HOME/custom-theme-oh-my-posh.rev2.json)"

#setopt menu_complete
setopt list_ambiguous
setopt auto_list

#source $HOME/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
#source $HOME/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

_dotnet_zsh_complete()
{
  local completions=("$(dotnet complete "$words")")

  # If the completion list is empty, just continue with filename selection
  if [ -z "$completions" ]
  then
    _arguments '*::arguments: _normal'
    return
  fi

  # This is not a variable assignment, don't remove spaces!
  _values = "${(ps:\n:)completions}"
}

compdef _dotnet_zsh_complete dotnet

# Fig post block. Keep at the bottom of this file.
#[[ -f "$HOME/.fig/shell/zshrc.post.zsh" ]] && builtin source "$HOME/.fig/shell/zshrc.post.zsh"
