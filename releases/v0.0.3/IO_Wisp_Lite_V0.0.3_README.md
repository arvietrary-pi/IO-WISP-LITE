# IO Wisp Lite V0.0.3

**Release:** V0.0.3  
**Release date:** 2026-09-02  
**Status:** Built-in PDF viewer and direct page navigation

IO Wisp Lite is a single-file, no-AI construction plan indexer and estimator's fieldbook.

## Start it

1. Download `IO_Wisp_Lite_V0.0.3.html`.
2. Open it in Chrome or Edge.
3. Enter the project-control details.
4. In **Project folder**, choose the parent folder where estimating work should be stored. IO Wisp creates `Project Name_Client - YYYY-MM-DD` inside it. The current **Location / client** field supplies the client part of the folder name.
5. Choose a PDF, extracted text file, or previous IO Wisp JSON output.
6. Select **Analyze selected file**. The input PDF or text source is copied into the project folder.
7. Review and correct the detected sheet numbers, drawing titles, page summaries, disciplines, revisions, scales, and review statuses.
8. Use **Scope Brief** to paste a request or load a `.txt`, `.md`, or `.json` brief. Apply it to separate inclusions, exclusions, and clarifications.
9. Review the strict scope gate: included work is accepted, excluded work is rejected, and unmentioned work is held for clarification.
10. Use **Estimator Checklist** and **Estimate Content** to complete the estimate record.
11. Review the **Estimating Roadmap** and adjust milestone statuses, references, and notes.
12. Use **Time & Report** to start/stop the whole-estimate timer or a checklist timer, add notes to finished sessions, and generate an estimate report.
13. Use **Pricing Library** to import reusable rates, review them, and export the library as Excel or CSV. The original Excel/CSV/PDF pricing source is copied into the project folder.
14. Open **Plan Viewer** or select **Open page** from the drawing register to inspect the physical PDF page inside IO Wisp.
15. Export the project file, TOC CSV, print the document register, or export the full Excel workbook. Generated files are written into the project folder when folder access is available.

## Project folders and edited PDFs

The **Choose parent folder** button asks for permission to write to one parent directory. The app then creates a child folder named:

`Project Name_Client - YYYY-MM-DD`

The folder name is created when the project folder is first made. Changing the project name or client later does not rename an existing folder automatically. This prevents accidental file moves; create a new project folder when starting a separate estimate.

Use **Save edited PDF as “Labeled, annotated.pdf”** to select a PDF that you annotated externally. IO Wisp copies it into the current project folder under that exact filename. The current Lite version does not yet edit PDF geometry itself.

Real folder writing requires Chrome or Edge with the File System Access API. If the browser does not support it, or permission is cancelled, the app continues using normal browser downloads and browser auto-save. The folder permission may need to be selected again after changing browser or computer.

## Save and reopen a project

The app automatically saves the current project in the browser where you are working. That is convenient for continuing later on the same browser, but it is not a portable backup.

- Click **Save project file** to download a JSON project file.
- Keep that JSON file with the original PDF and any pricing source files.
- On another computer, open the app, choose the JSON beside **Open saved project**, then click **Open saved project**.
- The JSON includes project details, the sheet index, checklist, roadmap, estimate-content notes, and time log. It does not embed the original PDF or the separate reusable Pricing Library.
- The JSON also records the project-folder name and a manifest of files saved there, but it cannot carry the browser’s folder permission to another computer.
- Use **Print / Save PDF** in **Time & Report** to create a PDF report through the browser print dialog. Use **Generate report** when you want an HTML copy that can be opened later.

The Pricing Library is saved separately in the browser so it can be reused across projects. Export it periodically as Excel or CSV for a portable backup.

## Terminal install

The starter package includes a dependency-free local server and launchers. On Windows, open Windows Terminal in the extracted package folder and run:

```powershell
.\install.cmd -InstallPath "C:\IO-Wisp"
cd C:\IO-Wisp
.\start.cmd
```

You can also run `npm start` or `node server.js` from the installed folder. The server uses `http://127.0.0.1:8080/` and opens the app in the browser. Keep the terminal open while using IO Wisp. See [TERMINAL_INSTALL.md](TERMINAL_INSTALL.md) for Windows, macOS/Linux, port, and fallback instructions.

## Useful fallback routes

- **Load demo set** shows the 19-page / 21-sheet test flow based on the 4 Baynes Street sample.
- **Add blank sheet** is for scanned pages or sheets that have no usable text layer.
- A previous IO Wisp JSON output can be imported and its noisy title guesses will be reduced to cleaner rule-based labels where possible.

The Excel workbook is generated per project; there is no pre-existing `.xlsx` inside the starter package. On **Plan Index**, click **Export Excel workbook**. The file ends in `_IO_Wisp_Estimating_Prep.xlsx` and saves in the selected project folder when folder access is available, otherwise it downloads through the browser.

The workbook contains separate sheets for **Project Summary**, **Table of Contents**, **Scope Gate**, **Estimator Checklist**, **Estimating Roadmap**, **Estimate Content**, **Review Flags**, **Time Log**, and **Pricing Library**.

## Positional PDF text reader

V0.0.2 reads every embedded text item on each physical PDF page and retains its page position while analyzing it. Text near the usual title-block region receives higher priority when detecting the sheet number, drawing title, revision, scale, and drawing date. The app then creates a deterministic page summary and keeps a short evidence excerpt for manual checking.

The full source text is read during analysis but is not permanently copied into browser storage. This prevents large plan sets from exceeding browser-storage limits. The extracted summary, title-block sample, evidence, counts, and drawing metadata are saved with the project.

## Excel-to-PDF links

The **Table of Contents** and **Review Flags** worksheets include an **Open PDF Page** hyperlink. The hyperlink uses the stored physical PDF page number. It never assumes that a drawing number such as `A02.03` is PDF page 2 or 3.

Keep the generated Excel workbook in the same folder as the original source PDF. Relative PDF-page links depend on Microsoft Excel, the operating system, and the installed PDF application honoring the `#page=` fragment. V0.0.3 also adds **Open in IO Wisp** as a second navigation route.

## Built-in plan viewer

V0.0.3 renders the original construction plan PDF inside IO Wisp using the same local PDF library used for text extraction. The viewer provides:

- Previous and next physical-page navigation
- Direct physical PDF page entry
- Zoom in and zoom out
- Fit-width display
- Drawing title and sheet number beside the plan
- Page summary, discipline, revision, scale, date, and extraction evidence
- **Open page** actions directly from the drawing register

Analyzing a PDF loads it into the viewer automatically for the current browser session. A reopened JSON project does not embed the original PDF, so select the source PDF again when prompted. When the project-folder permission is still available, IO Wisp attempts to reopen the saved source PDF from that project folder.

The Excel workbook contains both **Open PDF Page** and **Open in IO Wisp** hyperlinks. The IO Wisp link records the app location used to generate the workbook and requests the stored physical PDF page. If the PDF permission is not available in the new browser tab, select the original source PDF and the viewer will use the requested page.

## Pricing Library formats

For the cleanest import, use an Excel or CSV table with columns such as `Code`, `Category`, `Description`, `Unit`, `Material Rate`, `Labor Rate`, `Equipment Rate`, `Total Rate`, `Currency`, `Source`, `Source Date`, and `Notes`. JSON rows are also supported. TXT and PDF imports use a transparent line-and-number heuristic, so verify every imported record against the source.

The PDF text extractor is loaded from a public browser library when the page is opened. No plan file is uploaded to an AI service and no API key is used. If the extractor cannot load, use a `.txt` extraction, `.json` import, or manual sheet entries.

## Important limitation

This version indexes and organizes plan information. It does not perform exact scaled geometry takeoffs, OCR, structural design, code approval, or final pricing. Keep the source sheet/detail reference beside every quantity and verify the drawing visually before issuing an estimate.

## Version tracking

- **V0.0.1:** First tracked baseline with local PDF/text plan indexing, project-folder saving, project JSON backup, Excel generation, reports, scope gate, checklist, roadmap, timers, and pricing library.
- **V0.0.2:** Adds positional embedded-text reading, improved title-block sheet-number selection, page summaries, drawing metadata, and Excel-to-PDF page hyperlinks.
- **V0.0.3:** Adds the built-in PDF viewer, drawing-register page buttons, Excel-to-viewer hyperlinks, page controls, zoom, fit-width display, and drawing metadata beside the rendered page.

Every meaningful feature update should receive the next sequential version number and a dated changelog entry. Existing tracked releases should remain unchanged as recovery points.
