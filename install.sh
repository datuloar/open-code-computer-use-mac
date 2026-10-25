#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if [ "$(uname -s)" != Darwin ]; then
  printf '%s\n' 'This installer requires macOS.' >&2
  exit 1
fi
node scripts/verify.mjs
if [ -f PACKAGE-MANIFEST.json ]; then
  node scripts/package.mjs --check .
fi
if [ ! -x 'build/OpenCode Computer Use.app/Contents/MacOS/opencode-cu-native' ]; then
  node scripts/build.mjs
fi
node src/install-opencode.js "$@"
printf '%s\n' 'Restart OpenCode. Run node src/cli.js permissions, then doctor, to check macOS privacy access.'
