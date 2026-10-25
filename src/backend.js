import { existsSync, readFileSync, writeFileSync, renameSync, lstatSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { BackendHost } from './host.js';
import { ToolError } from './tool-error.js';
import { parseAnnounceSeconds } from './settings.js';

export const root = dirname(dirname(fileURLToPath(import.meta.url)));
export const stateDirectory = join(homedir(), 'Library', 'Caches', 'opencode-cu-mac');
export const binary = join(root, 'build', 'OpenCode Computer Use.app', 'Contents', 'MacOS', 'opencode-cu-native');
export const sleep = ms => delay(ms);

function state() {
  try {
    if (lstatSync(stateDirectory).isSymbolicLink()) return null;
    const value = JSON.parse(readFileSync(join(stateDirectory, 'session.json'), 'utf8'));
    return Date.now() / 1000 - value.updated < 5 ? value : null;
  } catch { return null; }
}

export const indicatorOwner = () => state()?.owner || '';
export function requestIndicatorStop(owner) {
  const current = state();
  if (!owner || current?.owner !== owner) return false;
  const staged = join(stateDirectory, `stop-${randomUUID()}.tmp`);
  try {
    writeFileSync(staged, JSON.stringify({ owner, token: current.token }), { mode: 0o600, flag: 'wx' });
    renameSync(staged, join(stateDirectory, 'stop.json'));
    return true;
  } catch { return false; }
}

export class DesktopClient {
  constructor({ host, owner = process.env.OPENCODE_CU_MAC_OWNER || `mcp:${randomUUID()}` } = {}) {
    this.owner = owner;
    this.host = host;
  }
  async call(name, args = {}, timeoutMs = 60000) {
    if (!this.host) {
      if (process.platform !== 'darwin') throw new ToolError('Desktop control requires macOS 14 or later. Source checks and packaging can run here.');
      if (!existsSync(binary)) throw new ToolError('Native helper is missing. Run node scripts/build.mjs on your Mac, then restart OpenCode.');
      this.host = new BackendHost({ command: binary, args: ['--serve'] });
    }
    const countdown = name === 'indicator' && args.action === 'stop' ? 5 : parseAnnounceSeconds(process.env.OPENCODE_CU_ANNOUNCE_SECONDS);
    const output = await this.host.call({ command: name, arguments: args, owner: this.owner, announceSeconds: countdown }, timeoutMs);
    try { return JSON.parse(output); }
    catch { throw new ToolError('Native helper returned an invalid response'); }
  }
  cancel() {
    requestIndicatorStop(this.owner);
    this.host?.kill(new ToolError('Desktop call cancelled; inspect partial input before retrying.'));
  }
  async close() {
    requestIndicatorStop(this.owner);
    this.host?.kill();
  }
}
