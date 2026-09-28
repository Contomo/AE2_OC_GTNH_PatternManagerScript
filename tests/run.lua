-- Contract mocks based on GTNH source, including terminal zero-based slots,
-- part-interface hidden side argument, typed NBT, and list-removing clears.
local artifact=... or 'assline.debug.lua'
-- OC does not expose manual collection. Do not mask accidental calls in tests.
collectgarbage=nil
local function cp(t) if type(t)~='table' then return t end local r={} for k,v in pairs(t) do r[k]=cp(v) end return r end
local function ser(t)
  if type(t)=='table' then
    local ks={};for k in pairs(t) do ks[#ks+1]=k end
    table.sort(ks,function(a,b) if type(a)==type(b) then return a<b end return type(a)<type(b) end)
    local r={};for _,k in ipairs(ks) do r[#r+1]='['..ser(k)..']='..ser(t[k]) end;return '{'..table.concat(r,',')..'}'
  elseif type(t)=='string' then return string.format('%q',t) else return tostring(t) end
end
local function unser(s) local f=load('return '..s,'mock','t',{});if f then return f() end end
local files,interfaces,mutations,fail,events,frame,history={},{},0,nil,{},{},{}
local foreground,background,fg,bg={},{},0xffffff,0
local controlDown=false
local now,energy,capacity,recharge,sleeps=123,10000,10000,0,0
local waitEvent,dataCalls,dataCost=nil,0,0
local powerDropAt,gpuFills=nil,0
local function typed(kind,value) return {__nbt_type=kind,__value=value} end
local function compound(value) return typed('compound',value or {}) end
local function item(label,qty,damage,extra)
  local t=extra and ser(compound(extra)) or nil
  return {name='gregtech:gt.metaitem.01',damage=damage or 123,size=qty or 128,label=label or 'Fine Europium Wire',tag=t,hasTag=t~=nil}
end
local function refresh(p)
  local root=unser(p.tag)
  for _,which in ipairs({'inputs','outputs'}) do
    local arr={}; local n=p.lengths[which]
    for i=1,n do arr[i]=compound(p[which][i] or {}) end
    root.__value[which=='inputs' and 'in' or 'out']=typed('list',arr)
  end
  p.tag=ser(root);return p
end
local function pattern(inputs,outputs,crafting)
  local n=0;for k in pairs(inputs or {}) do n=math.max(n,k) end
  local p={name='appliedenergistics2:item.ItemEncodedPattern',damage=0,size=1,hasTag=true,
    label='Encoded Pattern',inputs=cp(inputs or {}),outputs=cp(outputs or {item('Machine',1,999)}),
    isCraftable=crafting==true,tag=ser(compound({crafting=typed('byte',crafting and 1 or 0),substitute=typed('byte',0),
    preserved=typed('int',42)}))}
  p.lengths={inputs=n,outputs=#p.outputs};return refresh(p)
end
local function iface(name,x,patterns,side)
  local t={name=name,location={x=x,y=64,z=0,dimId=0},side=side or 6,patterns=patterns or {}}
  interfaces[#interfaces+1]=t;return t
end
local target,buffer,dest1,dest2,wrongDirect
local function byref(ref)
  for _,v in ipairs(interfaces) do if v.location.x==ref.location.x and v.side==ref.side then return v end end
  error('missing ref')
end
local function iterator(list)
  local index=0
  return setmetatable({}, {__call=function() index=index+1;return cp(list[index]) end})
end
local function mutate(label)
  mutations=mutations+1;history[#history+1]=label
  if powerDropAt==label then energy=2000;recharge=0;powerDropAt=nil end
  if fail and fail.label==label then fail=nil;error('injected '..label) end
end
local proxies={}
proxies.terminal={address='terminal',getInterfacesByName=function(name)
  local r={};for _,i in ipairs(interfaces) do if i.name==name then r[#r+1]=i end end;return iterator(r)
end,getInterfacesByLocation=function(loc,side)
  local r={};for _,i in ipairs(interfaces) do if i.location.x==loc.x and i.side==side then r[#r+1]=i end end;return iterator(r)
end,send=function(from,to)
  assert(from.slot>=0 and to.slot>=0,'zero based slots required')
  local a,b=byref(from),byref(to)
  if b.patterns[to.slot] then return false,'occupied' end
  if not a.patterns[from.slot] then return false,'source absent' end
  mutate('send-before')
  b.patterns[to.slot],a.patterns[from.slot]=a.patterns[from.slot],nil
  mutate('send-after')
  return true,to.slot
end}
local function directArgs(...)
  local a={...};local b=wrongDirect or buffer
  if b.side~=6 then assert(table.remove(a,1)==b.side,'multipart side missing/wrong') end
  local slot=table.remove(a,1);assert(slot>=1 and slot<=9,'one based direct slot required')
  return b,slot-1,a
end
proxies.direct={address='direct',getInterfacePattern=function(...)
  local b,s=directArgs(...);return cp(b.patterns[s])
end}
for _,which in ipairs({'Input','Output'}) do
  local key=which=='Input' and 'inputs' or 'outputs'
  proxies.direct['setInterfacePattern'..which]=function(...)
    local b,s,a=directArgs(...);local index,detail,tp=a[1],a[2],a[3]
    assert(index>=1,'one based entry index required')
    local p=assert(b.patterns[s]);mutate('set-before')
    if detail then
      assert(tp=='item','must use item type')
      local value=cp(detail);value.label='Item';value.hasTag=value.tag~=nil
      if value.tag then local root=unser(value.tag).__value;if root.display and root.display.__value.Name then value.label=root.display.__value.Name.__value end end
      p[key][index]=value;p.lengths[key]=math.max(p.lengths[key],index)
    else
      for i=index,p.lengths[key]-1 do p[key][i]=p[key][i+1] end
      p[key][p.lengths[key]]=nil;p.lengths[key]=p.lengths[key]-1
    end
    refresh(p);mutate('set-after');return true
  end
end
-- Match ConverterNBT.parseWithType, including its missing typed-string case.
-- A generic serialize/unserialize mock hid the real server's string loss.
local function encodeTree(v)
  if type(v)=='string' then return typed('string',v) end
  if type(v)~='table' then return nil end
  local kind=v.__nbt_type
  if kind=='string' then return nil end -- This is the upstream bug.
  if kind=='compound' then
    local r={};for k,x in pairs(v.__value) do r[k]=encodeTree(x) end;return compound(r)
  elseif kind=='list' then
    local r={};for _,x in ipairs(v.__value) do local n=encodeTree(x);if n then r[#r+1]=n end end
    return typed(kind,r)
  elseif kind=='byte' or kind=='short' or kind=='int' or kind=='long' or kind=='float'
    or kind=='double' or kind=='byte_array' or kind=='int_array' then return cp(v) end
end
local function dataCharge()
  dataCalls=dataCalls+1
  assert(energy>=capacity*0.25,'component called below reserve')
  energy=energy-dataCost
end
proxies.data={address='data',encodeNBT=function(t) dataCharge();return ser(encodeTree(t)) end,
  decodeNBT=function(t) dataCharge();return unser(t) end}
local gpu={}
local width,height=160,50
gpu.maxResolution=function() return 160,50 end;gpu.getResolution=function() return width,height end
gpu.setResolution=function(w,h) width,height=w,h;return true end
gpu.getForeground=function() return 0xffffff end;gpu.getBackground=function() return 0 end
gpu.setForeground=function(c) fg=c end;gpu.setBackground=function(c) bg=c end
gpu.fill=function()
  gpuFills=gpuFills+1
  frame={};foreground={};background={}
  for y=1,50 do foreground[y]={};background[y]={};for x=1,160 do foreground[y][x]=fg;background[y][x]=bg end end
end
gpu.set=function(x,y,s)
  assert(x>=1 and y>=1 and y<=50 and x+#s-1<=160,'GPU bounds '..x..','..y)
  frame[y]=(frame[y] or string.rep(' ',160)):sub(1,x-1)..s..(frame[y] or string.rep(' ',160)):sub(x+#s)
  for i=x,x+#s-1 do foreground[y][i]=fg;background[y][i]=bg end
end
local function snapshot(name)
  local rows,front,back={},{},{}
  for y=1,50 do
    rows[y]=string.format('%q',frame[y] or string.rep(' ',160))
    front[y]='['..table.concat(foreground[y],',')..']';back[y]='['..table.concat(background[y],',')..']'
  end
  print('SNAPSHOT '..name..' {"rows":['..table.concat(rows,',')..'],"foreground":['..table.concat(front,',')..'],"background":['..table.concat(back,',')..']}')
end
local methodsAsTables=false
local comp={gpu=gpu,list=function(kind)
  local list={me_interface={'direct'},me_interface_terminal={'terminal'},data={'data'}}
  local a=list[kind] or {};local i=0
  return function() i=i+1;if a[i] then return a[i],kind end end
end,proxy=function(addr)
  if not methodsAsTables then return proxies[addr] end
  local r={address=addr};for k,v in pairs(proxies[addr]) do
    if type(v)=='function' then r[k]=setmetatable({},{__call=function(_,...) return v(...) end}) else r[k]=v end
  end;return r
end}
package.preload.component=function() return comp end
package.preload.event=function() return {pull=function(timeout)
  if timeout and timeout<1 then
    sleeps=sleeps+1;now=now+timeout;energy=math.max(0,math.min(capacity,energy+recharge*timeout))
    if waitEvent then local e=waitEvent;waitEvent=nil;return table.unpack(e) end
    return
  end
  controlDown=false;local e=table.remove(events,1);assert(e,'test event queue empty')
  if type(e)=='function' then return e() end;return table.unpack(e)
end} end
package.preload.computer=function() return {freeMemory=function() return 1900000 end,uptime=function() return now end,
  energy=function() return energy end,maxEnergy=function() return capacity end} end
package.preload.filesystem=function() return {
  exists=function(p) return files[p]~=nil end,size=function(p) return #(files[p] or '') end,
  remove=function(p) files[p]=nil;return true end,
  rename=function(a,b) files[b],files[a]=files[a],nil;return true end} end
package.preload.serialization=function() return {serialize=ser,unserialize=unser} end
package.preload.unicode=function() return {len=string.len,wlen=string.len,sub=string.sub,char=string.char} end
package.preload.term=function() return {clear=function() end,setCursor=function() end} end
package.preload.keyboard=function() return {isControlDown=function() return controlDown end} end
local origOpen=io.open
local failDisk=false
io.open=function(path,mode)
  if path:sub(1,6)~='/home/' then return origOpen(path,mode) end
  if mode=='r' and not files[path] then return nil end
  local content=(mode=='r' or mode=='a') and (files[path] or '') or ''
  return {read=function() return content end,write=function(self,s) content=content..s;return self end,
    flush=function(self) if failDisk then return nil,'disk full' end;files[path]=content;return self end,
    close=function() files[path]=content end}
end
local api=assert(loadfile(artifact))('--test')
local cfg
local function reset()
  files={};interfaces={};mutations=0;history={};fail=nil;failDisk=false;wrongDirect=nil;methodsAsTables=false
  now,energy,capacity,recharge,sleeps=123,10000,10000,0,0;waitEvent,dataCalls,dataCost=nil,0,0
  powerDropAt,gpuFills=nil,0
  cfg=cp(api.defaults)
  target=iface(cfg.target,1,{[0]=pattern({item('Samarium Rod',1,5),item(),item(),item()})})
  buffer=iface(cfg.buffer,2,{[0]=pattern({item('Junk',3,9),item('Other',2,8),item('Third',1,7)},
    {item('Junk Out',5,6),item('Other Out',7,5)})})
  buffer.patterns[1]=cp(buffer.patterns[0])
  dest1=iface('Rename NAME_1',3);dest2=iface('Rename NAME_2',4)
end
local tests=0
local function test(name,f)
  reset();local ok,err=pcall(f);if not ok then error(name..': '..tostring(err),0) end
  tests=tests+1;print('PASS '..name)
end
local function mustFail(f,match)
  local ok,err=pcall(f);assert(not ok,'expected failure');assert(tostring(err):find(match,1,true),tostring(err))
end
test('read-only preview and per-pattern numbering',function()
  target.patterns[4]=cp(target.patterns[0]);local p=api.scan(cfg)
  assert(mutations==0);assert(#p.changes==2 and #p.recipes==2)
  assert(p.changes[1].edits[1].after.label=='NAME_1')
  assert(p.changes[1].edits[2].after.label=='NAME_2')
  assert(p.changes[2].edits[1].after.label=='NAME_1')
end)
test('full apply preserves first input, counts, outputs, flags and slots',function()
  target.patterns[4]=cp(target.patterns[0]);local before=cp(target.patterns[0]);local p=api.scan(cfg)
  api.apply(cfg,p)
  assert(target.patterns[0] and target.patterns[4]);assert(not buffer.patterns[0] and not buffer.patterns[1])
  local t=target.patterns[0]
  assert(ser(t.inputs[2])==ser(before.inputs[2]));assert(t.inputs[3].label=='NAME_1')
  assert(t.inputs[4].label=='NAME_2' and t.inputs[4].size==128)
  assert(ser(t.outputs)==ser(before.outputs));assert(unser(t.tag).__value.preserved.__value==42)
  assert(dest1.patterns[0].lengths.inputs==1 and dest1.patterns[0].lengths.outputs==1)
  assert(dest1.patterns[0].inputs[1].size==128 and dest1.patterns[0].outputs[1].size==128)
  assert(not files[api.paths.pending]);assert(files[api.paths.backup]);assert(#api.scan(cfg).changes==0)
end)
test('sparse input and pattern slots retained',function()
  target.patterns={[8]=pattern({[2]=item(),[5]=item(),[9]=item()})}
  local p=api.scan(cfg);assert(p.changes[1].edits[1].index==5);api.apply(cfg,p)
  assert(target.patterns[8].inputs[5].label=='NAME_1');assert(not target.patterns[8].inputs[1])
end)
test('matching recipes reused; different ratio rejected',function()
  local p=api.scan(cfg);local r=p.recipes[1]
  local a,b=cp(r.input),cp(r.output);a.size=64;b.size=64
  dest1.patterns[0]=pattern({a},{b});p=api.scan(cfg);assert(p.newRecipes==1)
  dest1.patterns[0].outputs[1].size=63;refresh(dest1.patterns[0]);assert(api.scan(cfg).newRecipes==2)
end)
test('different NBT or damage is not a duplicate',function()
  target.patterns[0]=pattern({item(nil,128,123),item(nil,128,124),item(nil,128,123,{special=typed('int',4)})})
  assert(#api.scan(cfg).changes==0)
end)
test('custom NBT survives name editing',function()
  local s=item(nil,128,123,{special=typed('long','9007199254740000'),display=compound({Lore=typed('list',{typed('string','hello')})})})
  target.patterns[0]=pattern({s,s})
  local p=api.scan(cfg);local n=unser(p.changes[1].edits[1].after.tag).__value
  assert(n.special.__value=='9007199254740000' and n.display.__value.Lore.__value[1].__value=='hello')
  api.apply(cfg,p)
end)
test('upstream typed-string loss is reproduced; raw strings survive',function()
  local card=proxies.data
  local bad=card.decodeNBT(card.encodeNBT(compound({Name=typed('string','NAME_1')})))
  assert(bad.__value.Name==nil,'mock must reproduce the server encoder bug')
  local good=card.decodeNBT(card.encodeNBT(compound({Name='NAME_1'})))
  assert(good.__value.Name.__value=='NAME_1')
end)
test('renaming preserves every nested NBT string and numeric type',function()
  local fields={id=typed('string','old-id'),display=compound({Name=typed('string','Old Name'),
    Lore=typed('list',{typed('string','line one'),typed('string','line two')})}),
    nested=typed('list',{compound({text=typed('string','deep'),flag=typed('byte',1)})}),
    shorts=typed('short',12),ints=typed('int',128),floats=typed('float',1.5),bytes=typed('byte_array',{0,-1,127})}
  local s=item('Old Name',128,123,fields);target.patterns[0]=pattern({s,s})
  local p=api.scan(cfg);local got=unser(p.changes[1].edits[1].after.tag).__value
  local wanted=cp(fields);wanted.display.__value.Name=typed('string','NAME_1')
  assert(ser(got)==ser(wanted));api.apply(cfg,p)
end)
test('round-trip check still rejects actual loss before mutations',function()
  local old=proxies.data.encodeNBT
  proxies.data.encodeNBT=function(t)
    local encoded=unser(old(t));encoded.__value.display=nil;return ser(encoded)
  end
  local ok,err=pcall(function() mustFail(function() api.scan(cfg) end,'NBT encode round trip failed');assert(mutations==0) end)
  proxies.data.encodeNBT=old
  assert(ok,err)
end)
test('missing destinations block all changes',function()
  dest1.name='unrelated';local p=api.scan(cfg);assert(#p.errors>0)
  mustFail(function() api.apply(cfg,p) end,'blockers');assert(mutations==0)
end)
test('full destination and insufficient donors are preview blockers',function()
  for i=0,8 do dest1.patterns[i]=pattern({item('x',1,800)}) end
  buffer.patterns={};local p=api.scan(cfg);assert(#p.errors>=3 and mutations==0)
end)
test('multiple rename interfaces with same name allocate deterministically',function()
  for i=0,8 do dest1.patterns[i]=pattern({item('x',1,800)}) end
  iface(dest1.name,5);local p=api.scan(cfg);assert(p.recipes[1].destination.location.x==5)
end)
test('changed preview rejected before any writes',function()
  local p=api.scan(cfg);target.patterns[0].inputs[2].size=64;refresh(target.patterns[0])
  mustFail(function() api.apply(cfg,p) end,'changed since preview');assert(mutations==0)
end)
test('hidden NBT rejected',function()
  target.patterns[0].tag=nil;mustFail(function() api.scan(cfg) end,'NBT');assert(mutations==0)
end)
test('crafting donors and crafting targets skipped',function()
  buffer.patterns[0].isCraftable=true;buffer.patterns[1].isCraftable=true
  target.patterns[2]=pattern({item(),item()},nil,true)
  local p=api.scan(cfg);assert(p.skipped==1 and #p.errors==2)
end)
test('multipart buffer side argument and callable proxy methods',function()
  buffer.side=3;methodsAsTables=true;local p=api.scan(cfg);api.apply(cfg,p);assert(#api.scan(cfg).changes==0)
end)
test('direct buffer mismatch cannot mutate',function()
  wrongDirect=iface('wrong',9,{[0]=pattern({item('wrong',5,900)})})
  mustFail(function() api.scan(cfg) end,'does not match');assert(mutations==0)
end)
test('disk full blocks mutation',function()
  local p=api.scan(cfg);failDisk=true;mustFail(function() api.apply(cfg,p) end,'Flush failed');assert(mutations==0)
end)
test('conversion failure after mutation recovers and rescans',function()
  local p=api.scan(cfg);fail={label='set-after'}
  mustFail(function() api.apply(cfg,p) end,'injected');assert(files[api.paths.pending]);assert(not dest1.patterns[0])
  api.recover(cfg);assert(dest1.patterns[0]);assert(not files[api.paths.pending])
  local nextPlan=api.scan(cfg);api.apply(cfg,nextPlan);assert(#api.scan(cfg).changes==0)
end)
test('power loss immediately after transfer is recognized',function()
  local p=api.scan(cfg);fail={label='send-after'}
  mustFail(function() api.apply(cfg,p) end,'injected');assert(files[api.paths.pending]);assert(dest1.patterns[0])
  api.recover(cfg);assert(not files[api.paths.pending])
end)
test('target interruption can finish without shifting inputs',function()
  local p=api.scan(cfg)
  for _,r in ipairs(p.recipes) do byref(r.destination).patterns[r.destination.slot]=pattern({r.input},{r.output}) end
  p=api.scan(cfg);fail={label='set-after'}
  mustFail(function() api.apply(cfg,p) end,'injected');assert(not target.patterns[0])
  api.recover(cfg);assert(target.patterns[0].inputs[4].label=='NAME_2')
end)
test('unrelated concurrent buffer edits stop recovery',function()
  local p=api.scan(cfg);fail={label='set-after'};mustFail(function() api.apply(cfg,p) end,'injected')
  buffer.patterns[0].inputs[2]=item('intruder',1,808);refresh(buffer.patterns[0])
  mustFail(function() api.recover(cfg) end,'Unexpected inputs');assert(files[api.paths.pending])
end)
test('literal NAME template and existing suffix collision',function()
  cfg.itemName='NAME_{n}';local p=api.scan(cfg);assert(p.changes[1].edits[1].after.label=='NAME_1')
  target.patterns[0].inputs[5]=cp(p.changes[1].edits[1].after);target.patterns[0].lengths.inputs=5;refresh(target.patterns[0])
  p=api.scan(cfg);assert(p.changes[1].edits[1].after.label=='NAME_2')
end)
test('fluids and fluid pseudo-items stay untouched',function()
  local fluid={name='molten.iron',size=1000,amount=1000,label='Molten Iron'}
  local drop={name='ae2fc:fluid_drop',damage=0,size=1000,label='Molten Iron'}
  target.patterns[0]=pattern({fluid,fluid,drop,drop});assert(#api.scan(cfg).changes==0)
end)
test('full buffer frees workspace by installing rename patterns first',function()
  for i=2,8 do buffer.patterns[i]=cp(buffer.patterns[0]) end
  local p=api.scan(cfg);assert(#p.empty==0 and #p.errors==0);api.apply(cfg,p)
  assert(target.patterns[0].inputs[3].label=='NAME_1')
end)
test('editable label template and literal punctuation in interface names',function()
  cfg.itemName='{label}_{n}';cfg.renameName='Rename ({label}) [{n}] 100%'
  dest1.name='Rename (Fine Europium Wire) [1] 100%';dest2.name='Rename (Fine Europium Wire) [2] 100%'
  local p=api.scan(cfg);assert(#p.errors==0);assert(p.changes[1].edits[1].after.label=='Fine Europium Wire_1')
  api.apply(cfg,p)
end)
test('UI renders and scans without mutation; clipboard target editing',function()
  events={{'key_down','kbd',115,31},function()
    assert(frame[14]:find('patterns scanned',1,true));assert(mutations==0)
    snapshot('preview')
    return 'touch','screen',25,5,0
  end,function() controlDown=true;return 'key_down','kbd',97,30 end,
  {'clipboard','kbd','New Target'}, {'key_down','kbd',13,28},function()
    assert(files[api.paths.config]:find('New Target',1,true));return 'key_down','kbd',113,16
  end}
  api.runUI();assert(mutations==0)
end)
test('settings draft can be cancelled and rename preview renders',function()
  files[api.paths.config]=ser(cfg)
  events={{'touch','screen',32,7,0},function()
    assert(frame[7]:find('Buffer interface name',1,true));snapshot('settings')
    return 'touch','screen',5,12,0
  end,function() controlDown=true;return 'key_down','kbd',97,30 end,
  {'clipboard','kbd','{label}_{n}'},{'key_down','kbd',13,28},{'touch','screen',24,5,0},
  {'key_down','kbd',115,31},{'touch','screen',23,9,0},function()
    assert(frame[12]:find('CREATE Rename NAME_1',1,true));snapshot('recipes')
    assert(frame[13]:find('128 x NAME_1',1,true));return 'key_down','kbd',113,16
  end}
  api.runUI();assert(mutations==0)
end)
test('click places cursor; Backspace removes one character, not the field',function()
  files[api.paths.config]=ser(cfg)
  events={{'touch','screen',150,5,0},{'key_down','kbd',8,14},{'key_down','kbd',13,28},function()
    assert(unser(files[api.paths.config]).target=='Advanced Assline (1')
    return 'key_down','kbd',113,16
  end}
  api.runUI()
end)
test('click clears Ctrl+A and repositions without saving or dropping edits',function()
  files[api.paths.config]=ser(cfg)
  events={{'touch','screen',22,5,0},{'key_down','kbd',88,45},
  function() controlDown=true;return 'key_down','kbd',97,30 end,
  {'touch','screen',24,5,0},{'key_down','kbd',8,14},{'key_down','kbd',13,28},function()
    assert(unser(files[api.paths.config]).target=='Advanced Assline (1)')
    return 'key_down','kbd',113,16
  end}
  api.runUI()
end)
test('performance log records charge, yields and component calls',function()
  energy=2000;recharge=2000
  api.scan(cfg);api.perfReport('scan complete')
  local log=assert(files['/home/assline-perf.log'])
  assert(log:find('energy=7500/10000',1,true))
  assert(log:find('pauses=1',1,true))
  assert(log:find('event.pull yields=',1,true))
  assert(log:find('getInterfacesByName calls=',1,true))
end)
test('full energy adds no artificial delays and no manual GC is available',function()
  assert(collectgarbage==nil)
  local p=api.scan(cfg);api.apply(cfg,p);assert(sleeps==0)
end)
test('low energy waits to resume threshold before component calls',function()
  energy=2000;recharge=2000;local messages={}
  api.scan(cfg,function(s) messages[#messages+1]=s end)
  assert(energy>=7500 and sleeps>0 and mutations==0)
  assert(table.concat(messages,' '):find('Waiting for energy',1,true))
end)
test('energy drain during apply pauses and continues successfully',function()
  local p=api.scan(cfg);dataCost=1000;recharge=5000
  api.apply(cfg,p)
  assert(sleeps>0 and not files[api.paths.pending]);assert(target.patterns[0].inputs[3].label=='NAME_1')
end)
test('stalled recharge retains active operation for recovery',function()
  local p=api.scan(cfg);powerDropAt='set-after'
  mustFail(function() api.apply(cfg,p) end,'No recharge')
  assert(files[api.paths.pending] and not dest1.patterns[0])
  energy=10000;api.recover(cfg);assert(dest1.patterns[0] and not files[api.paths.pending])
end)
test('Escape cancels low-energy wait without mutation',function()
  energy=2000;waitEvent={'key_down','kbd',27,1}
  mustFail(function() api.scan(cfg) end,'Work cancelled')
  assert(mutations==0 and not files[api.paths.pending])
end)
test('repeated recipes reuse verified NBT conversions within the scan',function()
  api.scan(cfg);local single=dataCalls;dataCalls=0
  for slot=1,8 do target.patterns[slot]=cp(target.patterns[0]) end
  api.scan(cfg);assert(dataCalls==single,'Repeated patterns should not repeat name NBT encoding')
end)
test('idle signals and cursor edits do not repaint the whole screen',function()
  files[api.paths.config]=ser(cfg)
  events={function() assert(gpuFills==1);return 'key_up','kbd',0,0 end,
  function() assert(gpuFills==1);return 'touch','screen',150,5,0 end,
  {'key_down','kbd',8,14},function()
    assert(gpuFills==1);return 'key_down','kbd',0,1
  end,{'key_down','kbd',113,16}}
  api.runUI()
end)
print('SUCCESS: '..tests..' tests ('..artifact..')')
