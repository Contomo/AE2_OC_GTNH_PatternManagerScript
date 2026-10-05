'use strict';
const fs = require('fs');
const path = require('path');
const {spawnSync} = require('child_process');
const root = path.dirname(__dirname);
require('./build.js');
let cli;
try { cli = require.resolve('fengari-node-cli/src/lua-cli.js'); } catch (_) {
  const cache = path.join(process.env.LOCALAPPDATA, 'npm-cache', '_npx');
  for (const dir of fs.readdirSync(cache)) {
    const candidate = path.join(cache, dir, 'node_modules/fengari-node-cli/src/lua-cli.js');
    if (fs.existsSync(candidate)) { cli = candidate; break; }
  }
}
if (!cli) throw Error('Install fengari-node-cli to run tests');
for (const file of ['assline_app.lua', 'interface_probe.lua', 'source/lib/planner.lua','source/lib/modes.lua','source/lib/components.lua','source/lib/settings.lua','source/lib/batch.lua','install.lua']) {
  const harness = file.startsWith('interface_probe') ? 'tests/probe.lua' : file==='source/lib/planner.lua' ? 'tests/planner.lua' : file==='source/lib/modes.lua' ? 'tests/modes.lua' : file==='source/lib/components.lua' ? 'tests/components.lua' : file==='source/lib/settings.lua' ? 'tests/settings.lua' : file==='source/lib/batch.lua' ? 'tests/batch.lua' : file==='install.lua' ? 'tests/install.lua' : 'tests/run.lua';
  const r = spawnSync(process.execPath, [cli, harness, file], {cwd:root, encoding:'utf8',maxBuffer:8*1024*1024});
  const output = (r.stdout || '').split('\n').filter(line => {
    const match = /^SNAPSHOT (\w+) (.+)$/.exec(line);
    if (!match) return true;
    const data = JSON.parse(match[2]);
    fs.writeFileSync(path.join(root, 'tests', path.basename(file) + '-' + match[1] + '.actual.json'), JSON.stringify(data));
    return false;
  }).join('\n');
  process.stdout.write(output); process.stderr.write(r.stderr || '');
  if (r.status !== 0 || !/SUCCESS: \d+ tests/.test(r.stdout)) process.exit(1);
}
const python=spawnSync('python',['-m','unittest','discover','-s','tests','-p','test_*.py'],{cwd:root,encoding:'utf8'});
process.stdout.write(python.stdout||'');process.stderr.write(python.stderr||'');
if(python.status!==0) process.exit(1);
