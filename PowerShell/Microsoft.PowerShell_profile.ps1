oh-my-posh init pwsh --config "C:\Users\e144259\OneDrive - Mastercard\custom-theme-oh-my-posh.rev3.json" | Invoke-Expression
Import-Module -Name Terminal-Icons
#Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete

# PowerShell parameter completion shim for the dotnet CLI
Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
    param($commandName, $wordToComplete, $cursorPosition)
        dotnet complete --position $cursorPosition "$wordToComplete" | ForEach-Object {
           [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
}
