import { randomUUID } from 'node:crypto';
import { createOpenCodeHooks } from '../src/opencode.js';
export default async function OpenCodeComputerUseMac(_context, options = {}) {
  return createOpenCodeHooks({ owner: `opencode-mac:${randomUUID()}`, node: options.node || 'node' });
}
