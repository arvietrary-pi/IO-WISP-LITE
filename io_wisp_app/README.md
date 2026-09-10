# Phase 7 implementation — 2026-09-05

**PHASE 7 — IMPLEMENTATION COMPLETE. INDEPENDENT VERIFICATION PENDING.**

Application version remains `0.0.6+1`; SQLite schema is now **7**. Open a project and choose **Estimator workflow** to use the 49-item checklist, eight Estimate Content areas, discipline-aware roadmap, and persisted whole-estimate or checklist-item timers. Checklist and roadmap resets are snapshot-backed, Scope Brief applies synchronize revision-backed generated content without removing estimator additions, and evidence links navigate by physical PDF page.

Focused Phase 7 tests, analyzer, Windows two-process restart integration, and the Windows release build passed. The complete 315-test regression run was attempted: 242 passed and 73 existing native file/PDF tests were blocked by Windows sandbox access denial `c0000022`; no Phase 7 test failed. Exact implementation, schema, evidence, limitations, and the blocked gate are in [PHASE7_IMPLEMENTATION_REPORT.md](../docs/migration/PHASE7_IMPLEMENTATION_REPORT.md). No pricing, export, packaging, Android-specific, AI, network, or background-service functionality was added.

---

# Phase 6 implementation — 2026-09-05

**PHASE 6 — IMPLEMENTATION COMPLETE. INDEPENDENT VERIFICATION PENDING.**

Application version remains `0.0.6+1`; the SQLite schema is **6**. The Phase 5 verified baseline remains the historical starting point.

Open a project, choose **Project files**, and use **Document Register** beside a managed PDF. **Analyze PDF** reads embedded text locally through the bundled PDFium engine, preserves physical coordinates, and generates one entry per physical PDF page. No cloud service, external extraction command, OCR, or AI is used.

The register displays physical page, effective sheet number, title, discipline, revision, status, and reviewed state. Search and filters are available. **Edit** stores selected estimator overrides separately from detected fields; clearing an override restores the detected value. Re-analysis refreshes detected fields only and preserves overrides, notes, review state, document state, and estimator sign-off. **Open page** navigates the built-in viewer by the 1-based physical PDF page, never by drawing sheet number.

Document control reports missing or duplicate sheet numbers, missing or mixed revisions, referenced drawings not provided, superseded drawings still referenced, unreviewed pages, unreadable embedded text, and duplicate source fingerprints. Per-page diagnostics disclose all five deterministic review reasons inherited from V0.0.5.

The canonical `Sample.pdf` analysis returns 19 physical pages with the expected sheet sequence; physical page 5 remains unnumbered and requires review. Implementation evidence and limitations are in [PHASE6_IMPLEMENTATION_REPORT.md](../docs/migration/PHASE6_IMPLEMENTATION_REPORT.md). Independent verification remains a separate next stage.

---

# Phase 5 acceptance closeout — 2026-09-04

**PHASE 5 — COMPLETE AND VERIFIED**

Independent Claude audit verdict: **PHASE 5 ACCEPTED**. Acceptance is recorded in the unchanged [independent audit report](../docs/migration/PHASE5_INDEPENDENT_AUDIT_REPORT.md); no confirmed defects or scope violations were found in the reviewed areas.

Verified baseline before Phase 5: `phase-4-verified` / `67b74de83773f36177681c561eea9a43570a3211`. Application version remains `0.0.6+1`; database schema is now **5**.

Intended verified tag: `phase-5-verified` (not created). This documentation-only closeout creates no commit, tag or push. **Phase 6 — NOT STARTED**; separate explicit authorization is required. This acceptance supersedes pending-verification and stop-at-Phase-4 status text in the preserved historical records and builder report; those records and both independent audit reports remain unchanged.

Choose an existing project → **Project files** → **Import source file** (if needed) → **Open / View PDF**. The viewer checks the exact managed identity and fingerprint, shows **Physical PDF page X of N**, and supports First/Previous/Next, whole-number entry with Go/Enter, zoom and fit width. Return with the app-bar Back button. After a full restart, select the same project/file to reopen its persisted index and managed PDF. Page/zoom preferences are not saved.

Offline PDFium is bundled in Windows builds. Internet is needed for initial dependency/build downloads, not viewer operation. Keep the whole release directory, including PDFium DLL, Flutter data, and third_party notices. No installer is supplied.

The viewer reports missing/changed/unusable sources explicitly, never substitutes a similarly named file, and exposes Retry. Restore the exact original managed copy through deliberate external recovery or import a new revision through Project files. It does not recreate deleted files. Large rasters display a resolution-reduction notice; corrupt/password/unsupported failures are explicitly ambiguous on this Windows renderer. No text extraction, OCR, drawing register or Phase 6 feature is included.

Accepted checks: **53/53** focused Phase 5 tests, **286/286** full serial regression tests, Phase 1–5 Windows integrations, exactly **19 physical pages** in `Sample.pdf`, real renders of pages **1, 10 and 19**, and offline restart/reopen passed. Analyzer and formatting are clean; diff check and Windows release build passed. Protected files remain unchanged; no Phase 6 leakage was found.

Android production deployment remains unverified. Fresh manual OS file-picker click-through was not independently revalidated in Phase 5. These and the renderer limitations above are non-blocking observations, not confirmed defects. Offline restart evidence uses a Debug integration executable; the Release build was verified separately.

See [test results](../docs/migration/TEST_RESULTS.md) for accepted evidence and audit limits, and the preserved [Phase 5 builder report](../docs/migration/PHASE5_IMPLEMENTATION_REPORT.md) for commands and implementation details.

---

## Preserved historical records

# Phase 4: deterministic Scope Brief

**PHASE 4 — COMPLETE AND VERIFIED.** Independent Claude audit — **ACCEPTED**. Version remains `0.0.6+1`; schema **4**. Phases 1–3 retain their established completion/verification status. Phase 5 remains NOT STARTED / BLOCKED pending explicit user authorization. Accepted checks: 83/83 focused Phase 4 tests, 233/233 full deterministic serial tests, all four Windows integration scenarios, clean flutter analyze and a passing Windows release build. No confirmed blocking defects. See [independent acceptance report](../docs/migration/PHASE4_INDEPENDENT_AUDIT_REPORT.md). Earlier release notes below are historical.

Open a project on the dashboard and choose **Scope Brief**. Paste/type instructions, choose strict mode, and select **Apply Scope Brief**. The reference `Exclude Prelims and Testing. Include all others.` returns 14 Included / 2 Rejected / 0 Held. Every package displays its effective result, detector result/reason and source evidence. Non-strict unmentioned packages are **Review**.

Use **Set / clear manual override**, select a decision, record an estimator reason and save. Saving creates an immutable revision and retains detector evidence. Applying identical trimmed text preserves overrides; changed trimmed text resets them. Case and internal whitespace edits count as changed text. Empty input applies all Held (or Review). Input is limited to 64,000 characters; unsupported control characters fail clearly. Use explicit Include / Exclude / Clarifications instructions: this is a bounded deterministic parser, not general prose interpretation.

Editor changes are **not saved until Apply**. The last applied gate stays visible while editing; **Discard editor changes** restores it. Closing the page discards draft edits. Successful raw text, strict state, manual reasons, all 16 results and prior revisions survive restart. **Revision history** shows prior snapshots; **Revert as a new revision** restores one after confirmation without deleting history.

Schema 4 adds scope revision/results/current tables. Schema-3 upgrades first retain a `.pre-v4-<uuid>.sqlite` snapshot. Existing projects, settings, legacy provenance and source-file records are preserved. Failed parsing or writes retain the prior applied gate. No new dependency, physical source-file change or network service is introduced. The unchanged legacy importer still defers Scope Brief values; this feature does not auto-import those values.

Builder commands: `flutter test test/scope --reporter expanded`, `flutter test --reporter expanded --concurrency=1`, `flutter test integration_test/phase4_windows_test.dart -d windows --dart-define=WISP_KEEP_EVIDENCE=true --reporter expanded`, `flutter analyze`, and `flutter build windows --release`. Detailed results, limitations and evidence paths: [Phase 4 report](../docs/migration/PHASE4_IMPLEMENTATION_REPORT.md).

---

# Phase 3: managed source files

Phase 3 is implemented pending independent verification. Version remains `0.0.6+1`; schema is 3. Phase 4 remains blocked.

Choose an existing project, open **Project files**, then **Import source file**. Select one file explicitly; IO WISP creates and verifies an unchanged managed copy. Files, including PDFs, are not parsed or analyzed. The list shows basename, file ID, relative path, SHA-256, bytes, UTC import time, state and revision relationship.

Identical bytes reuse their existing record. Different bytes with the same filename require **Import as revision**, **Use new name**, or **Cancel**. Revisions preserve prior copies. **Move managed copy to trash** asks for confirmation and retains the copy and its provenance. **Refresh file status** identifies missing or changed files; it does not recreate content.

The four directories `sources/`, `outputs/`, `imports/`, `trash/` are created lazily under the project's existing folder; no project is relocated. Empty managed directories may remain after failed imports. Do not delete uncertain staging/final files: pending operations appear as recovery needed and block further changes until reviewed. Automatic recovery, trash restore and purge are not included.

Migration 3 adds only `managed_files`; a schema-2 database receives a retained `.pre-v3-<uuid>.sqlite` snapshot before upgrade. Existing projects, legacy provenance and folder references are preserved. No absolute external source path or file BLOB is saved.

Windows storage must use ordinary local drive paths without junctions/reparse points/hard links. Names must be safe Windows basenames, up to 100 characters; managed paths are capped at 248 and source tokens at 220. Source files are opened read-only with no write/delete sharing. No overwrite option exists.

Additional development checks: `flutter test test/files --reporter expanded`, `flutter test --reporter expanded --concurrency=1`, and `flutter test integration_test/phase3_windows_test.dart -d windows --reporter expanded`. See migration DECISIONS and TEST_RESULTS for the full contract and exact evidence. The native integration substitutes file selection; a real OS picker interaction is a separate manual acceptance item.

---

# IO WISP native application — Phase 3

This directory contains the separate Flutter foundation for IO WISP. It is a native, offline-first Windows desktop application; it does not open the original browser app, use a WebView, or require a browser. Android platform structure is generated and the shared domain/repository contracts are kept platform-neutral for later work.

## Application identity

- Display name: `IO WISP`
- Development version: `0.0.6+1`
- Dart package: `io_wisp_app`
- Android application identifier: `com.iowisp.io_wisp_app`
- Windows executable: `build/windows/x64/runner/Release/io_wisp_app.exe`

## Phase 1 functionality

The implemented vertical slice contains:

- native startup and project dashboard;
- SQLite initialization with schema versioning and a migration ledger;
- one SQLite-backed settings store for the configured project root and active project ID;
- project creation, explicit editing, listing, selection, and switching;
- UUID project identities independent of visible names;
- safe Windows managed project folders;
- duplicate-name validation and double-submit protection;
- truthful database/filesystem failure messages and rollback of a newly created empty folder;
- Windows Explorer opening for an existing managed project folder.

Phase 2 adds a safe legacy-project JSON importer. PDFs, scope interpretation, drawing registers, estimating tools, pricing, exports, AI, synchronization, authentication, telemetry, and installers remain deferred.

## Import Existing Project

1. Select **Import Existing Project** on the dashboard, then **Select JSON file**.
2. Choose one portable **IO Wisp Lite V0.0.5** export in the native Windows dialog. The source is opened read-only.
3. Review the proposed display name, safe folder name, mapped fields, warnings, unsupported/deferred fields and duplicate status. **Preview only** creates no project record or folder. Cancel leaves project storage unchanged.
4. For likely duplicates, explicitly select **Skip** or **Import as a separate project**. Exact previously imported bytes are skipped. Existing projects are never overwritten or merged. A separate copy uses a visible `Name (import 2)` suffix when needed.
5. Acknowledge the findings and select **Confirm Import**. The importer revalidates the source and destination, creates a new UUID and empty project folder, and transactionally saves the project and import provenance.
6. Review the result and select **Open imported project**. The imported project becomes active; its UUID, fields, provenance and folder reference persist after closing/reopening the app.

Only project name, combined location/client, revision, estimator and optional valid project timestamps are mapped. Legacy ID is provenance only. Scope Brief, drawings, checklist, content, roadmap, times, source filenames and file manifests are **disclosed as deferred and not migrated**. Referenced documents and legacy folders are never accessed or copied. Keep the original JSON for future phases.

The supported envelope requires `io_assistant: "IO Wisp Lite"`, `app_version: "V0.0.5"`, and `project.name`. Other fields are optional but checked if present. Raw browser records, batch arrays, project-index exports, drawing-only JSON and other versions are unsupported. Unknown values are discarded with warnings. Source input limits are 8 MiB, 32 nesting levels, 100,000 counted tokens and 200 validation findings; duplicate object keys and invalid identity/date fields block import. Identity strings are limited to 300 characters; optional legacy ID to 128. A UTF-8 BOM is disclosed and accepted.

The importer accepts ordinary local Windows drive roots, checks every ancestor, and blocks UNC/device paths, junctions and symbolic-link roots. Folder components are capped at 55 characters each and the full path at 248. Imported paths/handles never supply a destination. An unused folder suffix is previewed for collisions. An expired (15 minutes) or changed source/project/root/folder preview must be refreshed.

On failure, SQLite rolls back and only the new empty project child is eligible for removal using its held Windows identity. Nonempty or unverifiable folders remain and are explicitly reported. Newly created configured-root ancestors may remain empty after a failed confirmation. Power-loss/crash recovery is not implemented; an orphan folder is retained and treated as a collision on retry. Each import is atomic for one project; batch import is unsupported.

Full format, mapping, provenance and protection decisions: [DECISIONS.md](../docs/migration/DECISIONS.md). Exact verification and limitations: [TEST_RESULTS.md](../docs/migration/TEST_RESULTS.md).

## Storage

The Windows database is stored at:

```text
%APPDATA%\IO WISP\io_wisp.sqlite
```

The default new-project root is:

```text
%USERPROFILE%\Documents\IO WISP Projects
```

The dashboard can save another absolute Windows root. Changing the root never moves or deletes existing project folders. Each new project creates a child folder using the existing convention:

```text
<sanitized project name>_<sanitized location or client> - YYYY-MM-DD
```

Invalid Windows filename characters, control characters, traversal separators, trailing dots/spaces, and reserved device names are sanitized or protected. If the generated folder already exists, a suffix such as `(2)` is used; an existing folder is never overwritten.

## Historical schema 2 contract

The database creates these tables from the migration ledger:

- `schema_migrations(version, applied_at)`
- `projects(id, name, name_normalized, location_client, revision, estimator, created_at, updated_at, status, safe_folder_name, project_root_reference, project_directory_reference, folder_created_at)`
- `app_settings(key, value)`
- `import_provenance(project_id, imported_from_legacy, imported_at, legacy_format, source_fingerprint, legacy_id, source_filename, source_byte_count, original_name_normalized, importer_version, accepted_warnings)`

`projects.id` is a UUID primary key. `name_normalized` has a unique constraint for duplicate display-name protection. The active project ID and configured root are both stored in `app_settings`, avoiding a second unsynchronized preference store.

Migration 2 preserves the Phase 1 tables and rows. Before upgrading schema 1, SQLite creates a consistent sibling snapshot named `io_wisp.sqlite.pre-v2-<uuid>.sqlite`. Keep that file as a recovery copy; it is never restored automatically. Failure to create the snapshot stops migration. DDL, migration ledger and user_version advance transactionally. Fresh databases now apply migrations 1–3; existing schema 2 upgrades through migration 3 as described above.

Provenance records the source's SHA-256 fingerprint, safe basename, byte count, legacy format/ID, import timestamp, importer version `legacy-json/1`, and accepted warning/deferred codes. It contains no complete source JSON, source absolute path, browser handles, unknown values or later-phase records. The fingerprint is unique, enforcing repeat-import protection at database level.

## Dependencies

Resolved with Flutter 3.47.2 / Dart 3.13.2:

- `sqlite3 ^3.5.2` — maintained SQLite bindings with native-assets support for Windows and Android;
- `path ^1.9.1` — platform-aware path joining and normalization;
- `uuid ^4.6.0` — stable UUID v4 project identities;
- `crypto 3.0.7` — source SHA-256; promoted from the unchanged Phase 1 transitive dependency;
- `ffi 2.2.0` — Windows directory ownership/rollback primitives; also promoted without a version change;
- `flutter_lints ^6.0.0` — development-only analysis rules.

The obsolete `sqlite3_flutter_libs` package was removed because `sqlite3` 3.x bundles its native SQLite assets itself. `path_provider` was not needed: the Windows path adapter uses process-local Windows environment paths behind an `AppStoragePaths` interface, leaving Android path selection for its future native adapter.

## Development commands

From this directory:

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter test integration_test/phase1_windows_test.dart -d windows
flutter test integration_test/phase2_windows_test.dart -d windows
flutter build windows --release
```

The installed SDK may be invoked by its full path when Flutter is not on `PATH`.

The Phase 1 and Phase 2 verification record is in `../docs/migration/TEST_RESULTS.md`.
The Windows integration test uses a fresh temporary SQLite database and real
temporary folders. It disposes the UI and closes/reopens SQLite; a separate
release-executable process restart is recorded in the acceptance evidence.
Neither test route loads user projects or legacy documents.

The JSON picker uses Windows `IFileOpenDialog` through a runner method channel; no file-selector plugin or Developer Mode is required. Automated integration replaces only file selection with a disposable fixture path; the actual dialog and full process restart require the separate native release acceptance recorded in TEST_RESULTS.

## Android readiness and limitations

The generated Android target and shared Dart layers are present, but Android verification is deferred. Flutter doctor reported that the Android command-line tools are missing on this machine. No Android storage permissions, shared-storage adapter, release signing, or Android packaging was added in Phase 1.

The Windows app currently stores project root references as Windows paths because Windows is the required target. The repository and storage interfaces are designed so an Android app-scoped documents adapter can be added later without changing project business rules.
