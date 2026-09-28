local artifact=...
local output,files={},{}
local savedPrint=print
print=function(s) output[#output+1]=s end
local function iterator(list)
  local n=0;return setmetatable({},{__call=function() n=n+1;return list[n] end})
end
local function entry(name,x)
  return {name=name,location={x=x,y=64,z=0,dimId=0},side=3,patterns={[0]={name='pattern'}}}
end
local grids={one={entry('OC Buffer',1)},two={entry('Advanced Assline (1)',2),entry('OC Buffer',3)}}
local function proxy(address)
  local entries=grids[address]
  return {
    getInterfaces=function() return iterator(entries) end,
    getInterfacesByName=function(name)
      local r={};for _,i in ipairs(entries) do if i.name==name then r[#r+1]=i end end
      return iterator(r)
    end,
    send=function() error('Probe must not transfer patterns') end
  }
end
package.preload.component=function() return {
  list=function() local n=0;return function() n=n+1;return ({'one','two'})[n],'me_interface_terminal' end end,
  proxy=proxy
} end
package.preload.serialization=function() return {
  unserialize=function() return {target='Advanced Assline (1)',buffer='OC Buffer',terminalAddress='one'} end,
  serialize=function(t) return '{x='..t.x..'}' end
} end
local realOpen=io.open
io.open=function(path,mode)
  if path=='/home/assline.cfg' then return {read=function() return '{}' end,close=function() end} end
  if path~='/home/interface_probe.txt' then return realOpen(path,mode) end
  assert(mode=='w');files[path]=''
  return {write=function(self,s) files[path]=files[path]..s;return self end,flush=function(self) return self end,close=function() end}
end
assert(loadfile(artifact))()
local s=files['/home/interface_probe.txt']
assert(s:find('EXACT "Advanced Assline (1)": 0 match(es)',1,true))
assert(s:find('EXACT "Advanced Assline (1)": 1 match(es)',1,true))
assert(s:find('TERMINAL one',1,true) and s:find('TERMINAL two',1,true))
assert(s:find('"Advanced Assline (1)" {x=2} side=3 occupied=1',1,true))
-- A failing terminal must be reported while another terminal is still examined.
grids.one=nil
assert(loadfile(artifact))('Missing target')
s=files['/home/interface_probe.txt']
assert(s:find('TERMINAL ERROR',1,true) and s:find('TERMINAL two',1,true))
assert(s:find('EXACT "Missing target": 0 match(es)',1,true))
savedPrint('SUCCESS: 2 tests ('..artifact..')')
