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
