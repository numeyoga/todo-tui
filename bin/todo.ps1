<#
.SYNOPSIS
    PowerShell wrapper for todo-tui on Windows.
.DESCRIPTION
    Runs todo-tui natively via escript or mix under Windows PowerShell and Windows Terminal.
.EXAMPLE
    .\bin\todo.ps1 ls
    .\bin\todo.ps1 --tui
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectDir = Split-Path -Parent $ScriptDir
$EscriptPath = Join-Path $ProjectDir "todo"

if (Test-Path $EscriptPath) {
    if (Get-Command "escript.exe" -ErrorAction SilentlyContinue) {
        & escript.exe $EscriptPath @Arguments
    } elseif (Get-Command "escript" -ErrorAction SilentlyContinue) {
        & escript $EscriptPath @Arguments
    } else {
        Push-Location $ProjectDir
        try {
            & mix run -e "TodoTxt.CLI.main(System.argv())" -- @Arguments
        } finally {
            Pop-Location
        }
    }
} else {
    Push-Location $ProjectDir
    try {
        & mix run -e "TodoTxt.CLI.main(System.argv())" -- @Arguments
    } finally {
        Pop-Location
    }
}
