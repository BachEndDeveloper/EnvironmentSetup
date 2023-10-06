$installedPrograms = winget list

function InstallApplication($applicationId)
{
    if ($installedPrograms -like "*"+$applicationId+"*")
    {
        Write-Output ($applicationId + " exists. Trying to upgrade")
        winget upgrade $applicationId -e --silent
    }
    else {
        Write-Output ($applicationId + " does not exist")
        winget install $applicationId -e --silent
    }
}

InstallApplication("Microsoft.VisualStudioCode")
InstallApplication("JanDeDobbeleer.OhMyPosh")
InstallApplication("Git.Git")
InstallApplication("Microsoft.NuGet")
InstallApplication("JetBrains.Toolbox")
InstallApplication("Microsoft.DotNet.SDK.6")
InstallApplication("Microsoft.DotNet.SDK.7")
InstallApplication("Microsoft.PowerShell")
InstallApplication("Microsoft.WindowsTerminal")
InstallApplication("Fork.Fork")
InstallApplication("Microsoft.AzureCLI")
InstallApplication("Microsoft.Bicep")
InstallApplication("Hashicorp.Terraform")
InstallApplication("Postman.Postman")
InstallApplication("Ghisler.TotalCommander")
InstallApplication("Notepad++.Notepad++")
InstallApplication("GitHub.cli")
InstallApplication("Microsoft.Azd")
InstallApplication("Mozilla.Firefox")


if (Get-Module -ListAvailable -Name Terminal-Icons) {
    Write-Host "Terminal-Icons module is already installed"
} 
else {
    Write-Host "Installing Terminal-Icons"
    Install-Module -Name Terminal-Icons -Repository PSGallery
}

Install-Module posh-git -Scope CurrentUser -Force

if (Get-Module -ListAvailable -Name PSReadLine) {
    Write-Host "PSReadLine module is already installed"
} 
else {
    Write-Host "Installing PSReadLine"
    Install-Module -Name PSReadLine -Repository PSGallery
}


Write-Output "Install fonts, setup font in Terminal/PowerShell, setup powershell profile and OhMyPoshTheme."
Write-Output "Open JetBrains Toolbox and install Rider and DataGrip."
Write-Output "In Rider: install Azure Toolkit and Rainbow Brackets. Enable new UI, set font to Cascadia Code, enable ligatures and set theme to Rider Night."

function InstallFont($fontToInstall)
{
    if (!($installedFonts -like "*" + $fontToInstall.Name + "*"))
    {
        Write-Output ('Installing font -' + $fontToInstall.BaseName)
        Copy-Item $Font "C:\Windows\Fonts"
        New-ItemProperty -Name $fontToInstall.BaseName -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts" -PropertyType string -Value $fontToInstall.name         
    }
    else 
    {
        Write-Output ($fontToInstall.Name + " already installed")
    }
}

# Getting machine wide installed fonts
$installedFonts = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'

#Install Cascadia Code font
$FontFolder = "Fonts\CascadiaCode"
$FontItem = Get-Item -Path $FontFolder
$FontList = Get-ChildItem -Path "$FontItem\*" -Include ('*.fon','*.otf','*.ttc','*.ttf')

foreach ($Font in $FontList) 
{
        InstallFont($Font)        
}

#Install Caskaydia Cove Nerd font
$FontFolder = "Fonts\CascadiaCodeNF"
$FontItem = Get-Item -Path $FontFolder
$FontList = Get-ChildItem -Path "$FontItem\*" -Include ('*.fon','*.otf','*.ttc','*.ttf')

foreach ($Font in $FontList) 
{
        InstallFont($Font)        
}

#Install JetBrains Mono font
$FontFolder = "Fonts\JetBrainsMono"
$FontItem = Get-Item -Path $FontFolder
$FontList = Get-ChildItem -Path "$FontItem\*" -Include ('*.fon','*.otf','*.ttc','*.ttf')

foreach ($Font in $FontList) 
{
        InstallFont($Font)        
}

#Install JetBrains Mono Nerd font
$FontFolder = "Fonts\JetBrainsMonoNF"
$FontItem = Get-Item -Path $FontFolder
$FontList = Get-ChildItem -Path "$FontItem\*" -Include ('*.fon','*.otf','*.ttc','*.ttf')

foreach ($Font in $FontList) 
{
        InstallFont($Font)        
}

# Saving OhMyPosh theme to $HOME directory.
if (-NOT (Test-Path "$HOME\custom-theme-oh-my-posh.json"))
{
    Copy-Item "OhMyPosh\custom-theme-oh-my-posh.json" $HOME
    Write-Output "custom-theme-oh-my-posh.json was copied to HOME"
}


if (-NOT (Test-Path $PROFILE))
{
    New-Item -path $PROFILE -type File -force
    Write-Output "PowerShell PROFILE was created"
}

if ([String]::IsNullOrWhiteSpace((Get-content $PROFILE)))
{
    Add-Content $PROFILE -Value "`r`noh-my-posh init pwsh --config (`"$HOME\custom-theme-oh-my-posh.json`") | Invoke-Expression"
    Add-Content $PROFILE -Value "Import-Module -Name Terminal-Icons"

    Write-Output "Added content to PowerShell PROFILE file"
}
