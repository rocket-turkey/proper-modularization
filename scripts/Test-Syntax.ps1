[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$count = 0
Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Extension -in @('.ps1','.psm1','.psd1') -and $_.FullName -notmatch '[/\\]work[/\\]' } | ForEach-Object {
    $tokens = $null; $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "$($_.FullName): $($errors -join '; ')" }
    $count++
}
Write-Host "PASS: parsed $count PowerShell source files on $($PSVersionTable.PSVersion)"
