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
InstallApplication("Brave.Brave")

Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Confirm

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


if (Test-Path $PROFILE)
{
    Remove-Item -Path $PROFILE
    # New-Item -path $PROFILE -type File -force
    # Write-Output "PowerShell PROFILE was created"
}

    # Add-Content $PROFILE -Value "`r`noh-my-posh init pwsh --config (`"$HOME\custom-theme-oh-my-posh.json`") | Invoke-Expression"
    # Add-Content $PROFILE -Value "Import-Module -Name Terminal-Icons"
Copy-Item -Path ".\Powershell\Microsoft.PowerShell_profile.ps1" -Destination $PROFILE

Write-Output "Added new PowerShell PROFILE file"

$Env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")  

#git config --global http.sslBackend schannel

$gitUsername = Read-Host -Prompt 'Input your default Git username'
$gitEmail = Read-Host -Prompt 'Input yout default Git email'

git config --global user.name $gitUsername
git config --global user.email $gitEmail

Copy-Item -Path "VSCode\settings.json" -Destination "$env:AppData\Code\User\"


$setupQmk = Read-Host -Prompt "Should I setup QMK and QMK MSYS? (y/n)"

if ($setupQmk -eq "y")
{
    InstallApplication("QMK.QMKToolbox")

    $qmkSavePath = "$HOME\Downloads\QMK_MSYS.exe"
    $qmkMsysVersion = "1.7.2";
    $qmkMsysUrl = "https://github.com/qmk/qmk_distro_msys/releases/download/$qmkMsysVersion/QMK_MSYS.exe"
    
    Write-Output "Downloading QMK MSYS version $qmkMsysVersion and starting installer"
    
    Invoke-Webrequest -Uri $qmkMsysUrl -OutFile $qmkSavePath

    if (Test-Path $qmkSavePath)
    {
        Start-Process $qmkSavePath -NoNewWindow -Wait
    }
}



