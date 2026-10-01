package.path='tests/lib/?.lua;'..package.path
-- Contract mocks based on GTNH source, including terminal zero-based slots,
-- part-interface hidden side argument, typed NBT, and list-removing clears.
local artifact=... or 'assline_app.lua'
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
local callCost,callCounts,pollEvents=0,{},{}
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
    for i=1,n do
      local stack=p[which][i]
      if p.newEncoding and stack then
        arr[i]=compound({Cnt=typed('int',p.rawCounts[which][i]),Count=typed('byte',0),
          Craft=typed('byte',0),Damage=typed('int',stack.damage),id=typed('short',7495),
          fieq=typed('byte',0),['Stack Type']='item'})
      elseif stack then
        local fields=cp(stack)
        fields.Count=typed('int',stack.size)
        arr[i]=compound(fields)
      else arr[i]=compound({}) end
    end
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
local function newPattern(inputs,outputs)
  local p=pattern(inputs,outputs)
  p.name='ae2fc:encodedPattern'
  p.newEncoding=true
  p.rawCounts={inputs={},outputs={}}
  for _,which in ipairs({'inputs','outputs'}) do
    for index,s in pairs(p[which]) do
      p.rawCounts[which][index]=s.size
      s.size=0
      s.amount=0
    end
  end
  return refresh(p)
end
local function iface(name,x,patterns,side)
  local t={name=name,location={x=x,y=64,z=0,dimId=0},side=side or 6,patterns=patterns or {}}
  interfaces[#interfaces+1]=t;return t
end
local target,buffer,editor,dest1,dest2,wrongDirect
local function byref(ref)
  for _,v in ipairs(interfaces) do if v.location.x==ref.location.x and v.side==ref.side then return v end end
  error('missing ref')
end
local function iterator(list)
  local index=0
  return setmetatable({getAll=function(include)
    assert(include==false,'Only metadata bulk reads are permitted')
    local r={};for _,i in ipairs(list) do r[#r+1]={name=i.name,location=cp(i.location),side=i.side} end;return r
  end}, {__call=function() index=index+1;return cp(list[index]) end})
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
  local a={...};local b=wrongDirect or editor
  if b.side~=6 then assert(table.remove(a,1)==b.side,'multipart side missing/wrong') end
  local slot=table.remove(a,1);if slot<1 or slot>9 then error('invalid slot') end
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
      assert(tp=='item' or tp=='fluid','must use item or fluid type')
      local value=cp(detail);value.label=tp=='fluid' and 'Molten fluid' or 'Item'
      value.hasTag=value.tag~=nil
      if tp=='fluid' then value.damage=nil;value.amount=value.size end
      if value.tag then local root=unser(value.tag).__value;if root.display and root.display.__value.Name then value.label=root.display.__value.Name.__value end end
      if p.newEncoding then
        p.rawCounts[key][index]=value.size
        value.size=0
        value.amount=0
      end
      p[key][index]=value;p.lengths[key]=math.max(p.lengths[key],index)
    else
      for i=index,p.lengths[key]-1 do p[key][i]=p[key][i+1] end
      p[key][p.lengths[key]]=nil;p.lengths[key]=p.lengths[key]-1
      if p.newEncoding then
        for i=index,p.lengths[key] do p.rawCounts[key][i]=p.rawCounts[key][i+1] end
        p.rawCounts[key][p.lengths[key]+1]=nil
      end
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
  decodeNBT=function(t) dataCharge();return unser(t) end,sha256=function(t) dataCharge();return 'mock-hash:'..t end}
for _,proxy in pairs(proxies) do
  for name,method in pairs(proxy) do
    if type(method)=='function' then
      proxy[name]=function(...)
        callCounts[name]=(callCounts[name] or 0)+1
        local result=table.pack(method(...))
        if proxy~=proxies.data then now=now+callCost end
        return table.unpack(result,1,result.n)
      end
    end
  end
end
local gpu={}
local width,height=160,50
gpu.maxResolution=function() return 160,50 end;gpu.getResolution=function() return width,height end
gpu.setResolution=function(w,h) width,height=w,h;return true end
gpu.getForeground=function() return 0xffffff end;gpu.getBackground=function() return 0 end
gpu.setForeground=function(c) fg=c end;gpu.setBackground=function(c) bg=c end
gpu.fill=function(x,y,w,h,s)
  gpuFills=gpuFills+1
  assert(x>=1 and y>=1 and x+w-1<=width and y+h-1<=height,'GPU fill bounds')
  for row=y,y+h-1 do
    local old=frame[row] or string.rep(' ',160)
    frame[row]=old:sub(1,x-1)..string.rep(s,w)..old:sub(x+w)
    foreground[row]=foreground[row] or {};background[row]=background[row] or {}
    for col=x,x+w-1 do foreground[row][col]=fg;background[row][col]=bg end
  end
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
    local e=table.remove(pollEvents,1)
    if type(e)=='function' then return e() elseif e then return table.unpack(e) end
    return
  end
  controlDown=false;local e=table.remove(events,1);assert(e,'test event queue empty')
  if type(e)=='function' then return e() end;return table.unpack(e)
end} end
package.preload.computer=function() return {freeMemory=function() return 1900000 end,uptime=function() return now end,
  energy=function() return energy end,maxEnergy=function() return capacity end} end
package.preload.filesystem=function() return {
  path=function(p) return p:match('^(.*[/])') or './' end,
  exists=function(p) return files[p]~=nil end,size=function(p) return #(files[p] or '') end,
  remove=function(p) files[p]=nil;return true end,
  rename=function(a,b) files[b],files[a]=files[a],nil;return true end} end
package.preload.serialization=function() return {serialize=ser,unserialize=unser} end
package.preload.unicode=function() return {len=string.len,wlen=string.len,sub=string.sub,char=string.char} end
package.preload.shell=function() return {resolve=function(p) return p end} end
package.preload.process=function() return {info=function() return {path=artifact} end} end
package.preload.term=function() return {clear=function() end,setCursor=function() end} end
package.preload.keyboard=function() return {isControlDown=function() return controlDown end} end
local origOpen=io.open
local failDisk=false
io.open=function(path,mode)
  if path:sub(1,6)~='/home/' then return origOpen(path,mode) end
  if mode=='r' and not files[path] then return nil end
  local content=(mode=='r' or mode=='a') and (files[path] or '') or ''
  local offset=0
  return {seek=function(_,whence,n) assert(whence=='set');offset=n;return n end,
    read=function() return content:sub(offset+1) end,write=function(self,s) content=content..s;return self end,
    flush=function(self) if failDisk then return nil,'disk full' end;files[path]=content;return self end,
    close=function() files[path]=content;return true end}
end
local api=assert(loadfile(artifact))('--test')
local cfg
local function reset()
  files={};interfaces={};mutations=0;history={};fail=nil;failDisk=false;wrongDirect=nil;methodsAsTables=false
  now,energy,capacity,recharge,sleeps=123,10000,10000,0,0;waitEvent,dataCalls,dataCost=nil,0,0
  powerDropAt,gpuFills=nil,0
  callCost,callCounts,pollEvents=0,{},{}
  cfg=cp(api.defaults)
  cfg.batch.mode='fixed'
  editor=iface(cfg.shared.editor,20)
  target=iface(cfg.programs.assline.target,1,{[0]=pattern({item('Samarium Rod',1,5),item(),item(),item()})})
  buffer=iface(cfg.shared.donors,2,{[0]=pattern({item('Junk',3,9),item('Other',2,8),item('Third',1,7)},
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
test('interface reads scale with target dependencies and distinct locations',function()
  cfg.programs.assline.renameName='Rename shared';dest1.name='Rename shared';target.patterns={}
  for slot=0,7 do
    local ingredient=item('Material '..slot,1,100+slot)
    target.patterns[slot]=pattern({ingredient,ingredient})
    buffer.patterns[slot]=cp(buffer.patterns[0])
  end
  local p=api.scan(cfg);assert(#p.recipes==8 and #p.changes==8)
  callCounts={};callCost=0.05
  api.apply(cfg,p)
  assert(callCounts.getInterfacesByLocation<150,callCounts.getInterfacesByLocation)
  assert(callCounts.getInterfacePattern<130,callCounts.getInterfacePattern)
  print('BENCHMARK 8 targets / 8 recipes / shared destination: location reads (remote donors / shared editor): '..callCounts.getInterfacesByLocation..'; direct reads: '..callCounts.getInterfacePattern)
end)

test('full-power UI accepts History and Escape while an intent is active',function()
  files[api.paths.config]=ser(cfg)
  events={{'touch','screen',38,11,0},{'touch','screen',38,47,0},{'touch','screen',118,39,0},function()
    callCost=0.05
    local function pending()
      if (callCounts.setInterfacePatternInput or 0)==0 then pollEvents[1]=pending;return 'key_up','kbd',0,0 end
      pollEvents[1]=function()
        assert(frame[12]:find('RECENT OPERATIONS',1,true),'History did not render during work')
        return 'key_down','kbd',27,1
      end
      return 'touch','screen',5,13,0
    end
    pollEvents={pending};return 'touch','screen',48,47,0
  end,function()
    assert(energy==capacity and files[api.paths.pending])
    assert(frame[49]:find('Work cancelled',1,true))
    return 'key_down','kbd',113,16
  end}
  api.runUI();callCost=0;api.recover(cfg)
  assert(dest1.patterns[0] and not files[api.paths.pending])
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

test('padded processing donors leave empty NBT cells without clearing them',function()
  for slot=0,1 do
    buffer.patterns[slot].lengths={inputs=64,outputs=32};refresh(buffer.patterns[slot])
  end
  local p=api.scan(cfg);callCounts={};api.apply(cfg,p)
  assert(callCounts.setInterfacePatternInput==8,callCounts.setInterfacePatternInput)
  assert(callCounts.setInterfacePatternOutput==4,callCounts.setInterfacePatternOutput)
  assert(dest1.patterns[0].lengths.inputs==62 and dest1.patterns[0].lengths.outputs==31)
  assert(not dest1.patterns[0].inputs[2] and not dest1.patterns[0].outputs[2])
  -- Padded recipes must remain eligible for reuse in subsequent scans.
  target.patterns[0]=pattern({item(),item(),item()})
  local nextPlan=api.scan(cfg);assert(nextPlan.newRecipes==0)
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
test('full destination blocks; insufficient donors only warn',function()
  for i=0,35 do dest1.patterns[i]=pattern({item('x',1,800)}) end
  buffer.patterns={};local p=api.scan(cfg);assert(#p.errors>0 and #p.warnings==1 and mutations==0)
end)
test('multiple rename interfaces with same name allocate deterministically',function()
  for i=0,35 do dest1.patterns[i]=pattern({item('x',1,800)}) end
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
  local p=api.scan(cfg);assert(p.skipped==1 and #p.errors==0 and #p.warnings==1)
end)
test('multipart buffer side argument and callable proxy methods',function()
  editor.side=3;methodsAsTables=true;local p=api.scan(cfg);api.apply(cfg,p);assert(#api.scan(cfg).changes==0)
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
  mustFail(function() api.apply(cfg,p) end,'injected');assert(files[api.paths.pending]);assert(editor.patterns[0])
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
  editor.patterns[0].inputs[2]=item('intruder',1,808);refresh(editor.patterns[0])
  mustFail(function() api.recover(cfg) end,'Unexpected inputs');assert(files[api.paths.pending])
end)
test('literal NAME template and existing suffix collision',function()
  cfg.programs.assline.itemName='NAME_{n}';local p=api.scan(cfg);assert(p.changes[1].edits[1].after.label=='NAME_1')
  target.patterns[0].inputs[5]=cp(p.changes[1].edits[1].after);target.patterns[0].lengths.inputs=5;refresh(target.patterns[0])
  p=api.scan(cfg);assert(p.changes[1].edits[1].after.label=='NAME_2')
end)
test('fluids and fluid pseudo-items stay untouched',function()
  local fluid={name='molten.iron',size=1000,amount=1000,label='Molten Iron'}
  local drop={name='ae2fc:fluid_drop',damage=0,size=1000,label='Molten Iron'}
  target.patterns[0]=pattern({fluid,fluid,drop,drop});assert(#api.scan(cfg).changes==0)
end)
test('a full pattern editor blocks editing even when remote donors are available',function()
  for slot=0,8 do editor.patterns[slot]=cp(buffer.patterns[0]) end
  local p=api.scan(cfg)
  assert(#p.empty==0 and #p.errors>0)
  mustFail(function() api.apply(cfg,p) end,'blockers');assert(mutations==0)
end)

test('editable label template and literal punctuation in interface names',function()
  cfg.programs.assline.itemName='{label}_{n}';cfg.programs.assline.renameName='Rename ({label}) [{n}] 100%'
  dest1.name='Rename (Fine Europium Wire) [1] 100%';dest2.name='Rename (Fine Europium Wire) [2] 100%'
  local p=api.scan(cfg);assert(#p.errors==0);assert(p.changes[1].edits[1].after.label=='Fine Europium Wire_1')
  api.apply(cfg,p)
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
local maker=api.maker
local function manifestFor(p)
  local r={kind=p.isCraftable and 'crafting' or 'processing',inputs={},outputs={},destination=cfg.programs.assline.target,label='Test recipe'}
  for _,which in ipairs({'inputs','outputs'}) do
    for k,v in pairs(p[which]) do r[which][k]={type='item',name=v.name,damage=v.damage,size=v.size,tag=v.tag} end
  end
  return {version=1,source={recipeVersion='2.9.0-beta-2',targetVersion='2.9.0-beta-3'},
    recipes={r}}
end
test('maker adapter discovers named banks without needing a local buffer',function()
  local wanted=pattern({item('Input',2,555)},{item('Output',1,666)})
  target.patterns={};iface('Editor',8);iface(cfg.shared.donors,9,{[0]=pattern({item('Other',1,556)})})
  local prof=manifestFor(wanted);local before=ser(interfaces)
  local p,s,r,labels=maker.scan(cfg,prof,{destination=cfg.programs.assline.target,donors=cfg.shared.donors,workspace=cfg.shared.editor})
  assert(#p.errors==0 and p.available.processing==3 and #p.creates==1 and #s.interfaces==4)
  assert(ser(interfaces)==before and mutations==0);assert(maker.planner.revalidate(r,s,p))
  local report=maker.report(p,prof,labels);assert(not report:find('VERSION MISMATCH',1,true));assert(report:find('slot 0',1,true))
end)
test('maker adapter reuses exact recipes and preserves substitutions as distinct',function()
  target.patterns={[0]=pattern({item('Input',2,555)},{item('Output',1,666)})}
  local prof=manifestFor(target.patterns[0]);local p=maker.scan(cfg,prof,{destination=cfg.programs.assline.target,donors=cfg.shared.donors,workspace=cfg.shared.editor});assert(p.reused==1 and #p.errors==0)
  local root=unser(target.patterns[0].tag);root.__value.substitute=typed('byte',1);target.patterns[0].tag=ser(root)
  p=maker.scan(cfg,prof,{destination=cfg.programs.assline.target,donors=cfg.shared.donors,workspace=cfg.shared.editor});assert(p.reused==0 and #p.preserved==1 and #p.errors==0)
end)
test('maker uses only crafting donors for crafting recipes',function()
  local wanted=pattern({item('One',1,555),item('Two',1,555)},{item('Bundled',1,666)},true)
  target.patterns={};iface('Editor',8);local prof=manifestFor(wanted)
  local p=maker.scan(cfg,prof,{destination=cfg.programs.assline.target,donors=cfg.shared.donors,workspace=cfg.shared.editor});assert(#p.errors==0 and #p.warnings==1 and p.required.crafting==1)
  buffer.patterns[8]=pattern({item('Craft ingredient',1,700)},{item('Craft output',1,701)},true)
  p=maker.scan(cfg,prof,{destination=cfg.programs.assline.target,donors=cfg.shared.donors,workspace=cfg.shared.editor});assert(#p.errors==0 and p.available.crafting==1 and #p.warnings==0 and mutations==0)
end)
test('maker stops on hidden ingredient NBT instead of treating it as ordinary',function()
  local prof=manifestFor(pattern({item('Input',1,555)},{item('Output',1,666)}))
  target.patterns[0].inputs[1].hasTag=true;target.patterns[0].inputs[1].tag=nil
  mustFail(function() maker.scan(cfg,prof,{destination=cfg.programs.assline.target,donors=cfg.shared.donors,workspace=cfg.shared.editor}) end,'Ingredient NBT hidden');assert(mutations==0)
end)
test('maker scan binds stale check to source version and policy',function()
  local wanted=pattern({item('Input',2,555)},{item('Output',1,666)})
  target.patterns={};iface('Editor',8);local prof=manifestFor(wanted)
  local p,s,r=maker.scan(cfg,prof,{destination=cfg.programs.assline.target,donors=cfg.shared.donors,workspace=cfg.shared.editor});r.source.recipeVersion='other'
  mustFail(function() maker.planner.revalidate(r,s,p) end,'changed')
end)
test('real wiremill preview routes 1x wire and fine wire separately without writes',function()
  cfg.programs.wiremill.wire1=cfg.programs.assline.target;cfg.programs.wiremill.wireFine='Fine wires'
  iface('Fine wires',12)
  local p,report,manifest=maker.preview(cfg,'wiremill')
  assert(#p.errors>0 and #p.layout>0 and mutations==0)
  assert(report:find('Insufficient capacity',1,true) and not report:find('VERSION MISMATCH',1,true))
  for _,r in ipairs(manifest.recipes) do assert(r.outputForm=='wire1' or r.outputForm=='wireFine') end
  assert(#p.capacities==2)
end)

test('old settings migrate once into shared and per-program sections without slot limits',function()
  local c=api.config.migrate({target='My assline',buffer='Old editor',makerWorkspace='Chosen editor',
    makerDonors='Remote banks',makerMode='coating',makerDestination='Insulator',makerPVC='off',makerPPS='on',
    bufferSlots='9',renameSlots='36',terminalAddress='terminal-prefix'})
  assert(c.version==2 and c.shared.editor=='Chosen editor' and c.shared.donors=='Remote banks')
  assert(c.programs.assline.target=='My assline' and c.programs.insulator.destination=='Insulator')
  assert(c.programs.insulator.polymer=='none' and c.shared.terminalAddress=='terminal-prefix')
  assert(c.bufferSlots==nil and c.renameSlots==nil and ser(api.config.migrate(c))==ser(c))
end)

test('assembly line uses every remote donor bank and never requires a direct donor component',function()
  buffer.patterns={}
  iface(cfg.shared.donors,30,{[35]=pattern({item('Donor A',1,800)})})
  iface(cfg.shared.donors,31,{[100]=pattern({item('Donor B',1,801)})})
  local p=api.scan(cfg);assert(p.available==2 and #p.errors==0)
  assert(p.available==2)
  api.apply(cfg,p);assert(#api.scan(cfg).changes==0 and next(editor.patterns)==nil)
end)

local function click(label,row)
  return function()
    for y=row or 1,row or 50 do
      local x=frame[y] and frame[y]:find(label,1,true)
      if x then return 'touch','screen',x,y,0 end
    end
    error('Visible control missing: '..label)
  end
end
local function nav(label)
  return function()
    for y=7,46 do
      local x=frame[y] and frame[y]:sub(1,29):find(label,1,true)
      if x then return 'touch','screen',x,y,0 end
    end
    error('Navigation missing: '..label)
  end
end
local function field(label)
  return function()
    for y=10,40 do
      if frame[y] and frame[y]:sub(34):find(label,1,true) then return 'touch','screen',34,y+1,0 end
    end
    error('Settings field missing: '..label)
  end
end
local function replace(label,value)
  return {field(label),function() controlDown=true;return 'key_down','kbd',97,30 end,
    {'clipboard','kbd',value},{'key_down','kbd',13,28}}
end
local function queue(...)
  events={}
  for _,step in ipairs({...}) do
    if type(step)=='table' and type(step[1])~='string' then for _,e in ipairs(step) do events[#events+1]=e end
    else events[#events+1]=step end
  end
end
local function quit() return 'key_down','kbd',113,16 end

test('program selection is explicit and all operation controls are on the bottom row',function()
  files[api.paths.config]=ser(cfg)
  queue(function()
    assert(frame[47]:find('[ Quit ]',1,true) and frame[47]:find('[ Recover ]',1,true))
    assert(not frame[7]:find('[ Scan ]',1,true));snapshot('programs')
    return 'touch','screen',38,17,0
  end,function()
    assert(mutations==0 and not callCounts.getInterfacesByName)
    assert(frame[17]:find('* Wire insulator',1,true));return quit()
  end)
  api.runUI()
end)

test('shared names survive navigation, quit and a fresh UI invocation',function()
  files[api.paths.config]=ser(cfg)
  queue(nav('Settings'),replace('Pattern editor interface','My editor'),replace('New pattern buffer name','My banks'),
    nav('Programs'),nav('Settings'),function()
      local c=unser(files[api.paths.config]);assert(c.shared.editor=='My editor' and c.shared.donors=='My banks')
      assert(frame[12]:find('My editor',1,true) and frame[16]:find('My banks',1,true));snapshot('settings');return quit()
    end)
  api.runUI()
  queue(nav('Settings'),function()
    assert(frame[12]:find('My editor',1,true) and frame[16]:find('My banks',1,true));return quit()
  end)
  api.runUI();assert(mutations==0)
end)

test('leaving an active field saves it and program settings do not overwrite shared settings',function()
  files[api.paths.config]=ser(cfg)
  queue(nav('Settings'),field('New pattern buffer name'),function() controlDown=true;return 'key_down','kbd',97,30 end,
    {'clipboard','kbd','Uncommitted banks'},nav('Wire insulator'),replace('Insulator interface name','Latex destinations'),
    click('[ Nothing ]',16),nav('Wiremill'),replace('1x wire interface name','1x wires'),replace('Fine wire interface name','Fine wires'),
    nav('Wire insulator'),function()
      local c=unser(files[api.paths.config])
      assert(c.shared.donors=='Uncommitted banks' and c.programs.insulator.destination=='Latex destinations')
      assert(c.programs.insulator.polymer=='none' and c.programs.insulator.pps=='on')
      assert(c.programs.wiremill.wire1=='1x wires' and c.programs.wiremill.wireFine=='Fine wires')
      assert(c.programs.assline.target==cfg.programs.assline.target);snapshot('insulator_settings');return quit()
    end)
  api.runUI();assert(mutations==0)
end)

test('assembly line preview requires explicit capacity verification before execution',function()
  files[api.paths.config]=ser(cfg)
  queue(click('[ Assembly line renamer ]'),click('[ Preview selected ]',47),function()
    assert(frame[14]:find('patterns scanned',1,true));snapshot('preview')
    assert(mutations==0);return 'touch','screen',48,47,0
  end,function() assert(mutations==0);return 'touch','screen',118,39,0 end,
    click('[ Rename recipes ]',9),function()
      assert(frame[12]:find('CREATE Rename NAME_1',1,true));snapshot('recipes')
      return 'touch','screen',48,47,0
    end,function()
      assert(target.patterns[0].inputs[3].label=='NAME_1' and not files[api.paths.pending])
      return quit()
    end)
  api.runUI()
end)

test('Esc cancels only an active edit and cursor repositioning does not discard saved fields',function()
  files[api.paths.config]=ser(cfg)
  queue(nav('Settings'),replace('New pattern buffer name','Saved banks'),field('Pattern editor interface'),
    {'key_down','kbd',88,45},function() controlDown=true;return 'key_down','kbd',97,30 end,
    {'touch','screen',36,12,0},{'key_down','kbd',8,14},{'key_down','kbd',27,1},nav('Programs'),function()
      local c=unser(files[api.paths.config]);assert(c.shared.donors=='Saved banks' and c.shared.editor==cfg.shared.editor)
      return quit()
    end)
  api.runUI()
end)

test('idle events and edits do not repaint the whole settings page',function()
  files[api.paths.config]=ser(cfg);local fills
  queue(nav('Settings'),function() fills=gpuFills;return 'key_up','kbd',0,0 end,
    function() assert(gpuFills==fills);return 'touch','screen',150,12,0 end,{'key_down','kbd',8,14},function()
      assert(gpuFills==fills);return 'key_down','kbd',27,1
    end,quit)
  api.runUI()
end)

test('history remains a separate page and lists operations newest first',function()
  files[api.paths.config]=ser(cfg)
  files['/home/assline-perf.log']='\nuptime=1 scan complete\nold report\n\nuptime=2 apply complete\nnew report\n'
  queue(nav('History'),function()
    assert(frame[12]:find('RECENT OPERATIONS',1,true) and frame[15]:find('uptime=2 apply complete',1,true))
    assert(frame[18]:find('uptime=1 scan complete',1,true));snapshot('history');return quit()
  end)
  api.runUI();assert(mutations==0)
end)

test('preview errors are visible and screen state is restored on quit',function()
  files[api.paths.config]=ser(cfg);target.name='gone';width,height=80,25
  queue(click('[ Assembly line renamer ]'),click('[ Preview selected ]',47),function()
    assert(frame[49]:find('Expected one interface',1,true));return 'interrupted'
  end)
  api.runUI();assert(width==80 and height==25);width,height=160,50
end)

local function matrixFixture()
  return {version=2,source={recipeVersion='test',targetVersion='test'},capabilities={{ingot=true,wire1=true,wireFine=true,cable1=true}},
    production={{ingot_wire=true,ingot_wireFine=true}},families={gt={ingot={name='gregtech:gt.metaitem.01',prefix=11000},
      wireFine={name='gregtech:gt.metaitem.02',prefix=19000}}},items={{name='gregtech:pvc',damage=0,option='pvc'}},
    materials={{name='A',family='gt',dsf=1,a=1,p=1,coating='standard',conductor={name='gregtech:gt.blockmachines',base=100}},
      {name='B',family='gt',dsf=2,a=1,p=1,coating='standard',conductor={name='gregtech:gt.blockmachines',base=200}}},
    rules={{id='coat',mode='coating',coating='standard',requires={'wire1','cable1'},
        inputs={{f='wire1',n=1},{i=1,n=2}},outputs={{f='cable1',n=1}},stock={}},
      {id='wire',mode='wiremill',process='ingot_wire',requires={'ingot','wire1'},inputs={{f='ingot',n=1}},outputs={{f='wire1',n=2}},stock={}},
      {id='fine',mode='wiremill',process='ingot_wireFine',requires={'ingot','wireFine'},inputs={{f='ingot',n=1}},outputs={{f='wireFine',n=8}},stock={}}}}
end
local function withMatrix(f)
  local saved=package.loaded.assline_data;package.loaded.assline_data=matrixFixture()
  local ok,why=pcall(f);package.loaded.assline_data=saved;assert(ok,why)
end
local function insulator()
  cfg.programs.insulator.destination=cfg.programs.assline.target;target.patterns={}
  return api.runner.preview(cfg,'insulator')
end

test('Fluid Shaper requests molten fluid, keeps molds stocked, and reuses its patterns',function()
  withMatrix(function()
    local data=package.loaded.assline_data
    data.capabilities[1].plate=true;data.capabilities[1].turbineBlade=true
    data.production[1].molten_plate=true
    data.production[1].molten_turbineBlade=true
    data.families.gt.plate={name='gregtech:gt.metaitem.01',prefix=17000}
    data.families.gt.turbineBlade={name='gregtech:gt.metaitem.02',prefix=16000}
    data.items[2]={name='gregtech:gt.metaitem.01',damage=32301,label='Mold (Plate)'}
    data.items[3]={name='gregtech:gt.metaitem.01',damage=32325,label='Mold (Turbine Blade)'}
    for _,material in ipairs(data.materials) do material.molten='molten.'..material.name:lower() end
    data.rules[#data.rules+1]={id='molten_plate',mode='solidifier',process='molten_plate',
      requires={'plate'},inputs={{fluid='material',n=144}},outputs={{f='plate',n=1}},stock={{i=2,n=1}}}
    data.rules[#data.rules+1]={id='molten_blade',mode='solidifier',process='molten_turbineBlade',
      requires={'turbineBlade'},inputs={{fluid='material',n=864}},outputs={{f='turbineBlade',n=1}},stock={{i=3,n=1}}}
    local settings=cfg.programs.fluidShaper
    settings.plate=cfg.programs.assline.target;settings.turbineBlade='Blades'
    settings.multiplier='2'
    target.patterns={};local blades=iface('Blades',70)
    buffer.patterns[2]=cp(buffer.patterns[0]);buffer.patterns[3]=cp(buffer.patterns[0])
    local preview=api.runner.preview(cfg,'fluidShaper')
    assert(#preview.plan.errors==0 and #preview.manifest.recipes==4)
    assert(preview.report:find('288 mB Molten A',1,true))
    for _,recipe in ipairs(preview.manifest.recipes) do
      assert(#recipe.inputs==1 and recipe.inputs[1].type=='fluid')
      assert(#recipe.stock==1 and recipe.stock[1].label:find('Mold',1,true))
    end
    api.runner.execute(cfg,preview)
    assert(target.patterns[0].inputs[1].name=='molten.a')
    assert(target.patterns[0].inputs[1].damage==nil)
    assert(target.patterns[0].inputs[1].size==288)
    assert(blades.patterns[0].inputs[1].size==1728)
    local again=api.runner.preview(cfg,'fluidShaper')
    assert(again.plan.reused==4 and #again.plan.creates==0)
  end)
end)

test('Fluid Shaper routes fluid and item pipes through their shared mold interface',function()
  withMatrix(function()
    local data=package.loaded.assline_data
    local forms={'pipeFluidTiny','pipeItemTiny'}
    for _,form in ipairs(forms) do
      data.capabilities[1][form]=true
      data.production[1]['molten_'..form]=true
    end
    data.items[2]={name='gregtech:gt.metaitem.01',damage=32326,label='Mold (Tiny Pipe)'}
    for n,material in ipairs(data.materials) do
      material.molten='molten.'..material.name:lower()
      material.overrides={
        pipeFluidTiny={name='gregtech:gt.blockmachines',damage=500+n},
        pipeItemTiny={name='gregtech:gt.blockmachines',damage=600+n},
      }
    end
    for _,form in ipairs(forms) do
      data.rules[#data.rules+1]={id='molten_'..form,mode='solidifier',
        process='molten_'..form,requires={form},inputs={{fluid='material',n=72}},
        outputs={{f=form,n=1}},stock={{i=2,n=1}}}
    end
    local setting=cfg.programs.fluidShaper
    setting.forms='pipeTiny';setting.pipeTiny='Tiny Pipes'
    local pipes=iface('Tiny Pipes',70)
    local preview=api.runner.preview(cfg,'fluidShaper')
    assert(#preview.plan.errors==0 and #preview.manifest.recipes==4)
    local seen={}
    for _,recipe in ipairs(preview.manifest.recipes) do
      seen[recipe.outputForm]=true
      assert(recipe.stock[1].damage==32326)
    end
    assert(seen.pipeFluidTiny and seen.pipeItemTiny)
    for _,entry in ipairs(preview.plan.layout) do
      assert(entry.destination.location.x==pipes.location.x)
    end
  end)
end)

test('generator starts short, waits between patterns and discovers a newly filled remote bank',function()
  withMatrix(function()
    buffer.patterns[1]=nil
    local preview=insulator()
    assert(#preview.plan.errors==0 and #preview.plan.warnings==1)
    local waits=0
    api.runner.execute(cfg,preview,function(message)
      if message:find('Waiting for processing donors',1,true) then
        waits=waits+1
        assert(target.patterns[0] and not target.patterns[1])
        assert(not files[api.paths.pending] and next(editor.patterns)==nil)
        pollEvents[1]=function()
          iface(cfg.shared.donors,91,{[100]=pattern({item('Refill',1,800)})})
        end
      end
    end)
    assert(waits==1 and sleeps>0 and target.patterns[1])
    assert(api.runner.preview(cfg,'insulator').plan.reused==2)
  end)
end)
test('ordinary processing patterns use ItemStack size even when amount is zero',function()
  local encoded=pattern({item('Red Steel Ingot',2048,11348)},
    {item('Red Steel Plate',512,17348)})
  encoded.inputs[1].amount=0
  encoded.outputs[1].amount=0
  refresh(encoded)
  target.patterns={[0]=encoded}
  local requested=pattern({item('Red Steel Ingot',4,11348)},
    {item('Red Steel Plate',1,17348)})
  local prof=manifestFor(requested)
  local p=maker.scan(cfg,prof,{destination=cfg.programs.assline.target,
    donors=cfg.shared.donors,workspace=cfg.shared.editor})
  assert(p.reused==1 and p.resizeCount==1 and #p.creates==0)
  assert(p.existing[1].status=='RESIZE')
  assert(p.existing[1].inputs:find('2048 x Red Steel Ingot',1,true))
end)
test('new Cnt patterns scan, resize and verify with Count left at zero',function()
  withMatrix(function()
    cfg.programs.insulator.destination=cfg.programs.assline.target
    target.patterns={}
    local first=api.runner.preview(cfg,'insulator')
    local recipe=first.manifest.recipes[1]
    local inputs,outputs={},{}
    for i,s in ipairs(recipe.inputs) do
      inputs[i]=cp(s);inputs[i].size=s.size*4
    end
    for i,s in ipairs(recipe.outputs) do
      outputs[i]=cp(s);outputs[i].size=s.size*4
    end
    target.patterns[0]=newPattern(inputs,outputs)
    local preview=api.runner.preview(cfg,'insulator')
    assert(preview.plan.reused==1 and preview.plan.resizeCount==1)
    assert(preview.plan.existing[1].inputs:find('4 x ',1,true))
    api.runner.execute(cfg,preview)
    local refreshed=api.runner.preview(cfg,'insulator')
    assert(refreshed.plan.reused==2 and refreshed.plan.resizeCount==0)
    local resized
    for _,p in pairs(target.patterns) do
      if p.name=='ae2fc:encodedPattern' then resized=p end
    end
    assert(resized)
    local root=unser(resized.tag).__value
    assert(root['in'].__value[1].__value.Cnt.__value==1)
    assert(root['in'].__value[1].__value.Count.__value==0)
  end)
end)
test('unreadable encoded counts are kept with a reason instead of blocking the scan',function()
  local encoded=pattern({item('Unknown input',1,111)},{item('Output',1,222)})
  encoded.inputs[1].size=0
  refresh(encoded)
  target.patterns={[0]=encoded}
  local requested=pattern({item('Unknown input',1,111)},{item('Output',1,222)})
  local prof=manifestFor(requested)
  local p=maker.scan(cfg,prof,{destination=cfg.programs.assline.target,
    donors=cfg.shared.donors,workspace=cfg.shared.editor})
  assert(p.reused==0 and #p.preserved==1)
  assert(p.existing[1].reason:find('no readable count',1,true))
end)

test('donors can be replaced after preview without replanning destinations',function()
  withMatrix(function()
    buffer.patterns={}
    local preview=insulator()
    assert(#preview.plan.errors==0 and preview.plan.available.processing==0)
    buffer.patterns[5]=pattern({item('New A',1,800)})
    buffer.patterns[9]=pattern({item('New B',1,801)})
    api.runner.execute(cfg,preview)
    assert(target.patterns[0] and target.patterns[1] and next(buffer.patterns)==nil)
  end)
end)

test('Escape while waiting leaves completed patterns installed and no pending operation',function()
  withMatrix(function()
    buffer.patterns[1]=nil
    local preview=insulator()
    mustFail(function()
      api.runner.execute(cfg,preview,function(message)
        if message:find('Waiting for processing donors',1,true) then
          waitEvent={'key_down','kbd',27,1}
        end
      end)
    end,'cancelled')
    assert(target.patterns[0] and not target.patterns[1])
    assert(not files[api.paths.pending] and next(editor.patterns)==nil)
    preview=api.runner.preview(cfg,'insulator')
    assert(preview.plan.reused==1 and #preview.plan.creates==1)
  end)
end)

test('assembly line shares refill waiting and ignores crafting refills',function()
  buffer.patterns={}
  local plan=api.scan(cfg)
  assert(#plan.errors==0 and #plan.warnings==1)
  local waits=0
  api.apply(cfg,plan,function(message)
    if message:find('Waiting for processing donors',1,true) then
      waits=waits+1
      assert(not files[api.paths.pending])
      pollEvents[1]=function()
        if waits==1 then buffer.patterns[8]=pattern({item('Crafting',1,800)},nil,true)
        else buffer.patterns[0]=pattern({item('Processing',1,801)}) end
      end
    end
  end)
  assert(waits==3 and buffer.patterns[8].isCraftable)
  assert(#api.scan(cfg).changes==0 and next(editor.patterns)==nil)
end)

test('destination filled during refill wait is never overwritten',function()
  withMatrix(function()
    buffer.patterns={}
    local preview=insulator()
    mustFail(function()
      api.runner.execute(cfg,preview,function(message)
        if message:find('Waiting for processing donors',1,true) then
          pollEvents[1]=function()
            target.patterns[0]=pattern({item('Concurrent',1,900)})
            buffer.patterns[0]=pattern({item('Refill',1,800)})
          end
        end
      end)
    end,'Destination slot is occupied')
    assert(mutations==0 and target.patterns[0].inputs[1].damage==900)
  end)
end)

test('insulator creates multi-input processing patterns via the shared editor',function()
  withMatrix(function()
    local preview=insulator();assert(#preview.plan.errors==0 and #preview.plan.creates==2 and mutations==0)
    api.runner.execute(cfg,preview)
    assert(target.patterns[0].inputs[2].size==2 and target.patterns[0].outputs[1].damage==106)
    assert(target.patterns[1].outputs[1].damage==206 and next(editor.patterns)==nil)
    assert(not files[api.paths.pending] and not files[api.paths.cursor])
    local nextPreview=api.runner.preview(cfg,'insulator');assert(nextPreview.plan.reused==2 and #nextPreview.plan.creates==0)
  end)
end)

test('wiremill executes into separate wire and fine-wire banks',function()
  withMatrix(function()
    cfg.programs.wiremill.wire1=cfg.programs.assline.target;cfg.programs.wiremill.wireFine='Fine wires';target.patterns={}
    local fine=iface('Fine wires',50)
    buffer.patterns[2]=cp(buffer.patterns[0]);buffer.patterns[3]=cp(buffer.patterns[0])
    local preview=api.runner.preview(cfg,'wiremill');assert(#preview.plan.errors==0 and #preview.plan.capacities==2)
    api.runner.execute(cfg,preview)
    assert(target.patterns[0].outputs[1].damage==100 and target.patterns[0].outputs[1].size==2)
    assert(fine.patterns[0].outputs[1].damage==19001 and fine.patterns[0].outputs[1].size==8)
    assert(target.patterns[1].outputs[1].damage==200 and fine.patterns[1].outputs[1].damage==19002)
  end)
end)

test('sorting existing patterns precedes imprinting and preserves unrelated patterns',function()
  withMatrix(function()
    local preview=insulator();api.runner.execute(cfg,preview)
    target.patterns[0],target.patterns[2]=target.patterns[1],target.patterns[0];target.patterns[1]=pattern({item('Unrelated',1,850)})
    local unrelated=cp(target.patterns[1]);preview=api.runner.preview(cfg,'insulator')
    assert(preview.plan.reused==2 and #preview.plan.moves>0 and #preview.plan.creates==0)
    api.runner.execute(cfg,preview)
    assert(target.patterns[0].outputs[1].damage==106 and target.patterns[1].outputs[1].damage==206)
    assert(ser(target.patterns[2])==ser(unrelated) and next(editor.patterns)==nil)
  end)
end)

test('every interruption point in a sorting cycle recovers and releases the editor',function()
  for interruptedMove=1,3 do
    reset()
    withMatrix(function()
      local preview=insulator();api.runner.execute(cfg,preview)
      target.patterns[0],target.patterns[1]=target.patterns[1],target.patterns[0]
      preview=api.runner.preview(cfg,'insulator');assert(#preview.plan.moves==3)
      local send=proxies.terminal.send;local completed=0
      proxies.terminal.send=function(...)
        local results=table.pack(send(...));completed=completed+1
        if completed==interruptedMove then error('cycle interrupted') end
        return table.unpack(results,1,results.n)
      end
      local ok,why=pcall(function() mustFail(function() api.runner.execute(cfg,preview) end,'cycle interrupted') end)
      proxies.terminal.send=send;assert(ok,why)
      assert(files[api.paths.pending] and files[api.paths.cursor])
      api.recover(cfg)
      assert(target.patterns[0].outputs[1].damage==106 and target.patterns[1].outputs[1].damage==206)
      assert(next(editor.patterns)==nil and not files[api.paths.pending] and not files[api.paths.cursor])
    end)
  end
end)

test('sorting progress write failure recovers without replaying an already delivered move',function()
  withMatrix(function()
    local preview=insulator();api.runner.execute(cfg,preview)
    target.patterns[0],target.patterns[1]=target.patterns[1],target.patterns[0]
    preview=api.runner.preview(cfg,'insulator')
    local send=proxies.terminal.send
    proxies.terminal.send=function(...) local result=table.pack(send(...));failDisk=true;return table.unpack(result,1,result.n) end
    local ok,why=pcall(function() mustFail(function() api.runner.execute(cfg,preview) end,'Flush failed') end)
    proxies.terminal.send=send;failDisk=false;assert(ok,why)
    api.recover(cfg)
    assert(target.patterns[0].outputs[1].damage==106 and target.patterns[1].outputs[1].damage==206)
    assert(next(editor.patterns)==nil and not files[api.paths.pending])
  end)
end)

test('imprint interruption retains a recoverable multi-input recipe',function()
  withMatrix(function()
    local preview=insulator();fail={label='set-after'}
    mustFail(function() api.runner.execute(cfg,preview) end,'injected');assert(files[api.paths.pending])
    api.recover(cfg);assert(target.patterns[0].inputs[2].size==2 and not files[api.paths.pending])
    local nextPreview=api.runner.preview(cfg,'insulator');api.runner.execute(cfg,nextPreview)
    assert(target.patterns[1].outputs[1].damage==206)
  end)
end)

test('generator previews reject changed destinations and settings before writes',function()
  withMatrix(function()
    local preview=insulator();local before=mutations
    target.patterns[10]=pattern({item('Concurrent',1,888)})
    mustFail(function() api.runner.execute(cfg,preview) end,'changed');assert(mutations==before)
    target.patterns[10]=nil;preview=api.runner.preview(cfg,'insulator')
    preview=api.runner.preview(cfg,'insulator');cfg.programs.insulator.polymer='none'
    mustFail(function() api.runner.execute(cfg,preview) end,'Settings changed');assert(mutations==before)
  end)
end)

test('70 recipes require two 36-slot destination interfaces and donor slots need no capacity',function()
  withMatrix(function()
    local data=package.loaded.assline_data;data.materials={}
    for n=1,70 do data.materials[n]={name=string.format('M%03d',n),family='gt',dsf=n,a=1,p=1,coating='standard',
      conductor={name='gregtech:gt.blockmachines',base=n*100}} end
    cfg.programs.insulator.destination=cfg.programs.assline.target;target.patterns={}
    iface(cfg.programs.assline.target,50)
    buffer.patterns={};for n=0,69 do buffer.patterns[n+100]=pattern({item('Donor',1,900)}) end
    local preview=api.runner.preview(cfg,'insulator')
    assert(#preview.plan.errors==0 and #preview.plan.creates==70)
    assert(preview.plan.capacities[1].patterns==70 and preview.plan.capacities[1].interfaces==2)
    assert(preview.plan.layout[37].destination.location.x==50 and preview.plan.layout[37].destination.slot==0)
    assert(preview.report:find('2 interfaces (70 patterns)',1,true) and mutations==0)
    local rows=maker.rows(preview.plan,preview.manifest)
    local banks={}
    for index,row in ipairs(rows) do
      if row[1]:find('+-- Interface',1,true) then banks[#banks+1]=index end
    end
    assert(#banks==2 and rows[banks[2]-1][1]=='')
    assert(rows[banks[2]+1][1]:find('  |  M037',1,true))
  end)
end)

test('Run program chooser and insulator preview share the same settings and execution flow',function()
  withMatrix(function()
    cfg.programs.insulator.destination=cfg.programs.assline.target;target.patterns={};files[api.paths.config]=ser(cfg)
    queue(nav('History'),click('[ Run program ]',47),click('[ Wire insulator ]'),click('[ Preview selected ]',47),function()
      assert(frame[7]:find('Preview - Wire insulator',1,true) and mutations==0);snapshot('insulator_preview')
      return 'touch','screen',118,39,0
    end,click('[ Execute preview ]',47),function()
      assert(target.patterns[0].outputs[1].damage==106 and target.patterns[1].outputs[1].damage==206)
      return quit()
    end)
    api.runUI()
  end)
end)

test('bender imprints ingot routes, stores circuits externally and switches 1x plates off',function()
  withMatrix(function()
    local data=package.loaded.assline_data
    data.capabilities[1].plate=true;data.capabilities[1].plateDouble=true
    data.production[1].ingot_plate=true;data.production[1].ingot_plateDouble=true
    data.families.gt.plate={name='gregtech:gt.metaitem.01',prefix=17000}
    data.families.gt.plateDouble={name='gregtech:gt.metaitem.01',prefix=18000}
    data.items[2]={name='gregtech:gt.integrated_circuit',damage=1,label='Programmed Circuit'}
    data.items[3]={name='gregtech:gt.integrated_circuit',damage=2,label='Programmed Circuit'}
    data.rules[#data.rules+1]={id='bend-1',mode='bender',process='ingot_plate',
      requires={'ingot','plate'},inputs={{f='ingot',n=1}},outputs={{f='plate',n=1}},stock={{i=2,n=1}}}
    data.rules[#data.rules+1]={id='bend-2',mode='bender',process='ingot_plateDouble',
      requires={'ingot','plateDouble'},inputs={{f='ingot',n=2}},outputs={{f='plateDouble',n=1}},stock={{i=3,n=1}}}
    cfg.programs.bender.plate=cfg.programs.assline.target
    cfg.programs.bender.foil='';cfg.programs.bender.forms='plate,plateDouble'
    target.patterns={}
    buffer.patterns[2]=cp(buffer.patterns[0]);buffer.patterns[3]=cp(buffer.patterns[0])
    local preview=api.runner.preview(cfg,'bender')
    assert(#preview.plan.errors==0 and #preview.plan.creates==4 and #preview.manifest.recipes==4)
    assert(preview.manifest.recipes[1].stock[1].damage==1)
    assert(#preview.manifest.recipes[1].inputs==1 and preview.manifest.recipes[1].inputs[1].name=='gregtech:gt.metaitem.01')
    files[api.paths.config]=ser(cfg)
    queue(nav('Programs'),click('[ Bending machine ]'),click('[ Preview selected ]',47),function()
      assert(frame[7]:find('Preview - Bending machine',1,true))
      snapshot('bender_preview')
      return click('[ Details ]',9)()
    end,function()
      assert(table.concat({frame[13] or '',frame[14] or '',frame[15] or ''},' '):find('circuit 1',1,true))
      snapshot('bender_circuits')
      return quit()
    end)
    api.runUI()
    api.runner.execute(cfg,preview)
    assert(target.patterns[0].inputs[1].size==1 and target.patterns[0].outputs[1].damage==17001)
    assert(target.patterns[1].inputs[1].size==2 and target.patterns[1].outputs[1].damage==18001)
    for _,p in pairs(target.patterns) do
      assert(#p.inputs==1 and p.inputs[1].name~='gregtech:gt.integrated_circuit')
    end
    cfg.programs.bender.forms='plateDouble'
    preview=api.runner.preview(cfg,'bender')
    assert(preview.plan.reused==2 and #preview.plan.creates==0 and #preview.plan.preserved==2)
    api.runner.execute(cfg,preview)
    assert(target.patterns[0].outputs[1].damage==18001 and target.patterns[1].outputs[1].damage==18002)
    assert(target.patterns[2].outputs[1].damage==17001 and target.patterns[3].outputs[1].damage==17002)
  end)
end)

test('bender output switches toggle independently and migrate into the unified settings',function()
  local old=cp(cfg);old.programs.bender.forms=nil
  local migrated=api.config.migrate(old)
  assert(migrated.programs.bender.forms:find('plateDouble',1,true))
  old.programs.bender.forms='plate,foil'
  old.programs.bender.plateSource=nil;old.programs.bender.springSmallSource=nil
  migrated=api.config.migrate(old)
  assert(migrated.programs.bender.forms=='plate,foil')
  assert(migrated.programs.bender.plateSource=='ingot' and migrated.programs.bender.springSmallSource=='stick')
  files[api.paths.config]=ser(cfg)
  queue(nav('Settings'),nav('Bending machine'),function()
    assert(frame[24]:find('[ 1x ]',1,true) and frame[24]:find('[ 2x ]',1,true))
    return click('[ 1x ]',24)()
  end,function()
    local c=unser(files[api.paths.config])
    local choices=api.programs.byId.bender.formChoices
    local selected=api.config.selected(c.programs.bender.forms,choices)
    assert(not selected.plate and selected.plateDouble and selected.foil)
    snapshot('bender_switches')
    return quit()
  end)
  api.runUI()
end)

test('Fluid Shaper enables each destination beside its interface field',function()
  local v=cfg.programs.fluidShaper
  v.plate='Plates'
  v.turbineBlade=''
  mustFail(function() api.config.requireProgram(cfg,'fluidShaper') end,
    'Turbine blade interface name')
  files[api.paths.config]=ser(cfg)
  queue(nav('Settings'),nav('Fluid Shaper'),function()
    assert(frame[12]:find('[   ]',1,true) and frame[12]:find('(not configured)',1,true))
    assert(frame[20]:find('[ X ]',1,true) and frame[20]:find('Plates',1,true))
    assert(frame[44]:find('Settings page 1/3',1,true))
    snapshot('fluid_shaper_settings')
    return click('[ Next ]',44)()
  end,function()
    assert(frame[36]:find('[ X ]',1,true) and frame[36]:find('(not configured)',1,true))
    snapshot('fluid_shaper_settings_page_2')
    return click('[ Next ]',44)()
  end,function()
    assert(frame[11]:find('Small pipe interface name',1,true))
    assert(frame[23]:find('Huge pipe interface name',1,true))
    assert(frame[27]:find('Pattern multiplier',1,true))
    return click('[ Previous ]',44)()
  end,function()
    return click('[ X ]',36)()
  end,function()
    local saved=unser(files[api.paths.config])
    assert(saved.programs.fluidShaper.forms=='plate')
    api.config.requireProgram(saved,'fluidShaper')
    assert(frame[36]:find('[   ]',1,true))
    return quit()
  end)
  api.runUI()
end)

test('Fluid Shaper pipe mold uses one switch and destination for both pipe types',function()
  local v=cfg.programs.fluidShaper
  v.forms='pipeTiny'
  mustFail(function() api.config.requireProgram(cfg,'fluidShaper') end,
    'Tiny pipe interface name')
  v.pipeTiny='Tiny Pipes'
  api.config.requireProgram(cfg,'fluidShaper')
  local program=api.programs.byId.fluidShaper
  assert(api.programs.switchKey(program,'pipeFluidTiny')=='pipeTiny')
  assert(api.programs.switchKey(program,'pipeItemTiny')=='pipeTiny')
end)

test('enabled bending outputs require only their own destination name',function()
  cfg.programs.bender.forms='sheetmetal'
  mustFail(function() api.config.requireProgram(cfg,'bender') end,'Sheet metal interface name')
  cfg.programs.bender.sheetMetal='Sheets'
  api.config.requireProgram(cfg,'bender')
  cfg.programs.bender.forms='springSmall'
  mustFail(function() api.config.requireProgram(cfg,'bender') end,'Spring interface name')
end)

test('bender input choices select one scraped route per output and keep fixed inputs',function()
  withMatrix(function()
    local data=package.loaded.assline_data
    local cap=data.capabilities[1]
    for _,form in ipairs({'plate','plateDouble','sheetmetal','springSmall','spring','stick','stickLong'}) do
      cap[form]=true
    end
    local processes=data.production[1]
    for _,process in ipairs({'ingot_plate','ingot_plateDouble','plate_plateDouble',
      'plate_sheetmetal','stick_springSmall_yield2','wire1_springSmall','stickLong_spring'}) do
      processes[process]=true
    end
    for form,prefix in pairs({plate=17000,plateDouble=18000,sheetmetal=30000,
      stick=23000,stickLong=24000,springSmall=33000,spring=34000}) do
      data.families.gt[form]={name='gregtech:gt.metaitem.01',prefix=prefix}
    end
    data.items[2]={name='gregtech:gt.integrated_circuit',damage=1}
    data.items[3]={name='gregtech:gt.integrated_circuit',damage=2}
    data.items[4]={name='gregtech:gt.integrated_circuit',damage=11}
    local function rule(id,source,destination,input,output,circuit)
      data.rules[#data.rules+1]={id=id,mode='bender',process=id,
        requires={source,destination},inputs={{f=source,n=input}},
        outputs={{f=destination,n=output}},stock={{i=circuit,n=1}}}
    end
    rule('ingot_plate','ingot','plate',1,1,2)
    rule('ingot_plateDouble','ingot','plateDouble',2,1,3)
    rule('plate_plateDouble','plate','plateDouble',2,1,3)
    rule('plate_sheetmetal','plate','sheetmetal',2,1,4)
    rule('stick_springSmall_yield2','stick','springSmall',1,2,2)
    rule('wire1_springSmall','wire1','springSmall',1,2,2)
    rule('stickLong_spring','stickLong','spring',1,1,2)
    local v=cfg.programs.bender
    v.plate=cfg.programs.assline.target;v.sheetMetal='Sheets';v.spring='Springs'
    v.forms='plate,plateDouble,sheetmetal,springSmall,spring'
    iface('Sheets',60);iface('Springs',61);target.patterns={}
    local first=api.runner.preview(cfg,'bender')
    assert(#first.plan.errors==0 and #first.manifest.recipes==10)
    for _,r in ipairs(first.manifest.recipes) do
      if r.outputForm=='plateDouble' then assert(r.inputs[1].damage==11000+tonumber(r.material=='A' and 1 or 2)) end
      if r.outputForm=='sheetmetal' then assert(r.inputs[1].damage>=17001 and r.inputs[1].damage<=17002) end
    end
    v.plateSource='plate';v.springSmallSource='wire1'
    local second=api.runner.preview(cfg,'bender')
    assert(#second.plan.errors==0 and #second.manifest.recipes==10)
    for _,r in ipairs(second.manifest.recipes) do
      local source=r.inputs[1].damage
      if r.outputForm=='plate' then assert(source>=11001 and source<=11002) end
      if r.outputForm=='plateDouble' then assert(source>=17001 and source<=17002) end
      if r.outputForm=='springSmall' then assert(r.inputs[1].name=='gregtech:gt.blockmachines') end
      if r.outputForm=='spring' then assert(source>=24001 and source<=24002) end
    end
  end)
end)

test('keypad digits and Enter edit settings without a Save button',function()
  files[api.paths.config]=ser(cfg)
  queue(nav('Settings'),nav('Bending machine'),function()
    assert(not frame[47]:find('Save settings',1,true))
    return field('Pattern multiplier')()
  end,function() controlDown=true;return 'key_down','kbd',97,30 end,
    {'key_down','kbd',0,0x50},{'key_down','kbd',0,0x4C},{'key_down','kbd',0,0x4D},
    {'key_down','kbd',13,0x9C},function()
      assert(unser(files[api.paths.config]).programs.bender.multiplier=='256')
      return quit()
    end)
  api.runUI()
end)

test('wiremill reuses 256 to 512 patterns, sorts and resizes them without disposable donors',function()
  withMatrix(function()
    cfg.programs.wiremill.wire1=cfg.programs.assline.target;cfg.programs.wiremill.wireFine='Fine wires'
    cfg.programs.wiremill.multiplier='256';target.patterns={}
    local fine=iface('Fine wires',50)
    buffer.patterns[2]=cp(buffer.patterns[0]);buffer.patterns[3]=cp(buffer.patterns[0])
    api.runner.execute(cfg,api.runner.preview(cfg,'wiremill'))
    assert(target.patterns[0].inputs[1].size==256 and target.patterns[0].outputs[1].size==512)
    assert(fine.patterns[0].outputs[1].size==2048 and next(buffer.patterns)==nil)
    cfg.programs.wiremill.multiplier='1'
    target.patterns[0],target.patterns[1]=target.patterns[1],target.patterns[0]
    local preview=api.runner.preview(cfg,'wiremill')
    assert(preview.plan.reused==4 and preview.plan.resizeCount==4 and #preview.plan.creates==0)
    assert(#preview.plan.moves==3 and #preview.plan.errors==0 and #preview.plan.warnings==0)
    assert(preview.report:find('RESIZE',1,true) and preview.report:find('1 / 256',1,true))
    files[api.paths.config]=ser(cfg)
    queue(nav('Programs'),click('[ Wiremill ]'),click('[ Preview selected ]',47),function()
      snapshot('maker_resize_preview');return quit()
    end)
    api.runUI()
    api.runner.execute(cfg,preview)
    assert(target.patterns[0].inputs[1].size==1 and target.patterns[0].outputs[1].size==2)
    assert(fine.patterns[0].outputs[1].size==8 and next(buffer.patterns)==nil)
    preview=api.runner.preview(cfg,'wiremill')
    assert(preview.plan.reused==4 and preview.plan.resizeCount==0 and #preview.plan.creates==0)
  end)
end)

test('changing the global tier resizes reused patterns through the common editor',function()
  withMatrix(function()
    local data=package.loaded.assline_data
    data.materials[1].tier='LuV';data.materials[2].tier='IV'
    for _,rule in ipairs(data.rules) do rule.eut=8 end
    cfg.programs.wiremill.wire1=cfg.programs.assline.target
    cfg.programs.wiremill.wireFine='Fine wires'
    target.patterns={};local fine=iface('Fine wires',50)
    buffer.patterns[2]=cp(buffer.patterns[0]);buffer.patterns[3]=cp(buffer.patterns[0])
    api.runner.execute(cfg,api.runner.preview(cfg,'wiremill'))
    cfg.batch.mode='tiered';cfg.batch.voltagePolicy='off'
    local preview=api.runner.preview(cfg,'wiremill')
    assert(preview.plan.reused==4 and preview.plan.resizeCount==4 and #preview.plan.creates==0)
    assert(preview.report:find('Batch 4x',1,true) and preview.report:find('Batch 32x',1,true))
    api.runner.execute(cfg,preview)
    assert(target.patterns[0].inputs[1].size==4 and target.patterns[1].inputs[1].size==32)
    assert(fine.patterns[0].outputs[1].size==32 and next(buffer.patterns)==nil)
    preview=api.runner.preview(cfg,'wiremill')
    cfg.batch.currentTier='ZPM'
    mustFail(function() api.runner.execute(cfg,preview) end,'Settings changed')
    preview=api.runner.preview(cfg,'wiremill')
    assert(preview.plan.resizeCount==4 and #preview.plan.creates==0)
    api.runner.execute(cfg,preview)
    assert(target.patterns[0].inputs[1].size==32 and target.patterns[1].inputs[1].size==64)
    assert(fine.patterns[0].outputs[1].size==256 and next(buffer.patterns)==nil)
  end)
end)

test('insulator resizes all inputs including polymer and PPS to the configured multiplier',function()
  withMatrix(function()
    local data=package.loaded.assline_data
    data.items[2]={name='gregtech:pps',damage=0,option='pps'}
    data.rules[1].inputs[3]={i=2,n=3}
    api.runner.execute(cfg,insulator());buffer.patterns={}
    cfg.programs.insulator.multiplier='7'
    local preview=api.runner.preview(cfg,'insulator')
    assert(preview.plan.reused==2 and preview.plan.resizeCount==2 and #preview.plan.creates==0)
    api.runner.execute(cfg,preview)
    assert(target.patterns[0].inputs[1].size==7 and target.patterns[0].inputs[2].size==14)
    assert(target.patterns[1].inputs[3].size==21 and target.patterns[1].outputs[1].size==7)
    assert(api.runner.preview(cfg,'insulator').plan.resizeCount==0)
    target.patterns[1].inputs[3].size=20;refresh(target.patterns[1])
    preview=api.runner.preview(cfg,'insulator')
    assert(preview.plan.reused==1 and #preview.plan.creates==1 and #preview.plan.preserved==1)
  end)
end)

test('interrupted resizing recovers the same ultimate pattern and a fresh preview resumes remaining work',function()
  for _,stage in ipairs({'send-after','set-after'}) do
    reset()
    withMatrix(function()
      api.runner.execute(cfg,insulator());buffer.patterns={}
      local p=target.patterns[0]
      p.name='appliedenergistics2:item.ItemEncodedUltimatePattern'
      local root=unser(p.tag);root.__value.crafting=nil;p.tag=ser(root)
      cfg.programs.insulator.multiplier='9'
      local preview=api.runner.preview(cfg,'insulator');fail={label=stage}
      mustFail(function() api.runner.execute(cfg,preview) end,'injected')
      assert(files[api.paths.pending]);api.recover(cfg)
      assert(target.patterns[0].name=='appliedenergistics2:item.ItemEncodedUltimatePattern')
      assert(target.patterns[0].outputs[1].size==9 and not files[api.paths.pending])
      assert(unser(target.patterns[0].tag).__value.preserved.__value==42)
      preview=api.runner.preview(cfg,'insulator')
      assert(preview.plan.reused==2 and preview.plan.resizeCount==1)
      api.runner.execute(cfg,preview);assert(target.patterns[1].outputs[1].size==9)
    end)
  end
end)

test('tier settings use a modal selector, save globally and show the shifted budgets',function()
  files[api.paths.config]=ser(cfg)
  queue(nav('Settings'),nav('Tier multipliers'),click('[ Tiered ]'),
    click('[ LuV v ]'),function()
      assert(frame[10]:find('Current progression tier',1,true))
      snapshot('tier_picker')
      -- Underlying Quit is inactive while the selector is open.
      return 'touch','screen',153,47,0
    end,function()
      assert(frame[10]:find('Current progression tier',1,true))
      return click('[ UV ]')()
    end,function()
      local c=unser(files[api.paths.config])
      assert(c.batch.mode=='tiered' and c.batch.currentTier=='UV')
      assert(frame[15]:find('[ UV v ]',1,true))
      snapshot('tier_settings')
      return click('[ Effective tiers ]',47)()
    end,function()
      assert(frame[10]:find('budgets at UV',1,true))
      assert(frame[30]:find('UV  4x',1,true))
      assert(frame[28]:find('ZPM  32x',1,true))
      snapshot('tier_budgets')
      return 'key_down','kbd',0,1
    end,click('[ Next ]',45),replace('Material 2 tier(s) below','96'),
    function()
      assert(unser(files[api.paths.config]).batch.below2=='96')
      return quit()
    end)
  api.runUI()
  queue(nav('Settings'),nav('Tier multipliers'),function()
    assert(frame[15]:find('[ UV v ]',1,true))
    assert(unser(files[api.paths.config]).batch.below2=='96')
    return quit()
  end)
  api.runUI()
end)

test('multiplier settings default on migration, reject fractions and stay separate per program',function()
  local old=cp(cfg);old.programs.wiremill.multiplier=nil;old.programs.insulator.multiplier=nil
  local migrated=api.config.migrate(old)
  assert(migrated.programs.wiremill.multiplier=='1' and migrated.programs.insulator.multiplier=='1')
  migrated.programs.wiremill.multiplier='0.5'
  mustFail(function() api.config.validate(migrated) end,'positive whole number')
  files[api.paths.config]=ser(cfg)
  queue(nav('Settings'),nav('Wiremill'),replace('Pattern multiplier','256'),nav('Wire insulator'),
    replace('Pattern multiplier','4'),function()
      local c=unser(files[api.paths.config])
      assert(c.programs.wiremill.multiplier=='256' and c.programs.insulator.multiplier=='4')
      snapshot('maker_multiplier_settings');return quit()
    end)
  api.runUI()
end)

test('shortage preview allows Execute and the UI Cancel button stops refill waiting',function()
  withMatrix(function()
    cfg.programs.insulator.destination=cfg.programs.assline.target
    target.patterns={};buffer.patterns={};files[api.paths.config]=ser(cfg)
    queue(nav('Programs'),click('[ Wire insulator ]'),click('[ Preview selected ]',47),function()
      assert(((frame[22] or '')..(frame[23] or '')..(frame[24] or '')):find('wait for refills.',1,true))
      snapshot('maker_refill_preview')
      return 'touch','screen',118,39,0
    end,function()
      local polls=0
      local function cancelWhenWaiting()
        polls=polls+1
        assert(polls<20,'refill wait never became visible')
        if not (frame[49] or ''):find('Waiting for processing donors',1,true) then
          pollEvents[1]=cancelWhenWaiting
          return
        end
        assert(not files[api.paths.pending] and mutations==0)
        snapshot('maker_refill_wait')
        return click('[ Cancel ]',47)()
      end
      pollEvents={cancelWhenWaiting}
      return click('[ Execute preview ]',47)()
    end,function()
      assert((frame[49] or ''):find('Work cancelled',1,true))
      assert(not files[api.paths.pending] and mutations==0)
      return quit()
    end)
    api.runUI()
  end)
end)

test('bender settings are editable and wire combining remains unavailable',function()
  files[api.paths.config]=ser(cfg)
  queue(nav('Settings'),nav('Bending machine'),replace('Plate interface name','Plates'),replace('Foil interface name','Foils'),
    replace('Sheet metal interface name','Sheets'),function()
      local c=unser(files[api.paths.config]);assert(c.programs.bender.plate=='Plates' and c.programs.bender.foil=='Foils')
      assert(c.programs.bender.sheetMetal=='Sheets' and mutations==0)
      snapshot('bender_settings')
      return nav('Programs')()
    end,click('[ Wire combining ]'),function()
      assert(mutations==0 and not callCounts.getInterfacesByName);return quit()
    end)
  api.runUI()
end)

test('PPS button derives its paint, hitbox and color from each current state',function()
  files[api.paths.config]=ser(cfg)
  local function toggle()
    local before
    return {function() before=unser(files[api.paths.config]).programs.insulator.pps;return 'touch','screen',35,20,0 end,
      function()
        local after=unser(files[api.paths.config]).programs.insulator.pps
        assert(after~=before)
        local label=after=='on' and '[ On ]' or '[ Off ]'
        assert(frame[20]:sub(34,33+#label)==label)
        for x=34,33+#label do assert(background[20][x]==(after=='on' and 0x246B47 or 0x27465E)) end
        assert(background[20][34+#label]==0x101A26 and frame[20]:sub(34+#label,34+#label)==' ')
        return 'touch','screen',34+#label,20,0
      end,function() assert(unser(files[api.paths.config]).programs.insulator.pps~=before);return 'key_up','kbd',0,0 end}
  end
  queue(nav('Settings'),nav('Wire insulator'),toggle(),toggle(),toggle(),toggle(),quit)
  api.runUI()
end)

test('wiremill route choices save independently and default to ingots',function()
  files[api.paths.config]=ser(cfg)
  assert(cfg.programs.wiremill.wireSource=='ingot' and cfg.programs.wiremill.fineSource=='ingot')
  queue(nav('Settings'),nav('Wiremill'),click('[ Rod ]',20),click('[ 1x wire ]',24),
    nav('Programs'),nav('Settings'),function()
      local v=unser(files[api.paths.config]).programs.wiremill
      assert(v.wireSource=='stick' and v.fineSource=='wire1')
      assert(background[20][frame[20]:find('[ Rod ]',1,true)]==0x246B47)
      assert(background[24][frame[24]:find('[ 1x wire ]',1,true)]==0x246B47)
      snapshot('wiremill_settings');return quit()
    end)
  api.runUI()
end)

test('empty encoded processing donors are counted through the terminal and imprinted',function()
  withMatrix(function()
    buffer.patterns={[0]=pattern({},{}),[1]=pattern({},{})}
    buffer.patterns[0].name='ae2fc:encodedPattern'
    buffer.patterns[1].name='ae2fc:encodedPattern'
    local preview=insulator()
    assert(preview.plan.donorBanks==1 and preview.plan.available.processing==2 and #preview.plan.errors==0)
    api.runner.execute(cfg,preview)
    assert(api.runner.preview(cfg,'insulator').plan.reused==2)
  end)
end)

test('NBT-bearing items without encoded recipe lists are not donors',function()
  target.patterns={};buffer.patterns={[0]=pattern({},{})}
  buffer.patterns[0].tag=ser(compound({unrelated=typed('int',5)}))
  local prof=manifestFor(pattern({item('Input',1,777)}))
  local p=maker.scan(cfg,prof,{destination=cfg.programs.assline.target,donors=cfg.shared.donors,workspace=cfg.shared.editor})
  assert(p.available.processing==0 and p.donorBanks==1 and p.donorRejected==1)
end)

test('existing copper fine wire with empty ingredient tags is reused',function()
  cfg.programs.wiremill.wire1=cfg.programs.assline.target;cfg.programs.wiremill.wireFine='Fine wires';target.patterns={}
  local copperIn=item('Copper Ingot',1,11035);local copperOut=item('Fine Copper Wire',8,19035)
  copperOut.name='gregtech:gt.metaitem.02'
  for _,v in ipairs({copperIn,copperOut}) do v.tag=ser(compound({}));v.hasTag=false end
  local existing=pattern({copperIn},{copperOut});existing.name='ae2fc:encodedPattern'
  iface('Fine wires',50,{[13]=existing})
  local preview=api.runner.preview(cfg,'wiremill')
  assert(preview.plan.reused==1)
  for _,r in ipairs(preview.plan.layout) do
    for _,recipe in ipairs(preview.manifest.recipes) do
      if recipe.key==r.key and recipe.material=='Copper' and recipe.outputForm=='wireFine' then assert(r.existing) end
    end
  end
  assert(#preview.manifest.unresolved==0 and mutations==0)
end)

test('insulator preview uses readable groups and contains no external-stock dump',function()
  withMatrix(function()
    package.loaded.assline_data.items[1].label='PVC Pulp'
    local preview=insulator();local report=preview.report
    assert(report:find('PVC Pulp',1,true) and not report:find('gregtech:',1,true))
    assert(not report:find('External',1,true) and not report:find('UNVERIFIED',1,true))
    local count=0;for _ in report:gmatch('%+%-%- Interface') do count=count+1 end;assert(count==1)
    local rows=maker.rows(preview.plan,preview.manifest)
    local guideTone,bridges
    bridges=0
    for _,row in ipairs(rows) do
      if row[1]:find('+-- Interface',1,true) then guideTone=row[2] end
      if row[1]=='  |' then
        bridges=bridges+1
        assert(row[2]==guideTone)
      end
      if row[3] then assert(row[4]==guideTone) end
    end
    assert(bridges==1 and report:find('\n  |\n',1,true))
    files[api.paths.config]=ser(cfg)
    queue(click('[ Wire insulator ]'),click('[ Preview selected ]',47),function()
      local interfaceY,materialY
      for y=12,42 do
        if frame[y]:find('+-- Interface',34,true) then interfaceY=y end
        if frame[y]:find('  |  A',34,true) then materialY=y end
      end
      assert(interfaceY and materialY)
      assert(foreground[interfaceY][36]==foreground[materialY][36])
      assert(foreground[materialY][36]~=foreground[materialY][39])
      snapshot('insulator_preview');return quit()
    end)
    api.runUI()
  end)
end)

test('real insulation preview shows named ingredients, capacity and reused cable',function()
  local saved=package.loaded.assline_data
  local subset=cp(require('assline_data'));subset.materials={}
  for _,material in ipairs(saved.materials) do
    if material.name=='Copper' or material.name=='NiobiumTitanium' then subset.materials[#subset.materials+1]=material end
  end
  package.loaded.assline_data=subset
  cfg.programs.insulator.destination='Wire insulator';target.name='Wire insulator';target.patterns={}
  for slot=0,11 do buffer.patterns[slot]=pattern({},{}) end
  local preview=api.runner.preview(cfg,'insulator')
  assert(#preview.plan.errors==0 and #preview.manifest.recipes==11)
  local r=preview.manifest.recipes[1]
  target.patterns[0]=pattern(r.inputs,r.outputs)
  local report=api.runner.preview(cfg,'insulator');assert(report.plan.reused==1)
  files[api.paths.config]=ser(cfg)
  queue(click('[ Wire insulator ]'),click('[ Preview selected ]',47),function()
    snapshot('real_insulator_preview');return quit()
  end)
  api.runUI();package.loaded.assline_data=saved
end)

test('preview identifies kept encoded outputs, excluded forms and labeled sorting moves',function()
  local saved=package.loaded.assline_data
  local fixture=matrixFixture()
  fixture.source.usagePolicy='reachable-nonrecycling-v3'
  fixture.usage={{cable1=true},{}}
  fixture.materials[1].u=1;fixture.materials[2].u=2
  package.loaded.assline_data=fixture
  local ok,why=pcall(function()
    cfg.programs.insulator.destination='Diagnosis';target.name='Diagnosis';target.patterns={}
    local first=api.runner.preview(cfg,'insulator')
    assert(#first.manifest.recipes==1 and #first.manifest.skipped==1)
    local wanted=first.manifest.recipes[1]
    local other=cp(wanted.outputs[1]);other.damage=206;other.label='B 1x Cable'
    target.patterns[0]=pattern(wanted.inputs,{other})
    target.patterns[1]=pattern(wanted.inputs,wanted.outputs)
    target.patterns[2]=pattern({item('Different route',1,55)},wanted.outputs)
    local preview=api.runner.preview(cfg,'insulator')
    assert(preview.plan.reused==1 and #preview.plan.preserved==2)
    assert(#preview.plan.existing==3 and #preview.plan.moves>0)
    assert(preview.plan.existing[1].status=='KEEP')
    assert(preview.plan.existing[1].reason:find('no path',1,true))
    assert(preview.plan.existing[2].status=='REUSE')
    assert(preview.plan.existing[3].status=='KEEP')
    assert(preview.plan.existing[3].reason:find('encoded inputs',1,true))
    assert(preview.plan.existing[3].requestedInputs:find('A 1x Wire',1,true))
    files[api.paths.config]=ser(cfg)
    local function screenText()
      local rows={};for y=1,50 do rows[#rows+1]=frame[y] or '' end
      return table.concat(rows,'\n')
    end
    queue(nav('Programs'),click('[ Wire insulator ]'),click('[ Preview selected ]',47),
      click('[ Existing ]',9),function()
        local screen=screenText()
        assert(screen:find('B 1x Cable',1,true) and screen:find('SORTING MOVES',1,true))
        assert(screen:find('Requested inputs:',1,true))
        snapshot('diagnosis_existing')
        return click('[ Excluded ]',9)()
      end,function()
        local screen=screenText()
        assert(screen:find('EXCLUDED BY RECIPE USE',1,true))
        assert(screen:find('B 1x Cable',1,true))
        snapshot('diagnosis_excluded')
        return click('[ Export report ]',45)()
      end,function()
        local report=assert(files['/home/assline-preview.txt'])
        assert(report:find('B 1x Cable',1,true))
        assert(report:find('Requested inputs:',1,true))
        assert(report:find('EXISTING DESTINATION PATTERNS',1,true))
        assert(report:find('SORTING MOVES',1,true))
        return quit()
      end)
    api.runUI()
  end)
  package.loaded.assline_data=saved
  assert(ok,why)
end)

test('five polymer choices save immediately with one highlighted choice and independent PPS',function()
  files[api.paths.config]=ser(cfg)
  local choices={{'PVC pulp','pvc'},{'Small PVC pulp','pvcSmall'},{'PDMS pulp','pdms'},{'Small PDMS pulp','pdmsSmall'},{'Nothing','none'}}
  local steps={nav('Settings'),nav('Wire insulator')}
  for _,option in ipairs(choices) do
    local label,value=option[1],option[2]
    steps[#steps+1]=click('[ '..label..' ]',16)
    steps[#steps+1]=function()
      assert(unser(files[api.paths.config]).programs.insulator.polymer==value)
      assert(unser(files[api.paths.config]).programs.insulator.pps=='on')
      for _,other in ipairs(choices) do
        local x=assert(frame[16]:find('[ '..other[1]..' ]',1,true))
        assert(background[16][x]==(other[2]==value and 0x246B47 or 0x27465E))
      end
      return 'key_up','kbd',0,0
    end
  end
  steps[#steps+1]=function() snapshot('insulator_settings');return quit() end
  queue(table.unpack(steps));api.runUI()
  local old=cp(cfg);old.programs.insulator.polymer=nil;old.programs.insulator.pvc='on'
  assert(api.config.migrate(old).programs.insulator.polymer=='pvcSmall')
  old.programs.insulator.pvc='off';assert(api.config.migrate(old).programs.insulator.polymer=='none')
end)

test('native touch drag drop scrolls, clamps and releases the scrollbar without stealing other drags',function()
  local log={'uptime=1 history fixture'};for i=1,110 do log[#log+1]='History line '..i end
  files['/home/assline-perf.log']=table.concat(log,'\n')..'\n\n';files[api.paths.config]=ser(cfg)
  local function position() return tonumber(frame[44]:match('Rows (%d+)')) end
  local bottom
  queue(nav('History'),function() assert(position()==1);return 'drag','screen',159,42,0,'Player' end,
    function() assert(position()==1);return 'touch','screen',159,12,0,'Player' end,
    {'drag','other-screen',159,100,0,'Player'},function() assert(position()==1);return 'drag','screen',159,100,0,'Other' end,
    function() assert(position()==1);return 'drag','screen',159,100,0,'Player' end,
    function() bottom=position();assert(bottom>70);snapshot('history_scrollbar');return 'drop','screen',159,100,0,'Player' end,
    {'drag','screen',159,12,0,'Player'},function() assert(position()==bottom);return 'touch','screen',159,42,0,'Player' end,
    {'drag','screen',159,-50,0,'Player'},function() assert(position()==1);return 'drop','screen',159,12,0,'Player' end,
    {'touch','screen',50,20,0,'Player'},{'drag','screen',159,42,0,'Player'},function() assert(position()==1);return quit() end)
  api.runUI()
end)

test('ultimate processing donors without crafting tags are recognized across eight terminal banks and remain recoverable',function()
  withMatrix(function()
    local function ultimate()
      local p=pattern({item('Disposable',1,333)})
      p.name='appliedenergistics2:item.ItemEncodedUltimatePattern'
      local root=unser(p.tag);root.__value.crafting=nil;p.tag=ser(root);return p
    end
    buffer.patterns={}
    for bank=1,8 do
      local b=bank==1 and buffer or iface(cfg.shared.donors,80+bank)
      for slot=0,35 do b.patterns[slot]=bank<=6 and ultimate() or pattern({item('Craft',1,222)},nil,true) end
    end
    local preview=insulator()
    assert(preview.plan.donorBanks==8 and preview.plan.donorOccupied==288)
    assert(preview.plan.available.processing==216 and preview.plan.available.crafting==72 and preview.plan.donorRejected==0)
    fail={label='set-after'};mustFail(function() api.runner.execute(cfg,preview) end,'injected')
    api.recover(cfg)
    assert(target.patterns[0].name=='appliedenergistics2:item.ItemEncodedUltimatePattern')
    assert(unser(target.patterns[0].tag).__value.crafting==nil)
    assert(api.runner.preview(cfg,'insulator').plan.reused==1)
  end)
end)

test('rejected donors explain the preserved flags that prevent imprinting',function()
  withMatrix(function()
    local root=unser(buffer.patterns[0].tag);root.__value.substitute=typed('byte',1);buffer.patterns[0].tag=ser(root)
    local p=insulator().plan
    assert(p.donorRejected==1 and p.donorReasons['Input substitution enabled']==1)
  end)
end)

if artifact=='assline_app.lua' then
  package.loaded.assline_data={};files[api.paths.config]=ser(cfg);events={{'interrupted'}}
  local before=package.path;assert(loadfile(artifact))();assert(package.path==before)
  assert(package.loaded.assline_data==nil,'Application library must unload on exit')
end
print('SUCCESS: '..tests..' tests ('..artifact..')')
