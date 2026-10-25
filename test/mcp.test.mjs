import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validate, TOOLS } from '../src/commands.js';
import { createServer, execute } from '../src/mcp.js';
import { DesktopClient } from '../src/backend.js';

test('invalid input is rejected before native startup',async()=>{
  let calls=0;const client={call:async()=>{calls++;return {};}};
  for(const [name,args] of [['drag',{x:1,y:2,to_x:99999,to_y:3}],['press',{keys:null}],['tap',{text:'Save',role:'Button'}],['screenshot',{x:0,y:0}],['scroll',{notches:0}],['focus',{}],['find',{text:'A',max_chars:50}],['wait',{seconds:1,role:'AXButton'}],['type',{text:'a'.repeat(2001)}],['tap',{text:'Save',pid:1,window:'A'}],['click',{x:NaN,y:5}],['type',{text:'hi',extra:true}]]) await assert.rejects(execute(client,name,args));
  assert.equal(calls,0);
});

test('valid macOS roles, whitespace and fractional screen points survive validation',()=>{
  validate('tap',{text:'Save',role:'AXButton',pid:1});
  validate('type',{text:'  \n\t'});
  validate('click',{x:10.5,y:20.25});
  assert.equal(TOOLS.filter(t=>t.gated).length,8);
});

test('MCP handshake and catalog expose native macOS tools',async()=>{
  const server=createServer({close:async()=>{}});
  const init=await server.handle({jsonrpc:'2.0',id:1,method:'initialize',params:{protocolVersion:'invalid'}});
  assert.equal(init.result.protocolVersion,'2025-06-18');
  assert.equal(init.result.serverInfo.name,'opencode-computer-use-mac');
  const list=await server.handle({jsonrpc:'2.0',id:2,method:'tools/list'});
  assert.equal(list.result.tools.length,15);
  assert.ok(!list.result.tools.some(t=>['resume','permissions'].includes(t.name)));
});

test('screenshots return pixels separately from compact metadata',async()=>{
  const image=Buffer.from('image').toString('base64');
  const result=await execute({call:async()=>({width:5,imageBase64:image,controlOn:false})},'screenshot',{});
  assert.deepEqual(JSON.parse(result.content[0].text),{width:5,controlOn:false});
  assert.equal(result.content[1].data,image);
});

test('conditional waits preserve role and target without input',async()=>{
  const calls=[];
  const result=await execute({call:async(name,args,ms)=>{calls.push({name,args,ms});return {found:true,control:{enabled:true}};}},'wait',{text:'Ready',pid:99,role:'AXButton',seconds:1});
  assert.equal(JSON.parse(result.content[0].text).condition,'enabled');
  assert.equal(calls[0].name,'find');assert.equal(calls[0].args.role,'AXButton');assert.equal(calls[0].args.details,true);assert.ok(calls[0].ms<=1000);
});

test('cancellation interrupts active work and never starts cancelled queued input',async()=>{
  let reject;let calls=0;let cancelled=0;
  const server=createServer({call:()=>{calls++;return new Promise((_,r)=>{reject=r;});},cancel:()=>{cancelled++;reject(new Error('cancelled'));},close:async()=>{}});
  const one=server.handle({jsonrpc:'2.0',id:1,method:'tools/call',params:{name:'click',arguments:{x:5,y:5}}});
  await Promise.resolve();
  const two=server.handle({jsonrpc:'2.0',id:2,method:'tools/call',params:{name:'type',arguments:{text:'never'}}});
  await server.handle({jsonrpc:'2.0',method:'notifications/cancelled',params:{requestId:2}});
  await server.handle({jsonrpc:'2.0',method:'notifications/cancelled',params:{requestId:1}});
  assert.equal((await one).result.isError,true);assert.equal((await two).result.isError,true);assert.equal(calls,1);assert.equal(cancelled,1);
});

test('bad countdown does not prevent doctor or stop',async()=>{
  const old=process.env.OPENCODE_CU_ANNOUNCE_SECONDS;
  const calls=[];const client=new DesktopClient({host:{call:async request=>{calls.push(request);return '{}';}}});
  process.env.OPENCODE_CU_ANNOUNCE_SECONDS='broken';
  try {
    await client.call('doctor');await client.call('indicator',{action:'stop'});
    await assert.rejects(client.call('click',{x:1,y:1}),/integer/);
    assert.equal(calls.length,2);
  }finally{if(old===undefined)delete process.env.OPENCODE_CU_ANNOUNCE_SECONDS;else process.env.OPENCODE_CU_ANNOUNCE_SECONDS=old;}
});
