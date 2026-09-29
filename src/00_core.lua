-- GTNH 2.9 / OpenOS. Terminal pattern slots are ZERO based; direct slots ONE based.
local component = require('component')
local event = require('event')
local computer = require('computer')
local fs = require('filesystem')
local serialization = require('serialization')
local unicode = require('unicode')
local C = {}
local U=require('assline_util')
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
