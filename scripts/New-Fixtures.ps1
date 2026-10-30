[CmdletBinding()]
param([string]$Path)
$ErrorActionPreference = 'Stop'
if (!$Path) { $Path = Join-Path $PSScriptRoot '../fixtures' }
New-Item -ItemType Directory -Path $Path -Force | Out-Null
foreach ($version in 1..3) {
    $dir = Join-Path $Path "v$version"
    New-Item -ItemType Directory -Path (Join-Path $dir 'payload/config') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $dir 'payload/app.txt'), "SampleApp version $version`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $dir 'payload/config/settings.json'), "{`"version`":$version,`"mode`":`"local`"}`n", [Text.UTF8Encoding]::new($false))
    $artifacts = @(
        [ordered]@{ source = 'payload/app.txt'; target = 'app.txt'; sha256 = (Get-FileHash -LiteralPath (Join-Path $dir 'payload/app.txt') -Algorithm SHA256).Hash.ToLowerInvariant() }
        [ordered]@{ source = 'payload/config/settings.json'; target = 'config/settings.json'; sha256 = (Get-FileHash -LiteralPath (Join-Path $dir 'payload/config/settings.json') -Algorithm SHA256).Hash.ToLowerInvariant() }
    )
    $manifest = [ordered]@{ releaseId = "release-$version"; application = 'SampleApp'; metadata = @{ environment = 'local' }; artifacts = $artifacts }
    [IO.File]::WriteAllText((Join-Path $dir 'release.json'), ($manifest | ConvertTo-Json -Depth 12) + "`n", [Text.UTF8Encoding]::new($false))
}
Write-Output "Fixtures ready: $([IO.Path]::GetFullPath($Path))"
