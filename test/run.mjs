import { readdirSync } from 'node:fs';
for (const name of readdirSync(new URL('.', import.meta.url)).filter(name=>name.endsWith('.test.mjs')).sort()) await import(new URL(name, import.meta.url));
