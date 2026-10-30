# Parnas information-hiding deployment experiment

Two complete, independently runnable PowerShell implementations deploy the same local application. Design A groups code by processing step; Design B assigns ownership of changeable decisions. Both implement the [shared contract](CONTRACT.md), with SHA-256 verification, staging, history, status, duplicate detection, and lineage-based rollback.

## Quick start

Extract the ZIP into a normal local folder. In PowerShell, change into the extracted project directory:

```powershell
# Once, if psake is not installed:
Install-Module psake -RequiredVersion 5.0.4 -Scope CurrentUser
./build.ps1
./build.ps1 -Task Demo
./build.ps1 -Task Package
```

The project uses [psake](https://github.com/psake/psake) for build orchestration. `build.ps1` imports installed psake 5.0.4 or later; it never downloads dependencies automatically. `psakefile.ps1` defines the task graph. The default task is Validate. Package depends on successful validation and creates `dist/ParnasDeploymentExperiment.zip` plus a SHA-256 file. It excludes generated `work/` and `dist/` folders and includes checksums for packaged files. Individual scripts remain available for focused runs.

| psake task | Action |
|---|---|
| Validate (default) | Syntax, both Pester suites, both smoke runs, controlled metrics verification |
| Syntax / Test / Smoke | Run the corresponding checks separately |
| Metrics | Run Pester, then verify source metrics in a scratch copy |
| Fixtures | Regenerate local fixtures explicitly |
| Demo | Run both designs in fresh unique destinations |
| Package | Validate, then assemble the clean project ZIP |
| Snapshot | Save `results/baseline.json` before making changes |
| Acceptance | Run the selected intervention acceptance probe |
| Measure | Record selected intervention metrics using its latest test summary |

Use `./build.ps1 -Task Test` for a focused regression run. For direct psake use: `Import-Module psake; Invoke-psake ./psakefile.ps1 -TaskList Validate`. Build scripts run checks in separate processes and fail on any nonzero exit code. The normal validation graph works after interventions too; it does not include probes that expect the baseline to reject new behavior. The psake Demo task automatically chooses fresh destinations.

Use fresh destination paths for each demo; repeating a successful demo against the same destination intentionally triggers duplicate-release errors. Paths with spaces are supported. The included manifests already contain real hashes; `./scripts/New-Fixtures.ps1` regenerates all three fixture releases if needed. No downloads are needed for the fixtures.

PowerShell 5.1 and 7 are targeted. The test runner uses Pester 3.4 or 4.x; Pester 5's discovery model is not supported by this classic suite. Windows often includes Pester 3.4. When invoked from PowerShell 7 with only Pester 3 installed, the runner explicitly launches Windows PowerShell 5.1 for the tests. On other systems use Pester 4.10.1 (`Install-Module Pester -RequiredVersion 4.10.1 -Scope CurrentUser`). The runner reports the actual host and Pester versions in each JSON summary. Syntax checks and the independent smoke script need no Pester:

```powershell
./scripts/Test-Syntax.ps1
./scripts/Test-Smoke.ps1 -Design processing
./scripts/Test-Smoke.ps1 -Design hiding
```

If your machine's execution policy blocks scripts, follow your organization's policy. No administrator privileges are required for this project.

## Use the public API

```powershell
Import-Module ./hiding/DeploymentEngine.psd1
Test-Release -ManifestPath ./fixtures/v1/release.json
Install-Release -ManifestPath ./fixtures/v1/release.json -Destination ./work/app
Install-Release -ManifestPath ./fixtures/v2/release.json -Destination ./work/app
Get-ReleaseStatus -Destination ./work/app
Undo-Release -Destination ./work/app
Get-ReleaseHistory -Destination ./work/app | Format-Table
```

Import only one engine per session: both expose the same names. Use a new PowerShell process when switching designs. The automated runner isolates them this way. All runtime data belongs under destinations you supply; nothing is deployed to the system.

## Architectures

| Design A: `processing/` | Responsibility and exposed knowledge |
|---|---|
| ReadRelease | Parses and checks raw JSON |
| ValidateRelease | Reads raw artifact fields and verifies hashes |
| CopyRelease | Reads raw fields, knows release and active directory layouts |
| WriteReleaseLog | Writes CSV events |
| DeploymentEngine | Coordinates steps; also understands CSV/history replay and release paths for rollback |

| Design B: `hiding/` | Hidden decision and stable internal API |
|---|---|
| ReleaseManifest | JSON schema → `Get-ReleaseDefinition` returning Id, Application, Files, Metadata |
| ArtifactStore | Storage layout → `Save-ReleaseArtifact`, `Set-ActiveRelease` |
| DeploymentJournal | Persistence and replay → `Get-DeploymentRecord`, `Add-DeploymentRecord`, `Get-DeploymentState` |
| DeploymentPolicy | Hash/approval rules → `Test-DeploymentPolicy` |
| DeploymentEngine | Workflow and whole-workspace publication |

The normalized B file definition has `SourcePath`, `RelativePath`, and `Digest`. Metadata is an opaque optional bag reserved for policy inputs. B's engine uses no CSV reader or release payload path. A exchanges raw manifest objects and repeats storage knowledge across workflow stages. A is a working, reasonable step-based baseline, not an intentionally broken version. There is no shared runtime implementation between designs; matching transaction machinery is duplicated so neither receives an unmeasured common deployment dependency. Neither design is constrained to equal line counts.

## Run the experiment

Read [the four intervention cards](interventions/README.md). These are change requests with executable acceptance probes, **not already applied patches**. Both delivered implementations are baseline versions. No comparative intervention outcome is claimed.

1. Run baseline tests and save their results. Make a baseline Git commit or retain an untouched extracted copy.
2. Freeze `interventions/boundaries.json` before starting. Capture a source snapshot:
   `./scripts/Save-Baseline.ps1 -OutputPath ./results/baseline.json`.
3. In separate branches or copies, implement one intervention for each design. Alternate which design you modify first. Do not change test expectations or the public API to make the change easier.
4. Record active implementation time. Run the shared suite, then `Test-Intervention.ps1` for the chosen change. Record first-run regression failures separately from final failures.
5. Measure the final source changes and fill in [the results worksheet](RESULTS-TEMPLATE.csv). Preserve source diffs and test evidence.
6. Return to untouched baseline before each of the remaining interventions. Keep all four independent.

```powershell
./scripts/Run-Tests.ps1 -Design hiding -ResultsDirectory ./results/journal-hiding
./scripts/Test-Intervention.ps1 -Design hiding -Intervention journal
./scripts/Measure-Change.ps1 -BaselinePath ./results/baseline.json `
  -Design hiding -Intervention journal -Minutes 25 -PublicApiChanges 0 `
  -TestSummaryPath ./results/journal-hiding/hiding-summary.json `
  -OutputPath ./results/journal-hiding/metrics.json
```

The same trial can use psake. Run Snapshot once **before** editing source. Then, after implementing the intervention:

```powershell
./build.ps1 -Task Snapshot # Before edits; do not overwrite this after changes
./build.ps1 -Task Test
./build.ps1 -Task Acceptance -Properties @{ Design = 'hiding'; Intervention = 'journal' }
./build.ps1 -Task Measure -Properties @{
  Design = 'hiding'; Intervention = 'journal'; Minutes = 25; PublicApiChanges = 0
}
```

Measure reads the summary produced by Test and writes `results/journal-hiding-metrics.json` for this example. Acceptance intentionally fails on the unchanged baseline. Save first-run failures before rerunning Test; each test run replaces its prior summary.

The acceptance probe for a change is expected to **fail against the baseline**. A probe prints PASS only after its assertions succeed; a thrown exception gives a failed script invocation. Capture its outcome alongside Pester summaries. Use fresh workspaces for interventions; historical storage migration is outside this experiment.

## Metrics and interpretation

`Save-Baseline.ps1` snapshots all source files in the two implementation directories. `Measure-Change.ps1` compares current files to that snapshot, including added/deleted files, without Git. It reports files/modules changed, lines added/deleted, baseline line count, owner-external modules, CP, manually supplied elapsed minutes and API changes, and counts from the supplied regression summary. Newlines are normalized; whitespace otherwise counts. Lines are measured using longest common subsequence; a modified line is one deletion plus one addition. Complexity is quadratic in lines per changed file, appropriate to this small project.

`CP = changed .psm1 modules outside the predeclared owner / other baseline .psm1 modules`.
Each baseline has five modules, so the denominator is four. New modules count in the numerator if outside the owner; CP can exceed one if you add many modules. Count that explicitly rather than hiding additions. Module manifests count as changed files, not modules. Tests, docs, fixtures, scripts, runtime data, and results are excluded from implementation metrics; record their edits separately. Public API changes and time are human observations, not automatically inferred. Do not submit a stale test summary; its recorded timestamp is preserved in metrics.

The predeclared owner is a reference boundary in A, even though A did not originally encapsulate that decision. It provides a consistent comparison, not a claim that all changes should be confined there. Report every necessary edit honestly. The policy change may already be localized in both designs; that is a valid result. Compare per-intervention observations and initial size/cost. Four trials by one implementer do not establish a general causal result. Practice effects, familiarity, chosen boundaries, extra abstraction, and the deliberately anticipated changes limit the study.

## Project contents

`processing/` and `hiding/`: five modules plus public module manifest each. `fixtures/`: three local releases. `tests/`: one shared 32-case Pester suite. `scripts/`: fixture/demo/test/smoke/syntax/measurement tools. `interventions/`: four change cards, fixed owners and acceptance probes. `results/`: recorded validation evidence. `VALIDATION.md`: actual checks and limitations. Generated test and demo data goes into `work/`, which is disposable after all PowerShell sessions using it have closed.

Read the transaction limitations in [CONTRACT.md](CONTRACT.md) before adapting this educational project. Published directories are briefly absent during the two-rename swap; concurrent use and crash recovery are outside scope.
