winget install Microsoft.VisualStudioCode -e --silent
winget install Git.Git -e --silent
winget install JetBrains.ToolBox -e --silent
winget install Microsoft.DotNet.SDK.6 -e --silent
winget install Microsoft.DotNet.SDK.7 -e --silent
winget install Microsoft.PowerShell -e --silent
winget install Microsoft.WindowsTerminal -e --silent
winget install Fork.Fork -e --silent
winget install Hashicorp.Terraform -e --silent
winget install Microsoft.AzureCLI -e --silent
winget install JanDeDobbeleer.OhMyPosh -e --silent
winget install Postman.Postman -e --silent
winget install Ghisler.TotalCommander -e --silent

Install-Module -Name Terminal-Icons -Repository PSGallery

Write-Output "Install fonts, setup font in Terminal/PowerShell, setup powershell profile and OhMyPoshTheme
Write-Output "Open JetBrains Toolbox and install Rider and DataGrip"
