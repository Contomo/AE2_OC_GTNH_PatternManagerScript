-- OpenOS bootstrap and updater. Download with wget; no application files needed.
local fs = require('filesystem')
local shell = require('shell')
local M = {}
local limit = 4 * 1024 * 1024

local function check(ok, message)
  if not ok then error(message, 0) end
  return ok
end

local function read(path)
  local file = io.open(path, 'rb')
  if not file then return nil end
  local value = file:read('*a')
  file:close()
  return value
end

local function finishWrite(file)
  -- OpenOS close returns no value and ignores buffered flush failures.
  -- Flush explicitly, then always close, including after a failed flush.
  local flushed, reason = pcall(function()
    local ok, why = file:flush()
    check(ok, 'Flush failed: '..tostring(why or 'unknown error'))
  end)
  local closed, result, why = pcall(function() return file:close() end)
  if not flushed then return nil, reason end
  if not closed then return nil, result end
  if result==false or why then return nil, why or 'Close failed' end
  return true
end

local function write(path, value)
  local file, reason = io.open(path, 'wb')
  check(file, 'Cannot write '..path..': '..tostring(reason))
  local ok, why = pcall(function()
    local written, reason = file:write(value)
    check(written, 'Write failed: '..tostring(reason or 'unknown error'))
  end)
  local finished, finishReason = finishWrite(file)
  check(ok, 'Cannot write '..path..': '..tostring(why))
  check(finished, 'Cannot finish write '..path..': '..tostring(finishReason))
end

local function move(from, to)
  local ok, reason = fs.rename(from, to)
  check(ok, 'Cannot move '..from..': '..tostring(reason))
end

local function directory(path)
  if fs.exists(path) then check(fs.isDirectory(path), 'Not a directory: '..path)
  else check(fs.makeDirectory(path), 'Cannot create directory: '..path) end
end

local function replace(path, value)
  write(path..'.new', value)
  if fs.exists(path) then
    if fs.exists(path..'.bak') then check(fs.remove(path..'.bak'), 'Cannot remove old backup') end
    move(path, path..'.bak')
  end
  local ok, reason = fs.rename(path..'.new', path)
  if not ok then
    if fs.exists(path..'.bak') then move(path..'.bak', path) end
    error('Cannot activate '..path..': '..tostring(reason), 0)
  end
end

local function releaseId(value)
  return type(value)=='string' and #value==16 and value:match('^[a-f0-9]+$')
end

function M.active(root)
  -- A power loss between renames leaves the backup as the active version.
  for _,name in ipairs({'active', 'active.bak'}) do
    local id = read(root..'/'..name)
    id = id and id:match('^([a-f0-9]+)%s*$')
    if releaseId(id) and fs.exists(root..'/releases/'..id..'/assline_app.lua') then return id end
  end
end

function M.manifest(value)
  local lines = {}
  for line in value:gmatch('[^\r\n]+') do lines[#lines+1]=line end
  check(lines[1]=='ASSLINE-RELEASE 1', 'Invalid release manifest (check the download URL)')
  local id, total = (lines[2] or ''):match('^([a-f0-9]+) (%d+)$')
  total = tonumber(total)
  check(releaseId(id) and total and total>0 and total<=limit, 'Invalid release size or ID')
  local result, seen, size = {id=id, bytes=total, files={}}, {}, 0
  for n=3,#lines do
    local path, bytes, checksum = lines[n]:match('^([%w_%-]+%.lua) (%d+) ([a-f0-9]+)$')
    bytes = tonumber(bytes)
    check(path and bytes and bytes>0 and bytes<=limit and checksum and #checksum==8,
      'Invalid release file entry')
    check(not seen[path], 'Duplicate release file')
    seen[path]=true; size=size+bytes
    result.files[#result.files+1]={path=path, bytes=bytes, checksum=checksum}
    check(#result.files<=256 and size<=limit, 'Release exceeds the 4 MB limit')
  end
  check(size==total, 'Manifest sizes do not add up')
  for _,path in ipairs({'assline.lua', 'assline_app.lua', 'install.lua'}) do
    check(seen[path], 'Release is missing '..path)
  end
  return result
end

local function checksum(a, b, chunk)
  for n=1,#chunk do
    a=(a+chunk:byte(n))%65521
    b=(b+a)%65521
  end
  return a,b
end

local function fingerprint(path)
  local file = io.open(path, 'rb')
  if not file then return nil end
  local size, a, b = 0, 1, 0
  while true do
    local chunk = file:read(8192)
    if not chunk then break end
    size=size+#chunk; a,b=checksum(a,b,chunk)
  end
  file:close()
  return size, string.format('%04x%04x', b,a)
end

local function verified(directory, manifest)
  for _,entry in ipairs(manifest.files) do
    local size, digest = fingerprint(directory..'/'..entry.path)
    if size~=entry.bytes or digest~=entry.checksum then return false end
  end
  return true
end

local function download(url, path, maximum)
  local internet = require('internet')
  local response = internet.request(url, nil, {['Cache-Control']='no-cache'})
  local file, size, a, b, parts = nil, 0, 1, 0, {}
  local ok, reason = pcall(function()
    if path then
      local why
      file, why = io.open(path, 'wb')
      check(file, 'Cannot write download: '..tostring(why))
    end
    for chunk in response do
      size=size+#chunk
      check(size<=maximum, 'Download exceeds expected size: '..url)
      if file then
        local written, why = file:write(chunk)
        check(written, 'Download write failed: '..tostring(why or 'unknown error'))
      else parts[#parts+1]=chunk end
      a,b=checksum(a,b,chunk)
    end
    if response.response then
      local code = response.response()
      check(not code or code==200, 'HTTP '..tostring(code)..': '..url)
    end
  end)
  if file then
    local finished, why = finishWrite(file)
    if ok and not finished then ok,reason=false,why end
  end
  pcall(function() response.close() end)
  check(ok, 'Download failed: '..tostring(reason)..' ('..url..')')
  return size, string.format('%04x%04x',b,a), table.concat(parts)
end

local function sourceURL(url)
  check(type(url)=='string' and #url<=2048 and url:match('^https?://[^%s]+$')
    and not url:find('[%c?#]'), 'Supply an HTTP(S) base URL containing the release files')
  return url:gsub('/+$','')
end

local function cleanup(directory)
  -- Release directories are flat. Leave unexpected directories/files alone.
  if not fs.exists(directory) then return end
  for name in fs.list(directory) do
    if name:match('^[%w_%-]+%.lua$') or name=='release.manifest' then
      fs.remove(directory..'/'..name)
    end
  end
  for _ in fs.list(directory) do return false end
  return fs.remove(directory)
end

function M.install(root, url, checkOnly)
  root = shell.resolve(root or '/home/assline'):gsub('/+$','')
  check(root~='' and root~='/' and not root:find('[%c]'), 'Invalid installation directory')
  url = sourceURL(url or (read(root..'/source.url') or ''):match('^([^\r\n]+)'))
  print('Checking '..url)
  local _, _, manifestText = download(url..'/release.manifest', nil, 65536)
  local manifest = M.manifest(manifestText)
  local active = M.active(root)
  local destination = root..'/releases/'..manifest.id
  if active==manifest.id and verified(destination, manifest)
    and read(root..'.lua')==read(destination..'/assline.lua') then
    if not checkOnly and read(root..'/source.url')~=url..'\n' then replace(root..'/source.url',url..'\n') end
    print('Already up to date: '..manifest.id)
    return false
  end
  if checkOnly then
    print('Update available: '..manifest.id)
    return true
  end
  directory(root..'/releases')
  local disk = fs.get(root)
  if disk and disk.spaceTotal and disk.spaceUsed then
    check(disk.spaceTotal()-disk.spaceUsed()>=manifest.bytes+65536,
      'Not enough disk space to download a complete release before replacing the current one')
  end
  local stage = root..'/stage-'..manifest.id
  cleanup(stage)
  check(not fs.exists(stage), 'Download directory contains unexpected files: '..stage)
  directory(stage)
  local ok, reason = pcall(function()
    for n,entry in ipairs(manifest.files) do
      print(string.format('Downloading %d/%d: %s',n,#manifest.files,entry.path))
      local path = stage..'/'..entry.path
      local size, digest = download(url..'/'..entry.path, path, entry.bytes)
      check(size==entry.bytes and digest==entry.checksum, 'Incomplete or changed download: '..entry.path)
      local parsed, why = loadfile(path)
      check(parsed, 'Invalid Lua in '..entry.path..': '..tostring(why))
    end
    write(stage..'/release.manifest',manifestText)
    if fs.exists(destination) then
      -- Repair an existing incomplete/corrupt copy without destroying it first.
      local damaged = root..'/damaged-'..manifest.id
      check(not fs.exists(damaged), 'Previous damaged copy still exists: '..damaged)
      move(destination, damaged)
      local promoted, why = fs.rename(stage, destination)
      if not promoted then move(damaged,destination); error(why,0) end
      cleanup(damaged)
    else move(stage,destination) end
    local launcher = check(read(destination..'/assline.lua'),'Missing launcher')
    if read(root..'.lua')~=launcher then replace(root..'.lua',launcher) end
    if read(root..'/source.url')~=url..'\n' then replace(root..'/source.url',url..'\n') end
    replace(root..'/active',manifest.id..'\n')
  end)
  if not ok then cleanup(stage); error('Install/update failed: '..tostring(reason),0) end
  -- Keep the immediately previous version for interrupted activation recovery.
  for name in fs.list(root..'/releases') do
    local id=name:gsub('/$','')
    if releaseId(id) and id~=manifest.id and id~=active then cleanup(root..'/releases/'..id) end
  end
  print('Installed '..manifest.id..'. Run '..root..'.lua')
  return true
end

if ...=='--module' then return M end
local args, options = shell.parse(...)
if options.help or options.h then
  print('Usage: install.lua <base-url> [installation-directory]')
  print('Default directory: /home/assline. Repeat to update; --check only checks.')
  return
end
return M.install(args[2] or '/home/assline', args[1], options.check)
