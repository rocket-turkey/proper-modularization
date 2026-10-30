$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$design = $env:DEPLOYMENT_EXPERIMENT_DESIGN
if ($design -notin @('processing','hiding')) { throw 'Run tests with scripts/Run-Tests.ps1.' }
Import-Module (Join-Path $project "$design/DeploymentEngine.psd1") -Force

function Write-TestManifest($Object) {
    $Object | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $script:m1 -Encoding UTF8
}
function Get-TreeFingerprint($Path) {
    if (!(Test-Path -LiteralPath $Path)) { return '<absent>' }
    $rootPath = [IO.Path]::GetFullPath($Path)
    (@(Get-ChildItem -LiteralPath $Path -Recurse -File -Force | Sort-Object FullName | ForEach-Object {
        $_.FullName.Substring($rootPath.Length) + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }) -join "`n")
}
Describe "$design shared behavioral contract" {
    BeforeEach {
        $script:case = Join-Path $project ('work/tests/' + [guid]::NewGuid().ToString('N'))
        $script:fx = Join-Path $case 'fixtures'
        & (Join-Path $project 'scripts/New-Fixtures.ps1') -Path $fx | Out-Null
        $script:dest = Join-Path $case 'destination with spaces'
        $script:m1 = Join-Path $fx 'v1/release.json'
        $script:m2 = Join-Path $fx 'v2/release.json'
        $script:m3 = Join-Path $fx 'v3/release.json'
    }
    It 'exports exactly the five public commands' {
        $commands = @(Get-Command -Module DeploymentEngine | Select-Object -ExpandProperty Name | Sort-Object)
        ($commands -join ',') | Should Be 'Get-ReleaseHistory,Get-ReleaseStatus,Install-Release,Test-Release,Undo-Release'
    }
    It 'validates a real manifest and hashes without creating a workspace' {
        $r = Test-Release $m1
        $r.Valid | Should Be $true
        $r.ArtifactCount | Should Be 2
        (Test-Path -LiteralPath $dest) | Should Be $false
    }
    It 'reports empty status and history without writes' {
        (Get-ReleaseStatus $dest).Status | Should Be 'Empty'
        @(Get-ReleaseHistory $dest).Count | Should Be 0
        (Test-Path -LiteralPath $dest) | Should Be $false
    }
    It 'installs exact payload bytes and returns the public result' {
        $r = Install-Release $m1 $dest
        $r.Status | Should Be 'Succeeded'
        $r.ReleaseId | Should Be 'release-1'
        (Get-FileHash (Join-Path $dest 'active/app.txt')).Hash | Should Be (Get-FileHash (Join-Path $fx 'v1/payload/app.txt')).Hash
        (Get-FileHash (Join-Path $dest 'active/config/settings.json')).Hash | Should Be (Get-FileHash (Join-Path $fx 'v1/payload/config/settings.json')).Hash
    }
    It 'records chronological history and current identity' {
        Install-Release $m1 $dest | Out-Null
        Install-Release $m2 $dest | Out-Null
        $h = @(Get-ReleaseHistory $dest)
        $h.Count | Should Be 2
        $h[0].Operation | Should Be 'Install'
        $h[1].PreviousReleaseId | Should Be 'release-1'
        ([datetime]$h[1].Timestamp).ToUniversalTime().Year | Should BeGreaterThan 2020
        (Get-ReleaseStatus $dest).ReleaseId | Should Be 'release-2'
        (Get-ReleaseStatus $dest).Application | Should Be 'SampleApp'
    }
    It 'rejects a duplicate ID without changing any workspace file' {
        Install-Release $m1 $dest | Out-Null
        $before = Get-TreeFingerprint $dest
        { Install-Release $m1 $dest } | Should Throw
        (Get-TreeFingerprint $dest) | Should Be $before
    }
    It 'rejects different applications in one workspace' {
        Install-Release $m2 $dest | Out-Null
        $m = Get-Content $m1 -Raw | ConvertFrom-Json; $m.application = 'Other'; Write-TestManifest $m
        { Install-Release $m1 $dest } | Should Throw
        (Get-ReleaseStatus $dest).ReleaseId | Should Be 'release-2'
    }
    It 'rejects a wrong hash before writing' {
        $m = Get-Content $m1 -Raw | ConvertFrom-Json; $m.artifacts[0].sha256 = ('0' * 64); Write-TestManifest $m
        { Install-Release $m1 $dest } | Should Throw
        (Test-Path -LiteralPath $dest) | Should Be $false
    }
    It 'rejects malformed JSON' {
        Set-Content $m1 '{invalid'
        { Test-Release $m1 } | Should Throw
    }
    It 'rejects a missing manifest' {
        { Test-Release (Join-Path $case 'missing.json') } | Should Throw
    }
    It 'rejects a missing source' {
        Remove-Item (Join-Path $fx 'v1/payload/app.txt')
        { Install-Release $m1 $dest } | Should Throw
    }
    It 'rejects an invalid release ID' {
        $m = Get-Content $m1 -Raw | ConvertFrom-Json; $m.releaseId = '../escape'; Write-TestManifest $m
        { Test-Release $m1 } | Should Throw
    }
    It 'rejects an empty application' {
        $m = Get-Content $m1 -Raw | ConvertFrom-Json; $m.application = ''; Write-TestManifest $m
        { Test-Release $m1 } | Should Throw
    }
    It 'rejects an empty artifact list' {
        $m = Get-Content $m1 -Raw | ConvertFrom-Json; $m.artifacts = @(); Write-TestManifest $m
        { Test-Release $m1 } | Should Throw
    }
    It 'rejects source traversal' {
        $m = Get-Content $m1 -Raw | ConvertFrom-Json; $m.artifacts[0].source = '../secret'; Write-TestManifest $m
        { Test-Release $m1 } | Should Throw
    }
    It 'rejects target traversal' {
        $m = Get-Content $m1 -Raw | ConvertFrom-Json; $m.artifacts[0].target = '../escape'; Write-TestManifest $m
        { Test-Release $m1 } | Should Throw
    }
    It 'rejects absolute targets' {
        $m = Get-Content $m1 -Raw | ConvertFrom-Json; $m.artifacts[0].target = 'C:/escape'; Write-TestManifest $m
        { Test-Release $m1 } | Should Throw
    }
    It 'rejects duplicate targets case insensitively' {
        $m = Get-Content $m1 -Raw | ConvertFrom-Json; $m.artifacts[1].target = 'APP.TXT'; Write-TestManifest $m
        { Test-Release $m1 } | Should Throw
    }
    It 'rejects a file and directory target collision' {
        $m = Get-Content $m1 -Raw | ConvertFrom-Json; $m.artifacts[1].target = 'app.txt/child'; Write-TestManifest $m
        { Test-Release $m1 } | Should Throw
    }
    It 'rejects malformed SHA-256 fields' {
        $m = Get-Content $m1 -Raw | ConvertFrom-Json; $m.artifacts[0].sha256 = 'bad'; Write-TestManifest $m
        { Test-Release $m1 } | Should Throw
    }
    It 'replaces the active tree without stale files' {
        Install-Release $m1 $dest | Out-Null
        Set-Content (Join-Path $dest 'active/stale.txt') 'stale'
        Install-Release $m2 $dest | Out-Null
        (Test-Path (Join-Path $dest 'active/stale.txt')) | Should Be $false
    }
    It 'rolls back payload, status, and history together' {
        Install-Release $m1 $dest | Out-Null
        Install-Release $m2 $dest | Out-Null
        $r = Undo-Release $dest
        $r.Operation | Should Be 'Rollback'
        $r.Status | Should Be 'Succeeded'
        (Get-ReleaseStatus $dest).ReleaseId | Should Be 'release-1'
        (Get-FileHash (Join-Path $dest 'active/app.txt')).Hash | Should Be (Get-FileHash (Join-Path $fx 'v1/payload/app.txt')).Hash
        $h = @(Get-ReleaseHistory $dest)
        $h.Count | Should Be 3
        $h[2].ReleaseId | Should Be 'release-1'
        $h[2].PreviousReleaseId | Should Be 'release-2'
    }
    It 'supports repeated rollback down the active lineage' {
        Install-Release $m1 $dest | Out-Null; Install-Release $m2 $dest | Out-Null; Install-Release $m3 $dest | Out-Null
        Undo-Release $dest | Out-Null; Undo-Release $dest | Out-Null
        (Get-ReleaseStatus $dest).ReleaseId | Should Be 'release-1'
        { Undo-Release $dest } | Should Throw
    }
    It 'rejects rollback on an empty or single release workspace' {
        { Undo-Release $dest } | Should Throw
        Install-Release $m1 $dest | Out-Null
        $before = Get-TreeFingerprint $dest
        { Undo-Release $dest } | Should Throw
        (Get-TreeFingerprint $dest) | Should Be $before
    }
    It 'rejects reuse of an ID even after rollback' {
        Install-Release $m1 $dest | Out-Null; Install-Release $m2 $dest | Out-Null; Undo-Release $dest | Out-Null
        { Install-Release $m2 $dest } | Should Throw
    }
    It 'can install a new ID after rollback' {
        Install-Release $m1 $dest | Out-Null; Install-Release $m2 $dest | Out-Null; Undo-Release $dest | Out-Null
        Install-Release $m3 $dest | Out-Null
        (Get-ReleaseStatus $dest).ReleaseId | Should Be 'release-3'
        Undo-Release $dest | Out-Null
        (Get-ReleaseStatus $dest).ReleaseId | Should Be 'release-1'
    }
    It 'preserves a deployed workspace on later validation failure' {
        Install-Release $m2 $dest | Out-Null
        $before = Get-TreeFingerprint $dest
        Set-Content (Join-Path $fx 'v1/payload/app.txt') 'tampered'
        { Install-Release $m1 $dest } | Should Throw
        (Get-TreeFingerprint $dest) | Should Be $before
    }
    It 'rejects an unmanaged destination without altering it' {
        New-Item -ItemType Directory $dest | Out-Null
        Set-Content (Join-Path $dest 'keep.txt') 'keep'
        $before = Get-TreeFingerprint $dest
        { Install-Release $m1 $dest } | Should Throw
        (Get-TreeFingerprint $dest) | Should Be $before
    }
    It 'accepts a pre-existing empty destination' {
        New-Item -ItemType Directory $dest | Out-Null
        (Install-Release $m1 $dest).Status | Should Be 'Succeeded'
    }
    It 'rejects a destination that is a file' {
        Set-Content $dest 'file'
        { Install-Release $m1 $dest } | Should Throw
        (Get-Content $dest -Raw).Trim() | Should Be 'file'
    }
    Context 'artifact copy fault injection' {
      It 'keeps the original tree after an injected artifact copy failure' {
        Install-Release $m1 $dest | Out-Null
        $before = Get-TreeFingerprint $dest
        $copyModule = if ($design -eq 'processing') { 'CopyRelease' } else { 'ArtifactStore' }
        Mock Copy-Item { throw 'Injected copy failure' } -ModuleName $copyModule
        { Install-Release $m2 $dest } | Should Throw
        (Get-TreeFingerprint $dest) | Should Be $before
        @(Get-ChildItem $case -Directory -Filter '.deploy-*' -Force).Count | Should Be 0
      }
    }
    Context 'journal write fault injection' {
      It 'keeps the original tree after an injected journal write failure' {
        Install-Release $m1 $dest | Out-Null
        $before = Get-TreeFingerprint $dest
        $logCommand = if ($design -eq 'processing') { 'Write-Event' } else { 'Add-DeploymentRecord' }
        Mock $logCommand { throw 'Injected journal failure' } -ModuleName DeploymentEngine
        { Install-Release $m2 $dest } | Should Throw
        (Get-TreeFingerprint $dest) | Should Be $before
      }
    }
}
