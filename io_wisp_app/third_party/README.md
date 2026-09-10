# PDF renderer dependencies and redistribution notices

Phase 5 uses `pdfrx_engine 0.5.0`, `pdfium_flutter 0.2.3`, and resolved `pdfium_dart 0.2.5`. The engine/Flutter bridge/bindings carry MIT licenses, copied here without alteration. The Flutter dependency lockfile pins the complete transitive graph. Flutter also aggregates Dart package licenses into its generated NOTICES asset.

`pdfium_dart`'s build hook bundles PDFium chromium/7811. The Windows x64 binary comes from:
https://github.com/bblanchon/pdfium-binaries/releases/download/chromium%2F7811/pdfium-win-x64.tgz

`pdfium/LICENSE` and every file under `pdfium/licenses/` were extracted unchanged from that exact archive. They include PDFium's BSD terms and notices for bundled third-party components. Windows CMake installs this entire directory alongside the executable. Native binary and archive hashes are recorded in Phase 5 evidence.

Build-time dependency/native asset downloads require network/cache availability. Viewer runtime calls no URL loader, network font resolver, remote asset or cache downloader. Production opens only a verified managed-source capability. Windows is exercised; Android support in the selected packages is a future portability option, not a delivered Android storage adapter.

Package references:
- https://pub.dev/packages/pdfrx_engine/versions/0.5.0
- https://pub.dev/packages/pdfium_flutter/versions/0.2.3
- https://pub.dev/packages/pdfium_dart/versions/0.2.5

Known upstream Windows behavior: pdfrx_engine 0.5.0 maps every failed native open to a password exception, because its FPDF_GetLastError call is outside the actual loading call's OS thread. The adapter truthfully reports corrupt/password-protected/unsupported ambiguity. It does not claim that every such file is encrypted. The callback-based streaming branch also has unproven Windows condition-variable wake ordering; production uses the engine's memory-backed branch, filled directly from protected chunked reads.
