import { readFileSync, existsSync } from 'node:fs';
import { TOOLS } from '../src/commands.js';
import { root } from '../src/backend.js';
import { join } from 'node:path';
import { readFrontmatter, readField } from '../src/frontmatter.js';

const required = ['native/main.swift', 'native/Session.swift', 'native/Info.plist', 'src/cli.js', 'opencode/plugin.js', 'opencode/mcp.js', 'opencode/SKILL.md', 'opencode/INSTRUCTIONS.md', 'README.md', 'LICENSE', 'install.sh', 'scripts/package.mjs', 'test/desktop.mjs', 'docs/PUBLISHING.md'];
for (const file of required) if (!existsSync(join(root, file))) throw new Error(`Missing ${file}`);
const manifest = JSON.parse(readFileSync(join(root, 'package.json')));
if (manifest.name !== 'opencode-computer-use-mac' || manifest.os[0] !== 'darwin' || manifest.main !== 'opencode/plugin.js') throw new Error('Incorrect macOS manifest');
const skill = readFileSync(join(root, 'opencode/SKILL.md'), 'utf8');
if (readField(readFrontmatter(skill), 'name')?.value !== manifest.name) throw new Error('Skill name must match the macOS package');
const instructions = readFileSync(join(root, 'opencode/INSTRUCTIONS.md'), 'utf8');
if (Buffer.byteLength(instructions) > 4000 || Buffer.byteLength(skill) > 8500) throw new Error('Agent guidance exceeds its context budget');
const catalog = TOOLS.map(({name, description, inputSchema}) => ({name, description, inputSchema}));
if (new Set(TOOLS.map(t=>t.name)).size !== TOOLS.length || JSON.stringify(catalog).length > 8000) throw new Error('Invalid or oversized tool catalog');
for (const source of [skill, instructions]) for (const match of source.matchAll(/`computer_([a-z_]+)`/g)) if (!TOOLS.some(t=>t.name===match[1])) throw new Error(`Unknown documented tool ${match[1]}`);
if (!readFileSync(join(root, 'native/Info.plist'), 'utf8').includes(`<string>${manifest.version}</string>`)) throw new Error('Bundle and package version disagree');
console.log(`Verified macOS package ${manifest.version}, ${TOOLS.length} tools and agent guidance`);
