# Shared behavioral contract (baseline 1.0)

Both engines export exactly the same five commands. Import only one engine in a session, or use separate processes, as the runners do. All commands use terminating errors on invalid input or failed I/O. Error wording is diagnostic and is not part of the contract. Success functions emit one result object; history emits zero or more event objects in chronological order. Internal helpers emit no output.

| Command | Parameters | Success result |
|---|---|---|
| `Test-Release` | `-ManifestPath` | `Valid=true`, `ReleaseId`, `Application`, `ArtifactCount` |
| `Install-Release` | `-ManifestPath`, `-Destination` | `Status=Succeeded`, `ReleaseId`, `Application`, `Operation=Install` |
| `Get-ReleaseHistory` | `-Destination` | events with `Operation`, `ReleaseId`, `Application`, `Timestamp`, `PreviousReleaseId` |
| `Get-ReleaseStatus` | `-Destination` | `Status=Deployed` or `Empty`, `ReleaseId`, `Application`; latter two null when empty |
| `Undo-Release` | `-Destination` | `Status=Succeeded`, restored identity, `Operation=Rollback` |

## Inputs and validation

Manifest paths are relative to the caller's current directory or absolute. Artifact source paths are relative to the manifest's directory. Destination is an absolute path or relative to the caller's current directory. Run against normal local directories. The tools do not require administrative privileges or network access.

Baseline JSON has `releaseId` (1–64 characters, ASCII alphanumeric first, then alphanumeric/dot/underscore/hyphen), nonblank `application`, optional opaque `metadata`, and a nonempty `artifacts` list. Each artifact has `source`, `target`, and a 64-hex-digit `sha256`. Unknown fields are ignored. Both slash styles are accepted for relative paths. Sources must be existing files. SHA-256 is checked before staging and again on staged copies to detect changes during copying.

Paths cannot be absolute, traverse with `.` or `..`, contain empty segments, wildcards, colons, trailing dots/spaces, or Windows device names. Target comparisons are case insensitive on every host, including directory/file prefix collisions. Symbolic links and reparse points in source ancestry or the workspace are rejected. These restrictions keep test behavior portable; this is not a general manifest format.

## Workspace and transaction semantics

Destination must be absent, empty, or already marked as an experiment workspace. A nonempty unmarked directory is refused. A filesystem root or file destination is refused. A workspace hosts one application. Every deployed release ID is reserved permanently in that workspace, including IDs later rolled back. Duplicate installs throw without writing.

`active/` contains only the active payload; it is replaced as a whole so removed files do not linger. History and stored payloads live alongside it. Readers return empty state for an absent/empty destination without creating it. Status is a logical deployment identity from the journal; it does not audit subsequent manual payload edits.

Each mutation copies the entire workspace into a unique sibling staging directory, modifies it there, and writes its journal there. It renames the original workspace to a sibling backup, then renames the staged workspace into place. On ordinary staging/copy/journal failures the original tree is unchanged. On a publish rename error it attempts restoration. If restoration fails, the old backup remains for manual recovery. Best-effort cleanup errors do not convert an already committed deployment into failure.

The rename pair is **not an atomic filesystem transaction**. Between the two renames readers can observe a missing destination. This experiment supports one process at a time and ordinary caught I/O failures, not concurrent readers/writers, power loss, process termination, malicious concurrent path replacement, or locked/open active files. Release storage and the journal are trusted local state; no tamper recovery or automatic crash recovery is promised. Whole-workspace copying intentionally prioritizes understandable failure behavior over performance. Do not use this sample as a production deployment tool.

## History and rollback

Install pushes the new ID onto the active lineage. Rollback requires at least two IDs in that lineage, restores the preceding ID, pops the current ID, and appends a `Rollback` event. It never toggles between the last two chronological events. Repeated rollback walks toward the first deployment, which cannot be removed by rollback. An install after rollback creates a new branch of the active lineage. Old payloads and historical events remain available internally, but no redo or arbitrary version-selection API is provided.

Events have UTC ISO-8601 timestamps, ordered by append position (not timestamp sort). `PreviousReleaseId` is the formerly active ID, empty on first installation; rollback `ReleaseId` is the restored ID. Invalid journal headers, operations, timestamps, duplicate installs, application mismatches, or inconsistent lineage throw. Readers do not silently repair corruption. The journal and payload are published together through staging.

## Test boundary

The same behavioral Pester suite runs for both implementations. Two fault-injection cases mock the copy primitive in its owner and the journal entry point as called by the engine; these are deliberately architecture-aware test setup around shared observable assertions. The journal fault remains usable when its serialization format changes. They confirm staging failures leave every original file unchanged. They do not demonstrate crash consistency or final-rename failure recovery.
