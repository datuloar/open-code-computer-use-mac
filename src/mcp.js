import { readFileSync } from 'node:fs';
import { createInterface } from 'node:readline';
import { setTimeout as delay } from 'node:timers/promises';
import { DesktopClient } from './backend.js';
import { TOOLS, validate } from './commands.js';
import { waitForControl } from './control-wait.js';
export { TOOLS } from './commands.js';

const version = JSON.parse(readFileSync(new URL('../package.json', import.meta.url))).version;
const protocols = ['2025-06-18', '2025-03-26', '2024-11-05'];

export async function execute(client, name, args = {}, signal) {
  validate(name, args);
  signal?.throwIfAborted();
  let result;
  if (name === 'wait') {
    if (args.text !== undefined) result = await waitForControl({ seconds: args.seconds, state: args.state, signal,
      observe: ms => client.call('find', { text: args.text, ...(args.pid ? { pid: args.pid } : {}), ...(args.window ? { window: args.window } : {}), ...(args.role ? { role: args.role } : {}), details: true }, ms) });
    else { await delay(args.seconds * 1000, undefined, { signal }); result = { waited: args.seconds }; }
  } else result = await client.call(name, args);
  signal?.throwIfAborted();
  const { imageBase64, ...text } = result;
  const content = [{ type: 'text', text: JSON.stringify(text) }];
  if (imageBase64) content.push({ type: 'image', data: imageBase64, mimeType: 'image/png' });
  return { content };
}

export function createServer(client = new DesktopClient()) {
  let queue = Promise.resolve();
  let active;
  let closed = false;
  const requests = new Map();
  const success = (id, result) => ({ jsonrpc: '2.0', id, result });
  const failure = (id, code, message) => ({ jsonrpc: '2.0', id, error: { code, message } });
  async function handle(message) {
    const { id, method, params } = message || {};
    if (message?.jsonrpc !== '2.0' || typeof method !== 'string') return failure(id ?? null, -32600, 'Invalid request');
    if (method === 'notifications/cancelled') {
      const request = requests.get(params?.requestId);
      request?.abort(new Error('Tool call cancelled; observe before retrying.'));
      if (request && request === active) client.cancel();
      return null;
    }
    if (id === undefined) return null;
    if (id === null || !['string', 'number'].includes(typeof id) || (typeof id === 'number' && !Number.isFinite(id))) return failure(null, -32600, 'Invalid request id');
    if (method === 'initialize') return success(id, { protocolVersion: protocols.includes(params?.protocolVersion) ? params.protocolVersion : protocols[0], capabilities: { tools: { listChanged: false } }, serverInfo: { name: 'opencode-computer-use-mac', version }, instructions: 'macOS screen coordinates are points, not Retina pixels. Prefer Accessibility find/tap. Read before input and verify afterward. Input shows a countdown. Stop indicator before other tools or replying. Physical Escape requires human approval and manual resume.' });
    if (method === 'ping') return success(id, {});
    if (method === 'tools/list') return success(id, { tools: TOOLS.map(({ name, description, inputSchema }) => ({ name, description, inputSchema })) });
    if (method !== 'tools/call') return failure(id, -32601, `Unknown method: ${method}`);
    if (requests.has(id)) return failure(id, -32600, 'Request id is already active');
    const controller = new AbortController();
    requests.set(id, controller);
    const run = queue.then(async () => {
      try {
        if (closed) throw new Error('MCP connection closed');
        controller.signal.throwIfAborted();
        active = controller;
        return success(id, await execute(client, params?.name, params?.arguments, controller.signal));
      } catch (error) { return success(id, { isError: true, content: [{ type: 'text', text: error.message }] }); }
      finally { if (active === controller) active = null; requests.delete(id); }
    });
    queue = run.catch(() => undefined);
    return run;
  }
  async function close() {
    closed = true;
    for (const request of requests.values()) request.abort(new Error('MCP connection closed'));
    await client.close();
  }
  return { handle, close };
}

export function serve() {
  const server = createServer();
  const lines = createInterface({ input: process.stdin, crlfDelay: Infinity });
  const write = value => { if (value) process.stdout.write(JSON.stringify(value) + '\n'); };
  lines.on('line', line => {
    let message;
    try { message = JSON.parse(line); }
    catch { write({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'Invalid JSON' } }); return; }
    server.handle(message).then(write).catch(error => process.stderr.write(error.message + '\n'));
  });
  const close = () => { server.close().finally(() => { process.exitCode = 0; }); };
  lines.on('close', close);
  process.stdin.on('error', close);
  process.stdout.on('error', close);
  process.once('SIGTERM', () => { close(); lines.close(); });
  process.once('SIGINT', () => { close(); lines.close(); });
}
