[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$scratch = Join-Path $root ('work/package-' + [guid]::NewGuid().ToString('N'))
$stage = Join-Path $scratch 'ParnasDeploymentExperiment'
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Path $stage, $dist -Force | Out-Null
foreach ($dir in @('processing','hiding','fixtures','tests','scripts','interventions','results')) {
    Copy-Item -LiteralPath (Join-Path $root $dir) -Destination $stage -Recurse -ErrorAction Stop
}
Get-ChildItem -LiteralPath $root -File -Force | Where-Object Name -ne 'SHA256SUMS.txt' | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $stage -ErrorAction Stop
}
$hashes = @(Get-ChildItem -LiteralPath $stage -Recurse -File -Force | Sort-Object FullName | ForEach-Object {
    (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $_.FullName.Substring($stage.Length + 1).Replace('\','/')
})
[IO.File]::WriteAllLines((Join-Path $stage 'SHA256SUMS.txt'), $hashes, [Text.UTF8Encoding]::new($false))
Copy-Item -LiteralPath (Join-Path $stage 'SHA256SUMS.txt') -Destination (Join-Path $root 'SHA256SUMS.txt') -Force
Add-Type -AssemblyName System.IO.Compression.FileSystem
$temporaryZip = Join-Path $scratch 'package.zip'
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $temporaryZip, [IO.Compression.CompressionLevel]::Optimal, $true)
$archive = [IO.Compression.ZipFile]::OpenRead($temporaryZip)
try {
    $entries = @($archive.Entries | Where-Object Name)
    if ($entries.Count -ne @(Get-ChildItem -LiteralPath $stage -Recurse -File -Force).Count) { throw 'ZIP entry count mismatch.' }
    if (@($entries | Where-Object { $_.FullName -match '/(work|dist)/' }).Count) { throw 'Generated directories leaked into the ZIP.' }
} finally { $archive.Dispose() }
$target = Join-Path $dist 'ParnasDeploymentExperiment.zip'
Move-Item -LiteralPath $temporaryZip -Destination $target -Force -ErrorAction Stop
((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() + '  ParnasDeploymentExperiment.zip') |
    Set-Content -LiteralPath ($target + '.sha256') -Encoding UTF8
Write-Host "Package ready: $target"
