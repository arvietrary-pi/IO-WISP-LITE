import fs from 'node:fs/promises';
import { createCanvas } from '@napi-rs/canvas';
import { getDocument } from 'pdfjs-dist/legacy/build/pdf.mjs';

const source = '/workspace/scratch/d868be9086d2/io_wisp_v0_001/Sample.pdf';
const output = '/workspace/scratch/d868be9086d2/outputs/d868be9086d2/v003_viewer_page_11.png';
const bytes = new Uint8Array(await fs.readFile(source));
const pdf = await getDocument({ data: bytes, disableWorker: true }).promise;
const physicalPage = 11;
const page = await pdf.getPage(physicalPage);
const viewport = page.getViewport({ scale: 0.5 });
const canvas = createCanvas(Math.ceil(viewport.width), Math.ceil(viewport.height));
const context = canvas.getContext('2d');
await page.render({ canvasContext: context, viewport }).promise;
await fs.writeFile(output, canvas.toBuffer('image/png'));

if (pdf.numPages !== 19) throw new Error(`Expected 19 pages; found ${pdf.numPages}.`);
if (!canvas.width || !canvas.height) throw new Error('Viewer render created an empty canvas.');
console.log(JSON.stringify({ pages: pdf.numPages, renderedPhysicalPage: physicalPage, width: canvas.width, height: canvas.height, output }));
