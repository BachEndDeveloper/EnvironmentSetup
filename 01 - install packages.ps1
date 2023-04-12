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
InstallApplication("JetBrains.ToolBox")
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


if (Get-Module -ListAvailable -Name Terminal-Icons) {
    Write-Host "Terminal-Icons module is already installed"
} 
else {
    Write-Host "Installing Terminal-Icons"
    Install-Module -Name Terminal-Icons -Repository PSGallery
}

Write-Output "Install fonts, setup font in Terminal/PowerShell, setup powershell profile and OhMyPoshTheme."
Write-Output "Open JetBrains Toolbox and install Rider and DataGrip."
Write-Output "In Rider: install Azure Toolkit and Rainbow Brackets. Enable new UI, set font to Cascadia Code, enable ligatures and set theme to Rider Night."

function InstallFont($fontToInstall)
{
    if (!($installedFonts -like "*" + $fontToInstall.Name + "*"))
    {
        Write-Host 'Installing font -' $fontToInstall.BaseName
        Copy-Item $Font "C:\Windows\Fonts"
        New-ItemProperty -Name $fontToInstall.BaseName -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts" -PropertyType string -Value $fontToInstall.name         
    }
    else 
    {
        Write-Output $fontToInstall.Name + " already installed"
    }
}

# Getting machine wide installed fonts
$installedFonts = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
#Install Cascadia Code font

$FontFolder = "Fonts\CascadiaCode"
$FontItem = Get-Item -Path $FontFolder
$FontList = Get-ChildItem -Path "$FontItem\*" -Include ('*.fon','*.otf','*.ttc','*.ttf')

foreach ($Font in $FontList) 
{
        InstallFont($Font)        
}

#Install Cascadia Code font

$FontFolder = "Fonts\CascadiaCodeNF"
$FontItem = Get-Item -Path $FontFolder
$FontList = Get-ChildItem -Path "$FontItem\*" -Include ('*.fon','*.otf','*.ttc','*.ttf')

foreach ($Font in $FontList) 
{
        InstallFont($Font)        
}