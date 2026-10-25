import { existsSync, lstatSync, readdirSync, readFileSync, mkdirSync, writeFileSync, copyFileSync } from 'node:fs';
import { join, resolve, relative, isAbsolute, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { root } from '../src/backend.js';

const digest = data => createHash('sha256').update(data).digest('hex');
const inside = (base,path) => { const name=relative(base,path);return name===''||(!name.startsWith(`..${sep}`)&&name!=='..'&&!isAbsolute(name)); };
const manifestName = 'PACKAGE-MANIFEST.json';

function walk(base, directory, visit) {
  const current=join(base,directory);
  if(lstatSync(current).isSymbolicLink())throw new Error(`Symlink cannot be packaged: ${directory}`);
  for(const entry of readdirSync(current,{withFileTypes:true}).sort((a,b)=>a.name.localeCompare(b.name,'en'))){
    const name=`${directory}/${entry.name}`;
    if(entry.isSymbolicLink())throw new Error(`Symlink cannot be packaged: ${name}`);
    if(entry.isDirectory())walk(base,name,visit);else if(entry.isFile())visit(name);
  }
}

export function buildPackage({outputDir, source=root, native=false}={}) {
  const output=resolve(outputDir||join(source,'dist',`package-${Date.now()}`));
  source=resolve(source);
  if(existsSync(output)||inside(output,source))throw new Error('Choose a new output directory outside existing source paths');
  for(const directory of ['src','native','scripts','opencode','test','docs','.github','build']) if(inside(join(source,directory),output))throw new Error('Output cannot be inside a packaged source directory');
  const files=[];
  const add=name=>{
    if(lstatSync(join(source,name)).isSymbolicLink())throw new Error(`Symlink cannot be packaged: ${name}`);
    const data=readFileSync(join(source,name));
    files.push({path:name,bytes:data.length,sha256:digest(data)});
  };
  for(const directory of ['src','native','scripts','opencode','test','docs','.github'])walk(source,directory,name=>{if(/\.(?:js|mjs|swift|plist|md|yml)$/.test(name))add(name);});
  for(const name of ['package.json','README.md','LICENSE','AGENTS.md','.gitignore','.gitattributes','install.sh'])add(name);
  if(native){if(process.platform!=='darwin')throw new Error('Native release packaging requires macOS');walk(source,'build/OpenCode Computer Use.app',add);}
  const directory=join(output,'opencode-computer-use-mac');
  for(const entry of files){const target=join(directory,entry.path);mkdirSync(resolve(target,'..'),{recursive:true});copyFileSync(join(source,entry.path),target);}
  const version=JSON.parse(readFileSync(join(source,'package.json'))).version;
  writeFileSync(join(directory,manifestName),JSON.stringify({schemaVersion:1,name:'opencode-computer-use-mac',version,native,architecture:native?process.arch:null,files},null,2)+'\n');
  return {directory,version,native,files:files.length};
}

export function verifyPackage(directory) {
  const base=resolve(directory);
  if(lstatSync(base).isSymbolicLink())throw new Error('Package root cannot be a symlink');
  const manifest=JSON.parse(readFileSync(join(base,manifestName)));
  if(manifest.name!=='opencode-computer-use-mac'||manifest.schemaVersion!==1||!Array.isArray(manifest.files)||!manifest.files.length)throw new Error('Invalid manifest');
  const expected=new Set();
  for(const file of manifest.files){
    if(typeof file.path!=='string'||file.path.includes('\\')||file.path.split('/').some(part=>!part||part==='.'||part==='..')||isAbsolute(file.path)||!inside(base,resolve(base,file.path))||expected.has(file.path))throw new Error('Unsafe manifest path');
    let current=base;for(const part of file.path.split('/')){current=join(current,part);if(lstatSync(current).isSymbolicLink())throw new Error('Package contains a symlink');}
    const data=readFileSync(current);if(data.length!==file.bytes||digest(data)!==file.sha256)throw new Error(`Integrity mismatch: ${file.path}`);expected.add(file.path);
  }
  const found=[];
  function scan(directory){for(const entry of readdirSync(directory,{withFileTypes:true})){const path=join(directory,entry.name);if(entry.isSymbolicLink())throw new Error('Package contains a symlink');if(entry.isDirectory())scan(path);else found.push(relative(base,path).split(sep).join('/'));}}
  scan(base);
  if(found.some(path=>path!==manifestName&&!expected.has(path)))throw new Error('Package has unexpected files');
  return {valid:true,files:expected.size,version:manifest.version};
}

if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  try{
    const args=process.argv.slice(2);
    if(args[0]==='--check'){console.log(JSON.stringify(verifyPackage(args[1]),null,2));}
    else{
      if(args.some(arg=>!['--native'].includes(arg)))throw new Error('Use --native or --check <directory>');
      const result=buildPackage({native:args.includes('--native')});
      verifyPackage(result.directory);
      if(args.includes('--native')){
        const archive=join(resolve(result.directory,'..'),`opencode-computer-use-mac-${result.version}-${process.arch}.zip`);
        execFileSync('ditto',['-c','-k','--sequesterRsrc','--keepParent',result.directory,archive],{stdio:'inherit'});
        const checksum=archive+'.sha256';
        writeFileSync(checksum,`${digest(readFileSync(archive))}  ${archive.split(sep).at(-1)}\n`);
        Object.assign(result,{archive,checksum});
      }
      console.log(JSON.stringify(result,null,2));
    }
  }catch(error){console.error(error.message);process.exitCode=1;}
}
