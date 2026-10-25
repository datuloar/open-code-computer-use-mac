import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync, existsSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { DesktopClient, binary, root, indicatorOwner } from '../src/backend.js';
import { execute } from '../src/mcp.js';

assert.equal(process.platform, 'darwin', 'Run this interactive test on macOS.');
assert.equal(indicatorOwner(), '', 'Stop the active desktop session before this test.');
const folder = mkdtempSync(join(tmpdir(), 'opencode-cu-mac-test-'));
const reportFile = join(folder, 'report.json');
const hash = createHash('sha256');
for (const directory of ['src', 'native', 'test']) for (const name of readdirSync(join(root, directory)).sort()) if (/\.(swift|m?js)$/.test(name)) hash.update(`${directory}/${name}\0`).update(readFileSync(join(root,directory,name)));
const report = {schemaVersion:1,status:'running',startedAt:new Date().toISOString(),sourceSha256:hash.digest('hex'),architecture:process.arch,checks:[]};
const save = () => writeFileSync(reportFile,JSON.stringify(report,null,2)+'\n');
const sleep = ms => new Promise(r=>setTimeout(r,ms));
async function until(check) { const until=Date.now()+10000; while(Date.now()<until){if(check())return;await sleep(50);}throw new Error('Fixture timed out'); }
const client = new DesktopClient();
let fixture;
async function check(name, action) {
  const start=performance.now();
  const entry={name,status:'failed'};
  try {await action();entry.status='passed';console.log(`PASS ${name}`);} catch(error){entry.error=error.message;throw error;}
  finally {entry.durationMs=Math.round(performance.now()-start);report.checks.push(entry);save();}
}
async function tool(name,args={}) { const result=await execute(client,name,args); return JSON.parse(result.content[0].text); }
console.log(`Interactive desktop report: ${reportFile}`);
save();
try {
  const doctor=await client.call('doctor');
  report.environment=doctor;
  await check('required permissions and human control are available',async()=>{
    assert.equal(doctor.permissions.accessibility,true,'Grant Accessibility first');
    assert.equal(doctor.permissions.screenRecording,true,'Grant Screen Recording first');
    assert.equal(doctor.humanStopped,false,'The human stopped control; do not resume automatically');
  });
  fixture=spawn(binary,['--fixture',folder],{stdio:'ignore'});
  fixture.on('error',error=>{report.fixtureError=error.message;save();});
  await until(()=>existsSync(join(folder,'ready.json')));
  const target=JSON.parse(readFileSync(join(folder,'ready.json')));
  await check('fixture is discoverable through Accessibility',async()=>{
    const tree=await tool('ui_tree',{pid:target.pid});
    assert.ok(tree.controls.some(c=>c.name==='Test editor'));
  });
  await check('focus starts visible control and reaches only the fixture',async()=>{
    await tool('focus',{pid:target.pid});
    assert.equal((await tool('indicator',{action:'status'})).controlOn,true);
  });
  const payload='  Hello Mac 👋\tUnicode\nsecond line  ';
  await check('Unicode, whitespace, tabs and newlines reach the owned editor',async()=>{
    await tool('tap',{pid:target.pid,text:'Test editor',role:'AXTextArea'});
    await tool('type',{text:payload});
    await until(()=>{try{return readFileSync(join(folder,'text.txt'),'utf8')===payload;}catch{return false;}});
  });
  await check('inspection reports a complete value and protects secure fields',async()=>{
    const field=await tool('find',{pid:target.pid,text:'Test editor',role:'AXTextArea',details:true});
    assert.equal(field.valueStatus,'available');assert.equal(field.truncated,false);assert.equal(field.value,payload);
    const secure=await tool('find',{pid:target.pid,text:'Test password',details:true});
    assert.equal(secure.valueStatus,'protected');assert.equal(secure.value,null);
  });
  await check('named click reaches the fixture button',async()=>{
    await tool('tap',{pid:target.pid,text:'Test action',role:'AXButton'});
    await until(()=>existsSync(join(folder,'clicked.txt')));
  });
  await check('capture returns PNG with point coordinates',async()=>{
    const window=(await tool('windows')).windows.find(w=>w.pid===target.pid);
    assert.ok(window);
    const region={x:Math.ceil(window.bounds.x),y:Math.ceil(window.bounds.y),width:Math.floor(window.bounds.width),height:Math.floor(window.bounds.height)};
    const result=await execute(client,'screenshot',region);
    const image=Buffer.from(result.content.find(c=>c.type==='image').data,'base64');
    assert.equal(image.readUInt32BE(16),region.width);assert.equal(image.readUInt32BE(20),region.height);
    writeFileSync(join(folder,'fixture.png'),image);
  });
  await check('stop closes control and conditional reads do not restart it',async()=>{
    await tool('indicator',{action:'stop'});
    const value=await tool('wait',{pid:target.pid,text:'Test action',seconds:2});
    assert.equal(value.observation.found,true);
    assert.equal((await tool('indicator',{action:'status'})).controlOn,false);
  });
  report.status='passed';
} catch(error) {report.status='failed';report.error=error.message;process.exitCode=1;console.error(error.message);}
finally {
  try {await client.call('indicator',{action:'stop'});} catch {}
  await client.close();
  if(fixture&&fixture.exitCode===null)fixture.kill();
  report.finishedAt=new Date().toISOString();save();
  console.log(`Saved ${reportFile}. Physical Escape, Stop and Retina appearance require human checks.`);
}
