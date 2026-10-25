import assert from 'node:assert/strict';
import { DesktopClient } from '../src/backend.js';
import { createServer } from '../src/mcp.js';

assert.equal(process.platform, 'darwin');
const client = new DesktopClient();
const server = createServer(client);
try {
  const doctor = await client.call('doctor');
  assert.equal(doctor.platform, 'macOS');
  assert.equal(typeof doctor.permissions.accessibility, 'boolean');
  const init = await server.handle({jsonrpc:'2.0',id:1,method:'initialize',params:{protocolVersion:'2025-06-18'}});
  assert.equal(init.result.serverInfo.name,'opencode-computer-use-mac');
  const status = await server.handle({jsonrpc:'2.0',id:2,method:'tools/call',params:{name:'indicator',arguments:{action:'status'}}});
  assert.equal(JSON.parse(status.result.content[0].text).controlOn,false);
  const invalid = await server.handle({jsonrpc:'2.0',id:3,method:'tools/call',params:{name:'drag',arguments:{x:10,y:10,to_x:99999,to_y:10}}});
  assert.equal(invalid.result.isError,true);
  assert.equal((await client.call('indicator',{action:'status'})).controlOn,false);
  console.log(JSON.stringify({passed:true,scope:'Native startup, permissions report, MCP handshake, validation and inactive control. No desktop input.',permissions:doctor.permissions}));
} finally { await server.close(); }
