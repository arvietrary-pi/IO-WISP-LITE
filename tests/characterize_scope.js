// Read-only legacy characterization; does not evaluate the browser UI or write releases.
const fs = require('fs');
const vm = require('vm');
const html = fs.readFileSync('releases/v0.0.5/IO_Wisp_Lite_V0.0.5.html','utf8');
const catalog = html.match(/const SCOPE_PACKAGES = (\[[\s\S]*?\n      \]);/)[0];
const funcs = html.slice(html.indexOf('function splitScopeSections('),html.indexOf('function applyScopeBrief('));
const ctx = vm.createContext({});
vm.runInContext(`${catalog}\nconst state={project:{scopeBrief:{}}}; function ensureScopeBrief() {}\n${funcs}\nfunction run(raw,strict){const p=splitScopeSections(raw);state.project.scopeBrief={included:p.included.join('\\n'),excluded:p.excluded.join('\\n'),clarifications:p.clarifications.join('\\n'),strict,gate:[]};buildScopeGate();return state.project.scopeBrief;}`,ctx);
const cases = JSON.parse(fs.readFileSync('io_wisp_app/test/fixtures/scope_cases.json','utf8'));
const labels = {'Included':'included','Rejected':'rejected','Hold / clarify':'held','Review':'review'};
const out = cases.map(f => {
 const legacy=ctx.run(f.raw,f.strict);
 const differences=legacy.gate.filter(r => labels[r.decision] !== (f.decisions[r.key] || f.default)).map(r=>({package:r.key,legacy:labels[r.decision],intended:f.decisions[r.key] || f.default}));
 return {name:f.name,raw:f.raw,strict:f.strict,legacy,differences};
});
console.log(JSON.stringify(out,null,2));
