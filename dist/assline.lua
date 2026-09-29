-- Stable OpenOS entry point. Releases live beside it in <script-name>/releases.
local fs = require('filesystem')
local shell = require('shell')
local arguments = {...}
local path = shell.resolve(require('process').info().path)
local root = path:gsub('%.lua$','')
local function release(name)
  local file = io.open(root..'/'..name,'r')
  if not file then return end
  local id = file:read('*l'); file:close()
  if id and #id==16 and id:match('^[a-f0-9]+$') then
    local directory=root..'/releases/'..id
    if fs.exists(directory..'/assline_app.lua') then return directory end
  end
end
local directory = release('active') or release('active.bak')
assert(directory,'No installed release. Run the wget installer first.')
if arguments[1]=='--update' or arguments[1]=='--check-update' then
  local updater = assert(loadfile(directory..'/install.lua'))('--module')
  return updater.install(root,arguments[2],arguments[1]=='--check-update')
end
return assert(loadfile(directory..'/assline_app.lua'))('--module-directory',directory..'/',table.unpack(arguments))
