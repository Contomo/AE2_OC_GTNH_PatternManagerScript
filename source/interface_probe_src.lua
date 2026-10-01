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
local shared=config.shared or {}
local assline=config.programs and config.programs.assline or {}
local target=args[1] or assline.target or config.target or 'Advanced Assline (1)'
local editor=shared.editor or config.makerWorkspace or config.buffer or 'OC Pattern Editor'
local buffer=shared.donors or config.makerDonors or 'OC Pattern Buffer'
local out=assert(io.open('/home/interface_probe.txt','w'))
local function log(s)
  s=tostring(s); assert(out:write(s..'\n')); print(s)
end
local function each(result,visit)
  assert(result~=nil,'API returned nil')
  -- Calling the iterator materializes all pattern NBT for each machine.
  -- getAll(false) is the API's metadata-only path, including exact lookups.
  if result.getAll then result=result.getAll(false)
  elseif getmetatable(result) then error('Metadata-only getAll(false) unavailable; refusing full pattern scan') end
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
log('AE INTERFACE VISIBILITY PROBE v2 (metadata only; read only)')
log('Target: '..quote(target))
log('Pattern editor: '..quote(editor))
log('New pattern buffers: '..quote(buffer))
log('Configured terminal prefix: '..quote(shared.terminalAddress or config.terminalAddress or ''))
local count=0
for address,kind in component.list('me_interface_terminal',true) do
  if kind=='me_interface_terminal' then
    count=count+1
    local ok,err=pcall(function()
      local p=component.proxy(address)
      log('\nTERMINAL '..address)
      exact(p,target);exact(p,editor);if buffer~=editor then exact(p,buffer) end
      log('ALL API-VISIBLE INTERFACES (exact names, no pattern NBT):')
      local total=0
      local result=p.getInterfaces()
      log('Result type: '..type(result))
      each(result,function(i)
        total=total+1
        log('  '..quote(i.name)..' '..location(i))
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
