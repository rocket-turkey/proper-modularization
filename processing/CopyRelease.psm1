function Copy-Release {
    param($Manifest, [string]$ManifestPath, [string]$Root)
    $release = Join-Path $Root ('releases/' + $Manifest.releaseId)
    New-Item -ItemType Directory -Path $release -ErrorAction Stop | Out-Null
    $base = Split-Path ([IO.Path]::GetFullPath($ManifestPath)) -Parent
    foreach ($a in $Manifest.artifacts) {
        $dest = Join-Path $release $a.target.Replace('\', '/')
        New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force -ErrorAction Stop | Out-Null
        Copy-Item -LiteralPath (Join-Path $base $a.source.Replace('\', '/')) -Destination $dest -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash -ne $a.sha256) { throw 'Artifact changed during deployment.' }
    }
    $active = Join-Path $Root 'active'
    if (Test-Path -LiteralPath $active) { Remove-Item -LiteralPath $active -Recurse -Force -ErrorAction Stop }
    Copy-Item -LiteralPath $release -Destination $active -Recurse -ErrorAction Stop
}
Export-ModuleMember -Function Copy-Release
