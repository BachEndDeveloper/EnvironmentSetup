# Setup Ubuntu
# Install Homebrew

if ! command -v brew &> /dev/null then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" | echo "HOMEBREW installed!"

    test -d ~/.linuxbrew && eval "$(~/.linuxbrew/bin/brew shellenv)"
    test -d /home/linuxbrew/.linuxbrew && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    test -r ~/.bash_profile && echo "eval \"\$($(brew --prefix)/bin/brew shellenv)\"" >> ~/.bash_profile
    echo "eval \"\$($(brew --prefix)/bin/brew shellenv)\"" >> ~/.profile

    sudo apt-get install build-essential procps curl file git
else
    brew update | echo "HOMEBREW updated!"
fi

# Method for installing or upgrade brew packages.
InstallOrUpdate() {
    installed=$(brew ls --versions $1)
    if [[ -z "$installed"  ]] ; then
        brew install $2 $1 | echo "Installed $1"
    else
        brew upgrade $1 | echo "Tried upgrading $1"
    fi
}


# Packages to install
InstallOrUpdate zsh
InstallOrUpdate zsh-syntax-highlighting
InstallOrUpdate zsh-autosuggestions
InstallOrUpdate terraform
InstallOrUpdate azure-cli
InstallOrUpdate jandedobbeleer/oh-my-posh/oh-my-posh
InstallOrUpdate git
InstallOrUpdate exa

# Install Fonts
## TODO copy the fonts
# Go into each font fold in repo and install. 
cp Fonts/CascadiaCode/* /Library/Fonts
cp Fonts/CascadiaCode/* ~/Library/Fonts

cp Fonts/CascadiaCodeNF/* /Library/Fonts
cp Font/CascadiaCodeNF/* ~/Library/Fonts

cp OhMyPosh/custom-theme-oh-my-posh.json $HOME
cp Zsh/.zshrc $HOME

echo "Set fonts in terminal to NF font. Set IDE fonts aswell."
