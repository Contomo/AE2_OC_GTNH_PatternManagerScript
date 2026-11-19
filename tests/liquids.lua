package.path = 'tests/lib/?.lua;./?.lua;' .. package.path
local U = require('assline_util')
local Supply = require('assline_supply')
local Melting = require('assline_melting')
local Config = require('assline_config')
local tests = 0
local function test(name, run)
  run(); tests = tests + 1; print('PASS ' .. name)
end
local function stack(name, fluid)
  return { type = fluid and 'fluid' or 'item', name = name, damage = not fluid and 0 or nil, size = 1, label = name }
end
local function recipe(inputs, outputs)
  return { kind = 'processing', inputs = inputs, outputs = outputs }
end
local dust, ingot, fluid, raw = stack('test:dust'), stack('test:ingot'), stack('test.fluid', true), stack('test:raw')

local function catalog()
  return {
    version = 1, source = { recipeVersion = 'test', targetVersion = 'test' },
    names = { 'test:dust', 'test:ingot', 'test.fluid', 'nitrogen' },
    items = { { name = 1, type = 'item', damage = 0, label = 'Test Dust' },
      { name = 2, type = 'item', damage = 0, label = 'Test Ingot' },
      { name = 3, type = 'fluid', label = 'Test Fluid' }, { name = 4, type = 'fluid', label = 'Nitrogen' } },
    feeds = { { { 1, 1 } } }, products = { { { 3, 144 } } },
    extraction = { rules = {}, sets = { {} } },
    materials = { { name = 'Test', key = 'test', tier = 'LV', native = false, fluid = 3, ingot = 2,
      castEUt = 8, dsf = 0, ex = 1,
      exExtra = { { kind = 'literal', name = 'test:ingot', damage = 0, n = 1, amount = 144 } },
      routes = { { feed = 1, output = 1, circuit = 1, gas = 0, rank = 0, eut = 24, ticks = 100, cost = 1 },
        { feed = 1, output = 1, circuit = 11, gas = 4, gasAmount = 100, rank = 0, eut = 24, ticks = 50, cost = 1 } } } },
  }
end
local function options()
  return { forms = { c0 = true, c1 = true, c11 = true, ingot = true }, gas = 'none', multiplier = 1 }
end

test('supply proof detects ingot dust loops and accepts an independent alternative', function()
  local graph = Supply.new()
  graph:add(recipe({ fluid }, { ingot }), 'cast')
  graph:add(recipe({ ingot }, { dust }), 'macerator')
  assert(not graph:independent({ dust }, { fluid, ingot }))
  graph:add(recipe({ raw }, { dust }), 'raw-feed')
  assert(graph:independent({ dust }, { fluid, ingot }))
  assert(not graph:independent({ dust }, { fluid, ingot }, { ['raw-feed'] = true }))
end)

test('AND inputs and OR producers use a least fixed point even through a cyclic group', function()
  local a, b = stack('test:a'), stack('test:b')
  for direction = 1, 2 do
    local graph = Supply.new()
    if direction == 1 then graph:add(recipe({ a }, { b }), 'ab') end
    graph:add(recipe({ b }, { a }), 'ba')
    if direction == 2 then graph:add(recipe({ a }, { b }), 'ab') end
    assert(not graph:independent({ a }, {}))
    graph:add(recipe({ raw }, { b }), 'independent')
    assert(graph:independent({ a, b }, {}))
    assert(not graph:independent({ a, fluid }, { fluid }))
  end
end)

test('extractor matching uses proportions, aggregates duplicates and preserves exact identities', function()
  local match = Melting.extractorMatcher(catalog())
  local r = recipe({ U.clone(ingot) }, { U.clone(fluid) })
  r.inputs[1].size, r.outputs[1].size = 1024, 147456
  assert(match(r) == 'test.fluid')
  r.inputs[2] = U.clone(r.inputs[1]); r.outputs[1].size = 294912
  assert(match(r) == 'test.fluid')
  r.outputs[1].size = 294911; assert(not match(r))
  r.outputs[1].size = 294912; r.inputs[1].tag = 'different'; assert(not match(r))
end)

test('one dry route and one casting recipe share batches while circuits stay stocked', function()
  local data, opts, graph = catalog(), options(), Supply.new()
  opts.multiplier = 256
  local result = Melting.compile(data, opts, graph)
  assert(#result.recipes == 2 and #graph.recipes == 0)
  assert(result.recipes[1].outputForm == 'c1' and #result.recipes[1].inputs == 1)
  assert(result.recipes[1].stock[1].damage == 1 and result.recipes[1].stock[1].size == 1)
  assert(result.recipes[1].inputs[1].size == 256 and result.recipes[1].outputs[1].size == 36864)
  assert(result.recipes[2].outputForm == 'ingot' and result.recipes[2].outputs[1].size == 256)
  opts.gas = 'nitrogen'
  result = Melting.compile(data, opts, graph)
  assert(result.recipes[1].outputForm == 'c11' and #result.recipes[1].inputs == 2)
  assert(result.recipes[1].inputs[2].name == 'nitrogen' and result.recipes[1].stock[1].damage == 11)
end)

test('process gas can stay stocked without changing the gas-assisted circuit or reaction fluids', function()
  local data,opts=catalog(),options()
  data.names[5]='reaction.fluid';data.items[5]={name=5,type='fluid',label='Reaction Fluid'}
  data.feeds[1][2]={5,10}
  opts.gas,opts.requestGas,opts.multiplier='nitrogen',false,256
  local r=Melting.compile(data,opts,Supply.new()).recipes[1]
  assert(r.outputForm=='c11' and #r.inputs==2)
  assert(r.inputs[2].name=='reaction.fluid' and r.inputs[2].size==2560)
  assert(r.stock[1].damage==11 and r.stock[2].name=='nitrogen' and r.stock[2].size==100)
  local keys=Melting.coreKeys(data)
  assert(keys[require('assline_planner').recipeKey(r)])
end)

test('a missing selected gas variant never silently falls back to circuit one', function()
  local opts=options();opts.gas='xenon'
  local result=Melting.compile(catalog(),opts,Supply.new())
  assert(#result.recipes==0 and result.skipped[1].reason:find('no-gas fallback',1,true))
  local data=catalog();data.materials[1].routes={data.materials[1].routes[1]}
  result=Melting.compile(data,opts,Supply.new())
  assert(#result.recipes==2 and result.recipes[1].outputForm=='c1')
end)

test('Melting Core can check future casts without emitting Fluid Shaper recipes', function()
  local opts=options();opts.emitCasting=false
  local graph=Supply.new()
  local result=Melting.compile(catalog(),opts,graph)
  assert(#result.recipes==1 and result.recipes[1].outputForm=='c1' and #graph.recipes==0)
  graph:add(recipe({ingot},{dust}),'macerator')
  result=Melting.compile(catalog(),opts,graph)
  assert(#result.recipes==0 and #result.skipped==1 and #graph.recipes==1)
end)

test('Fluid Shaper candidates use the same joint dependency proof and retire only ingot extraction', function()
  local cast=recipe({U.clone(fluid)},{U.clone(ingot)})
  cast.outputForm,cast.material,cast.label='ingot','Test','Ingot'
  local base={recipes={cast},skipped={}}
  local graph=Supply.new()
  local result=Melting.filterCasts(base,graph)
  assert(#result.recipes==0 and #result.skipped==1)
  graph:add(recipe({raw},{fluid}),'native')
  result=Melting.filterCasts(base,graph)
  assert(#result.recipes==1 and result.suppliedFluids[fluid.name] and #graph.recipes==1)
  cast.outputForm='plate'
  result=Melting.filterCasts(base,graph)
  assert(#result.recipes==1 and not next(result.suppliedFluids))
end)

test('priority classification uses configurable heat and voltage, including boundary cases', function()
  local policy={highHeat=9000,highVoltage='UV',mediumHeat=10000,mediumVoltage='UEV'}
  assert(Melting.priority({heat=3000,eut=1920},policy)=='high')
  assert(Melting.priority({heat=9000,eut=122880},policy)=='medium')
  assert(Melting.priority({heat=10800,eut=491520},policy)=='low')
  assert(Melting.priority({heat=11701,eut=31457280},policy)=='low')
  assert(Melting.priority({heat=1000,eut=31457280},policy)=='low')
  assert(Melting.priority({heat=10000,eut=24},policy)=='low')
  policy.highHeat=12000;policy.highVoltage='UIV'
  assert(Melting.priority({heat=11701,eut=31457280},policy)=='high')
end)

test('native-fluid materials preserve their producer and never generate a remelting route', function()
  local data, graph = catalog(), Supply.new()
  data.materials[1].native, data.materials[1].nativeMachine = true, 'Alloy Blast Smelter'
  graph:add(recipe({ raw }, { fluid }), 'abs')
  graph:add(recipe({ fluid }, { ingot }), 'cast')
  graph:add(recipe({ ingot }, { dust }), 'dust')
  local result = Melting.compile(data, options(), graph)
  assert(#result.recipes == 1 and result.recipes[1].outputForm == 'ingot')
  assert(result.skipped[1].reason:find('installed independent', 1, true))
  assert(#graph.recipes == 3)
end)

test('a dust feed supplied only by the new cast is excluded without inventing availability', function()
  local graph = Supply.new()
  graph:add(recipe({ fluid }, { ingot }), 'cast')
  graph:add(recipe({ ingot }, { dust }), 'macerator')
  local result = Melting.compile(catalog(), options(), graph)
  assert(#result.recipes == 0 and #result.skipped == 2)
  assert(result.skipped[1].reason:find('loop', 1, true))
end)

test('two planned molten routes cannot bootstrap each other as external supplies', function()
  local data = catalog()
  data.names[5], data.names[6] = 'other.fluid', 'test:other-ingot'
  data.items[5] = { name = 5, type = 'fluid', label = 'Other Fluid' }
  data.items[6] = { name = 6, type = 'item', damage = 0, label = 'Other Ingot' }
  data.materials[2] = U.clone(data.materials[1])
  local other = data.materials[2]
  other.name, other.key, other.fluid, other.ingot = 'Other', 'other', 5, 6
  other.routes = { U.clone(other.routes[1]) }
  other.routes[1].feed, other.routes[1].output = 2, 2
  data.feeds[1], data.feeds[2] = { { 5, 144 } }, { { 3, 144 } }
  data.products[2] = { { 5, 144 } }
  local result = Melting.compile(data, options(), Supply.new())
  assert(#result.recipes == 0)
  data.feeds[1], data.feeds[2] = { { 6, 1 } }, { { 2, 1 } }
  result = Melting.compile(data, options(), Supply.new())
  assert(#result.recipes == 0, 'New ingot casts must not close a cross-material melting loop')
  data.feeds[1] = { { 1, 1 } }
  result = Melting.compile(data, options(), Supply.new())
  assert(#result.recipes == 4, 'An independent dust feed should ground the entire two-metal chain')
end)

test('a cast without a liquid producer cannot falsely ground another new melting route', function()
  local data = catalog()
  data.names[5], data.names[6] = 'other.fluid', 'test:other-ingot'
  data.items[5] = { name = 5, type = 'fluid', label = 'Other Fluid' }
  data.items[6] = { name = 6, type = 'item', damage = 0, label = 'Other Ingot' }
  data.materials[2] = U.clone(data.materials[1])
  local other = data.materials[2]
  other.name, other.key, other.fluid, other.ingot, other.routes = 'Other', 'other', 5, 6, {}
  data.feeds[1] = { { 6, 1 } }
  local graph = Supply.new()
  graph:add(recipe({ ingot }, { Melting.ingredient(data, 6) }), 'existing-other-solid')
  local result = Melting.compile(data, options(), graph)
  assert(#result.recipes == 0 and #graph.recipes == 1)
end)

test('material and voltage gates remain active and magnetic or attuned casts stay excluded', function()
  local data, opts = catalog(), options()
  opts.batch = U.clone(Config.defaults.batch)
  opts.batch.currentTier, data.materials[1].tier = 'LV', 'UHV'
  local result = Melting.compile(data, opts, Supply.new())
  assert(#result.recipes == 0 and result.tierExcluded > 0)
  data.materials[1].tier, data.materials[1].key = 'LV', 'testattuned'
  result = Melting.compile(data, options(), Supply.new())
  assert(#result.recipes == 0 and result.skipped[1].reason:find('attuned', 1, true))
end)

test('scraped Quantum and Hypogen keep native fluids while Tungsten gains molten production', function()
  local data = U.clone(require('assline_liquid_data'))
  local selected = {}
  for _, material in ipairs(data.materials) do
    if material.key == 'quantum' or material.key == 'hypogen' or material.key == 'tungsten' then
      selected[#selected + 1] = material
      if material.key ~= 'tungsten' then assert(material.native and material.nativeMachine) end
    end
  end
  assert(#selected == 3); data.materials = selected
  local graph = Supply.new()
  for _, material in ipairs(selected) do
    if material.key ~= 'tungsten' then graph:add(recipe({ raw }, { Melting.ingredient(data, material.fluid) }), material.key) end
  end
  local result = Melting.compile(data, options(), graph)
  local casts, molten = 0, 0
  for _, r in ipairs(result.recipes) do
    if r.outputForm == 'ingot' then casts = casts + 1
    else molten = molten + 1; assert(r.material == 'Tungsten') end
  end
  assert(casts == 3 and molten == 1)
end)

test('the complete scraped casting catalog has valid unique processing identities', function()
  local data, graph = require('assline_liquid_data'), Supply.new()
  for _, material in ipairs(data.materials) do
    graph:add(recipe({ raw }, { Melting.ingredient(data, material.fluid) }), material.key)
  end
  local result = Melting.compile(data, options(), graph)
  local seen = {}
  for _, row in ipairs(result.recipes) do
    assert(row.outputForm == 'ingot')
    local key = require('assline_planner').recipeKey(row)
    assert(not seen[key], 'Duplicate cast for ' .. row.material)
    seen[key] = true
  end
  assert(#result.recipes > 300)
end)

print('SUCCESS: ' .. tests .. ' tests (liquid supply and Melting Core)')
