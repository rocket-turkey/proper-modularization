# Four independent change requests

Use a fresh baseline copy for each card, for each design. Do not combine changes. Freeze `boundaries.json` and baseline snapshots first. Keep all five public commands and their parameters/results unchanged. Run all 32 shared tests after every change. The extra probe is invoked as `./scripts/Test-Intervention.ps1 -Design hiding -Intervention journal` (substitute design/card).

## 1. Journal: CSV → JSON Lines

Owner: A `WriteReleaseLog.psm1`; B `DeploymentJournal.psm1`.

Replace CSV with UTF-8 `journal.jsonl` in fresh workspaces. Each nonempty line is one compact JSON object with exactly the existing event fields. Keep chronological append order, ISO timestamps, empty initial previous ID, corruption detection and lineage replay. Readers must work after module unload/new process, not depend on in-memory cached events. No CSV file should be created. Migration of already deployed CSV workspaces is not required.

In B, change persistence behind Add/Get/State. In A, discover and update every direct serialization reader/writer; do not fix only the writer. Do not rename the public API just because the representation changes. Validate corrupt records manually in addition to the extra probe; an invalid JSON line must throw.

Acceptance: shared regression suite; `-Intervention journal` checks two installs, rollback bytes/status/history, absence of CSV, and three parseable JSON lines. Add a focused malformed-line test and a new-process reread check when implementing.

## 2. Layout: per-release trees → content-addressed blobs

Owner: A `CopyRelease.psm1`; B `ArtifactStore.psm1`.

Store payload bytes at `blobs/<lowercase-sha256>`, once per distinct content digest in the workspace. Store each release mapping at `release-index/<releaseId>.json` with `{ "files": [ { "target": "app.txt", "sha256": "..." } ] }`. Do not create `releases/`. Continue materializing ordinary files in `active/` using these mappings, so all caller-visible payload behavior remains unchanged. Verify blob digests on use; reject a corrupt blob. Keep historical blobs and indexes; garbage collection is out of scope. Fresh workspaces only.

In B, retain Save/Set-Active interfaces. In A, find layout knowledge in copy and rollback paths. Publication still occurs inside the existing staged workspace. Acceptance: shared regression suite; `-Intervention layout` verifies the new representation and restored bytes. Add a focused identical-content/dedup test and corrupt-blob rollback test. Count blob files before/after two releases sharing a file; count should grow only by distinct new digests.

## 3. Schema: flat list → nested components (backward compatible)

Owner: A `ReadRelease.psm1`; B `ReleaseManifest.psm1`.

Keep accepting baseline v1 manifests. Add v2 JSON with top-level `schemaVersion: 2`, the same release/application/metadata fields, and `components: [{ name: "app", files: [{ source, target, sha256 }] }]`. Both source and target remain rooted as in v1, not relative to component names. Require at least one component, unique nonblank component names, nonempty file lists, and global target uniqueness/prefix safety. Reject unsupported explicit schema versions. This is an additive schema change; preserve all shared test expectations.

In B, normalize either schema to the existing definition. In A, choose whether to normalize in the reader or update raw-schema consumers; record your choice. Returning normalized v1 from the A reader is allowed and may localize this change too. Do not force extra edits for the sake of the hypothesis.

Acceptance: shared regression suite; `-Intervention schema` validates and installs two v2 component groups and rejects a duplicate target spanning groups. Add focused unsupported-version, empty-group, duplicate-name and v1 compatibility tests.

## 4. Policy: SHA-256 plus production approval

Owner: A `ValidateRelease.psm1`; B `DeploymentPolicy.psm1`.

Continue requiring correct SHA-256 for every release. For manifests with `metadata.environment` equal to `production` (case insensitive), require nonblank strings `metadata.approvedBy` and `metadata.approvalTicket`. Missing metadata or non-production environments keep baseline behavior. The approval is a local experiment input, not an authenticated real-world authorization service. Apply the same policy to validation and installation. Rollback remains allowed without rereading the original manifest or requiring a new approval.

B's existing opaque Metadata bag passes policy inputs without new engine parameters. A already passes the raw manifest. This intervention is intentionally capable of staying within a single module in both architectures; report that result if observed.

Acceptance: shared regression suite; `-Intervention policy` rejects unapproved production through Test and Install without creating a workspace, accepts complete approval, and still rejects a wrong hash. Add focused missing-one-field and whitespace-only tests. No public API change is required.

## Recording

For each run save the source diff, baseline snapshot, final metrics JSON, Pester JSON/XML, extra acceptance output, first regression failure count, final failure count and elapsed active minutes. Record test/fixture edits separately; they are outside implementation CP. Do not treat the shipped baseline validation as a measurement of intervention effectiveness.
