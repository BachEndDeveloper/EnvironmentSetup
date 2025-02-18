# Setup Mac
# WORK IN PROGRESS

# Install Homebrew
which -s brew
if [[ $? != 0 ]] ; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    PATH=$PATH:/opt/homebrew/bin
else
    brew update | echo "HOMEBREW updated!"
fi

brew upgrade
# Method for installing or upgrade brew packages.
InstallOrUpdate() {
    echo "Checking if $1 is installed. (Is a cask: $2)"
    installed=$(brew ls $1)
    if [[ -z "$installed"  ]] ; then
        echo "Installing $1"
        brew install $2 $1 | echo "Installed $1"
    else 
        echo "$1 is already installed"
    fi
}

# Packages to install
InstallOrUpdate jetbrains-toolbox --cask 
InstallOrUpdate visual-studio-code --cask 
InstallOrUpdate iterm2 --cask 
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
InstallOrUpdate amazon-q --cask
InstallOrUpdate alt-tab --cask
InstallOrUpdate eza
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

# Install Fonts
## TODO copy the fonts
# Go into each font fold in repo and install. 
# cp Fonts/CascadiaCode/* /Library/Fonts
# cp Fonts/CascadiaCode/* ~/Library/Fonts

# cp Fonts/CascadiaCodeNF/* /Library/Fonts
# cp Fonts/CascadiaCodeNF/* ~/Library/Fonts

# cp OhMyPosh/custom-theme-oh-my-posh.json $HOME
# cp Zsh/.zshrc $HOME

# echo "Set fonts in terminal to NF font. Set IDE fonts aswell."

# cp VSCode/settings.json $HOME/.config/code/User/

# cp iterm2/com.googlecode.iterm2.plist.xml iterm2/com.googlecom.iterm2.plist
# plutil -convert binary1 iterm2/com.googlecode.iterm2.plist

# mv ~/Library/Preferences/com.googlecode.iterm2.plist ~/Library/Preferences/com.googlecode.iterm2.plist.backup
# mv iterm2/com.googlecode.iterm2.plist ~/Library/Preferences/com.googlecode.iterm2.plist
