[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$files = @()
foreach ($d in @('processing','hiding')) {
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $root $d) -Recurse -File | Sort-Object FullName) {
        $files += [ordered]@{ Path = $f.FullName.Substring($root.Length + 1).Replace('\','/'); Text = [IO.File]::ReadAllText($f.FullName).Replace("`r`n","`n") }
    }
}
$out = [IO.Path]::GetFullPath($OutputPath)
New-Item -ItemType Directory -Path (Split-Path $out -Parent) -Force | Out-Null
[ordered]@{ Version = 1; RecordedUtc = [datetime]::UtcNow.ToString('o'); Files = $files } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host "Baseline saved: $out"
