#!/usr/bin/env node
import { TOOLS } from './commands.js';
import { DesktopClient, indicatorOwner, requestIndicatorStop, sleep } from './backend.js';
import { execute, serve } from './mcp.js';

const [name, raw, ...extra] = process.argv.slice(2);
if (!name || ['--help', 'help'].includes(name)) {
  console.log('opencode-cu-mac <command> [JSON arguments]\nCommands: doctor, permissions, resume, stop, mcp, ' + TOOLS.map(t => t.name).join(', '));
} else if (name === 'mcp') serve();
else {
  const client = new DesktopClient();
  try {
    if (extra.length) throw new Error('Pass arguments as one JSON object.');
    const args = raw ? JSON.parse(raw) : {};
    if (name === 'stop' && indicatorOwner()) {
      const owner = indicatorOwner();
      requestIndicatorStop(owner);
      for (let attempt = 0; attempt < 60 && indicatorOwner() === owner; attempt++) await sleep(50);
      if (indicatorOwner() === owner) throw new Error('Control did not stop; press Escape in the desktop session.');
      console.log('Stopped desktop control.');
    } else if (['doctor', 'permissions', 'resume'].includes(name)) console.log(JSON.stringify(await client.call(name, args), null, 2));
    else {
      const result = await execute(client, name === 'stop' ? 'indicator' : name, name === 'stop' ? { action: 'stop' } : args);
      console.log(JSON.stringify(result, null, 2));
    }
  } catch (error) { console.error(error.message); process.exitCode = 1; }
  finally { await client.close(); }
}
