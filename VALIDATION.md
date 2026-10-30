# Validation performed

Executed on Windows on October 30, 2026. These are baseline correctness and tooling checks, not results of the four proposed change experiments.

| Check | Actual runtime | Result |
|---|---|---|
| Shared Pester suite, processing design | Windows PowerShell 5.1.26100.9711, Pester 3.4.0 | 32 passed, 0 failed, 0 skipped |
| Shared Pester suite, information-hiding design | Windows PowerShell 5.1.26100.9711, Pester 3.4.0 | 32 passed, 0 failed, 0 skipped |
| Independent processing smoke assertions | PowerShell 7.6.5 | 11 passed |
| Independent information-hiding smoke assertions | PowerShell 7.6.5 | 11 passed |
| Source parser checks | PowerShell 5.1 and 7.6.5 | All 25 PowerShell files parsed, including psake workflow |
| Metrics identity comparison | PowerShell 7.6.5 | 0 changed files and lines |
| Metrics controlled modified/added/deleted-module comparison | PowerShell 7.6.5 | 4 changed modules, 3 outside owner, CP 0.75, expected line additions |
| Eight intervention probes against baseline | PowerShell 7.6.5 | All rejected the unchanged baseline as expected |

The Pester cases include exact deployed bytes, history/status, two kinds of fault injection, malformed manifests, invalid hashes, missing files, path and target conflicts, duplicate IDs, application isolation, unmanaged destinations, repeated rollback, and install-after-rollback lineage. Fault tests compare hashes of every original workspace file after failure. Smoke assertions independently check validation, install, duplicate rejection, rollback bytes and identity, history, and failed-install nonmutation.

The installed Pester 3.4 framework did not behave correctly under PowerShell 7 during the first test-harness attempt. The final runner explicitly uses Windows PowerShell 5.1 for that framework. It also avoids Pester 3's optional CIM environment probe when writing XML. The recorded final JSON and JUnit XML reports in `results/` identify the actual runtime. Full Pester coverage on PowerShell 7 with Pester 4, Pester 5, Linux, and macOS was **not executed**. PowerShell 7 validation here consists of parser checks and the independent smoke assertions, not the full Pester suite.

The four intervention implementations have **not** been applied or validated. Their instruction cards and additional executable acceptance probes are supplied for independent trials. The probes cover selected acceptance conditions; each card also specifies focused tests to add during implementation. No measured claim that one architecture outperforms the other is included.

No concurrency, crash/power-loss, forced process termination, final-rename fault injection, hostile filesystem mutation, or network-filesystem testing was performed. See `CONTRACT.md` for supported transaction behavior and recovery limits.

To reproduce from the extracted project directory:

```powershell
./build.ps1 # psake Validate: syntax, Pester, smoke, metrics verification
./build.ps1 -Task Package # validate before producing dist/ ZIP
```

The psake workflow was executed with psake 5.0.4 on PowerShell 7.6.5. Package ran the full validation graph successfully; the Test task used the documented Windows PowerShell 5.1 fallback for Pester 3.4. Smoke task reports are `results/*-build-smoke.json`, with their actual host version recorded. Demo was also executed through psake. A deliberately failing baseline Acceptance task was checked to return a nonzero process exit code. These checks establish task wiring and failure propagation, not successful intervention implementations.

`results/*-summary.json` and `results/*.xml` record the final Pester runs. `results/*-pwsh-smoke.json` records the PowerShell 7 smoke runs. `results/tooling-validation.json` records the metrics/probe harness checks. Source snapshot metrics and trial worksheets should be generated afresh when conducting interventions.
