-- Installer contracts: realistic OpenOS directory/rename behavior, HTTP streams,
-- failed transfers, and release switching. No network or host filesystem writes.
package.path='tests/lib/?.lua;'..package.path
local originalOpen, originalLoad = io.open, loadfile
local fixture=require('assline_install_fixtures')
local installerSource, launcherSource = fixture.installer, fixture.launcher
local actualManifest = fixture.manifest
local files, dirs, responses, requested, closed, renameFailure, freeBytes, interrupted
local handles, flushFailure, closeFailure, memoryBytes
local root, url = '/home/assline', 'https://updates.invalid/dist'
local function parent(path) return path:match('^(.*)/[^/]+$') end
local function mkdir(path)
  local current=''
  for name in path:gmatch('[^/]+') do current=current..'/'..name;dirs[current]=true end
end
local function list(path)
  local result, seen = {}, {}
  for _,map in ipairs({files,dirs}) do
    for key in pairs(map) do
      local tail=key:sub(1,#path+1)==path..'/' and key:sub(#path+2)
      if tail and tail~='' then
        local name=tail:match('^[^/]+')
        if not seen[name] then result[#result+1]=name..(dirs[path..'/'..name] and '/' or '');seen[name]=true end
      end
    end
  end
  table.sort(result);local n=0
  return function() n=n+1;return result[n] end
end
local fs={
  exists=function(path) return files[path]~=nil or dirs[path]~=nil end,
  isDirectory=function(path) return dirs[path]==true end,
  makeDirectory=function(path)
    if dirs[path] or files[path] then return nil,'already exists' end
    mkdir(path);return true
  end,
  list=list,
  get=function() return {spaceTotal=function() return freeBytes end,spaceUsed=function()
    local total=0;for _,value in pairs(files) do total=total+#value end;return total
  end} end,
  remove=function(path)
    if dirs[path] then if list(path)() then return nil,'directory not empty' end;dirs[path]=nil
    elseif files[path]~=nil then files[path]=nil else return nil,'not found' end
    return true
  end,
  rename=function(from,to)
    if renameFailure==to then
      renameFailure=nil
      if interrupted then error('power loss') end
      return nil,'injected rename failure'
    end
    assert(not dirs[to] and files[to]==nil,'OpenOS rename must not overwrite an existing destination')
    assert(dirs[parent(to)],'Destination parent must exist')
    if files[from]~=nil then files[to],files[from]=files[from],nil;return true end
    if not dirs[from] then return nil,'missing source' end
    local changes={}
    for _,map in ipairs({files,dirs}) do
      for path,value in pairs(map) do
        if path==from or path:sub(1,#from+1)==from..'/' then changes[#changes+1]={map,path,to..path:sub(#from+1),value} end
      end
    end
    for _,c in ipairs(changes) do c[1][c[2]]=nil;c[1][c[3]]=c[4] end
    return true
  end}
io.open=function(path,mode)
  if path:sub(1,6)~='/home/' then return originalOpen(path,mode) end
  local writing=mode:find('w',1,true)
  if not dirs[parent(path)] then return nil,'missing parent' end
  if not writing and files[path]==nil then return nil,'missing file' end
  if writing then files[path]='' end
  local position,pending=1,''
  local handle={closed=false,path=path,
    read=function(_,length)
      local content=files[path]
      if position>#content then return nil end
      local value
      if length=='*a' then value=content:sub(position);position=#content+1
      elseif length=='*l' then
        local ending=content:find('\n',position,true) or #content+1
        value=content:sub(position,ending-1);position=ending+1
      else value=content:sub(position,position+length-1);position=position+#value end
      return value
    end,
    write=function(self,value) pending=pending..value;return self end,
    flush=function(self)
      local chunk=pending;pending=''
      if flushFailure==path then flushFailure=nil;return nil,'disk write failed' end
      if writing then
        local used=0;for _,value in pairs(files) do used=used+#value end
        if used+#chunk>freeBytes then return nil,'not enough disk space' end
      end
      if writing then files[path]=files[path]..chunk end
      return self
    end,
    close=function(self)
      -- OpenOS close flushes but ignores the flush result, then returns no value.
      if writing then self:flush() end
      self.closed=true
      if closeFailure==path then closeFailure=nil;error('disk close failed') end
    end}
  handles[#handles+1]=handle
  return handle
end
loadfile=function(path,...)
  if path:sub(1,6)=='/home/' then return load(files[path] or '', '@'..path, 't', _G) end
  return originalLoad(path,...)
end
package.preload.filesystem=function() return fs end
package.preload.shell=function() return {resolve=function(p) return p end,parse=function(...) return {...},{} end} end
package.preload.process=function() return {info=function() return {path=root..'.lua'} end} end
package.preload.computer=function() return {freeMemory=function() return memoryBytes end} end
package.preload.internet=function() return {request=function(address)
  requested[#requested+1]=address
  local source=responses[address]
  if not source then error('network unavailable') end
  local position,done=1,false
  local response={close=function() if not done then closed=closed+1;done=true end end,
    response=function() return source.code or 200 end}
  return setmetatable(response,{__call=function()
    if source.fail and position>4096 then error('connection lost') end
    if position>#source.body then return nil end
    local chunk=source.body:sub(position,position+4095);position=position+#chunk;return chunk
  end})
end} end
local M=assert(originalLoad('install.lua'))('--module')
local count=0
local function reset()
  files,dirs,responses,requested,closed={},{},{},{},0
  renameFailure,interrupted,freeBytes=nil,false,4*1024*1024
  handles,flushFailure,closeFailure={},nil,nil
  memoryBytes=16*1024*1024
  mkdir('/home')
  for _,name in ipairs({'assline.cfg','assline.pending','assline.last','assline-perf.log'}) do files['/home/'..name]='preserve '..name end
end
local function checksum(value)
  local a,b=1,0
  for n=1,#value do a=(a+value:byte(n))%65521;b=(b+a)%65521 end
  return string.format('%04x%04x',b,a)
end
local function release(id,app)
  local payload={['assline.lua']=launcherSource,['install.lua']=installerSource,
    ['assline_app.lua']=app or ('return {version="'..id..'", args={...}}')}
  local entries,total={},0
  for _,name in ipairs({'assline.lua','install.lua','assline_app.lua'}) do
    local text=payload[name];total=total+#text
    entries[#entries+1]=name..' '..#text..' '..checksum(text)
    responses[url..'/'..name]={body=text}
  end
  local text='ASSLINE-RELEASE 1\n'..id..' '..total..'\n'..table.concat(entries,'\n')..'\n'
  responses[url..'/release.manifest']={body=text}
  return text
end
local savedPrint=print
print=function() end
local function test(name,f)
  reset();f()
  for _,handle in ipairs(handles) do assert(handle.closed,'File handle left open: '..handle.path) end
  count=count+1;savedPrint('PASS '..name)
end
local function failure(f,part)
  local ok,why=pcall(f);assert(not ok and tostring(why):find(part,1,true),tostring(why))
end
local function oldRelease()
  release('aaaaaaaaaaaaaaaa');M.install(root,url)
  return files[root..'.lua']
end

test('real readable release installs with matching build checksums and preserves user state',function()
  responses[url..'/release.manifest']={body=actualManifest}
  local manifest=M.manifest(actualManifest)
  for _,entry in ipairs(manifest.files) do responses[url..'/'..entry.path]={body=fixture.files[entry.path]} end
  files[root..'.lua']='legacy script'
  assert(M.install(root,url));assert(M.active(root)==manifest.id)
  for _,name in ipairs({'assline.cfg','assline.pending','assline.last','assline-perf.log'}) do assert(files['/home/'..name]=='preserve '..name) end
  assert(closed==#requested and files[root..'.lua.bak']=='legacy script')
end)
test('updates remember the URL, skip unchanged releases and retain one previous release',function()
  oldRelease();release('bbbbbbbbbbbbbbbb');assert(M.install(root))
  local before=#requested;assert(not M.install(root));assert(#requested==before+1)
  release('cccccccccccccccc');M.install(root)
  assert(M.active(root)=='cccccccccccccccc')
  assert(dirs[root..'/releases/bbbbbbbbbbbbbbbb'] and not dirs[root..'/releases/aaaaaaaaaaaaaaaa'])
end)
test('check command downloads only the manifest without installing',function()
  oldRelease();release('bbbbbbbbbbbbbbbb');local before=#requested
  assert(assert(loadfile(root..'.lua'))('--check-update'))
  assert(#requested==before+1 and M.active(root)=='aaaaaaaaaaaaaaaa')
end)
test('changing the source URL is saved even when the release is unchanged',function()
  oldRelease();local replacement='https://another.invalid/dist'
  responses[replacement..'/release.manifest']=responses[url..'/release.manifest']
  local before=#requested;assert(not M.install(root,replacement))
  assert(files[root..'/source.url']==replacement..'\n' and #requested==before+1)
end)
test('failed HTTP leaves the current release and launcher untouched',function()
  local boot=oldRelease();release('bbbbbbbbbbbbbbbb')
  responses[url..'/install.lua']={body='HTTP error',code=404}
  failure(function() M.install(root) end,'HTTP 404')
  assert(M.active(root)=='aaaaaaaaaaaaaaaa' and files[root..'.lua']==boot)
  assert(not dirs[root..'/stage-bbbbbbbbbbbbbbbb'] and closed==#requested)
end)
test('same-length corrupt downloads fail checksum verification',function()
  oldRelease();release('bbbbbbbbbbbbbbbb')
  local response=responses[url..'/assline_app.lua'];response.body='x'..response.body:sub(2)
  failure(function() M.install(root) end,'Incomplete or changed download')
  assert(M.active(root)=='aaaaaaaaaaaaaaaa')
end)
test('a mid-download connection loss closes the stream and preserves the active release',function()
  oldRelease();release('bbbbbbbbbbbbbbbb','return true\n--'..string.rep('x',10000))
  responses[url..'/assline_app.lua'].fail=true
  failure(function() M.install(root) end,'connection lost')
  assert(M.active(root)=='aaaaaaaaaaaaaaaa' and closed==#requested)
  assert(not dirs[root..'/stage-bbbbbbbbbbbbbbbb'])
end)

test('buffered download write failure closes the file and preserves the active release',function()
  local boot=oldRelease();release('bbbbbbbbbbbbbbbb')
  flushFailure=root..'/stage-bbbbbbbbbbbbbbbb/assline.lua'
  failure(function() M.install(root) end,'Flush failed: disk write failed')
  assert(M.active(root)=='aaaaaaaaaaaaaaaa' and files[root..'.lua']==boot)
  assert(not dirs[root..'/stage-bbbbbbbbbbbbbbbb'] and closed==#requested)
end)

test('buffered activation write failure preserves the previous pointer',function()
  local boot=oldRelease();release('bbbbbbbbbbbbbbbb')
  flushFailure=root..'/active.new'
  failure(function() M.install(root) end,'Cannot finish write '..root..'/active.new: Flush failed: disk write failed')
  assert(M.active(root)=='aaaaaaaaaaaaaaaa' and files[root..'.lua']==boot)
  assert(files[root..'/active']=='aaaaaaaaaaaaaaaa\n')
end)

test('download close exceptions are reported without leaking the stream',function()
  local boot=oldRelease();release('bbbbbbbbbbbbbbbb')
  closeFailure=root..'/stage-bbbbbbbbbbbbbbbb/assline.lua'
  failure(function() M.install(root) end,'disk close failed')
  assert(M.active(root)=='aaaaaaaaaaaaaaaa' and files[root..'.lua']==boot)
  assert(not dirs[root..'/stage-bbbbbbbbbbbbbbbb'] and closed==#requested)
end)
test('Lua syntax is checked before activation even with a valid checksum',function()
  oldRelease();release('bbbbbbbbbbbbbbbb','this is invalid Lua')
  failure(function() M.install(root) end,'Invalid Lua')
  assert(M.active(root)=='aaaaaaaaaaaaaaaa')
end)
test('failed activation restores the previous pointer and the launcher still runs',function()
  oldRelease();release('bbbbbbbbbbbbbbbb');renameFailure=root..'/active'
  failure(function() M.install(root) end,'Cannot activate')
  local app=assert(loadfile(root..'.lua'))('example')
  assert(app.version=='aaaaaaaaaaaaaaaa' and app.args[3]=='example')
  assert(M.install(root) and M.active(root)=='bbbbbbbbbbbbbbbb')
end)
test('interrupted activation uses its backup and the next update completes',function()
  oldRelease();release('bbbbbbbbbbbbbbbb');renameFailure=root..'/active';interrupted=true
  failure(function() M.install(root) end,'power loss')
  assert(not files[root..'/active'] and M.active(root)=='aaaaaaaaaaaaaaaa')
  assert(assert(loadfile(root..'.lua'))().version=='aaaaaaaaaaaaaaaa')
  interrupted=false;assert(M.install(root));assert(M.active(root)=='bbbbbbbbbbbbbbbb')
end)
test('insufficient free disk space leaves the existing version active',function()
  oldRelease();release('bbbbbbbbbbbbbbbb');freeBytes=1
  failure(function() M.install(root) end,'Not enough disk space')
  assert(M.active(root)=='aaaaaaaaaaaaaaaa' and not dirs[root..'/stage-bbbbbbbbbbbbbbbb'])
end)

local function actualRelease(id)
  local manifest=M.manifest(actualManifest)
  local text=actualManifest
  if id then text=text:gsub(manifest.id,id,1) end
  responses[url..'/release.manifest']={body=text}
  for _,entry in ipairs(manifest.files) do responses[url..'/'..entry.path]={body=fixture.files[entry.path]} end
  return M.manifest(text)
end

local function tightDisk()
  local first=actualRelease();M.install(root,url)
  -- OpenOS and unrelated files share the only 4 MB drive. One release fits;
  -- two do not. flush() enforces the actual byte budget in these tests.
  files['/home/unrelated-files']=string.rep('u',2000000)
  local next=actualRelease('bbbbbbbbbbbbbbbb')
  return first,next
end

test('a stale rollback release and abandoned stage are pruned before the space check',function()
  oldRelease();release('bbbbbbbbbbbbbbbb');M.install(root)
  local previous=root..'/releases/aaaaaaaaaaaaaaaa'
  files[previous..'/old_generated.lua']=string.rep('x',2500000)
  mkdir(root..'/stage-dddddddddddddddd');files[root..'/stage-dddddddddddddddd/assline_app.lua']='partial'
  release('cccccccccccccccc', 'return true\n--'..string.rep('x',1200000))
  memoryBytes=1 -- Success proves that obsolete files freed enough disk for normal staging.
  assert(M.install(root) and M.active(root)=='cccccccccccccccc')
  assert(not dirs[previous] and not dirs[root..'/stage-dddddddddddddddd'])
  assert(dirs[root..'/releases/bbbbbbbbbbbbbbbb'])
end)

test('the real six-file release updates on one 4 MB drive through verified RAM staging',function()
  local first,next=tightDisk()
  assert(M.install(root) and M.active(root)==next.id)
  assert(not dirs[root..'/releases/'..first.id])
  for _,entry in ipairs(next.files) do
    assert(files[root..'/releases/'..next.id..'/'..entry.path]==fixture.files[entry.path])
  end
  assert(files['/home/unrelated-files']==string.rep('u',2000000))
  for _,name in ipairs({'assline.cfg','assline.pending','assline.last','assline-perf.log'}) do
    assert(files['/home/'..name]=='preserve '..name)
  end
  assert(closed==#requested)
end)

test('RAM staging leaves current code intact on HTTP, checksum and Lua syntax failures',function()
  for _,kind in ipairs({'http','checksum','syntax'}) do
    reset();local first,next=tightDisk()
    local old=files[root..'/releases/'..first.id..'/assline_app.lua']
    local response=responses[url..'/assline_app.lua']
    local reason
    if kind=='http' then response.code=500;reason='HTTP 500'
    elseif kind=='checksum' then response.body='x'..response.body:sub(2);reason='Incomplete or changed download'
    else
      local source='this is invalid Lua'
      response.body=source
      local text=responses[url..'/release.manifest'].body
      local oldBytes,oldSum=text:match('assline_app%.lua (%d+) ([a-f0-9]+)')
      local newTotal=next.bytes-tonumber(oldBytes)+#source
      text=text:gsub(next.id..' '..next.bytes,next.id..' '..newTotal,1)
      text=text:gsub('assline_app%.lua '..oldBytes..' '..oldSum,'assline_app.lua '..#source..' '..checksum(source),1)
      responses[url..'/release.manifest'].body=text;reason='Invalid Lua'
    end
    failure(function() M.install(root) end,reason)
    assert(M.active(root)==first.id and files[root..'/releases/'..first.id..'/assline_app.lua']==old)
    assert(not dirs[root..'/releases/'..next.id] and closed==#requested)
    for _,h in ipairs(handles) do assert(h.closed) end
  end
end)

test('a RAM update restores previous code after an ordinary disk write failure',function()
  local first,next=tightDisk()
  flushFailure=root..'/releases/'..next.id..'/assline_app.lua'
  failure(function() M.install(root) end,'previous release restored')
  assert(M.active(root)==first.id and not dirs[root..'/releases/'..next.id])
  for _,entry in ipairs(first.files) do
    assert(files[root..'/releases/'..first.id..'/'..entry.path]==fixture.files[entry.path])
  end
  assert(M.install(root) and M.active(root)==next.id)
end)

test('a RAM update restores the launcher and pointer if activation fails',function()
  local first,next=tightDisk()
  local boot=files[root..'.lua'];renameFailure=root..'/active'
  failure(function() M.install(root) end,'previous release restored')
  assert(M.active(root)==first.id and files[root..'.lua']==boot)
  assert(not dirs[root..'/releases/'..next.id] and files[root..'/source.url']==url..'\n')
end)

test('rerunning the bootstrap repairs a power-cut replacement with no usable active release',function()
  local first,next=tightDisk()
  local old=root..'/releases/'..first.id
  for _,entry in ipairs(first.files) do assert(fs.remove(old..'/'..entry.path)) end
  assert(fs.remove(old..'/release.manifest'));assert(fs.remove(old))
  local partial=root..'/releases/'..next.id
  mkdir(partial);files[partial..'/assline_app.lua']='return true -- interrupted copy'
  assert(M.active(root)==nil)
  assert(M.install(root,url) and M.active(root)==next.id)
  assert(files['/home/assline.cfg']=='preserve assline.cfg' and files['/home/assline.pending']=='preserve assline.pending')
end)

test('insufficient RAM or a release too large for the drive never removes active code',function()
  local first=tightDisk();memoryBytes=1
  failure(function() M.install(root) end,'Not enough free RAM')
  assert(M.active(root)==first.id)
  memoryBytes=16*1024*1024;files['/home/unrelated-files']=string.rep('u',3000000)
  failure(function() M.install(root) end,'new release itself')
  assert(M.active(root)==first.id and files['/home/assline.cfg']=='preserve assline.cfg')
end)
test('manifest paths cannot escape the release directory and duplicates are rejected',function()
  local text=release('aaaaaaaaaaaaaaaa')
  failure(function() M.manifest(text:gsub('assline_app.lua','../assline.cfg',1)) end,'Invalid release file')
  failure(function() M.manifest(text..'assline.lua 1 00000000\n') end,'Duplicate')
  failure(function() M.manifest('ASSLINE-RELEASE 1\naaaaaaaaaaaaaaaa 4194305\n') end,'Invalid release size')
end)
print=savedPrint
print('SUCCESS: '..count..' tests (wget installer/updater)')
