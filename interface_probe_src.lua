-- Read-only AE terminal visibility diagnostic. No pattern setters/transfers.
local component=require('component')
local serialization=require('serialization')
local args={...}
local config={}
local f=io.open('/home/assline.cfg','r')
if f then
  local raw=f:read('*a'); f:close()
  local ok,value=pcall(serialization.unserialize,raw or '')
  if ok and type(value)=='table' then config=value end
end
local target=args[1] or config.target or 'Advanced Assline (1)'
local buffer=config.buffer or 'OC Buffer'
local out=assert(io.open('/home/interface_probe.txt','w'))
local function log(s)
  s=tostring(s); assert(out:write(s..'\n')); print(s)
end
local function each(result,visit)
  assert(result~=nil,'API returned nil')
  if type(result)=='table' and not getmetatable(result) then
    for _,entry in pairs(result) do
      if type(entry)=='table' and entry.location then visit(entry) end
    end
  else
    while true do local entry=result(); if not entry then break end; visit(entry) end
  end
end
local function quote(v) return string.format('%q',tostring(v)) end
local function location(i)
  return serialization.serialize(i.location)..' side='..tostring(i.side)
end
local function exact(p,name)
  local count=0
  local ok,err=pcall(function()
    each(p.getInterfacesByName(name),function(i)
      count=count+1
      log('  MATCH '..quote(i.name)..' '..location(i))
    end)
  end)
  log('EXACT '..quote(name)..': '..(ok and tostring(count)..' match(es)' or 'ERROR '..tostring(err)))
end
log('AE INTERFACE VISIBILITY PROBE v1 (read only)')
log('Target: '..quote(target))
log('Buffer: '..quote(buffer))
log('Configured terminal prefix: '..quote(config.terminalAddress or ''))
local count=0
for address,kind in component.list('me_interface_terminal',true) do
  if kind=='me_interface_terminal' then
    count=count+1
    local ok,err=pcall(function()
      local p=component.proxy(address)
      log('\nTERMINAL '..address)
      exact(p,target); exact(p,buffer)
      log('ALL API-VISIBLE INTERFACES (exact names, no pattern NBT):')
      local total=0
      local result=p.getInterfaces()
      log('Result type: '..type(result))
      each(result,function(i)
        total=total+1
        local slots=0
        for _,v in pairs(i.patterns or {}) do
          if type(v)=='table' and v.name then slots=slots+1 end
        end
        log('  '..quote(i.name)..' '..location(i)..' occupied='..slots)
      end)
      log('TOTAL '..total)
    end)
    if not ok then log('TERMINAL ERROR '..tostring(err)) end
  end
end
if count==0 then log('No me_interface_terminal component connected.') end
log('\nOC can see fewer interfaces than the manual GUI: the checked upstream driver')
log('excludes P2P outputs and does not follow pattern provider/repeater links to other grids.')
log('An absent entry cannot be diagnosed as one specific cause from this API alone.')
assert(out:flush());out:close()
print('Saved /home/interface_probe.txt')
