function Save-ReleaseArtifact {
    param([string]$Root, $Definition)
    $release = Join-Path $Root ('releases/' + $Definition.Id)
    New-Item -ItemType Directory -Path $release -ErrorAction Stop | Out-Null
    foreach ($file in $Definition.Files) {
        $target = Join-Path $release $file.RelativePath
        New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force -ErrorAction Stop | Out-Null
        Copy-Item -LiteralPath $file.SourcePath -Destination $target -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $file.Digest) { throw 'Artifact changed during deployment.' }
    }
}
function Set-ActiveRelease {
    param([string]$Root, [string]$ReleaseId)
    $release = Join-Path $Root ('releases/' + $ReleaseId)
    if (!(Test-Path -LiteralPath $release -PathType Container)) { throw 'Stored release is missing.' }
    $active = Join-Path $Root 'active'
    if (Test-Path -LiteralPath $active) { Remove-Item -LiteralPath $active -Recurse -Force -ErrorAction Stop }
    Copy-Item -LiteralPath $release -Destination $active -Recurse -ErrorAction Stop
}
Export-ModuleMember -Function Save-ReleaseArtifact, Set-ActiveRelease
