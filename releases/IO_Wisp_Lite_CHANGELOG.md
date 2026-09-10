# IO Wisp Lite — Version History

## V0.0.5 — 2026-09-02

Scope-directive and marked-up plan naming correction.

### Fixed

- `Exclude prelims and testing. Include all others.` now rejects Preliminaries and Testing / Commissioning and includes every other standard work package
- `Prelim`, `prelims`, `preliminary works`, and `general requirements` are recognized as Preliminaries terminology
- Applying a changed raw scope brief reparses and replaces stale inclusion, exclusion, and clarification fields
- A changed brief resets old row-level overrides so the new instruction takes control
- Package names found only in exclusions or clarifications are no longer accidentally treated as included

### Improved

- The edited-PDF action is now **Save marked-up plan PDF**
- The suggested output name follows `Project_Set-or-Revision_Marked-Up_Plans.pdf`
- The suggested name remains editable before saving
- The saved file manifest describes the file as a marked-up plan PDF

### Validation

- Scope test passed with 14 included packages, 2 rejected packages, and 0 packages on hold for the supplied instruction
- Scope tests passed for explicit-only inclusions, strict-mode holds, `include all except ...`, changed-brief reparsing, and manual overrides
- JavaScript syntax and interface-ID validation passed

### Preserved

All V0.0.4, V0.0.3, V0.0.2, and V0.0.1 capabilities.

## V0.0.4 — 2026-09-02

Multi-project control and project-folder reliability release.

### Added

- **Saved projects** dropdown for browser-local project records
- **New project** workflow with a separate project identity
- **Save project details** action that explicitly captures the latest text fields
- Automatic migration of the existing single V0.0.3 browser project
- Separate parent-folder and project-folder handles for each saved project
- **Open / locate project folder** action for restoring browser folder access
- Linked-folder and proposed-folder display after a project name or client change

### Fixed

- Folder creation now reads the latest project-name and client text before creating the directory
- A folder handle from the previously opened project is no longer reused by another project
- Selecting **Create updated project folder** after renaming a project creates and links the new folder while leaving the old folder untouched
- The original folder date is retained when preparing an updated folder name

### Validation

- JavaScript syntax validation passed
- All 113 static HTML IDs are unique; all 104 JavaScript ID references resolve
- Automated checks passed for V0.0.3 storage migration, explicit field saving, two-project creation and switching, and renamed-folder creation

### Preserved

All V0.0.3, V0.0.2, and V0.0.1 capabilities.

## V0.0.3 — 2026-09-02

Built-in plan viewer release.

### Added

- PDF rendering inside IO Wisp
- Direct physical-page navigation
- Previous/next page controls
- Zoom and fit-width controls
- Drawing metadata and summary beside the rendered page
- **Open page** actions in the drawing register
- **Open in IO Wisp** hyperlinks in Excel
- Source-PDF reopening from the permitted project folder when available

### Preserved

All V0.0.2 and V0.0.1 capabilities.

## V0.0.2 — 2026-09-02

Embedded CAD-text reader and Excel-link release.

### Added

- Positional reading of embedded PDF text
- Title-block region detection
- Ranked sheet-number selection that rejects common false candidates
- Deterministic page summaries
- Revision, scale, drawing-date, text-item, and line-count fields
- Separate physical PDF page and drawing-sheet-number storage
- **Open PDF Page** hyperlinks in Excel Table of Contents and Review Flags
- Expanded CSV and report outputs with drawing metadata

### Validation

- Tested against the 19-page sample plan
- Readable embedded text confirmed on all 19 pages
- Drawing sheet number identified on 18 pages
- The separate survey page without a reliable sheet number remains intentionally unnumbered for manual review

## V0.0.1 — 2026-09-02

First tracked baseline of the latest working build.

The baseline snapshot was originally saved with the compact label `V0.001`. The project now uses the clarified three-part format `V0.0.x`.

### Included capabilities

- Local PDF and text plan indexing
- Editable drawing register and table of contents
- Project folders and persistent browser state
- Portable project JSON files
- Scope brief and strict include/exclude/clarify gate
- Estimator checklist and estimate-content notes
- Estimating roadmap
- Time tracking and estimate reports
- Pricing-library import and export
- Real Excel, CSV, JSON, HTML, and print-to-PDF outputs
