# Synthetic PDF fixtures

Regenerate from the repository root with `node tests/generate_pdf_fixtures.js` (Node built-ins only). The generator writes deterministic PDF 1.4 objects, cross-reference offsets, page boxes and numbered vector/text content. These files contain no project or drawing facts.

- `one.pdf`: one portrait page.
- `geometry.pdf`: portrait, landscape and 90-degree rotated physical pages.
- `huge-page.pdf`: a 20,000 × 10,000 point synthetic page to exercise downscaling.
- `zero.pdf`: valid empty page tree, rejected as unusable.
- `corrupt.pdf`: PDF header followed by invalid document content.
- `not-pdf.pdf`: ordinary text with a misleading extension.
- `password.pdf`: Standard Security Handler revision 2, 40-bit RC4. User password `secret`, owner password `owner`. Test fixture only; no encryption/writer product feature.

The protected 19-page `test_assets/Sample.pdf` is separate and never regenerated. It remains the real native acceptance source.

`../phase4_schema.sql` contains the exact schema statements from the retained Phase 4 `schema4.json` evidence, ordered tables before indexes/triggers, plus synthetic ledger timestamps and user_version=4. It tests the actual prior schema rather than deriving an old schema from the current migration code.
