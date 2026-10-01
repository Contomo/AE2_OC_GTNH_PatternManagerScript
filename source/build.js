"use strict";
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const root = path.dirname(__dirname);
const deployment = [];
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
function emit(file, source, testOnly=false) {
  fs.mkdirSync(path.dirname(path.join(root,file)), {recursive:true});
  fs.writeFileSync(path.join(root,file), source);
  if (!testOnly) deployment.push(file);
}
function checksum(data) {
  let a=1,b=0;
  for (const byte of data) { a=(a+byte)%65521; b=(b+a)%65521; }
  return b.toString(16).padStart(4,'0')+a.toString(16).padStart(4,'0');
}
const section = file => '-- Source: '+file+'\n'+read(file);
const inline = source => source.replaceAll("require('assline_util')",'U')
  .replaceAll("require('assline_programs')",'Programs').replaceAll("require('assline_config')",'Config')
  .replaceAll("require('assline_planner')",'Planner').replaceAll("require('assline_modes')",'Modes');
const pure = (name,file) => 'local '+name+'=(function()\n'+inline(section(file))+'\nend)()\n';
const body = pure('U','source/lib/util.lua')+pure('Programs','source/lib/programs.lua')+pure('Config','source/lib/config.lua')+
  inline(['source/app/00_core.lua','source/app/10_plan.lua','source/app/20_apply.lua'].map(section).join('\n'))+'\n'+
  pure('Planner','source/lib/planner.lua')+pure('Modes','source/lib/modes.lua')+
  pure('Preview','source/lib/preview.lua')+
  inline(section('source/app/25_maker.lua'))+'\n'+section('source/app/30_ui.lua')+'\n'+section('source/app/90_main.lua');
const entry = `-- Readable application bundle, generated from the source files named below.
local savedPath=package.path
local function unload()
  for name in pairs(package.loaded) do
    if name:match('^assline_') then package.loaded[name]=nil end
  end
end
unload()
local fs=require('filesystem')
local args=table.pack(...)
local directory=fs.path(require('shell').resolve(require('process').info().path))
if args[1]=='--module-directory' then
  directory=args[2]
  table.remove(args,1);table.remove(args,1);args.n=args.n-2
end
package.path=directory..'?.lua;'..savedPath
local ok,result=pcall(function(...)
${body}
end,table.unpack(args,1,args.n))
package.path=savedPath
if args[1]~='--test' then unload() end
if not ok then error(result,0) end
return result
`;
for (const [name,file] of [['util','source/lib/util.lua'],['programs','source/lib/programs.lua'],['config','source/lib/config.lua'],['planner','source/lib/planner.lua'],['modes','source/lib/modes.lua'],['preview','source/lib/preview.lua']]) {
  emit('tests/lib/assline_'+name+'.lua',read(file),true);
}
// Remove obsolete artifacts owned by the previous single-line/chunked build.
for (const file of fs.readdirSync(root)) {
  if (file==='assline.debug.lua' || file==='assline-deploy.tar' || /^assline_data_\w+\d+\.lua$/.test(file)) {
    fs.unlinkSync(path.join(root,file));
  }
}
emit('assline.lua',read('source/launcher.lua'));
emit('assline_app.lua',entry);
emit('assline_data.lua',read('data/matrix.lua'));
emit('interface_probe.lua',read('source/interface_probe_src.lua'));
emit('install.lua',read('source/install.lua'));
fs.mkdirSync(path.join(root,'dist'),{recursive:true});
const files=deployment.map(file=>{
  const data=Buffer.from(read(file),'utf8');
  fs.writeFileSync(path.join(root,'dist',file),data);
  return {path:file,bytes:data.length,checksum:checksum(data)};
});
const bytes=files.reduce((total,file)=>total+file.bytes,0);
if (bytes>4*1024*1024) throw Error('Application/library exceed the 4 MB disk limit');
const release=crypto.createHash('sha256').update(JSON.stringify(files)).digest('hex').slice(0,16);
const manifest='ASSLINE-RELEASE 1\n'+release+' '+bytes+'\n'+
  files.map(file=>file.path+' '+file.bytes+' '+file.checksum+'\n').join('');
fs.writeFileSync(path.join(root,'dist/release.manifest'),manifest);
fs.writeFileSync(path.join(root,'deployment.json'),JSON.stringify({format:1,release,bytes,files},null,2)+'\n');
// Fengari has loadfile but no host io.open; provide the actual built bytes as
// a test-only fixture so installer checksums are tested across JS and Lua.
const literal=value=>{
  let equals='=';
  while(value.includes(']'+equals+']')) equals+='=';
  return '['+equals+'['+value+']'+equals+']';
};
const fixture='return {installer='+literal(read('install.lua'))+',launcher='+literal(read('source/launcher.lua'))+
  ',manifest='+literal(manifest)+',files={'+files.map(file=>'['+JSON.stringify(file.path)+']='+literal(read(file.path))).join(',\n')+'}}\n';
emit('tests/lib/assline_install_fixtures.lua',fixture,true);
console.log('Readable release '+release+': '+files.length+' files, '+bytes+' bytes / 4 MB');
