Properties {
    $ProjectRoot = $PSScriptRoot
    $PowerShellExe = (Get-Process -Id $PID).Path
    $Design = 'hiding'
    $Intervention = 'journal'
    $Minutes = 0
    $PublicApiChanges = 0
}

# Each script runs in an isolated process: scripts that use exit cannot terminate psake,
# and the two identically named deployment modules cannot interfere with one another.
function Invoke-ProjectScript {
    param([string]$Name, [string[]]$Arguments = @())
    & $PowerShellExe -NoProfile -File (Join-Path $ProjectRoot "scripts/$Name") @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Name failed with exit code $LASTEXITCODE." }
}

Task Default -Depends Validate

Task Syntax -Description 'Parse every project PowerShell source file.' {
    Invoke-ProjectScript 'Test-Syntax.ps1'
}
Task Fixtures -Description 'Regenerate the three local sample releases.' {
    Invoke-ProjectScript 'New-Fixtures.ps1'
}
Task Test -Description 'Run the same Pester contract suite for both designs.' {
    Invoke-ProjectScript 'Run-Tests.ps1'
}
Task Smoke -Description 'Run independent smoke assertions in the build host.' {
    New-Item -ItemType Directory -Path (Join-Path $ProjectRoot 'results') -Force | Out-Null
    foreach ($d in @('processing','hiding')) {
        Invoke-ProjectScript 'Test-Smoke.ps1' @('-Design', $d, '-OutputPath', (Join-Path $ProjectRoot "results/$d-build-smoke.json"))
    }
}
Task Metrics -Depends Test -Description 'Verify metrics using controlled source changes in a scratch copy.' {
    Invoke-ProjectScript 'Test-Metrics.ps1'
}
Task Validate -Depends Syntax, Test, Smoke, Metrics -Description 'Run all baseline correctness and metrics checks.'

Task Package -Depends Validate -Description 'Validate and create a clean ZIP with checksums in dist/.' {
    Invoke-ProjectScript 'New-Package.ps1'
}
Task Demo -Description 'Run both demos with fresh destination directories.' {
    $token = [guid]::NewGuid().ToString('N')
    foreach ($d in @('processing','hiding')) {
        Invoke-ProjectScript 'Run-Demo.ps1' @('-Design', $d, '-Destination', (Join-Path $ProjectRoot "work/demos/$token/$d"))
    }
}
Task Snapshot -Description 'Save the baseline source snapshot before interventions.' {
    Invoke-ProjectScript 'Save-Baseline.ps1' @('-OutputPath', (Join-Path $ProjectRoot 'results/baseline.json'))
}
Task Acceptance -Description 'Run the chosen intervention probe; expected to fail on baseline.' {
    Invoke-ProjectScript 'Test-Intervention.ps1' @('-Design', $Design, '-Intervention', $Intervention)
}
Task Measure -Description 'Measure the chosen intervention using its existing test summary.' {
    Invoke-ProjectScript 'Measure-Change.ps1' @(
        '-BaselinePath', (Join-Path $ProjectRoot 'results/baseline.json'),
        '-Design', $Design, '-Intervention', $Intervention,
        '-Minutes', ([double]$Minutes).ToString([Globalization.CultureInfo]::InvariantCulture),
        '-PublicApiChanges', [string]$PublicApiChanges,
        '-TestSummaryPath', (Join-Path $ProjectRoot "results/$Design-summary.json"),
        '-OutputPath', (Join-Path $ProjectRoot "results/$Intervention-$Design-metrics.json")
    )
}
