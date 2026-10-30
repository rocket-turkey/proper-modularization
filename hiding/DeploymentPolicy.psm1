function Test-DeploymentPolicy {
    param($Definition)
    foreach ($file in $Definition.Files) {
        if ((Get-FileHash -LiteralPath $file.SourcePath -Algorithm SHA256 -ErrorAction Stop).Hash -ne $file.Digest) { throw "Hash mismatch: $($file.RelativePath)" }
    }
}
Export-ModuleMember -Function Test-DeploymentPolicy
