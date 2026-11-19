package.path = 'tests/lib/?.lua;' .. package.path
local U = require('assline_util')
local Plasma = require('assline_plasma')
local Config = require('assline_config')
local Planner = require('assline_planner')
local data = require('assline_plasma_data')
local n = 0
local function test(name, run) run(); n=n+1; print('PASS '..name) end
local function options()
  return { plasmaTier=2, multistep=true, includeFusion=true, plasmaFeed='fluid', multiplier=1 }
end

test('the real catalog emits one unique processing pattern per plasma instead of every feed variant',function()
  local result=Plasma.compile(data,options())
  assert(#result.recipes==120 and #result.skipped==0)
  local keys,outputs={},{}
  for _,r in ipairs(result.recipes) do
    assert(#r.inputs==1 and #r.outputs==1 and #r.stock==0)
    local key=Planner.recipeKey(r);assert(not keys[key]);keys[key]=true
    assert(not outputs[r.outputs[1].name]);outputs[r.outputs[1].name]=true
  end
end)

test('fusion exclusion compares exact plasma output IDs and removes thirty products',function()
  local opts=options();opts.includeFusion=false
  local result=Plasma.compile(data,opts)
  assert(#result.recipes==90 and #result.skipped==30)
  for _,r in ipairs(result.recipes) do assert(not r.fusion) end
  for _,r in ipairs(result.skipped) do assert(r.reason:find('regular Fusion Reactor',1,true)) end
end)

test('plasma tiers and the multistep unlock are independent upper limits',function()
  local opts=options();opts.plasmaTier=0;opts.multistep=false
  local result=Plasma.compile(data,opts)
  assert(#result.recipes==81)
  for _,r in ipairs(result.recipes) do assert(r.plasmaTier==0 and not r.multistep) end
  opts.multistep=true;assert(#Plasma.compile(data,opts).recipes==98)
  opts.plasmaTier=1;assert(#Plasma.compile(data,opts).recipes==107)
  opts.plasmaTier=2;assert(#Plasma.compile(data,opts).recipes==120)
end)

test('feed preferences select one path with fallback only for unavailable types',function()
  for _,path in ipairs({'fluid','dust'}) do
    local opts=options();opts.plasmaFeed=path
    local result=Plasma.compile(data,opts)
    for index,r in ipairs(result.recipes) do
      local row=data.materials[index]
      local pair=row.paths[path] or row.paths[path=='fluid' and 'dust' or 'fluid']
      assert(r.inputs[1].name==data.names[data.items[pair[1]].name] and r.inputs[1].size==pair[2])
    end
  end
end)

test('a fixed multiplier scales every quantity and ignores global material voltage and curve gates',function()
  local opts=options();opts.multiplier=8;opts.batch=U.clone(Config.defaults.batch)
  opts.batch.currentTier='ULV';opts.batch.unknownPolicy='skip'
  local result=Plasma.compile(data,opts)
  assert(#result.recipes==120 and not result.policy.batch)
  for index,r in ipairs(result.recipes) do
    assert(r.batch.multiplier==8 and r.batch.context:find('Plasma tier',1,true))
    assert(r.outputs[1].size==data.materials[index].output[2]*8)
  end
end)

test('disabled destinations allocate no recipes and invalid upgrade selections fail',function()
  local opts=options();opts.forms={}
  assert(#Plasma.compile(data,opts).recipes==0)
  opts.plasmaTier=3;assert(not pcall(Plasma.compile,data,opts))
end)

print('SUCCESS: '..n..' tests (Plasma Fabricator)')
