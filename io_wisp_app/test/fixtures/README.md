# Synthetic legacy fixture

`legacy_v005.json` follows `exportJson()` at line 2012 and `blankProject()` / `normalizeProjectRecord()` at lines 664–684 of the preserved V0.0.5 HTML. Every identity, project, client, drawing and note here is invented. No real project or document is referenced or required. It is a complete export envelope with a deliberately small later-phase dataset. Test variants are built in temporary storage; tests never modify this source fixture.

The importer supports this single-project envelope only. The browser's project-index array is a summary index, not a portable batch export. Its permissive `parseJson()` accepting an array's first element is not evidence of a safe multiple-project format.
