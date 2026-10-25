import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { installOpenCode } from '../src/install-opencode.js';
import { pluginUrl, instructionsPath, SKILL_NAME } from '../src/opencode.js';

const directory = mkdtempSync(join(tmpdir(), 'opencode-mac-host-test-'));
const configDir = join(directory, 'config', 'opencode');
const configPath = join(configDir, 'opencode.json');
mkdirSync(configDir, { recursive: true });
writeFileSync(configPath, JSON.stringify({ model: 'test/unchanged', provider: {}, instructions: [] }));
installOpenCode({ configDir, configPath });
const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith('OPENCODE_')));
Object.assign(env, {
  OPENCODE_TEST_HOME: directory,
  XDG_CONFIG_HOME: join(directory, 'config'),
  XDG_CACHE_HOME: join(directory, 'cache'),
  XDG_DATA_HOME: join(directory, 'data'),
  XDG_STATE_HOME: join(directory, 'state'),
  OPENCODE_CONFIG_DIR: configDir,
  OPENCODE_DISABLE_PROJECT_CONFIG: '1',
  OPENCODE_DISABLE_AUTOUPDATE: '1',
  OPENCODE_DISABLE_MODELS_FETCH: '1',
  NO_COLOR: '1',
});
const executable = process.env.OPENCODE_EXECUTABLE || 'opencode';
const run = args => execFileSync(executable, args, { cwd: directory, env, encoding: 'utf8', timeout: 60000, maxBuffer: 4 * 1024 * 1024, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
const version = run(['--version']).trim();
const config = JSON.parse(run(['debug', 'config']));
assert.equal(config.model, 'test/unchanged');
assert.ok(config.plugin.some(value => (Array.isArray(value) ? value[0] : value) === pluginUrl));
assert.ok(config.instructions.includes(instructionsPath), 'Native plugin must inject its instructions');
assert.match(config.mcp.computer.environment.OPENCODE_CU_MAC_OWNER, /^opencode-mac:/);
const skills = JSON.parse(run(['debug', 'skill']));
assert.ok(skills.some(skill => skill.name === SKILL_NAME));
const status = run(['mcp', 'list']).replace(/\u001b\[[0-9;]*m/g, '');
assert.match(status, /computer\s+connected/);
const report = { passed: true, version, scope: 'Real OpenCode plugin loading, instructions, skill discovery and MCP connection. No model call or desktop input.', directory };
writeFileSync(join(directory, 'report.json'), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify(report, null, 2));
