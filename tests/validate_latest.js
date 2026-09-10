const fs = require('fs');
const path = require('path');
const vm = require('vm');

const APP_PATH = path.resolve(__dirname, '..', 'releases', 'v0.0.5', 'IO_Wisp_Lite_V0.0.5.html');
const html = fs.readFileSync(APP_PATH, 'utf8');

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

assert(html.includes("const APP_VERSION = 'V0.0.5'"), 'V0.0.5 version marker is missing.');

const inlineScriptStart = html.lastIndexOf('<script>');
assert(inlineScriptStart >= 0, 'Inline application script opening tag was not found.');
const staticMarkup = html.slice(0, inlineScriptStart);
const staticIds = [...staticMarkup.matchAll(/\bid=["']([^"']+)["']/g)].map(match => match[1]);
const duplicateIds = [...new Set(staticIds.filter((id, index) => staticIds.indexOf(id) !== index))];
assert(!duplicateIds.length, `Duplicate static HTML IDs: ${duplicateIds.join(', ')}`);

const scripts = [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)];
assert(scripts.length, 'No inline application script found.');
const appScript = scripts[scripts.length - 1][1];
const jsIdRefs = [...appScript.matchAll(/\$\(['"]([^'"]+)['"]\)/g)].map(match => match[1]);
const missingIds = [...new Set(jsIdRefs.filter(id => !staticIds.includes(id)))];
assert(!missingIds.length, `JavaScript references missing HTML IDs: ${missingIds.join(', ')}`);
new vm.Script(appScript, {filename: path.basename(APP_PATH)});

class StorageMock {
  constructor(seed = {}) { this.map = new Map(Object.entries(seed)); }
  getItem(key) { return this.map.has(key) ? this.map.get(key) : null; }
  setItem(key, value) { this.map.set(String(key), String(value)); }
  removeItem(key) { this.map.delete(String(key)); }
}

class ElementMock {
  constructor(id = '') {
    this.id = id;
    this.value = '';
    this.checked = false;
    this.disabled = false;
    this.textContent = '';
    this.innerHTML = '';
    this.dataset = {};
    this.files = [];
    this.style = {};
    this.listeners = {};
    this.previousElementSibling = {className: 'dot'};
    this.classList = {add() {}, remove() {}, toggle() {}};
  }
  addEventListener(type, handler) { this.listeners[type] = handler; }
  querySelectorAll() { return []; }
  querySelector() { return null; }
  closest() { return this; }
  focus() {}
  getContext() { return {}; }
}

const elements = new Map();
const getElement = id => {
  if (!elements.has(id)) elements.set(id, new ElementMock(id));
  return elements.get(id);
};
const documentMock = {
  getElementById: getElement,
  querySelectorAll() { return []; },
  createElement() { return new ElementMock(); }
};

const legacyProject = {
  name: 'Legacy Project', location: 'Client One', revision: 'Rev A', estimator: 'Estimator',
  pages: 0, sourceFile: '', sheets: [], checklist: [], content: {}, roadmap: [], timeEntries: [], scopeBrief: {},
  folderName: 'Legacy Project_Client One - 2026-09-01', folderCreatedAt: '2026-09-01T08:00:00.000Z', files: []
};
const localStorage = new StorageMock({'io-wisp-lite-project-v1': JSON.stringify(legacyProject)});

const createdFolders = [];
const makeDirectory = name => ({
  name,
  queryPermission: async () => 'granted',
  requestPermission: async () => 'granted',
  getDirectoryHandle: async childName => {
    createdFolders.push(childName);
    return makeDirectory(childName);
  }
});
const pickedParent = makeDirectory('Projects');

const windowMock = {
  location: {search: '', href: 'https://example.test/io-wisp.html'},
  indexedDB: null,
  showDirectoryPicker: async options => options && options.startIn ? options.startIn : pickedParent,
  addEventListener() {},
  print() {},
  setTimeout,
  clearTimeout
};
const context = {
  window: windowMock,
  document: documentMock,
  localStorage,
  navigator: {},
  URL,
  URLSearchParams,
  Blob,
  TextDecoder,
  TextEncoder,
  console,
  confirm: () => true,
  setTimeout,
  clearTimeout,
  setInterval: () => 0,
  clearInterval() {},
  requestAnimationFrame: callback => callback(),
  performance
};
windowMock.document = documentMock;
windowMock.localStorage = localStorage;
windowMock.navigator = context.navigator;

vm.createContext(context);
vm.runInContext(appScript, context, {filename: path.basename(APP_PATH)});

function input(id, value) {
  const element = getElement(id);
  element.value = value;
  assert(element.listeners.input, `Input listener missing for ${id}.`);
  element.listeners.input({target: element});
}

function activeProject() {
  const projectId = localStorage.getItem('io-wisp-lite-active-project-v1');
  return JSON.parse(localStorage.getItem(`io-wisp-lite-project-v2:${projectId}`));
}

(async () => {
  const indexKey = 'io-wisp-lite-project-index-v1';
  const activeKey = 'io-wisp-lite-active-project-v1';

  let index = JSON.parse(localStorage.getItem(indexKey));
  assert(index.length === 1, 'Legacy project was not migrated into the project index.');
  const firstId = localStorage.getItem(activeKey);
  assert(firstId && activeProject().name === 'Legacy Project', 'Migrated active project was not saved.');

  input('projectName', '4 Baynes Street');
  input('projectRevision', 'SD Rev 03');
  getElement('saveProjectDetailsBtn').listeners.click();
  assert(activeProject().name === '4 Baynes Street', 'Explicit project save did not capture the latest project name.');
  assert(getElement('markedUpPdfFilename').value === '4_Baynes_Street_SD_Rev_03_Marked-Up_Plans.pdf', 'Marked-up PDF suggestion is not project/revision aware.');

  await getElement('chooseParentFolderBtn').listeners.click();
  assert(createdFolders.includes('4 Baynes Street_Client One - 2026-09-01'), 'Folder creation did not use the latest project name.');
  input('projectName', 'Renamed Project');
  await getElement('createProjectFolderBtn').listeners.click();
  assert(createdFolders.includes('Renamed Project_Client One - 2026-09-01'), 'Updated folder creation did not use the renamed project.');

  getElement('scopeBriefInput').value = 'Exclude Prelims and Testing\nInclude All others';
  getElement('applyScopeBtn').listeners.click();
  const scope = activeProject().scopeBrief;
  const included = scope.gate.filter(item => item.decision === 'Included');
  const rejected = scope.gate.filter(item => item.decision === 'Rejected');
  const held = scope.gate.filter(item => item.decision === 'Hold / clarify');
  assert(included.length === 14, `Expected 14 included packages, received ${included.length}.`);
  assert(rejected.length === 2, `Expected 2 rejected packages, received ${rejected.length}.`);
  assert(held.length === 0, `Expected 0 held packages, received ${held.length}.`);
  assert(rejected.some(item => item.key === 'preliminaries'), 'Preliminaries was not rejected.');
  assert(rejected.some(item => item.key === 'testing'), 'Testing / commissioning was not rejected.');

  await getElement('newProjectBtn').listeners.click();
  const secondId = localStorage.getItem(activeKey);
  assert(secondId && secondId !== firstId, 'New project did not receive a separate identity.');
  input('projectName', 'Second Project');
  input('projectLocation', 'Client Two');
  getElement('saveProjectDetailsBtn').listeners.click();
  index = JSON.parse(localStorage.getItem(indexKey));
  assert(index.length === 2, 'Saved-project index does not contain both projects.');

  await getElement('projectPicker').listeners.change({target: {value: firstId}});
  assert(getElement('projectName').value === 'Renamed Project', 'Switching projects did not restore the first project.');
  assert(localStorage.getItem(activeKey) === firstId, 'Switching projects did not update the active project key.');

  process.stdout.write(`Static IDs: ${staticIds.length} unique; JavaScript ID references: ${new Set(jsIdRefs).size} resolved.\n`);
  process.stdout.write('IO Wisp Lite V0.0.5 handover validation passed.\n');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
