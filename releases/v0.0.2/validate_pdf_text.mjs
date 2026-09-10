import fs from 'node:fs/promises';
import { getDocument, Util } from 'pdfjs-dist/legacy/build/pdf.mjs';

const pdfPath = '/workspace/scratch/d868be9086d2/io_wisp_v0_001/Sample.pdf';
const bytes = new Uint8Array(await fs.readFile(pdfPath));
const pdf = await getDocument({ data: bytes, disableWorker: true }).promise;
const pageResults = [];

function extractSheetNumbers(text) {
  const raw = String(text || '').toUpperCase();
  const matches = raw.match(/\b[A-Z]{1,3}(?:[-/ ]?\d{1,3})(?:[.\-]\d{1,3}){0,2}[A-Z]?\b/g) || [];
  const normalized = matches.map((value) => value.replace(/[ ]+/g, '').replace(/\//g, '-')).filter((value) => /[A-Z]/.test(value) && /\d/.test(value));
  return [...new Set(normalized)].filter((value) => !/^AS\d/.test(value) && !/^ISO\d/.test(value) && !/^NCC\d/.test(value));
}

function sheetCandidateScore(candidate, position = 0) {
  const value = String(candidate || '').toUpperCase();
  const prefix = value.match(/^([A-Z]{1,3})/)?.[1] || '';
  const digits = (value.match(/\d/g) || []).length;
  const recognized = /^(A|AR|G|GN|S|ST|C|CV|E|EL|M|ME|P|PL|H|F|FP|FS|L)$/.test(prefix);
  const suspicious = /^(AND|TO|OF|LOT|BED|COL|HR|GR|PB|EP|PC|FW|RJ|TOW|RL|LB|N)$/.test(prefix);
  let score = Math.max(0, 4 - position);
  if (/[.\-]/.test(value)) score += 12;
  if (recognized) score += 6;
  if (digits >= 3) score += 3;
  if (/^[A-Z]{1,3}-?\d{2,4}(?:[.\-]\d{1,3})?[A-Z]?$/.test(value)) score += 10;
  if (suspicious) score -= 14;
  return score;
}

function chooseSheetNumber(candidates, candidateHints = []) {
  return candidates
    .map((value, index) => {
      const base = sheetCandidateScore(value, index);
      const y = Math.max(0, ...candidateHints.filter((hint) => hint.value === value).map((hint) => hint.yRatio || 0));
      const spatial = base >= 9 ? (y >= 0.9 ? 30 : y >= 0.82 ? 15 : 0) : 0;
      return { value, score: base + spatial };
    })
    .sort((a, b) => b.score - a.score || candidates.indexOf(a.value) - candidates.indexOf(b.value))[0];
}

for (let pageNumber = 1; pageNumber <= pdf.numPages; pageNumber += 1) {
  const page = await pdf.getPage(pageNumber);
  const viewport = page.getViewport({ scale: 1 });
  const content = await page.getTextContent();
  const items = content.items
    .map((item) => {
      const text = String(item.str || '').replace(/\s+/g, ' ').trim();
      if (!text) return null;
      const transform = Util.transform(viewport.transform, item.transform || [1, 0, 0, 1, 0, 0]);
      const height = Math.max(5, Math.hypot(Number(transform[2]) || 0, Number(transform[3]) || 0), Number(item.height) || 0);
      return { text, x: Number(transform[4]) || 0, y: Number(transform[5]) || 0, height };
    })
    .filter(Boolean)
    .sort((a, b) => a.y - b.y || a.x - b.x);
  const lines = [];
  items.forEach((item) => {
    let line = null;
    for (let index = lines.length - 1; index >= Math.max(0, lines.length - 8); index -= 1) {
      const candidate = lines[index];
      const tolerance = Math.max(2.5, Math.min(8, Math.max(item.height, candidate.height) * 0.48));
      if (Math.abs(candidate.y - item.y) <= tolerance) { line = candidate; break; }
    }
    if (!line) { line = { y: item.y, x: item.x, height: item.height, items: [] }; lines.push(line); }
    line.items.push(item);
    line.x = Math.min(line.x, item.x);
    line.y = (line.y * (line.items.length - 1) + item.y) / line.items.length;
    line.height = Math.max(line.height, item.height);
  });
  lines.sort((a, b) => a.y - b.y || a.x - b.x);
  const normalizedLines = lines.map((line) => {
    line.items.sort((a, b) => a.x - b.x);
    return { text: line.items.map((item) => item.text).join(' ').replace(/\s+/g, ' ').trim(), x: line.x, y: line.y };
  });
  const titleBlockLines = normalizedLines.filter((line) => (line.y / viewport.height >= 0.62 && line.x / viewport.width >= 0.40) || line.y / viewport.height >= 0.82);
  const titleBlockItems = items.filter((item) => (item.y / viewport.height >= 0.62 && item.x / viewport.width >= 0.40) || item.y / viewport.height >= 0.82);
  const titleBlockText = titleBlockLines.map((line) => line.text).join(' ');
  const sheetCandidates = extractSheetNumbers(titleBlockText);
  const candidateHints = normalizedLines.flatMap((line) => extractSheetNumbers(line.text).map((value) => ({ value, yRatio: line.y / viewport.height })));
  const selectedSheet = chooseSheetNumber(sheetCandidates, candidateHints);
  const candidateLines = normalizedLines.filter((line) => /\bA\d{2}[.\-]\d{2}\b/i.test(line.text)).map((line) => ({ text: line.text.slice(0, 180), xRatio: Number((line.x / viewport.width).toFixed(3)), yRatio: Number((line.y / viewport.height).toFixed(3)) }));
  pageResults.push({
    page: pageNumber,
    textItems: items.length,
    titleBlockItems: titleBlockItems.length,
    sheetCandidates,
    selectedSheet: selectedSheet?.score >= 9 ? selectedSheet.value : '',
    candidateLines,
    sample: items.slice(0, 8).map((item) => item.text).join(' ').slice(0, 160),
    titleBlockSample: titleBlockItems.slice(0, 12).map((item) => item.text).join(' ').slice(0, 220),
  });
}

const readablePages = pageResults.filter((page) => page.textItems > 0).length;
const pagesWithTitleBlockText = pageResults.filter((page) => page.titleBlockItems > 0).length;
if (readablePages !== pdf.numPages) throw new Error(`Expected ${pdf.numPages} readable pages; found ${readablePages}.`);
if (pagesWithTitleBlockText < Math.ceil(pdf.numPages * 0.8)) throw new Error('Title-block region text was not found on enough pages.');
const expectedSheets = ['A00.01','A00.04','A00.11','A00.12','','A01.02','A01.03','A01.11','A02.01','A02.02','A02.03','A02.04','A02.05','A02.06','A02.07','A02.08','A04.01','A04.02','A05.01'];
pageResults.forEach((page, index) => {
  if (page.selectedSheet !== expectedSheets[index]) throw new Error(`PDF page ${page.page}: expected ${expectedSheets[index] || '[blank]'}, detected ${page.selectedSheet || '[blank]'}.`);
});

console.log(JSON.stringify({ pages: pdf.numPages, readablePages, pagesWithTitleBlockText, pageResults }, null, 2));
