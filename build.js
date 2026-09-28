'use strict';
const fs = require('fs');
const path = require('path');
let luamin;
try { luamin = require('luamin'); } catch (_) {
  luamin = require(path.join(process.env.APPDATA, 'npm', 'node_modules', 'luamin'));
}
const source = fs.readdirSync(path.join(__dirname, 'src')).filter(x => x.endsWith('.lua')).sort()
  .map(x => fs.readFileSync(path.join(__dirname, 'src', x), 'utf8')).join('\n');
const min = luamin.minify(source);
const bytes = Buffer.byteLength(min);
if (bytes > 32000 || /[\r\n]/.test(min)) throw Error('Deployment exceeds single-paste budget: ' + bytes);
fs.writeFileSync(path.join(__dirname, 'assline.debug.lua'), source);
fs.writeFileSync(path.join(__dirname, 'assline.lua'), min);
console.log('Built assline.lua: ' + bytes + ' / 32000 bytes, one line');
const probe = luamin.minify(fs.readFileSync(path.join(__dirname, 'interface_probe_src.lua'), 'utf8'));
if (Buffer.byteLength(probe) > 32000 || /[\r\n]/.test(probe)) throw Error('Probe exceeds paste budget');
fs.writeFileSync(path.join(__dirname, 'interface_probe.lua'), probe);
console.log('Built interface_probe.lua: ' + Buffer.byteLength(probe) + ' bytes, one line');
