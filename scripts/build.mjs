import { execFileSync } from 'node:child_process';
import { mkdirSync, readdirSync, copyFileSync } from 'node:fs';
import { join } from 'node:path';
import { root, binary } from '../src/backend.js';

if (process.platform !== 'darwin') throw new Error('Build the native helper on macOS with Xcode Command Line Tools.');
const app = join(root, 'build', 'OpenCode Computer Use.app', 'Contents');
mkdirSync(join(app, 'MacOS'), { recursive: true });
copyFileSync(join(root, 'native', 'Info.plist'), join(app, 'Info.plist'));
const sources = readdirSync(join(root, 'native')).filter(name => name.endsWith('.swift')).sort().map(name => join(root, 'native', name));
const arch = process.arch === 'arm64' ? 'arm64' : 'x86_64';
try {
  execFileSync('xcrun', ['swiftc', '-swift-version', '5', '-O', '-target', `${arch}-apple-macosx14.0`, ...sources,
    '-framework', 'AppKit', '-framework', 'ApplicationServices', '-framework', 'ScreenCaptureKit', '-framework', 'Vision', '-o', binary], { stdio: 'pipe', timeout: 180000 });
} catch (error) {
  const details = String(error.stderr || error.message);
  process.stderr.write(details);
  if (process.env.GITHUB_ACTIONS) for (const line of details.split('\n').filter(line => line.includes('error:'))) console.error(`::error::${line.replaceAll('%', '%25').replaceAll('\r', '%0D')}`);
  process.exit(1);
}
execFileSync('codesign', ['--force', '--sign', '-', '--identifier', 'io.github.datuloar.opencodemac', join(root, 'build', 'OpenCode Computer Use.app')], { stdio: 'inherit' });
execFileSync(binary, ['--check'], { stdio: 'inherit', timeout: 10000 });
console.log(`Built ${binary}`);
