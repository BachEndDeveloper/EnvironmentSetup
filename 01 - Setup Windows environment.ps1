# Setup Windows
#
# Fail fast and loudly: any cmdlet error becomes terminating instead of being written
# to the error stream while the script carries on. Steps that may fail benignly are
# guarded explicitly below (try/catch + Write-Warning, Test-Path checks, -Force on
# idempotent writes).
# Native executables are a separate matter: PowerShell 7.3+ can make non-zero exit codes
# from native commands terminating too, and 7.4 turns that on by default. That would break
# `winget upgrade`, which returns non-zero when a package is already current, so the
# tolerance is asserted explicitly below rather than assumed.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false  # PowerShell 7.3+; ignored on 5.1

# $IsWindows only exists on PowerShell 6+, so the version test has to come first: on 5.1 it
# is undefined (falsy) and would make this throw on the one OS that is actually supported.
if ($PSVersionTable.PSVersion.Major -ge 6 -and -not $IsWindows)
{
    throw "This is the Windows setup script - use '01 - Setup Mac Environment.sh' on macOS."
}

# Installing fonts writes to the system fonts folder and the HKLM registry, so the whole
# script requires elevation. Fail here rather than half-way through.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin)
{
    throw "This script must be run from an elevated (Administrator) PowerShell - see README."
}

# Every font install and config copy below uses a repo-relative path, and under 'Stop' the
# first `Get-Item` on a missing folder is fatal. Without this check that abort lands AFTER
# ~21 winget installs and BEFORE any personalisation, with a message that never mentions
# the working directory. Fail here instead, naming the problem.
foreach ($requiredPath in 'Fonts\CascadiaCode','Fonts\CascadiaCodeNF','Fonts\JetBrainsMono',
                          'Fonts\JetBrainsMonoNF','OhMyPosh','PowerShell','WindowsTerminal','VSCode')
{
    if (-not (Test-Path $requiredPath))
    {
        throw "Run this script from the repo root - '$requiredPath' was not found in '$PWD'."
    }
}

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

# Emits a non-terminating ExecutionPolicyOverride error whenever a more specific scope is
# already set - which the README's own 'Set-ExecutionPolicy -Scope Process' step causes, and
# which is also normal on GPO-managed machines. Under 'Stop' that would abort everything below.
try
{
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Confirm
}
catch
{
    Write-Warning "Could not set the CurrentUser execution policy (a more specific scope or a GPO may override it): $($_.Exception.Message)"
}

# Stock PowerShell 5.1 negotiates SSLv3/TLS 1.0 by default, which the PowerShell Gallery
# refuses. Without this, every Install-Module below fails on an otherwise healthy machine.
if ($PSVersionTable.PSVersion.Major -lt 6) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

# Module installs fail on routine conditions (declined NuGet provider prompt, untrusted
# repository prompt, transient gallery error). try/catch keeps each failure to one module
# instead of the fonts, profile, git identity and terminal settings that follow - but it
# cannot answer a ShouldContinue PROMPT, which would block the run waiting on input.
# `-Force` is what actually suppresses those prompts; `-Scope CurrentUser` avoids needing
# the machine-wide module path.
if (Get-Module -ListAvailable -Name Terminal-Icons) {
    Write-Host "Terminal-Icons module is already installed"
} 
else {
    Write-Host "Installing Terminal-Icons"
    try
    {
        Install-Module -Name Terminal-Icons -Repository PSGallery -Scope CurrentUser -Force
    }
    catch
    {
        Write-Warning "Failed to install Terminal-Icons: $($_.Exception.Message)"
    }
}

try
{
    Install-Module posh-git -Scope CurrentUser -Force
}
catch
{
    Write-Warning "Failed to install posh-git: $($_.Exception.Message)"
}

if (Get-Module -ListAvailable -Name PSReadLine) {
    Write-Host "PSReadLine module is already installed"
} 
else {
    Write-Host "Installing PSReadLine"
    try
    {
        Install-Module -Name PSReadLine -Repository PSGallery -Scope CurrentUser -Force
    }
    catch
    {
        Write-Warning "Failed to install PSReadLine: $($_.Exception.Message)"
    }
}


Write-Output "Install fonts, setup font in Terminal/PowerShell, setup powershell profile and OhMyPoshTheme."
Write-Output "Open JetBrains Toolbox and install Rider and DataGrip."
Write-Output "In Rider: install Azure Toolkit and Rainbow Brackets. Enable new UI, set editor font to Monaspace Neon (ligatures on) and terminal font to MonaspiceNe Nerd Font, set theme to Rider Night. (Monaspace is not yet bundled for Windows - install it manually.)"

function InstallFont($fontToInstall)
{
    # $installedFonts is read from script scope; $fontToInstall is this function's parameter.
    if (!($installedFonts -like "*" + $fontToInstall.Name + "*"))
    {
        Write-Output ('Installing font -' + $fontToInstall.BaseName)
        try
        {
            # -Force: the font file is very often already present (Cascadia Code ships with
            # Windows Terminal / VS), and without it the copy throws and kills every later step.
            Copy-Item $fontToInstall.FullName (Join-Path $env:SystemRoot "Fonts") -Force
            # -Force keeps this idempotent: re-running must not fail on an existing value.
            New-ItemProperty -Name $fontToInstall.BaseName -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts" -PropertyType string -Value $fontToInstall.name -Force | Out-Null
        }
        catch
        {
            Write-Warning "Failed to install font $($fontToInstall.Name): $($_.Exception.Message)"
        }
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


# Back up rather than delete: under 'Stop' any failure between a delete and the copy would
# leave the user with no profile at all. Copy-Item -Force overwrites, so no delete is needed.
if (Test-Path $PROFILE)
{
    $profileBackup = "$PROFILE.bak"
    if (Test-Path $profileBackup)
    {
        # Never clobber the first backup - it holds the user's own profile. Without this,
        # the second run backs up the profile THIS script installed, over the original.
        $profileBackup = "$PROFILE.$(Get-Date -Format 'yyyyMMdd-HHmmss').bak"
    }
    Copy-Item -Path $PROFILE -Destination $profileBackup -Force
    Write-Output "Existing PowerShell profile backed up to $profileBackup"
    # New-Item -path $PROFILE -type File -force
    # Write-Output "PowerShell PROFILE was created"
}

    # Add-Content $PROFILE -Value "`r`noh-my-posh init pwsh --config (`"$HOME\custom-theme-oh-my-posh.json`") | Invoke-Expression"
    # Add-Content $PROFILE -Value "Import-Module -Name Terminal-Icons"
# The profile directory does not exist on a machine where PowerShell has never written one.
New-Item -ItemType Directory -Path (Split-Path -Parent $PROFILE) -Force | Out-Null
Copy-Item -Path ".\PowerShell\Microsoft.PowerShell_profile.ps1" -Destination $PROFILE -Force

Write-Output "Added new PowerShell PROFILE file"

$Env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")  

#git config --global http.sslBackend schannel

$gitUsername = Read-Host -Prompt 'Input your default Git username'
$gitEmail = Read-Host -Prompt 'Input yout default Git email'

git config --global user.name $gitUsername
git config --global user.email $gitEmail

Write-Output "Setting up Windows Terminal local settings"

# Both destinations only exist once the app has been launched at least once. Warn and
# continue rather than aborting the rest of the setup.
$wtSettingsDir = "$env:USERPROFILE\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState"
if (Test-Path $wtSettingsDir)
{
    Copy-Item -Path ".\WindowsTerminal\settings.json" -Destination $wtSettingsDir
}
else
{
    Write-Warning "Windows Terminal settings folder not found ($wtSettingsDir) - launch Windows Terminal once, then re-run this script."
}

$vsCodeUserDir = "$env:AppData\Code\User"
if (Test-Path $vsCodeUserDir)
{
    Copy-Item -Path ".\VSCode\settings.json" -Destination $vsCodeUserDir
}
else
{
    Write-Warning "VS Code user folder not found ($vsCodeUserDir) - launch VS Code once, then re-run this script."
}


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



