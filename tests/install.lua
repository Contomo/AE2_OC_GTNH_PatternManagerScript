-- Installer contracts: realistic OpenOS directory/rename behavior, HTTP streams,
-- failed transfers, and release switching. No network or host filesystem writes.
package.path='tests/lib/?.lua;'..package.path
local originalOpen, originalLoad = io.open, loadfile
local fixture=require('assline_install_fixtures')
local installerSource, launcherSource = fixture.installer, fixture.launcher
local actualManifest = fixture.manifest
local files, dirs, responses, requested, closed, renameFailure, freeBytes, interrupted
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
  get=function() return {spaceTotal=function() return freeBytes end,spaceUsed=function() return 0 end} end,
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
  local position=1
  return {
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
    write=function(self,value) files[path]=files[path]..value;return self end,
    close=function() return true end}
end
loadfile=function(path,...)
  if path:sub(1,6)=='/home/' then return load(files[path] or '', '@'..path, 't', _G) end
  return originalLoad(path,...)
end
package.preload.filesystem=function() return fs end
package.preload.shell=function() return {resolve=function(p) return p end,parse=function(...) return {...},{} end} end
package.preload.process=function() return {info=function() return {path=root..'.lua'} end} end
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
  reset();f();count=count+1;savedPrint('PASS '..name)
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
test('manifest paths cannot escape the release directory and duplicates are rejected',function()
  local text=release('aaaaaaaaaaaaaaaa')
  failure(function() M.manifest(text:gsub('assline_app.lua','../assline.cfg',1)) end,'Invalid release file')
  failure(function() M.manifest(text..'assline.lua 1 00000000\n') end,'Duplicate')
  failure(function() M.manifest('ASSLINE-RELEASE 1\naaaaaaaaaaaaaaaa 4194305\n') end,'Invalid release size')
end)
print=savedPrint
print('SUCCESS: '..count..' tests (wget installer/updater)')
