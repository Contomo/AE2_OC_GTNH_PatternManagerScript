package.path='tests/lib/?.lua;'..package.path
local P=assert(loadfile('maker/planner.lua'))()
local function cp(t) if type(t)~='table' then return t end local r={};for k,v in pairs(t) do r[k]=cp(v) end;return r end
local function pat(key,kind,donor) return {fingerprint='nbt:'..key,recipeKey=key,kind=kind or 'processing',donor=donor} end
local function inv(name,x,role,cap,patterns)
  return {name=name,location={dimId=0,x=x,y=64,z=0},side=6,role=role,capacity=cap,patterns=patterns or {}}
end
local function recipe(key,kind,dest) return {key=key,kind=kind or 'processing',destination=dest or 'Target'} end
local function fixture(patterns,cap)
  return {terminal='terminal',interfaces={inv('Target',10,'destination',cap or 3,patterns),
    inv('OC Buffer',20,'donor',3,{[0]=pat('donor1','processing',true),[1]=pat('donor2','crafting',true)}),
    inv('OC Editor',30,'workspace',1)}}
end
local function addr(e) return e.location.x..':'..e.slot end
local function simulate(p,s)
  assert(#p.errors==0,table.concat(p.errors,'; '))
  local state={};for _,i in ipairs(s.interfaces) do for slot,t in pairs(i.patterns) do state[i.location.x..':'..slot]=cp(t) end end
  for _,m in ipairs(p.moves) do
    local from,to=addr(m.from),addr(m.to)
    assert(state[from] and state[from].fingerprint==m.fingerprint,'wrong source')
    assert(not state[to],'overwrite');state[to],state[from]=state[from],nil
  end
  -- Sorting must already have vacated every reserved position before imprinting.
  for _,c in ipairs(p.creates) do assert(not state[addr(c.to)],'creation slot not freed before imprinting') end
  for _,c in ipairs(p.creates) do
    local d=assert(state[addr(c.from)]);assert(d.kind==c.kind and d.donor and d.fingerprint==c.fingerprint)
    assert(not state[addr(c.workspace)]);assert(not state[addr(c.to)])
    state[addr(c.from)]=nil;state[addr(c.to)]=pat(c.key,c.kind)
  end
  for _,l in ipairs(p.layout) do assert(state[addr(l.destination)].recipeKey==l.key,'wrong final layout') end
  for _,u in ipairs(p.preserved) do assert(state[addr(u.to)].fingerprint==u.fingerprint,'foreign pattern lost') end
  return state
end
local n=0
local function test(name,f) local ok,why=pcall(f);assert(ok,name..': '..tostring(why));n=n+1;print('PASS '..name) end
local function fails(f,part) local ok,why=pcall(f);assert(not ok and tostring(why):find(part,1,true),tostring(why)) end

test('complete sorting precedes creates; foreign patterns survive',function()
  local s=fixture({[0]=pat('A'),[1]=pat('foreign')},3)
  local r={recipes={recipe('B'),recipe('A')}};local original=cp(s)
  local p=P.plan(r,s);assert(p.reused==1 and #p.creates==1 and #p.preserved==1)
  simulate(p,s);assert(s.interfaces[1].patterns[0].recipeKey=='A')
  assert(P.plan(r,original).baseline==p.baseline)
end)
test('full destination permutation uses a workspace cycle',function()
  local s=fixture({[0]=pat('B'),[1]=pat('A')},2)
  local p=P.plan({recipes={recipe('A'),recipe('B')}},s)
  assert(#p.moves==3 and #p.creates==0);simulate(p,s)
end)
test('all six-pattern permutations preserve identity',function()
  local values={'A','B','C','D','E','F'};local request={recipes={}}
  for _,key in ipairs(values) do request.recipes[#request.recipes+1]=recipe(key) end
  local count=0
  local function permute(k)
    if k==7 then
      local slots={};for i,v in ipairs(values) do slots[i-1]=pat(v) end
      local s=fixture(slots,6);simulate(P.plan(request,s),s);count=count+1;return
    end
    for i=k,6 do values[k],values[i]=values[i],values[k];permute(k+1);values[k],values[i]=values[i],values[k] end
  end
  permute(1);assert(count==720)
end)
test('same-name interfaces sort by numeric location and spill from slot zero',function()
  local s=fixture({},1);s.interfaces[#s.interfaces+1]=inv('Target',2,'destination',1,{[0]=pat('B')})
  s.interfaces[1].patterns[0]=pat('A')
  local r={recipes={recipe('A'),recipe('B')}};local p=P.plan(r,s)
  assert(p.layout[1].destination.location.x==2 and p.layout[2].destination.location.x==10)
  simulate(p,s)
  local reversed=cp(s);reversed.interfaces={s.interfaces[4],s.interfaces[3],s.interfaces[2],s.interfaces[1]}
  assert(P.revalidate(r,reversed,p).baseline==p.baseline)
end)
test('twenty remote donor banks count processing and crafting separately',function()
  local s=fixture({},36);s.interfaces[2].patterns={}
  for x=40,59 do s.interfaces[#s.interfaces+1]=inv('OC Buffer',x,'donor',2,{[0]=pat('d'..x,'processing',true),[1]=pat('c'..x,'crafting',true)}) end
  local r={recipes={}};for i=1,15 do r.recipes[#r.recipes+1]=recipe('p'..i);r.recipes[#r.recipes+1]=recipe('c'..i,'crafting') end
  local p=P.plan(r,s);assert(p.available.crafting==20 and p.available.processing==20 and #p.creates==30);simulate(p,s)
end)
test('wrong donor kind, non-disposable patterns and full workspace block',function()
  local s=fixture({},3);s.interfaces[2].patterns[0].donor=false
  local r={recipes={recipe('A')}};local p=P.plan(r,s)
  assert(#p.errors>0 and #p.moves==0 and #p.creates==0)
  s.interfaces[2].patterns[0].donor=true;s.interfaces[3].patterns[0]=pat('busy')
  p=P.plan(r,s);assert(#p.errors>0 and #p.creates==0)
end)
test('unrelated and duplicate patterns consume capacity',function()
  local s=fixture({[0]=pat('A'),[1]=pat('A'),[2]=pat('foreign')},3)
  local p=P.plan({recipes={recipe('A'),recipe('B')}},s)
  assert(#p.errors>0 and #p.moves==0 and #p.creates==0)
  s.interfaces[1].capacity=4;p=P.plan({recipes={recipe('A'),recipe('B')}},s)
  assert(#p.preserved==2);simulate(p,s)
end)
test('out-of-capacity patterns and overlapping roles are rejected',function()
  local s=fixture({[8]=pat('A')},3);assert(#P.plan({recipes={recipe('A')}},s).errors>0)
  s=fixture({},3);s.interfaces[2].location=cp(s.interfaces[1].location)
  fails(function() P.plan({recipes={recipe('A')}},s) end,'Overlapping')
end)
test('stale fingerprints, policies and edited previews fail revalidation',function()
  local r={recipes={recipe('A')},policy={pps=true}};local s=fixture({[0]=pat('A')},3);local p=P.plan(r,s)
  P.revalidate(r,s,p)
  s.interfaces[1].patterns[0].fingerprint='edited';fails(function() P.revalidate(r,s,p) end,'changed')
  s.interfaces[1].patterns[0].fingerprint='nbt:A';r.policy.pps=false;fails(function() P.revalidate(r,s,p) end,'changed')
  r.policy.pps=true;p.layout[1].destination.slot=2;fails(function() P.revalidate(r,s,p) end,'changed')
end)
test('no-op plan needs no workspace or donors',function()
  local s=fixture({[0]=pat('A')},1);s.interfaces={s.interfaces[1]}
  local p=P.plan({recipes={recipe('A')}},s);assert(#p.errors==0 and #p.moves==0 and #p.creates==0)
end)
test('recipe identity retains grid positions, quantities, NBT and flags',function()
  local a={type='item',name='gregtech:gt.blockmachines',damage=1360,size=1}
  local r={kind='processing',inputs={cp(a),cp(a)},outputs={{type='item',name=a.name,damage=1361,size=1}}}
  local key=P.recipeKey(r);r.inputs={cp(a)};r.inputs[1].size=2;assert(P.recipeKey(r)==key)
  r.inputs[1].size=1;assert(P.recipeKey(r)~=key)
  r.kind='crafting';local grid=P.recipeKey(r);r.inputs={[2]=a};assert(P.recipeKey(r)~=grid)
  r.inputs={[1]=a};a.tag='custom';assert(P.recipeKey(r)~=grid);a.tag=nil;r.substitute=true;assert(P.recipeKey(r)~=grid)
  r.inputs[1].size=2;fails(function() P.recipeKey(r) end,'individual items')
end)
test('malformed sparse manifests and cancellation cannot return partial operations',function()
  local s=fixture({},3)
  fails(function() P.plan({recipes={[1]=recipe('A'),[3]=recipe('B')}},s) end,'contiguous')
  fails(function() P.plan({recipes={recipe('A')}},s,function() error('cancelled') end) end,'cancelled')
  assert(s.interfaces[2].patterns[0].fingerprint=='nbt:donor1')
end)
print('SUCCESS: '..n..' tests (pure planner; includes 720 permutations)')
