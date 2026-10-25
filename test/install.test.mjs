import {test,after} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,readFileSync,writeFileSync,existsSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,dirname,resolve,basename} from 'node:path';
import {installOpenCode} from '../src/install-opencode.js';
import {configureOpenCode,createOpenCodeHooks} from '../src/opencode.js';
import {buildPackage,verifyPackage} from '../scripts/package.mjs';

const folders=[];
const folder=()=>{const p=mkdtempSync(join(tmpdir(),'opencode-mac-unit-'));folders.push(p);return p;};
after(()=>{for(const p of folders){assert.equal(dirname(resolve(p)),resolve(tmpdir()));assert.ok(basename(p).startsWith('opencode-mac-unit-'));rmSync(p,{recursive:true,force:true});}});

test('installer preserves user providers and settings, backs up changes and is idempotent',()=>{
  const dir=folder();const configPath=join(dir,'opencode.json');
  const original={model:'user/chosen',provider:{user:{option:'preserve'}},mcp:{other:{type:'local',command:['other']}},instructions:['user.md']};
  writeFileSync(configPath,JSON.stringify(original));
  const install=installOpenCode({configDir:dir,configPath,announceSeconds:3});
  const config=JSON.parse(readFileSync(configPath));
  assert.equal(config.model,original.model);assert.deepEqual(config.provider,original.provider);assert.deepEqual(config.mcp.other,original.mcp.other);assert.deepEqual(config.instructions,original.instructions);assert.equal(config.mcp.computer.environment.OPENCODE_CU_ANNOUNCE_SECONDS,'3');assert.ok(existsSync(install.backups));
  const bytes=readFileSync(configPath,'utf8');
  assert.equal(installOpenCode({configDir:dir,configPath}).backups,null);assert.equal(readFileSync(configPath,'utf8'),bytes);
  installOpenCode({configDir:dir,configPath,uninstall:true});
  const removed=JSON.parse(readFileSync(configPath));assert.equal(removed.mcp.computer,undefined);assert.equal(removed.model,original.model);assert.ok(!existsSync(install.skill));
});

test('conflicting MCP entry is never overwritten',()=>{
  const config={mcp:{computer:{command:['another-client']}}};
  const before=JSON.stringify(config);assert.throws(()=>configureOpenCode(config),/already in use/);assert.equal(JSON.stringify(config),before);
});

test('native OpenCode hooks protect session ownership and stop at tool transitions',async()=>{
  let owner='mine';let stops=0;const hooks=createOpenCodeHooks({owner:'mine',readOwner:()=>owner,stop:()=>{stops++;owner='';},pause:async()=>{}});
  const config={};await hooks.config(config);assert.equal(config.mcp.computer.environment.OPENCODE_CU_MAC_OWNER,'mine');assert.ok(config.instructions[0].endsWith('INSTRUCTIONS.md'));
  await hooks['tool.execute.before']({tool:'computer_click',sessionID:'one'},{args:{x:1,y:1}});
  await assert.rejects(hooks['tool.execute.before']({tool:'computer_type',sessionID:'two'},{args:{text:'bad'}}),/another OpenCode session/);
  await hooks['tool.execute.before']({tool:'read',sessionID:'one'},{args:{}});assert.equal(stops,1);
  owner='foreign';await hooks.dispose();assert.equal(stops,1);
});

test('disabled integration remains disabled and does not inject instructions',async()=>{
  const config={};configureOpenCode(config);config.mcp.computer.enabled=false;
  const hooks=createOpenCodeHooks({owner:'mine'});await hooks.config(config);assert.equal(config.mcp.computer.enabled,false);assert.equal(config.instructions,undefined);
});

test('portable package integrity detects tampering, extra files and traversal',()=>{
  const parent=folder();const result=buildPackage({outputDir:join(parent,'export')});
  assert.equal(verifyPackage(result.directory).valid,true);
  assert.ok(existsSync(join(result.directory,'native/main.swift')));assert.ok(existsSync(join(result.directory,'install.sh')));
  assert.throws(()=>buildPackage({outputDir:join(parent,'export')}),/new output/);
  const file=join(result.directory,'README.md');const original=readFileSync(file);writeFileSync(file,'changed');assert.throws(()=>verifyPackage(result.directory),/mismatch/);writeFileSync(file,original);
  writeFileSync(join(result.directory,'unexpected.txt'),'bad');assert.throws(()=>verifyPackage(result.directory),/unexpected/);
  const manifest=join(result.directory,'PACKAGE-MANIFEST.json');const data=JSON.parse(readFileSync(manifest));data.files[0].path='../secret';writeFileSync(manifest,JSON.stringify(data));assert.throws(()=>verifyPackage(result.directory),/Unsafe/);
});
