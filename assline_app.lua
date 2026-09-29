-- Readable application bundle, generated from the source files named below.
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
local U=(function()
-- Source: lib/util.lua
local function check(ok, why) if not ok then error(why or 'Operation failed', 0) end return ok end
local function clone(t)
  if type(t) ~= 'table' then return t end
  local r = {}; for k,v in pairs(t) do r[k] = clone(v) end; return r
end
local function keys(t)
  local r = {}; for k in pairs(t or {}) do r[#r+1] = k end
  table.sort(r, function(a,b) if type(a)==type(b) then return a<b end return type(a)<type(b) end)
  return r
end
local function canonical(t)
  if type(t) ~= 'table' then return type(t)..':'..string.format('%q', tostring(t)) end
  local r = {}; for _,k in ipairs(keys(t)) do r[#r+1] = canonical(k)..':'..canonical(t[k]) end
  return '{'..table.concat(r, ',')..'}'
end
local function eq(a,b)
  if type(a)~=type(b) then return false end
  if type(a)~='table' then return a==b end
  for k,v in pairs(a) do if not eq(v,b[k]) then return false end end
  for k in pairs(b) do if a[k]==nil then return false end end
  return true
end
local function integer(n) return type(n)=='number' and n==math.floor(n) and math.abs(n)<2147483648 end
local function sequence(t,label)
  check(type(t)=='table',label..' must be an array')
  local count=0
  for k in pairs(t) do check(integer(k) and k>=1 and k<=#t,label..' must be a contiguous array');count=count+1 end
  check(count==#t,label..' must be a contiguous array')
end
local function endpoint(i,slot) return {location=clone(i.location),side=i.side,slot=slot} end
local function where(i) return canonical({i.location,i.side}) end
local function locationText(i)
  local l=i.location
  return tostring(l.x)..','..tostring(l.y)..','..tostring(l.z)..' / '..tostring(l.dimId or '?')..' side '..tostring(i.side)
end
local function ordered(a,b)
  for _,k in ipairs({'dimId','x','y','z'}) do
    local x,y=a.location[k] or 0,b.location[k] or 0
    if x~=y then return x<y end
  end
  return a.side<b.side
end
return {check=check,clone=clone,keys=keys,canonical=canonical,eq=eq,integer=integer,sequence=sequence,
  endpoint=endpoint,where=where,ordered=ordered,locationText=locationText}

end)()
-- Source: src/00_core.lua
-- GTNH 2.9 / OpenOS. Terminal pattern slots are ZERO based; direct slots ONE based.
local component = require('component')
local event = require('event')
local computer = require('computer')
local fs = require('filesystem')
local serialization = require('serialization')
local unicode = require('unicode')
local C = {}
local U=U
local check,clone,keys,canonical,eq=U.check,U.clone,U.keys,U.canonical,U.eq
local function trim(s) return tostring(s or ''):match('^%s*(.-)%s*$') end
local function truth(x) return x==true or x==1 end
local function exists(x) return type(x)=='table' and type(x.name)=='string' end
local function largest(t)
  local n=0; for k in pairs(t or {}) do if type(k)=='number' and k>n then n=k end end; return n
end
local function token(t, label, n)
  return (t:gsub('{label}', function() return label end):gsub('{n}', tostring(n)))
end
local defaults = {target='Advanced Assline (1)', buffer='OC Buffer', itemName='NAME_{n}',
  renameName='Rename NAME_{n}', terminalAddress='', bufferAddress='', dataAddress='', bufferSlots='9', renameSlots='9',
  energyPause='25',energyResume='75',makerDestination='',makerDonors='',makerWorkspace='',
  makerSlots='9',makerDonorSlots='9',makerWorkspaceSlots='9',makerMode='wiremill',makerPVC='on',makerPPS='on'}
local cfg = clone(defaults)
local work={pause=0.25,resume=0.75}
local perf
local tagKeys,renameTags,tagCount,renameCount={},{},0,0
local function releaseWork()
  perf=nil;work.progress=nil;work.control=nil
  tagKeys,renameTags,tagCount,renameCount={},{},0,0
end
local function sampleEnergy()
  local t=computer.uptime();local e,m=computer.energy(),computer.maxEnergy()
  if perf then perf.samples=perf.samples+1;perf.sampleTime=perf.sampleTime+computer.uptime()-t end
  check(type(m)=='number' and m>0,'Computer energy capacity unavailable')
  return e,m
end
local function record(name,elapsed)
  if not perf then return end
  local v=perf.calls[name] or {0,0,0};perf.calls[name]=v
  v[1]=v[1]+1;v[2]=v[2]+elapsed;v[3]=math.max(v[3],elapsed)
end
local function perfReport(status)
  if not perf then return end
  local e,m=sampleEnergy();local elapsed=computer.uptime()-perf.started;local callTime=0
  local out={string.format('\nuptime=%.1fs %s elapsed=%.2fs energy=%.0f/%.0f (%.1f%% -> %.1f%%)',
    computer.uptime(),status,elapsed,e,m,perf.startPct*100,e/m*100),
    string.format('free memory=%d -> %d bytes',perf.memory,computer.freeMemory()),
    string.format('energy samples=%d time=%.3fs pauses=%d event.pull yields=%d wait=%.2fs',
      perf.samples,perf.sampleTime,perf.pauses,perf.yields,perf.wait)}
  for name,v in pairs(perf.calls) do
    callTime=callTime+v[2]
    out[#out+1]=string.format('%s calls=%d time=%.3fs max=%.3fs',name,v[1],v[2],v[3])
  end
  out[#out+1]=string.format('other time=%.3fs (Lua planning, file I/O, UI)',math.max(0,elapsed-perf.wait-callTime))
  local path='/home/assline-perf.log'
  if fs.exists(path) and fs.size(path)>65536 then fs.remove(path) end
  local f=io.open(path,'a')
  if f then f:write(table.concat(out,'\n')..'\n');f:close() end
  releaseWork()
end
local function energyFraction()
  local e,m=sampleEnergy();return e/m
end
local function rest(seconds)
  local deadline=computer.uptime()+seconds
  repeat
    if perf then perf.yields=perf.yields+1 end
    local t=computer.uptime()
    local delay=math.max(0,math.min(0.25,deadline-computer.uptime()))
    local e=work.control and (work.control(delay) or {}) or {event.pull(delay)}
    if perf then perf.wait=perf.wait+computer.uptime()-t end
    check(e[1]~='interrupted' and not (e[1]=='key_down' and e[4]==1),
      'Work cancelled. Use Recover if an operation is pending; otherwise scan again.')
  until computer.uptime()>=deadline
end
local function gate()
  if work.control and work.control(0) and perf then perf.yields=perf.yields+1 end
  if energyFraction()<work.pause then
    if perf then perf.pauses=perf.pauses+1 end
    local lastGain,lastValue,lastReport=computer.uptime(),computer.energy(),-math.huge
    while energyFraction()<work.resume do
      local now=computer.uptime();local value=computer.energy()
      if value>lastValue then lastGain=now end
      lastValue=value
      check(energyFraction()>=work.pause/2,'Energy keeps falling; work stopped. Recharge, then Recover / Scan.')
      check(now-lastGain<30,'No recharge for 30 seconds; work stopped. Check power input, then Recover / Scan.')
      if work.progress and now-lastReport>=2 then
        work.progress(string.format('Waiting for energy: %.0f%% -> %.0f%%. Esc cancels.',energyFraction()*100,work.resume*100))
        lastReport=now
      end
      rest(0.25)
    end
  end
end
local function startWork(c,progress,control)
  work={pause=tonumber(c.energyPause)/100,resume=tonumber(c.energyResume)/100,progress=progress,control=control}
  local e,m=sampleEnergy()
  perf={started=computer.uptime(),startPct=e/m,memory=computer.freeMemory(),samples=0,sampleTime=0,pauses=0,yields=0,wait=0,calls={}}
  tagKeys,renameTags,tagCount,renameCount={},{},0,0
end
local paths = {config='/home/assline.cfg', pending='/home/assline.pending', backup='/home/assline.last'}
local function readRaw(path)
  if not fs.exists(path) then return nil end
  check(fs.size(path)<=400000, 'File too large: '..path)
  local f=check(io.open(path,'r'), 'Cannot open '..path)
  local s=f:read('*a'); f:close()
  check(s, 'Cannot read '..path)
  return s
end
local function readFile(path)
  local s=readRaw(path); if not s then return nil end
  local t=serialization.unserialize(s); check(type(t)=='table','Invalid file: '..path); return t
end
local function writeFile(path,t)
  local s=serialization.serialize(t)
  check(#s<=400000,'Recovery data exceeds disk/memory budget; use a smaller target interface')
  check(computer.freeMemory()>#s+131072,'Not enough memory to verify saved data; use a smaller target interface')
  local temp=path..'.tmp'; local f=check(io.open(temp,'w'),'Cannot write '..temp)
  local ok,err=pcall(function() check(f:write(s),'Write failed'); check(f:flush(),'Flush failed') end)
  f:close(); check(ok,err)
  check(readRaw(temp)==s,'Saved file verification failed')
  if fs.exists(path) then check(fs.remove(path),'Cannot replace '..path) end
  check(fs.rename(temp,path),'Cannot finish saving '..path)
end
local function validate(c)
  for k in pairs(defaults) do check(type(c[k])=='string' and #c[k]<=512,'Invalid setting: '..k) end
  check(c.target~='' and c.buffer~='' and c.renameName~='','Interface names cannot be empty')
  check(c.target~=c.buffer,'Target and buffer must differ')
  check(c.itemName:find('{n}',1,true),'Item name template needs {n}')
  for _,k in ipairs({'itemName','renameName'}) do
    check(not c[k]:gsub('{label}',''):gsub('{n}',''):find('[{}]'),'Unknown template token: '..k)
  end
  for _,k in ipairs({'bufferSlots','renameSlots','makerSlots','makerDonorSlots','makerWorkspaceSlots'}) do
    local n=tonumber(c[k]); check(n and n>=1 and n<=512 and n==math.floor(n),k..' must be 1..512')
  end
  check(c.makerMode=='wiremill' or c.makerMode=='coating','Unknown maker mode')
  for _,k in ipairs({'makerPVC','makerPPS'}) do check(c[k]=='on' or c[k]=='off',k..' must be on or off') end
  local pause,resume=tonumber(c.energyPause),tonumber(c.energyResume)
  check(pause and resume and pause>=10 and pause<=80 and resume>=pause+10 and resume<=95,
    'Energy pause must be 10..80%; resume at least 10% higher, up to 95%')
end
local function selectDevice(kind, prefix)
  local matches={}
  for addr,tp in component.list(kind,true) do
    if tp==kind and (prefix=='' or addr:sub(1,#prefix)==prefix) then matches[#matches+1]=addr end
  end
  check(#matches==1,'Need one '..kind..' (found '..#matches..'); set its address in Settings')
  return component.proxy(matches[1])
end
local function invoke(p,name,...)
  check(p[name]~=nil,'Missing API '..name..'; check GTNH / OpenComputers version')
  gate()
  local t=computer.uptime();local a,b,c=p[name](...)
  record(name,computer.uptime()-t)
  return a,b,c
end
local function nbt(data, tag)
  local t=tag and invoke(data,'decodeNBT',tag) or {__nbt_type='compound',__value={}}
  check(type(t)=='table' and t.__nbt_type=='compound' and type(t.__value)=='table','Typed NBT support required (GTNH 2.9 Data Card)')
  return t
end
local function tagKey(data,s)
  check(not truth(s.hasTag) or type(s.tag)=='string','NBT is hidden; enable allowItemStackNBTTags in OC config')
  if not s.tag then return '{}' end
  if tagKeys[s.tag] then return tagKeys[s.tag] end
  local key=canonical(nbt(data,s.tag))
  if tagCount<32 and #s.tag<=2048 and #key<=2048 then
    tagKeys[s.tag]=key;tagCount=tagCount+1
  end
  return key
end
local function identity(data,s)
  return s.name..':'..tostring(s.damage or 0)..':'..tagKey(data,s)
end
local function stack(s)
  if not exists(s) then return nil end
  return {name=s.name,damage=s.damage,size=s.size,amount=s.amount,label=s.label,tag=s.tag,hasTag=s.hasTag}
end
local function stackEq(data,a,b)
  if not exists(a) or not exists(b) then return not exists(a) and not exists(b) end
  if a.name~=b.name or a.damage~=b.damage or a.size~=b.size or a.amount~=b.amount then return false end
  if a.tag==b.tag and (a.tag or (not truth(a.hasTag) and not truth(b.hasTag))) then return true end
  return identity(data,a)==identity(data,b) and a.size==b.size and a.amount==b.amount
end
-- GTNH's typed decoder emits string wrappers, but its encoder only accepts
-- bare strings (the parseWithType match has no ("string", value) case).
-- Unwrap strings recursively, including existing names/lore and nested lists.
-- Keep all other NBT type wrappers intact. Never weaken round-trip verification.
local function encodableNBT(t)
  if type(t)~='table' then return t end
  if t.__nbt_type=='string' then
    check(type(t.__value)=='string','Invalid NBT string value')
    return t.__value
  end
  local r={};for k,v in pairs(t) do r[k]=encodableNBT(v) end;return r
end
local function renamed(data,s,name)
  local key=canonical({s.tag or false,name})
  local r=stack(s);r.hasTag=true;r.label=name
  if renameTags[key] then r.tag=renameTags[key];return r end
  local t=nbt(data,s.tag)
  local d=t.__value.display
  if not d then d={__nbt_type='compound',__value={}}; t.__value.display=d end
  check(d.__nbt_type=='compound','Invalid display NBT')
  d.__value.Name={__nbt_type='string',__value=name}
  r.tag=check(invoke(data,'encodeNBT',encodableNBT(t)),'NBT encode failed')
  check(eq(nbt(data,r.tag),t),'NBT encode round trip failed')
  if renameCount<32 and #key<=2048 and #r.tag<=2048 then renameTags[key]=r.tag;renameCount=renameCount+1 end
  return r
end
local function compact(p)
  if not exists(p) then return nil end
  local r=stack(p); r.isCraftable=p.isCraftable; r.inputs={}; r.outputs={}
  for _,which in ipairs({'inputs','outputs'}) do
    for k,s in pairs(p[which] or {}) do if exists(s) then r[which][k]=stack(s) end end
  end
  return r
end
local function patternEq(data,a,b)
  if not exists(a) or not exists(b) then return not exists(a) and not exists(b) end
  return stackEq(data,a,b)
end
local function processing(p)
  return exists(p) and p.inputs and p.outputs and (p.isCraftable==false or p.isCraftable==0)
end
local sides={down=0,up=1,north=2,south=3,west=4,east=5,unknown=6}
local function side(s)
  if type(s)=='number' then return s end
  return check(sides[tostring(s):lower()], 'Unknown interface side: '..tostring(s))
end
local function endpoint(i,slot) return U.endpoint({location=i.location,side=side(i.side)},slot) end
local function where(i) return U.where(endpoint(i)) end
local function iterate(result, callback)
  check(result~=nil,'Interface lookup failed')
  if type(result)=='table' and not getmetatable(result) then
    for _,i in pairs(result) do if type(i)=='table' and i.location then callback(i) end end
  else
    while true do gate();local t=computer.uptime();local i=result();record('terminal iterator',computer.uptime()-t);if not i then break end; callback(i) end
  end
end
local function lookup(hw,name,metadata)
  local found={}
  local result=invoke(hw.terminal,'getInterfacesByName',name)
  if metadata then
    check(result and result.getAll,'Metadata-only discovery requires getAll(false)')
    result=invoke(result,'getAll',false)
  end
  iterate(result,function(i)
    check(not metadata or i.patterns==nil,'Driver ignored metadata-only discovery')
    if i.name==name then found[#found+1]=i end
  end)
  table.sort(found,function(a,b) return U.ordered(endpoint(a),endpoint(b)) end)
  return found
end
local function unique(hw,name)
  local list=lookup(hw,name); check(#list==1,'Expected one interface named "'..name..'", found '..#list)
  return list[1]
end
local function current(hw,ref)
  local found
  iterate(invoke(hw.terminal,'getInterfacesByLocation',ref.location,ref.side),function(i)
    if where(i)==where(ref) then check(not found,'Ambiguous interface location'); found=i end
  end)
  return check(found,'Interface unavailable at '..where(ref))
end
local function direct(hw,name,slot,...)
  if hw.buffer.side~=6 then return invoke(hw.direct,name,hw.buffer.side,slot+1,...) end
  return invoke(hw.direct,name,slot+1,...)
end
local function connect(c,progress,control)
  validate(c)
  startWork(c,progress,control)
  local hw={terminal=selectDevice('me_interface_terminal',c.terminalAddress),
    direct=selectDevice('me_interface',c.bufferAddress),data=selectDevice('data',c.dataAddress)}
  hw.buffer=endpoint(unique(hw,c.buffer))
  nbt(hw.data,invoke(hw.data,'encodeNBT',{__nbt_type='compound',__value={}}))
  return hw
end
C.defaults=defaults
C.perfReport=perfReport
C.releaseWork=releaseWork

-- Source: src/10_plan.lua
local function item(s)
  return exists(s) and s.damage~=nil and s.amount==nil
    and not s.name:lower():find('fluiddrop',1,true) and not s.name:lower():find('fluid_drop',1,true)
    and not s.name:lower():find('fluidpacket',1,true) and not s.name:lower():find('fluid_packet',1,true)
end
local function metadata(data,p)
  local t=nbt(data,p.tag); t.__value['in']=nil; t.__value.out=nil; return t
end
local function safeDonor(data,p)
  if not processing(p) or not p.tag then return false end
  local t=nbt(data,p.tag).__value
  for _,k in ipairs({'substitute','beSubstitute'}) do
    if t[k] and truth(t[k].__value) then return false end
  end
  return true
end
local function pureRecipe(data,p,r)
  if not safeDonor(data,p) then return false end
  for _,which in ipairs({'inputs','outputs'}) do
    for index,s in pairs(p[which]) do if exists(s) and index~=1 then return false end end
  end
  local a,b=p.inputs[1],p.outputs[1]
  return item(a) and item(b) and a.size>0 and a.size==b.size
    and identity(data,a)==identity(data,r.input) and identity(data,b)==identity(data,r.output)
end
local function scan(c,progress,control)
  local hw=connect(c,progress,control)
  local target=unique(hw,c.target)
  check(where(target)~=where(hw.buffer),'Target is the buffer')
  local buffer=current(hw,hw.buffer)
  local p={target=endpoint(target),buffer=hw.buffer,changes={},recipes={},errors={},scanned=0,skipped=0,donors={},empty={}}
  local function problem(s) p.errors[#p.errors+1]=s end
  local wanted={}
  for _,slot in ipairs(keys(target.patterns)) do
    gate()
    local original=target.patterns[slot]
    if exists(original) then
      p.scanned=p.scanned+1
      if processing(original) then
        check(type(original.tag)=='string','Pattern NBT is hidden; enable allowItemStackNBTTags')
        local counts,occupied,changes={},{},{}
        for _,s in pairs(original.inputs) do if item(s) then occupied[identity(hw.data,s)]=true end end
        for _,index in ipairs(keys(original.inputs)) do
          local s=original.inputs[index]
          if item(s) then
            local id=identity(hw.data,s); local n=counts[id] or 0; counts[id]=n+1
            if n>0 then
              check(type(s.size)=='number' and s.size>0 and s.size<=2147483647,'Unsupported input amount')
              local output,label
              repeat
                label=token(c.itemName,s.label or s.name,n)
                check(unicode.len(label)<=128,'Generated item name is longer than 128 characters')
                output=renamed(hw.data,s,label)
                if not occupied[identity(hw.data,output)] then break end
                n=n+1; check(n<=512,'Cannot allocate unique item names')
              until false
              counts[id]=n+1; occupied[identity(hw.data,output)]=true
              changes[#changes+1]={index=index,before=stack(s),after=output}
              local destName=token(c.renameName,s.label or s.name,n)
              local recipeKey=canonical({destName,id,identity(hw.data,output)})
              if not wanted[recipeKey] then
                local r={input=stack(s),output=output,name=destName}
                wanted[recipeKey]=r; p.recipes[#p.recipes+1]=r
              end
            end
          end
        end
        if #changes>0 then p.changes[#p.changes+1]={slot=slot,original=compact(original),edits=changes} end
      else p.skipped=p.skipped+1 end
    end
    if progress then progress('Scanning pattern '..tostring(slot+1)) end
    check(computer.freeMemory()>160000,'Low memory; scan a smaller target interface')
  end
  -- Only requested names are fetched; no getAll(true) of a large ME network.
  local groups,used={},{ }
  for _,r in ipairs(p.recipes) do
    if not groups[r.name] then groups[r.name]=lookup(hw,r.name) end
    local group=groups[r.name]
    for _,i in ipairs(group) do
      check(where(i)~=where(target) and where(i)~=where(hw.buffer),'Rename interface overlaps target or buffer')
      for _,slot in ipairs(keys(i.patterns)) do
        if pureRecipe(hw.data,i.patterns[slot],r) then
          r.existing=endpoint(i,slot); break
        end
      end
      if r.existing then break end
    end
    if not r.existing then
      for _,i in ipairs(group) do
        local key=where(i); used[key]=used[key] or {}
        for slot=0,tonumber(c.renameSlots)-1 do
          if not exists(i.patterns[slot]) and not used[key][slot] then
            used[key][slot]=true; r.destination=endpoint(i,slot); break
          end
        end
        if r.destination then break end
      end
      if not r.destination then problem('No free slot in "'..r.name..'" (missing, full, or slot limit too low)') end
    end
    if progress then progress('Checking '..r.name) end
  end
  local donors={}
  for slot=0,tonumber(c.bufferSlots)-1 do
    local remote=buffer.patterns[slot]
    local live=direct(hw,'getInterfacePattern',slot)
    check(patternEq(hw.data,remote,live),'Direct buffer does not match "'..c.buffer..'" at slot '..(slot+1))
    if not exists(remote) then p.empty[#p.empty+1]=slot
    elseif safeDonor(hw.data,remote) then donors[#donors+1]={slot=slot,original=compact(remote)} end
  end
  local n=0
  for _,r in ipairs(p.recipes) do
    if not r.existing then
      n=n+1
      if donors[n] then r.donor=donors[n] else problem('Need more disposable processing patterns in '..c.buffer) end
    end
  end
  p.newRecipes=n; p.available=#donors
  if #p.changes>0 and #p.empty==0 and n==0 then problem('Leave one empty pattern slot in '..c.buffer..' for editing') end
  return p,hw
end
C.scan=scan

-- Source: src/20_apply.lua
-- One durable intent per moved pattern. Recovery completes only that operation;
-- another scan is required before continuing the rest of a batch.
local function rawList(data,p,which)
  local root=nbt(data,p.tag).__value
  local t=root[which=='inputs' and 'in' or 'out']
  check(t and t.__nbt_type=='list','Unsupported encoded pattern layout')
  return t.__value
end
local function expected(op)
  local p=compact(op.original)
  if op.kind=='recipe' then
    p.inputs={[1]=op.input}; p.outputs={[1]=op.output}
  else for _,e in ipairs(op.edits) do p.inputs[e.index]=e.after end end
  return p
end
local function semantic(hw,p,q)
  if not exists(p) or not exists(q) or p.name~=q.name or p.damage~=q.damage then return false end
  if not eq(metadata(hw.data,p),metadata(hw.data,q)) then return false end
  for _,which in ipairs({'inputs','outputs'}) do
    local all={}; for k in pairs(p[which] or {}) do all[k]=true end; for k in pairs(q[which] or {}) do all[k]=true end
    for k in pairs(all) do if not stackEq(hw.data,p[which][k],q[which][k]) then return false end end
  end
  return true
end
local function allowedPartial(hw,p,op)
  check(exists(p) and p.name==op.original.name and p.damage==op.original.damage,'Unexpected pattern in buffer')
  check(eq(metadata(hw.data,p),metadata(hw.data,op.original)),'Pattern flags or other NBT changed; recovery stopped')
  local final=expected(op)
  for _,which in ipairs({'inputs','outputs'}) do
    local all={}; for k in pairs(p[which] or {}) do all[k]=true end
    for k in pairs(op.original[which]) do all[k]=true end
    for k in pairs(final[which]) do all[k]=true end
    for k in pairs(all) do
      local a=p[which][k]; local old=op.original[which][k]; local new=final[which][k]
      check(stackEq(hw.data,a,old) or stackEq(hw.data,a,new),'Unexpected '..which..' slot '..k..'; recovery stopped')
    end
  end
end
local function transfer(hw,from,to)
  local ok,slot=invoke(hw.terminal,'send',from,to)
  check(ok==true,'Pattern transfer failed: '..tostring(slot))
  check(slot==to.slot,'Pattern moved to unexpected slot '..tostring(slot))
end
local function setEntry(hw,slot,which,index,s)
  local method=which=='inputs' and 'setInterfacePatternInput' or 'setInterfacePatternOutput'
  if s then
    check(direct(hw,method,slot,index,{name=s.name,damage=s.damage,size=s.size,tag=s.tag},'item')==true,'Pattern setter returned failure')
  else check(direct(hw,method,slot,index)==true,'Pattern clear returned failure') end
end
local function finish(hw,op,progress)
  check(op.version==1 and op.direct==hw.direct.address and op.terminal==hw.terminal.address
    and op.data==hw.data.address and where(op.buffer)==where(hw.buffer),'Recovery hardware differs from saved operation')
  local goal=expected(op)
  local dest=current(hw,op.destination)
  local remote=current(hw,op.buffer)
  local p=remote.patterns[op.slot]
  check(patternEq(hw.data,p,direct(hw,'getInterfacePattern',op.slot)),'Direct/terminal buffer mismatch')
  local delivered=dest.patterns[op.destination.slot]
  if not exists(p) and exists(delivered) and semantic(hw,delivered,goal) then
    return -- A transfer succeeded immediately before the power loss.
  end
  if op.kind=='edit' and not exists(p) then
    check(patternEq(hw.data,delivered,op.original),'Original target pattern changed')
    transfer(hw,op.destination,endpoint(op.buffer,op.slot))
    p=direct(hw,'getInterfacePattern',op.slot)
    check(patternEq(hw.data,p,op.original),'Moved pattern failed read-back')
  else check(not exists(delivered),'Destination slot is occupied') end
  allowedPartial(hw,p,op)
  if op.kind=='recipe' then
    -- Clearing removes an NBT list element: ALWAYS clear from the end.
    for _,which in ipairs({'inputs','outputs'}) do
      local s=which=='inputs' and op.input or op.output
      local entries=rawList(hw.data,p,which)
      if not stackEq(hw.data,p[which][1],s) then setEntry(hw,op.slot,which,1,s) end
      for index=largest(entries),2,-1 do
        local entry=entries[index]
        check(entry and entry.__nbt_type=='compound' and type(entry.__value)=='table','Invalid pattern list entry')
        -- AE ignores empty compounds. Do not spend a server tick removing every
        -- unused cell in a padded processing donor. Clear nonempty cells only.
        if next(entry.__value)~=nil then setEntry(hw,op.slot,which,index) end
      end
    end
  else
    for _,e in ipairs(op.edits) do
      if not stackEq(hw.data,p.inputs[e.index],e.after) then setEntry(hw,op.slot,'inputs',e.index,e.after) end
    end
  end
  p=direct(hw,'getInterfacePattern',op.slot)
  check(semantic(hw,p,goal),'Edited pattern read-back failed; saved recovery record retained')
  check(patternEq(hw.data,current(hw,op.buffer).patterns[op.slot],p),'Edited direct buffer differs from named terminal buffer')
  local liveDest=current(hw,op.destination)
  check(not exists(liveDest.patterns[op.destination.slot]),'Destination filled during edit')
  transfer(hw,endpoint(op.buffer,op.slot),op.destination)
  local after=current(hw,op.destination).patterns[op.destination.slot]
  check(semantic(hw,after,goal),'Destination read-back failed')
  check(not exists(direct(hw,'getInterfacePattern',op.slot)),'Buffer slot did not empty')
  if progress then progress('Verified pattern in destination slot '..(op.destination.slot+1)) end
end
local function saveOp(hw,op)
  check(not fs.exists(paths.pending),'An unfinished operation needs Recover first')
  op.version=1; op.direct=hw.direct.address; op.terminal=hw.terminal.address; op.data=hw.data.address; op.buffer=clone(hw.buffer)
  writeFile(paths.pending,op)
end
local function clearOp() check(fs.remove(paths.pending),'Cannot clear completed recovery record') end
local function apply(c,plan,progress,control)
  check(not fs.exists(paths.pending),'Use Recover before applying another scan')
  check(#plan.errors==0,'Resolve scan blockers first')
  local fresh,hw=scan(c,progress,control)
  check(eq(fresh,plan),'Patterns or destinations changed since preview. Scan again.')
  fresh=nil
  writeFile(paths.backup,{config=clone(c),plan=plan})
  local workspace=plan.empty[1]
  for _,r in ipairs(plan.recipes) do
    if not r.existing then
      local op={kind='recipe',slot=r.donor.slot,original=r.donor.original,destination=r.destination,input=r.input,output=r.output}
      -- Recheck the exact disposable pattern before writing the intent.
      check(patternEq(hw.data,direct(hw,'getInterfacePattern',op.slot),op.original),'Buffer pattern changed')
      saveOp(hw,op); finish(hw,op,progress); clearOp(); workspace=workspace or op.slot
    end
  end
  for _,v in ipairs(plan.changes) do
    -- One fresh snapshot per interface, used only for this target operation.
    -- Check only the recipes used by this target, not the batch's full manifest.
    local required={}
    for _,e in ipairs(v.edits) do required[identity(hw.data,e.after)]=true end
    local snapshots={}
    for _,r in ipairs(plan.recipes) do
      if required[identity(hw.data,r.output)] then
        local e=r.existing or r.destination;local key=where(e)
        if not snapshots[key] then snapshots[key]=current(hw,e) end
        check(pureRecipe(hw.data,snapshots[key].patterns[e.slot],r),'Rename recipe removed or changed; scan again')
      end
    end
    check(workspace~=nil,'No free buffer slot')
    local op={kind='edit',slot=workspace,original=v.original,edits=v.edits,destination=endpoint(plan.target,v.slot)}
    check(not exists(direct(hw,'getInterfacePattern',workspace)),'Buffer workspace occupied')
    saveOp(hw,op); finish(hw,op,progress); clearOp()
  end
end
local function recover(c,progress,control)
  local op=check(readFile(paths.pending),'No pending operation')
  local hw=connect(c,progress,control); finish(hw,op,progress); clearOp()
end
C.apply=apply; C.recover=recover; C.paths=paths; C.finish=finish

local Planner=(function()
-- Source: maker/planner.lua
-- Pure pattern placement planner. No component, filesystem or UI calls.
-- Recipe modes provide an ordered manifest; adapters provide compact snapshots.
local M={version=1}
local U=U
local copy,integer,need,sequence,encoded=U.clone,U.integer,U.check,U.sequence,U.canonical
local ref,place,ordered=U.endpoint,U.where,U.ordered
local function address(r) return place(r)..':'..r.slot end
local function validateSnapshot(snapshot)
  need(type(snapshot)=='table' and type(snapshot.interfaces)=='table','Missing interface snapshot')
  sequence(snapshot.interfaces,'Interfaces')
  local interfaces,seen={},{}
  for _,i in ipairs(snapshot.interfaces) do
    need(type(i.location)=='table','Missing interface location')
    for _,k in ipairs({'dimId','x','y','z'}) do need(integer(i.location[k]),'Invalid location '..k) end
    need(integer(i.side) and i.side>=0 and i.side<=6,'Invalid interface side')
    need(integer(i.capacity) and i.capacity>=1 and i.capacity<=512,'Usable capacity must be 1..512')
    need(type(i.name)=='string' and i.name~='','Missing exact interface name')
    need(i.role=='destination' or i.role=='donor' or i.role=='workspace','Invalid interface role')
    local id=place(i);need(not seen[id],'Overlapping interface roles or duplicate location: '..id);seen[id]=true
    need(type(i.patterns)=='table','Missing pattern snapshot')
    for slot,p in pairs(i.patterns) do
      need(integer(slot) and slot>=0,'Invalid zero-based pattern slot')
      need(type(p)=='table' and type(p.fingerprint)=='string' and p.fingerprint~='','Missing pattern fingerprint')
      need(p.kind=='crafting' or p.kind=='processing' or p.kind=='unknown','Invalid pattern type')
      need(p.recipeKey==nil or type(p.recipeKey)=='string','Invalid recipe key')
      need(p.donor==nil or type(p.donor)=='boolean','Invalid disposable-donor flag')
    end
    interfaces[#interfaces+1]=i
  end
  table.sort(interfaces,ordered)
  return interfaces
end

-- Processing recipes compare multisets; crafting recipes compare exact grid
-- positions. Amounts, item NBT and substitution policy remain part of identity.
function M.recipeKey(recipe)
  need(recipe.kind=='crafting' or recipe.kind=='processing','Recipe kind must be explicit')
  local function entries(list,grid)
    need(type(list)=='table','Missing recipe ingredients')
    local r={}
    for index,s in pairs(list) do
      need(integer(index) and index>=1 and index<=512,'Invalid recipe entry index')
      need(type(s)=='table' and type(s.name)=='string' and s.name~='','Missing registry name')
      need(s.type=='item' or s.type=='fluid','Ingredient type must be explicit')
      local n=s.size
      need(integer(n) and n>0,'Ingredient quantity must be a positive integer')
      if s.type=='item' then need(integer(s.damage) and s.damage>=0,'Missing item damage') end
      need(s.tag==nil or type(s.tag)=='string','NBT must be an exact encoded tag string')
      local id=encoded({s.type,s.name,s.damage or false,s.tag or false})
      if grid then
        need(index<=9 and s.type=='item' and n==1,'Crafting inputs must be individual items in a 3x3 grid')
        r[index]={id,n}
      else r[id]=(r[id] or 0)+n end
    end
    need(next(r)~=nil,'Empty ingredient list')
    return r
  end
  need(recipe.substitute==nil or type(recipe.substitute)=='boolean','Invalid substitution policy')
  need(recipe.beSubstitute==nil or type(recipe.beSubstitute)=='boolean','Invalid output substitution policy')
  return encoded({recipe.kind,entries(recipe.inputs,recipe.kind=='crafting'),entries(recipe.outputs,false),
    recipe.substitute==true,recipe.beSubstitute==true})
end

function M.plan(request,snapshot,checkpoint)
  need(type(request)=='table' and type(request.recipes)=='table','Missing ordered recipe manifest')
  sequence(request.recipes,'Recipes')
  need(#request.recipes>0,'Manifest contains no recipes')
  local interfaces=validateSnapshot(snapshot)
  local p={version=1,errors={},layout={},moves={},creates={},preserved={},reused=0,required={crafting=0,processing=0},
    available={crafting=0,processing=0}}
  local problems={}
  local function block(message) if not problems[message] then p.errors[#p.errors+1]=message;problems[message]=true end end
  local groups,donors,workspace,tokens,occupied={},{crafting={},processing={}},nil,{},{}
  for _,i in ipairs(interfaces) do
    if checkpoint then checkpoint() end
    for slot in pairs(i.patterns) do
      if slot>=i.capacity then block('Pattern outside configured usable capacity: '..i.name..' slot '..slot) end
    end
    if i.role=='destination' then
      local g=groups[i.name] or {slots={},tokens={},wanted={}};groups[i.name]=g
      for slot=0,i.capacity-1 do
        local e=ref(i,slot);g.slots[#g.slots+1]=e
        local pattern=i.patterns[slot]
        if pattern then
          local t={pattern=pattern,current=e};tokens[#tokens+1]=t;g.tokens[#g.tokens+1]=t;occupied[address(e)]=t
        end
      end
    elseif i.role=='donor' then
      for slot=0,i.capacity-1 do
        local pattern=i.patterns[slot]
        if pattern and pattern.donor and donors[pattern.kind] then
          local list=donors[pattern.kind];list[#list+1]={from=ref(i,slot),fingerprint=pattern.fingerprint}
        end
      end
    else
      for slot=0,i.capacity-1 do
        if not i.patterns[slot] and not workspace then workspace=ref(i,slot) end
      end
    end
  end
  local seen,groupOrder={},{}
  for _,r in ipairs(request.recipes) do
    if checkpoint then checkpoint() end
    need(type(r.key)=='string' and r.key~='' and not seen[r.key],'Recipe keys must be unique and nonempty')
    need(type(r.destination)=='string' and r.destination~='','Missing recipe destination group')
    need(r.kind=='crafting' or r.kind=='processing','Invalid requested pattern type')
    seen[r.key]=true
    local g=groups[r.destination]
    if not g then block('No destination interfaces named '..r.destination)
    else
      if #g.wanted==0 then groupOrder[#groupOrder+1]=g end
      g.wanted[#g.wanted+1]=r
    end
  end
  for _,g in ipairs(groupOrder) do
    if checkpoint then checkpoint() end
    for n,r in ipairs(g.wanted) do
      if checkpoint then checkpoint() end
      local match
      for _,t in ipairs(g.tokens) do
        if not t.selected and t.pattern.recipeKey==r.key and t.pattern.kind==r.kind then match=t;break end
      end
      local dest=g.slots[n]
      local entry={key=r.key,kind=r.kind,destination=dest,existing=match~=nil};p.layout[#p.layout+1]=entry
      if match then match.selected=true;match.goal=dest;p.reused=p.reused+1
      else p.required[r.kind]=p.required[r.kind]+1 end
    end
    local n=#g.wanted
    for _,t in ipairs(g.tokens) do
      if not t.selected then
        n=n+1;t.goal=g.slots[n];p.preserved[#p.preserved+1]={from=t.current,to=t.goal,fingerprint=t.pattern.fingerprint}
      end
    end
    if n>#g.slots then block('Insufficient capacity in '..g.wanted[1].destination..': need '..n..', have '..#g.slots) end
  end
  for kind,list in pairs(donors) do
    p.available[kind]=#list
    if #list<p.required[kind] then block('Need '..p.required[kind]..' disposable '..kind..' donors; have '..#list) end
  end
  local needsMoves=false
  for _,t in ipairs(tokens) do if t.goal and address(t.current)~=address(t.goal) then needsMoves=true end end
  if (needsMoves or p.required.crafting+p.required.processing>0) and not workspace then
    block('Leave an empty slot in the dedicated editing/workspace interface')
  end
  -- A blocked plan never contains executable operations.
  if #p.errors>0 then return p end
  local function move(t,to)
    need(not occupied[address(to)],'Planner attempted to overwrite an occupied slot')
    p.moves[#p.moves+1]={from=copy(t.current),to=copy(to),fingerprint=t.pattern.fingerprint}
    occupied[address(t.current)]=nil;occupied[address(to)]=t;t.current=to
  end
  while true do
    if checkpoint then checkpoint() end
    local stuck,advanced=nil,false
    for _,t in ipairs(tokens) do
      if t.goal and address(t.current)~=address(t.goal) then
        if not occupied[address(t.goal)] then move(t,t.goal);advanced=true else stuck=stuck or t end
      end
    end
    if not stuck then break end
    if not advanced then
      need(not occupied[address(workspace)],'Planner cycle did not release workspace')
      move(stuck,workspace)
    end
  end
  local nextDonor={crafting=0,processing=0}
  for _,entry in ipairs(p.layout) do
    if not entry.existing then
      need(not occupied[address(entry.destination)],'New recipe destination was not cleared')
      local kind=entry.kind;nextDonor[kind]=nextDonor[kind]+1
      local donor=donors[kind][nextDonor[kind]]
      p.creates[#p.creates+1]={key=entry.key,kind=kind,from=copy(donor.from),to=copy(entry.destination),
        workspace=copy(workspace),fingerprint=donor.fingerprint}
    end
  end
  -- Compact baseline used by an executor to reject stale previews before writes.
  p.baseline=encoded({snapshot.terminal,interfaces,request})
  return p
end

function M.revalidate(request,snapshot,preview,checkpoint)
  local fresh=M.plan(request,snapshot,checkpoint)
  need(#fresh.errors==0 and preview.baseline and fresh.baseline==preview.baseline
    and encoded(fresh)==encoded(preview),'Patterns, settings or manifest changed; scan again')
  return fresh
end
M.sequence=sequence
return M

end)()
local Modes=(function()
-- Source: maker/modes.lua
-- Compact runtime recipe compiler. This module has no component/UI calls.
-- Eligibility uses form capabilities, production flags and rare exceptions.
local U=U
local Planner=Planner
local M={}
local aliases={rod='stick',rodLong='stickLong',gear='gearGt',gearSmall='gearGtSmall',
  casing='itemCasing',springLarge='spring',frameBox='frameGt',boltedCasing='casingBolted',reboltedCasing='casingRebolted'}
local labels={ingot='Ingot',stick='Rod',dust='Dust',wireFine='Fine wire'}
function M.supports(data,material,form)
  form=aliases[form] or form
  return U.check(data.capabilities[material.a],'Unknown capability set')[form]==true
end
function M.resolve(data,material,form)
  form=aliases[form] or form
  U.check(M.supports(data,material,form),'Material does not support '..form)
  local override=(material.overrides or {})[form]
  if override then return U.clone(override) end
  local kind,size=form:match('^(wire)(%d+)$')
  if not kind then kind,size=form:match('^(cable)(%d+)$') end
  if kind then
    local offsets={[1]=0,[2]=1,[4]=2,[8]=3,[12]=4,[16]=5}
    local item=U.check(material.conductor,'Missing conductor resolver')
    local offset=U.check(offsets[tonumber(size)],'Invalid conductor size')
    return {name=item.name,damage=item.base+offset+(kind=='cable' and 6 or 0)}
  end
  local pipe,variant=form:match('^(pipeFluid)(.+)$')
  if not pipe then pipe,variant=form:match('^(pipeItemRestrictive)(.+)$') end
  if not pipe then pipe,variant=form:match('^(pipeItem)(.+)$') end
  if pipe then
    local offsets={Tiny=0,Small=1,Medium=2,Large=3,Huge=4,Quadruple=5,Nonuple=6}
    local item=U.check(material[pipe],'Missing pipe resolver')
    return {name=item.name,damage=item.base+U.check(offsets[variant],'Invalid pipe size')}
  end
  local family=U.check(data.families[material.family],'Unknown resolver family')
  local item=U.check(family[form],'Missing form resolver')
  if item.template then return {name=item.template:gsub('%%s',material.dsf),damage=0} end
  U.check(U.integer(material.dsf),'Material has no metadata suffix')
  return {name=item.name,damage=item.prefix+material.dsf}
end
function M.eligible(data,material,rule)
  if (material.deny or {})[rule.id] then return false end
  if rule.mode=='coating' then
    if material.coating~=rule.coating then return false end
  elseif not (data.production[material.p] or {})[rule.process] then return false end
  for _,form in ipairs(rule.requires) do if not M.supports(data,material,form) then return false end end
  return true
end
function M.compile(data,mode,options,checkpoint)
  options=options or {}
  U.check(data.version==2,'Unsupported material matrix')
  U.check(mode=='wiremill' or mode=='coating','Mode has no verified recipe rules yet')
  local manifest={version=1,source=U.clone(data.source),policy={mode=mode,pvc=options.pvc~=false,pps=options.pps~=false},recipes={}}
  local seen,unresolved={},{}
  manifest.unresolved={}
  for _,material in ipairs(data.materials) do
    if checkpoint then checkpoint() end
    for _,rule in ipairs(data.rules) do
      if rule.mode==mode and M.eligible(data,material,rule) then
        local function resolve(e,stocked)
          local item
          if e.f then item=M.resolve(data,material,e.f)
          else item=U.clone(U.check(data.items[e.i],'Unknown shared item')) end
          if item.option and options[item.option]==false and not stocked then return nil end
          item.option=nil;item.type='item';item.size=e.n
          U.check(U.integer(item.size) and item.size>0,'Invalid ingredient quantity')
          -- Oracle IDs are normalized to lower case. GT/Minecraft families above
          -- have known spelling; other families still need a registry resolver.
          if not item.name:match('^gregtech:') and not item.name:match('^minecraft:') and not unresolved[item.name] then
            unresolved[item.name]=true;manifest.unresolved[#manifest.unresolved+1]=item.name
          end
          return item
        end
        local out=rule.outputs[1]
        local label=labels[out.f] or out.f or 'item'
        local kind,size=label:match('^(%a+)(%d+)$')
        if kind=='wire' or kind=='cable' then label=size..'x '..(kind=='wire' and 'Wire' or 'Cable') end
        local source=rule.inputs[1].f
        local route=mode=='wiremill' and (' / from '..(labels[source] or source)) or ''
        local recipe={kind='processing',inputs={},outputs={},label=material.name..' / '..label..route,stock={}}
        for _,which in ipairs({'inputs','outputs'}) do
          for _,e in ipairs(rule[which]) do
            local item=resolve(e)
            if item then recipe[which][#recipe[which]+1]=item
            else recipe.stock[#recipe.stock+1]=resolve(e,true) end
          end
        end
        for _,e in ipairs(rule.stock or {}) do
          recipe.stock[#recipe.stock+1]=e.fluid and U.clone(e) or resolve(e,true)
        end
        U.check(#recipe.inputs>0 and #recipe.outputs>0,'Rule contains no consumed solids')
        local key=Planner.recipeKey(recipe)
        if not seen[key] then manifest.recipes[#manifest.recipes+1]=recipe;seen[key]=recipe
        elseif U.canonical(seen[key].stock)~=U.canonical(recipe.stock) then
          local existing=seen[key]
          existing.stockAlternatives=existing.stockAlternatives or {}
          existing.stockAlternatives[#existing.stockAlternatives+1]=recipe.stock
        end
      end
    end
  end
  U.check(#manifest.recipes>0,'No verified recipes for this mode')
  return manifest
end
return M

end)()
-- Source: maker/scan.lua
-- Read-only OC adapter. Donor banks are discovered by exact terminal name.
-- Pattern reads are performed one interface at a time; metadata discovery never
-- converts an entire network's pattern inventories into Lua tables.
local function discover(hw,name) return lookup(hw,name,true) end
local function patternRecipe(data,p)
  check(type(p.tag)=='string','Pattern NBT hidden; enable allowItemStackNBTTags')
  local root=nbt(data,p.tag).__value
  local crafting=truth(p.isCraftable)
  check(p.isCraftable~=nil and p.inputs and p.outputs,'Unsupported encoded pattern')
  local r={kind=crafting and 'crafting' or 'processing',inputs={},outputs={},
    substitute=root.substitute and truth(root.substitute.__value) or false,
    beSubstitute=root.beSubstitute and truth(root.beSubstitute.__value) or false}
  for _,which in ipairs({'inputs','outputs'}) do
    for index,s in pairs(p[which]) do
      if exists(s) then
        check(not truth(s.hasTag) or type(s.tag)=='string','Ingredient NBT hidden')
        r[which][index]={type=s.damage~=nil and s.amount==nil and 'item' or 'fluid',
          name=s.name,damage=s.damage,size=s.amount or s.size,tag=s.tag}
      end
    end
  end
  return r
end
local function scanManifest(c,manifest,routing,progress,control,started)
  validate(c);if not started then startWork(c,progress,control) end
  local groups={{name=routing.destination,role='destination',slots=routing.slots},
    {name=routing.donors,role='donor',slots=routing.donorSlots},
    {name=routing.workspace,role='workspace',slots=routing.workspaceSlots}}
  check(manifest.version==1 and type(manifest.recipes)=='table','Unsupported manifest schema')
  Planner.sequence(manifest.recipes,'Recipes')
  check(type(manifest.source)=='table' and type(manifest.source.recipeVersion)=='string'
    and type(manifest.source.targetVersion)=='string','Manifest must identify recipe and target versions')
  local hw={terminal=selectDevice('me_interface_terminal',c.terminalAddress),data=selectDevice('data',c.dataAddress)}
  local snapshot={terminal=hw.terminal.address,interfaces={}}
  local names={}
  for _,g in ipairs(groups) do
    check(type(g.name)=='string' and g.name~='' and not names[g.name],'Configured interface names must be unique')
    check(g.role=='destination' or g.role=='donor' or g.role=='workspace','Invalid group role')
    check(type(g.slots)=='number' and g.slots>=1 and g.slots<=512 and g.slots==math.floor(g.slots),'Set usable group slots to 1..512')
    names[g.name]=true
    local found=discover(hw,g.name)
    for _,entry in ipairs(found) do
      local i=current(hw,endpoint(entry))
      check(i.name==g.name,'Interface renamed while scanning; scan again')
      local compacted={name=i.name,location=clone(i.location),side=side(i.side),role=g.role,capacity=g.slots,patterns={}}
      for slot,p in pairs(i.patterns or {}) do
        if exists(p) then
          check(type(p.tag)=='string','Pattern NBT hidden in '..g.name)
          local value={kind='unknown',fingerprint=canonical({p.name,p.damage,p.size,invoke(hw.data,'sha256',p.tag)})}
          if p.name=='appliedenergistics2:item.ItemEncodedPattern' and p.isCraftable~=nil and p.inputs and p.outputs then
            local r=patternRecipe(hw.data,p)
            value.kind=r.kind
            local valid,key=pcall(Planner.recipeKey,r)
            if valid then value.recipeKey=key end
            value.donor=valid and not r.substitute and not r.beSubstitute
          end
          compacted.patterns[slot]=value
        end
      end
      snapshot.interfaces[#snapshot.interfaces+1]=compacted
      if progress then progress('Read '..i.name..' at '..U.locationText(i)) end
      check(computer.freeMemory()>160000,'Low memory while collecting compact interface snapshot')
    end
  end
  local request={recipes={},source=clone(manifest.source),policy=clone(manifest.policy or {}),unresolved=clone(manifest.unresolved)}
  local labels={}
  for _,r in ipairs(manifest.recipes) do
    local key=Planner.recipeKey(r)
    request.recipes[#request.recipes+1]={key=key,kind=r.kind,destination=routing.destination,
      stock=clone(r.stock),stockAlternatives=clone(r.stockAlternatives)}
    labels[key]=r.label or r.id or r.outputs[1].name
  end
  local plan=Planner.plan(request,snapshot,function()
    gate();check(computer.freeMemory()>160000,'Low memory while planning')
  end)
  return plan,snapshot,request,labels
end
local function describe(e)
  if not e then return '(no available slot)' end
  return U.locationText(e)..' slot '..e.slot
end
local function previewReport(plan,manifest,labels)
  local details={}
  local function ingredients(list)
    local out={}
    for _,s in ipairs(list or {}) do
      out[#out+1]=tostring(s.size or s.n)..'x '..(s.fluid or (s.name..':'..s.damage))
    end
    return table.concat(out,', ')
  end
  for _,recipe in ipairs(manifest.recipes) do details[Planner.recipeKey(recipe)]=recipe end
  local lines={'PATTERN MAKER / PREVIEW','Recipe source: '..manifest.source.recipeVersion..
    ' | target: '..manifest.source.targetVersion,'Slots below are ZERO based; configured capacities must match unlocked rows.',
    'Workspace connectivity is not verified by this read-only tool.'}
  if manifest.source.excludedRecipes then lines[#lines+1]='Unsupported source recipes excluded: '..manifest.source.excludedRecipes end
  for _,name in ipairs(manifest.unresolved or {}) do lines[#lines+1]='UNVERIFIED registry spelling: '..name end
  lines[#lines+1]='Fluids, circuits and omitted PVC/PPS require external stocking; alternatives use the listed primary item.'
  lines[#lines+1]=string.format('Reuse %d | Create %d processing + %d crafting | Preserve %d unrelated/duplicate patterns',
    plan.reused,plan.required.processing,plan.required.crafting,#plan.preserved)
  for _,err in ipairs(plan.errors) do lines[#lines+1]='BLOCKED: '..err end
  lines[#lines+1]='FINAL LAYOUT (material and rule order)'
  for _,r in ipairs(plan.layout) do
    lines[#lines+1]=(r.existing and 'REUSE ' or 'CREATE ')..labels[r.key]..' -> '..describe(r.destination)
    local recipe=details[r.key]
    lines[#lines+1]='  '..ingredients(recipe.inputs)..' -> '..ingredients(recipe.outputs)
    if recipe.stock and #recipe.stock>0 then lines[#lines+1]='  External: '..ingredients(recipe.stock) end
    if recipe.stockAlternatives then lines[#lines+1]='  Other external-stock alternatives: '..#recipe.stockAlternatives end
  end
  lines[#lines+1]='SORT EXISTING PATTERNS FIRST'
  for _,m in ipairs(plan.moves) do lines[#lines+1]=describe(m.from)..' -> '..describe(m.to) end
  for _,m in ipairs(plan.preserved) do lines[#lines+1]='PRESERVE '..describe(m.from)..' -> '..describe(m.to) end
  lines[#lines+1]='THEN IMPRINT AND INSTALL (not executed in this release)'
  for _,m in ipairs(plan.creates) do
    lines[#lines+1]=labels[m.key]..': donor '..describe(m.from)..' via '..describe(m.workspace)..' -> '..describe(m.to)
  end
  return table.concat(lines,'\n')..'\n'
end

C.maker={planner=Planner,scan=scanManifest,report=previewReport,discover=discover}
function C.maker.preview(c,progress,control)
  validate(c);startWork(c,progress,control)
  check(c.makerDestination~='' and c.makerDonors~='' and c.makerWorkspace~='',
    'Set destination, donor bank and workspace names in Maker setup')
  local manifest=Modes.compile(require('assline_data'),c.makerMode,
    {pvc=c.makerPVC=='on',pps=c.makerPPS=='on'},gate)
  local plan,_,_,labels=scanManifest(c,manifest,{destination=c.makerDestination,donors=c.makerDonors,
    workspace=c.makerWorkspace,slots=tonumber(c.makerSlots),donorSlots=tonumber(c.makerDonorSlots),
    workspaceSlots=tonumber(c.makerWorkspaceSlots)},progress,control,true)
  return plan,previewReport(plan,manifest,labels)
end

-- Source: src/30_ui.lua
local function runUI()
  local gpu=component.gpu; check(gpu,'GPU required')
  local term=require('term'); local keyboard=require('keyboard')
  local oldW,oldH=gpu.getResolution(); local oldFG=gpu.getForeground(); local oldBG=gpu.getBackground()
  local maxW,maxH=gpu.maxResolution(); check(maxW>=160 and maxH>=50,'Use a tier 3 GPU and screen with 160x50 resolution')
  local w,h=math.min(160,maxW),math.min(50,maxH)
  local colors={bg=0x101A26,panel=0x1A2A3C,text=0xDCE6EF,muted=0x8297AB,blue=0x5AC8FA,
    green=0x72D69A,yellow=0xFFD277,red=0xFF8585,button=0x27465E}
  local state={page='main',offset=0,section='changes',status='Enter a target, then Scan to preview changes.',tone='muted',running=true}
  local fields={
    {'buffer','Buffer interface name','Exact terminal display name of the directly connected interface.'},
    {'itemName','Item name template','{label} = original display name; {n} = duplicate number starting at 1.'},
    {'renameName','Rename interface template','Examples: Rename NAME_{n} or Rename {label}_{n}. Same names can span interfaces.'},
    {'bufferSlots','Usable buffer slots','Visible/unlocked pattern slots. Default 9; set 36 when all rows are available.'},
    {'renameSlots','Usable rename slots','Slots to use on each rename interface. Default 9; set 36 with capacity upgrades.'},
    {'terminalAddress','Terminal component address','Blank selects the only me_interface_terminal; otherwise paste an address/prefix.'},
    {'bufferAddress','Buffer component address','Blank selects the only me_interface; use an address/prefix if there are several.'},
    {'dataAddress','Data Card address','Blank selects the only data component. Tier 1 is sufficient.'},
    {'energyPause','Pause work below energy %','Default 25. Work waits for the resume level before continuing.'},
    {'energyResume','Resume work at energy % (default 75)','Must be at least 10 percentage points above the pause threshold.'}}
  local buttons={}; local edit
  local makerFields={
    {'makerDestination','Destination name','Exact name; all matching remote interfaces share the layout.'},
    {'makerDonors','Donor bank name','Exact name; all matching banks supply encoded donors.'},
    {'makerWorkspace','Editing/workspace name','Dedicated interface with an empty pattern slot.'},
    {'makerSlots','Destination slots per interface','Configured unlocked capacity, 1..512.'},
    {'makerDonorSlots','Donor slots per interface','Configured unlocked capacity, 1..512.'},
    {'makerWorkspaceSlots','Workspace slots per interface','Configured unlocked capacity, 1..512.'},
    {'makerPVC','Request PVC (on/off)','Consumed PVC only. Fluids and catalysts stay externally stocked.'},
    {'makerPPS','Request PPS (on/off)','Consumed PPS only; independent of PVC.'}}
  local paintKey,paintCache=nil,{}
  local contentKey,contentRows
  local function text(x,y,s,width,tone,bg)
    width=math.min(width or w-x+1,w-x+1); if width<1 then return end
    s=tostring(s or ''):gsub('\194\167.',''):gsub('[%c]',' ')
    s=unicode.sub(s,1,width)
    local key=x..':'..y..':'..width;local value=s..':'..tostring(tone)..':'..tostring(bg)
    if paintCache[key]==value then return end
    paintCache[key]=value
    gpu.setForeground(colors[tone or 'text']); gpu.setBackground(colors[bg or 'bg'])
    gpu.set(x,y,s..string.rep(' ',math.max(0,width-unicode.wlen(s))))
  end
  local function button(x,y,label,action,enabled)
    local length=unicode.len(label)+4
    text(x,y,'[ '..label..' ]',length,enabled==false and 'muted' or 'text','button')
    if enabled~=false then buttons[#buttons+1]={x=x,y=y,w=length,action=action} end
    return x+length+2
  end
  local location=U.locationText
  local function description(s) return tostring(s.size or '?')..' x '..tostring(s.label or s.name) end
  local function lines()
    local r={}; local p=state.plan
    local function add(s,tone) r[#r+1]={s,tone or 'text'} end
    if state.error then add('LAST ERROR','red');add(state.error,'red');add('') end
    if state.section=='maker' then
      if state.makerReport then for line in state.makerReport:gmatch('[^\n]+') do add(line) end
      else add('Open Maker setup, choose a mode and interface names, then Preview.','muted') end
    elseif state.section=='history' then
      add('RECENT OPERATIONS (newest first)','blue')
      add('/home/assline-perf.log; showing up to 16 KB.','muted');add('')
      for _,line in ipairs(state.history or {}) do add(line) end
      if not state.history or #state.history==0 then add('No operations recorded yet.','muted') end
    elseif state.section=='help' then
      add('SETUP','blue');add('Tier 3 screen/GPU, keyboard, 2 MB+ RAM, tier 1+ Data Card.')
      add('Connect the terminal and adapter-connected buffer to the same AE grid.')
      add('Use disposable encoded PROCESSING donors. Crafting donors are skipped.')
      add('Keep machines idle and buffer isolated from machinery. Enable allowItemStackNBTTags.')
      add('');add('WORKFLOW','blue');add('Set exact names and usable slot limits. Scan, review both tabs, then Apply.')
      add('Rename recipes install first. Edited targets return to their original slots.')
      add('');add('RECOVERY','yellow');add('After interruption, leave patterns in place and Recover; then Scan again.')
      add('Recovery stops on foreign edits. Pending: /home/assline.pending; backup: /home/assline.last.')
      add('History shows recent timing, charge and memory reports from /home/assline-perf.log.')
    elseif not p then
      add('Nothing scanned yet. Scan to see exactly what will change.','muted')
      add('Example: rod, 128 wire, 128 wire, 128 wire','muted')
      add('Result:  rod, 128 wire, 128 NAME_1, 128 NAME_2','green')
      add('The first occurrence stays unchanged. Numbering starts over in each pattern.','muted')
    elseif state.section=='recipes' then
      for _,v in ipairs(p.recipes) do
        add((v.existing and 'REUSE  ' or 'CREATE ')..v.name,v.existing and 'green' or 'yellow')
        add('  '..description(v.input)..' -> '..description(v.output))
        local e=v.existing or v.destination
        if e then add('  Slot '..(e.slot+1)..' at '..location(e),'muted') end
        if v.donor then add('  Consumes buffer pattern slot '..(v.donor.slot+1),'yellow') end
      end
      if #p.recipes==0 then add('No rename recipes required.','green') end
    else
      for _,v in ipairs(p.changes) do
        local out=v.original.outputs[1]
        add('PATTERN '..(v.slot+1)..'  '..(out and description(out) or '(no first output)'),'blue')
        for _,e in ipairs(v.edits) do
          add('  Input '..e.index..': '..description(e.before))
          add('        -> '..description(e.after),'green')
        end
      end
      if #p.changes==0 then add('No duplicate item inputs found.','green') end
    end
    return r
  end
  local draw,action,handle,commitEdit
  local function startEdit(key,draft,cursor)
    local values=draft and state.draft or cfg
    if not edit or edit.key~=key or edit.draft~=draft then
      edit={key=key,value=values[key],draft=draft}
    end
    edit.cursor=math.max(1,math.min(cursor,unicode.len(edit.value)+1));edit.selectAll=false
  end
  local function editorRow(x,y,width,key,draft)
    local values=draft and state.draft or cfg; local val=values[key]
    local first,cursor=1,nil
    if edit and edit.key==key then
      first=math.max(1,edit.cursor-width+3);cursor=edit.cursor
      val=unicode.sub(edit.value,first,edit.cursor-1)..'|'..unicode.sub(edit.value,edit.cursor)
      text(x,y,val,width,edit.selectAll and 'yellow' or 'blue','panel')
    else text(x,y,val=='' and (key:match('^maker') and '(required)' or '(automatic)') or val,width,'text','panel') end
    if state.busy then return end
    buttons[#buttons+1]={x=x,y=y,w=width,editKey=key,draft=draft,action=function(clickX)
      local at=first+clickX-x
      if cursor and at>cursor then at=at-1 end -- Account for the visible cursor glyph.
      startEdit(key,draft,at)
    end}
  end
  draw=function()
    local key=state.page..state.section..tostring(state.plan)..tostring(state.makerPlan)..tostring(state.busy)..tostring(state.error)..tostring(fs.exists(paths.pending))
    if key~=paintKey then
      gpu.setBackground(colors.bg);gpu.fill(1,1,w,h,' ');paintCache={};paintKey=key
    end
    buttons={}
    text(2,2,'ASSEMBLY LINE / PATTERN RENAMER',w-4,'blue')
    text(2,3,string.format('GTNH 2.9   |   %.0f%% energy   |   %d KB free',
      energyFraction()*100,math.floor(computer.freeMemory()/1024)),w-4,'muted')
    if state.page=='maker' then
      local x=button(2,5,'Preview',function() action('makerScan') end,not fs.exists(paths.pending))
      x=button(x,5,'Mode: '..state.draft.makerMode,function()
        commitEdit();state.draft.makerMode=state.draft.makerMode=='wiremill' and 'coating' or 'wiremill'
      end)
      button(x,5,'Back',function() state.page='main';edit=nil end)
      for i,f in ipairs(makerFields) do
        local y=7+(i-1)*4
        text(3,y,f[2],w-6,'blue');editorRow(3,y+1,w-6,f[1],true);text(3,y+2,f[3],w-6,'muted')
      end
      text(3,42,'Preview only. LATEX, combining and the new mode executor are the next stages.',w-6,'yellow')
    elseif state.page=='settings' then
      local x=button(2,5,'Save settings',function() action('save') end)
      button(x,5,'Cancel',function() state.page='main'; edit=nil end)
      for i,f in ipairs(fields) do
        local y=7+(i-1)*4
        text(3,y,f[2],w-6,'blue'); editorRow(3,y+1,w-6,f[1],true)
        if y+2<h-2 then text(3,y+2,f[3],w-6,'muted') end
      end
    else
      text(2,5,'Target interface',19,'blue'); editorRow(22,5,w-24,'target',false)
      local pending=fs.exists(paths.pending)
      local x=button(2,7,'Scan',function() action('scan') end,not pending and not state.busy)
      x=button(x,7,'Apply preview',function() action('apply') end,state.section~='maker' and state.plan and #state.plan.errors==0 and #state.plan.changes>0 and not pending and not state.busy)
      x=button(x,7,'Settings',function() action('settings') end,not state.busy)
      x=button(x,7,'Recover',function() action('recover') end,pending and not state.busy)
      x=button(x,7,'Quit',function() state.cancelled=true;state.running=false end)
      if state.busy then button(x,7,'Cancel work',function() state.cancelled=true end) end
      if not state.busy then button(x,7,'Maker setup',function() action('makerSettings') end) end
      x=2
      for _,tab in ipairs({{'changes','Input changes'},{'recipes','Rename recipes'},{'help','Setup / help'},{'history','History'},{'maker','Pattern maker'}}) do
        local section=tab[1]
        x=button(x,9,(state.section==section and '* ' or '')..tab[2],function() action(section) end)
      end
      local sideX=math.max(67,w-48); local contentW=sideX-4
      local rowsKey=state.section..tostring(state.plan)..tostring(state.makerPlan)..tostring(state.history)..tostring(state.error)
      if rowsKey~=contentKey then
        contentRows={};contentKey=rowsKey
        for _,r in ipairs(lines()) do
          for pos=1,math.max(1,unicode.len(r[1])),contentW do
            contentRows[#contentRows+1]={unicode.sub(r[1],pos,pos+contentW-1),r[2]}
          end
        end
      end
      local rows=contentRows
      local room=h-14
      state.offset=math.max(0,math.min(state.offset,math.max(0,#rows-room)))
      for n=1,room do local r=rows[state.offset+n];text(2,11+n,r and r[1] or '',contentW,r and r[2] or 'text') end
      text(2,h-2,'Rows '..math.min(#rows,state.offset+1)..'-'..math.min(#rows,state.offset+room)..' / '..#rows..'   (wheel / PgUp / PgDn)',contentW,'muted')
      text(sideX,12,'WHAT WILL HAPPEN',w-sideX-1,'blue')
      local p=state.plan
      if state.section=='maker' and state.makerPlan then
        local m=state.makerPlan
        text(sideX,14,m.reused..' existing patterns reused',w-sideX-1,'green')
        text(sideX,15,#m.layout..' ordered recipe positions',w-sideX-1)
        text(sideX,16,#m.moves..' sorting moves',w-sideX-1)
        text(sideX,17,(m.required.processing+m.required.crafting)..' donors needed',w-sideX-1,'yellow')
        text(sideX,19,#m.errors..' capacity/donor blockers',w-sideX-1,#m.errors==0 and 'green' or 'red')
        text(sideX,21,'Read-only preview; no patterns moved.',w-sideX-1,'yellow')
      elseif p then
        text(sideX,14,p.scanned..' patterns scanned',w-sideX-1)
        text(sideX,15,#p.changes..' patterns to update',w-sideX-1,'green')
        text(sideX,16,p.newRecipes..' buffer patterns to consume',w-sideX-1,'yellow')
        text(sideX,17,(#p.recipes-p.newRecipes)..' existing rename recipes reused',w-sideX-1,'green')
        text(sideX,18,p.skipped..' non-processing patterns skipped',w-sideX-1,'muted')
        local y=21
        if #p.errors==0 then text(sideX,y,'Ready to apply after review.',w-sideX-1,'green')
        else
          text(sideX,y,'BLOCKED: '..#p.errors..' issue(s)',w-sideX-1,'red'); y=y+2
          for _,err in ipairs(p.errors) do
            for pos=1,unicode.len(err),w-sideX-2 do
              if y<h-5 then text(sideX,y,unicode.sub(err,pos,pos+w-sideX-3),w-sideX-1,'red'); y=y+1 end
            end
            y=y+1
          end
        end
      end
      if pending then
        text(sideX,h-6,'UNFINISHED OPERATION',w-sideX-1,'red')
        text(sideX,h-5,'Select Recover before scanning.',w-sideX-1,'yellow')
      end
    end
    text(2,h-1,state.status,w-3,state.tone)
  end
  local lastProgress=0
  local function progress(message)
    if computer.uptime()-lastProgress>=1 then
      state.status=message; state.tone='yellow'; text(2,h-1,message,w-3,'yellow'); lastProgress=computer.uptime()
    end
    -- Recharge waits are handled before component calls by gate().
  end
  local function saveConfig() validate(cfg); writeFile(paths.config,cfg) end
  local function history()
    local f=io.open('/home/assline-perf.log','r');local groups={}
    if f then
      f:seek('set',math.max(0,fs.size('/home/assline-perf.log')-16384))
      local raw=f:read('*a') or '';f:close()
      for block in raw:gmatch('uptime=[^\n]*\n.-\n\n') do groups[#groups+1]=block end
      -- Include the last report, which has no following blank line.
      if #groups==0 or raw:sub(-2)~='\n\n' then
        local last=raw:match('.*\n(uptime=.*)') or (raw:match('^uptime=') and raw)
        if last then groups[#groups+1]=last end
      end
    end
    state.history={}
    for n=#groups,1,-1 do
      for line in groups[n]:gmatch('[^\n]+') do state.history[#state.history+1]=line end
      state.history[#state.history+1]=''
    end
  end
  commitEdit=function()
    if not edit then return end
    local value=trim(edit.value)
    if edit.draft then state.draft[edit.key]=value
    else
      check(value~='','Target name cannot be empty')
      cfg[edit.key]=value; state.plan=nil; saveConfig()
    end
    edit=nil
  end
  local lastPoll=-math.huge
  local function control(delay)
    local pulled
    if delay>0 or computer.uptime()-lastPoll>=0.1 then
      draw()
      local e={event.pull(delay)}
      handle(e);lastPoll=computer.uptime();pulled=e
    end
    check(not state.cancelled,'Work cancelled. Use Recover if an operation is pending; otherwise scan again.')
    return pulled
  end
  action=function(name)
    commitEdit()
    state.error=nil
    state.history=nil
    local isWork=name=='scan' or name=='apply' or name=='recover' or name=='makerScan'
    check(not isWork or not state.busy,'Work already running')
    if isWork then state.busy=true;state.cancelled=false;lastPoll=computer.uptime();state.status='Working: '..name..' (Esc cancels)';state.tone='yellow' end
    local success,why=pcall(function()
    if name=='history' then history();state.section=name;state.offset=0
    elseif name=='changes' or name=='recipes' or name=='help' or name=='maker' then state.section=name;state.offset=0
    elseif name=='makerSettings' then state.page='maker';state.draft=clone(cfg)
    elseif name=='makerScan' then
      validate(state.draft);writeFile(paths.config,state.draft);cfg=state.draft
      state.page='main';state.section='maker';state.offset=0;state.plan=nil;state.makerPlan=nil;state.makerReport=nil
      state.makerPlan,state.makerReport=C.maker.preview(cfg,progress,control)
      state.status='Maker preview complete. Review capacity, sorting and donor requirements.';state.tone='green'
    elseif name=='scan' then
      state.plan=nil; state.offset=0; state.plan=scan(cfg,progress,control)
      state.status='Scan complete. Review Input changes and Rename recipes, then Apply preview.'; state.tone='green'
    elseif name=='apply' then
      check(state.plan,'Scan first'); local p=state.plan; state.plan=nil
      apply(cfg,p,progress,control)
      state.status='Done. Updated '..#p.changes..' patterns and installed '..p.newRecipes..' rename recipes.'; state.tone='green'
    elseif name=='recover' then
      state.plan=nil; recover(cfg,progress,control)
      state.status='Saved operation completed. Scan again to continue the rest of the batch.';state.tone='green'
    elseif name=='settings' then state.page='settings';state.draft=clone(cfg)
    elseif name=='save' then
      validate(state.draft); writeFile(paths.config,state.draft); cfg=state.draft;state.plan=nil;state.page='main'
      state.status='Settings saved. Scan to build a new preview.';state.tone='green'
    end
    end)
    if isWork then state.busy=false end
    check(success,why)
    if isWork then
      local ok,why=pcall(perfReport,name..' complete');releaseWork();check(ok,why)
      if state.section=='history' then history() end
    end
  end
  local function insert(s)
    s=s:gsub('[\r\n]',' '):gsub('%z','')
    if edit.selectAll then edit.value='';edit.cursor=1;edit.selectAll=false end
    edit.value=unicode.sub(edit.value,1,edit.cursor-1)..s..unicode.sub(edit.value,edit.cursor)
    edit.cursor=edit.cursor+unicode.len(s)
  end
  handle=function(e)
    if e[1]=='interrupted' then state.cancelled=true;state.running=false
    elseif e[1]=='touch' then
      for _,b in ipairs(buttons) do
        if e[3]>=b.x and e[3]<b.x+b.w and e[4]==b.y then
          if edit and (b.editKey~=edit.key or b.draft~=edit.draft) then commitEdit() end
          b.action(e[3],e[4]); break
        end
      end
    elseif e[1]=='scroll' and not edit then state.offset=state.offset-e[5]*3
    elseif e[1]=='clipboard' and edit then insert(e[3])
    elseif e[1]=='key_down' then
      local char,key=e[3],e[4]
      if state.busy and (key==1 or char==113) then
        state.cancelled=true;if char==113 then state.running=false end
      elseif edit then
        if key==28 then commitEdit()
        elseif key==1 then edit=nil
        elseif key==30 and keyboard.isControlDown() then edit.selectAll=true
        elseif key==203 then edit.cursor=math.max(1,edit.cursor-1);edit.selectAll=false
        elseif key==205 then edit.cursor=math.min(unicode.len(edit.value)+1,edit.cursor+1);edit.selectAll=false
        elseif key==199 then edit.cursor=1;edit.selectAll=false
        elseif key==207 then edit.cursor=unicode.len(edit.value)+1;edit.selectAll=false
        elseif key==14 or key==211 then
          if edit.selectAll then edit.value='';edit.cursor=1;edit.selectAll=false
          else
            local at=key==14 and edit.cursor-1 or edit.cursor
            if at>=1 then edit.value=unicode.sub(edit.value,1,at-1)..unicode.sub(edit.value,at+1);edit.cursor=at end
          end
        elseif char and char>=32 and not keyboard.isControlDown() then insert(unicode.char(char)) end
      elseif key==201 then state.offset=state.offset-(h-14)
      elseif key==209 then state.offset=state.offset+(h-14)
      elseif state.page=='main' then
        if char==115 and not state.busy and not fs.exists(paths.pending) then action('scan')
        elseif char==97 and state.section~='maker' and not state.busy and state.plan and #state.plan.errors==0 and #state.plan.changes>0 then action('apply')
        elseif char==113 then state.running=false end
      end
    end
  end
  local ok,err=pcall(function()
    gpu.setResolution(w,h)
    local loaded=readFile(paths.config)
    if loaded then for k in pairs(defaults) do if loaded[k]~=nil then cfg[k]=loaded[k] end end;validate(cfg) end
    while state.running do
      draw()
      local e={event.pull(1)}
      local success,why=pcall(handle,e)
      if not success then
        state.status=tostring(why);state.error=state.status;state.offset=0;state.tone='red'
        pcall(perfReport,'stopped: '..state.status);releaseWork()
        if state.section=='history' then pcall(history) end
      end
    end
  end)
  releaseWork();state.plan=nil;state.history=nil;state.draft=nil;state.makerPlan=nil;state.makerReport=nil;buttons={};paintCache={};contentRows=nil;contentKey=nil;edit=nil
  gpu.setResolution(oldW,oldH);gpu.setForeground(oldFG);gpu.setBackground(oldBG);term.clear();term.setCursor(1,1)
  if not ok then error(err,0) end
end
C.runUI=runUI

-- Source: src/90_main.lua
if ...=='--test' then return C end
runUI()

end,table.unpack(args,1,args.n))
package.path=savedPath
if args[1]~='--test' then unload() end
if not ok then error(result,0) end
return result
