-- Pure pattern placement planner. No component, filesystem or UI calls.
-- Recipe modes provide an ordered manifest; adapters provide compact snapshots.
local M={version=1}
local U=require('assline_util')
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
    available={crafting=0,processing=0},donorBanks=0,donorOccupied=0,donorRejected=0,donorReasons={}}
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
      p.donorBanks=p.donorBanks+1
      for slot=0,i.capacity-1 do
        local pattern=i.patterns[slot]
        if pattern then
          p.donorOccupied=p.donorOccupied+1
          if not pattern.donor then
            p.donorRejected=p.donorRejected+1
            local reason=pattern.reason or 'Unsupported pattern'
            p.donorReasons[reason]=(p.donorReasons[reason] or 0)+1
          end
        end
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
      local entry={key=r.key,kind=r.kind,group=r.destination,destination=dest,existing=match~=nil};p.layout[#p.layout+1]=entry
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
