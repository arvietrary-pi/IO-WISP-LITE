// Deterministic synthetic PDF 1.4 fixtures; no real drawing facts. Run from root.
const fs = require('node:fs');
const crypto = require('node:crypto');
const folder = 'io_wisp_app/test/fixtures/pdf';
fs.mkdirSync(folder, {recursive:true});
function rc4(key, data) {
  const s=Array.from({length:256},(_,i)=>i); let j=0;
  for(let i=0;i<256;i++){j=(j+s[i]+key[i%key.length])%256;[s[i],s[j]]=[s[j],s[i]];}
  let i=0;j=0;return Buffer.from([...data].map(b=>{i=(i+1)%256;j=(j+s[i])%256;[s[i],s[j]]=[s[j],s[i]];return b^s[(s[i]+s[j])%256];}));
}
const md5=b=>crypto.createHash('md5').update(b).digest();
const pad=Buffer.from('28bf4e5e4e758a4164004e56fffa01082e2e00b6d0683e802f0ca9fe6453697a','hex');
const password=s=>Buffer.concat([Buffer.from(s,'ascii'),pad]).subarray(0,32);
function pdf(name, geometry, encrypted=false) {
  const objects=[]; const add=s=>{objects.push(Buffer.isBuffer(s)?s:Buffer.from(s,'binary'));return objects.length;};
  const id=Buffer.from('00112233445566778899aabbccddeeff','hex');
  let key,owner,user;
  if(encrypted){owner=rc4(md5(password('owner')).subarray(0,5),password('secret'));const p=Buffer.alloc(4);p.writeInt32LE(-4);key=md5(Buffer.concat([password('secret'),owner,p,id])).subarray(0,5);user=rc4(key,pad);}
  add('<< /Type /Catalog /Pages 2 0 R >>');
  add('<< /Type /Pages /Count '+geometry.length+' /Kids ['+geometry.map((_,i)=>(4+i*2)+' 0 R').join(' ')+'] >>');
  add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  geometry.forEach(([w,h,rotation=0],i)=>{
    const contentId=5+i*2;
    add('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 '+w+' '+h+'] /Rotate '+rotation+' /Resources << /Font << /F1 3 0 R >> >> /Contents '+contentId+' 0 R >>');
    let content=Buffer.from('0.1 0.4 0.6 rg 30 30 120 120 re f BT /F1 28 Tf 40 200 Td (SYNTHETIC PHYSICAL PAGE '+(i+1)+') Tj ET','ascii');
    if(encrypted){const suffix=Buffer.from([contentId&255,(contentId>>8)&255,0,0,0]);content=rc4(md5(Buffer.concat([key,suffix])).subarray(0,10),content);}
    add(Buffer.concat([Buffer.from('<< /Length '+content.length+' >>\nstream\n'),content,Buffer.from('\nendstream')]));
  });
  let encryptId;
  if(encrypted)encryptId=add('<< /Filter /Standard /V 1 /R 2 /Length 40 /O <'+owner.toString('hex')+'> /U <'+user.toString('hex')+'> /P -4 >>');
  const parts=[Buffer.from('%PDF-1.4\n% synthetic fixture\n')],offsets=[0];let size=parts[0].length;
  objects.forEach((o,i)=>{offsets.push(size);const part=Buffer.concat([Buffer.from((i+1)+' 0 obj\n'),o,Buffer.from('\nendobj\n')]);parts.push(part);size+=part.length;});
  parts.push(Buffer.from('xref\n0 '+(objects.length+1)+'\n0000000000 65535 f \n'+offsets.slice(1).map(o=>String(o).padStart(10,'0')+' 00000 n \n').join('')+'trailer\n<< /Size '+(objects.length+1)+' /Root 1 0 R'+(encrypted?' /Encrypt '+encryptId+' 0 R /ID [<'+id.toString('hex')+'><'+id.toString('hex')+'>]':'')+' >>\nstartxref\n'+size+'\n%%EOF\n'));
  fs.writeFileSync(folder+'/'+name,Buffer.concat(parts));
}
pdf('one.pdf',[[612,792]]);
pdf('geometry.pdf',[[612,792],[1000,500],[612,792,90]]);
pdf('huge-page.pdf',[[20000,10000]]);
pdf('zero.pdf',[]);
pdf('password.pdf',[[612,792]],true);
fs.writeFileSync(folder+'/corrupt.pdf','%PDF-1.4\nthis is not a document');
fs.writeFileSync(folder+'/not-pdf.pdf','Synthetic ordinary non-PDF file.');
console.log('Generated 7 deterministic fixtures; password.pdf user password is secret.');
