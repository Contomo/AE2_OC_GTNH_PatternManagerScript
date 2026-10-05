package.path = 'tests/lib/?.lua;' .. package.path
local Modes = require('assline_modes')
local Config = require('assline_config')
local Planner = require('assline_planner')
local U = require('assline_util')
local data = require('assline_component_data')
local tests = 0
local function test(name, run)
  run()
  tests = tests + 1
  print('PASS ' .. name)
end
local function compile(options)
  return Modes.compile(data, 'components', options)
end

test(
  'all eight component groups compile thirteen native batches with exact stock circuits',
  function()
    local result = compile({ casingTier = 'UXV', rubber = 'sbr' })
    assert(#result.recipes == 104 and #result.skipped == 0 and #result.unresolved == 0)
    local byForm, outputs, fluids, wrap, dense = {}, {}, false, false, false
    for _, recipe in ipairs(result.recipes) do
      assert(recipe.outputs[1].size == 64 and recipe.batch.multiplier == 1 and recipe.batch.native)
      local out = recipe.outputs[1]
      assert(not outputs[out.name .. ':' .. out.damage])
      outputs[out.name .. ':' .. out.damage] = true
      byForm[recipe.outputForm] = (byForm[recipe.outputForm] or 0) + 1
      local low = recipe.casingTier == 'LV'
        or recipe.casingTier == 'MV'
        or recipe.casingTier == 'HV'
        or recipe.casingTier == 'EV'
      assert(#recipe.stock == (low and 0 or 1))
      if not low then
        assert(recipe.stock[1].name == 'gregtech:gt.integrated_circuit')
        assert(recipe.stock[1].damage == recipe.componentCircuit and recipe.stock[1].size == 1)
      end
      for _, input in ipairs(recipe.inputs) do
        assert(input.name ~= 'gregtech:gt.integrated_circuit')
        fluids = fluids or input.type == 'fluid'
        wrap = wrap or input.name == 'GoodGenerator:circuitWrap'
        dense = dense or input.name == 'bartworks:gt.bwMetaGeneratedplateDense'
        assert(input.size > 0 and U.integer(input.size))
      end
      assert(type(Planner.recipeKey(recipe)) == 'string')
    end
    for _, group in ipairs(data.components) do
      assert(byForm[group.key] == 13)
    end
    assert(fluids and wrap and dense)
  end
)

test(
  'casing eligibility is independent of lower recipe voltage and optional shared gates',
  function()
    local result = compile({ casingTier = 'IV' })
    assert(#result.recipes == 40 and #result.skipped == 64)
    for _, recipe in ipairs(result.recipes) do
      if recipe.casingTier == 'IV' then
        assert(recipe.batch.recipeTier == 'EV')
      end
    end
    local batch = U.clone(Config.defaults.batch)
    batch.currentTier = 'IV'
    result = compile({ casingTier = 'UXV', batch = batch })
    assert(#result.recipes == 40)
    batch.abovePolicy = 'fixed'
    batch.voltageTier = 'HV'
    result = compile({ casingTier = 'UXV', batch = batch })
    assert(#result.recipes == 32)
    result = compile({ casingTier = 'LV', batch = batch })
    assert(#result.recipes == 8)
    assert(not pcall(compile, { casingTier = 'ULV' }))
  end
)

test(
  'rubber selector changes both molten and solid polymer routes without multiplying outputs',
  function()
    local sbr = compile({ casingTier = 'LuV', rubber = 'sbr' })
    local silicone = compile({ casingTier = 'LuV', rubber = 'silicone' })
    assert(#sbr.recipes == 48 and #silicone.recipes == 48)
    local changed = 0
    for index, recipe in ipairs(sbr.recipes) do
      local other = silicone.recipes[index]
      assert(U.eq(recipe.outputs, other.outputs) and recipe.outputForm == other.outputForm)
      if recipe.outputForm == 'pump' or recipe.outputForm == 'conveyor' then
        assert(Planner.recipeKey(recipe) ~= Planner.recipeKey(other))
        changed = changed + 1
      else
        assert(Planner.recipeKey(recipe) == Planner.recipeKey(other))
      end
    end
    assert(changed == 12)
    local rubber = compile({ casingTier = 'UXV', rubber = 'rubber' })
    assert(#rubber.recipes == 88 and #rubber.skipped == 16)
    assert(not pcall(compile, { casingTier = 'LV', rubber = 'invented' }))
  end
)

test(
  'native batches bypass quantity curves and limits but remain subject to tier eligibility',
  function()
    local batch = U.clone(Config.defaults.batch)
    batch.currentTier = 'UXV'
    batch.itemLimit = '1'
    batch.fluidLimit = '1'
    local result = compile({ casingTier = 'UXV', batch = batch })
    assert(#result.recipes == 104)
    local large = false
    for _, recipe in ipairs(result.recipes) do
      assert(recipe.outputs[1].size == 64 and recipe.batch.multiplier == 1)
      for _, input in ipairs(recipe.inputs) do
        large = large or input.size > 589824
      end
    end
    assert(large)
    batch.currentTier = 'ULV'
    assert(#compile({ casingTier = 'UXV', batch = batch }).recipes == 0)
  end
)

test('alternate choices are distinct verified routes for the same output', function()
  local result = compile({ casingTier = 'UXV', rubber = 'sbr' })
  local motorAlternates = false
  for index, choices in ipairs(result.choices) do
    local seen = {}
    for _, recipe in ipairs(choices) do
      local key = Planner.recipeKey(recipe)
      assert(not seen[key])
      seen[key] = true
      assert(U.eq(recipe.outputs, result.recipes[index].outputs))
    end
    if result.recipes[index].outputForm == 'motor' and result.recipes[index].casingTier == 'LV' then
      assert(#choices == 4)
      motorAlternates = true
    end
  end
  assert(motorAlternates)
end)

test(
  'unified configuration supplies eight distinct defaults and casing/rubber selections',
  function()
    local cfg = Config.migrate({
      version = 2,
      shared = Config.defaults.shared,
      batch = Config.defaults.batch,
      programs = {},
    })
    local values = cfg.programs.componentAssembly
    assert(values.casingTier == 'LuV' and values.rubber == 'sbr')
    for _, component in ipairs(data.components) do
      assert(values[component.key] == 'Component Assembly Line (' .. component.label .. ')')
    end
    assert(Config.requireProgram(cfg, 'componentAssembly'))
    values.piston = values.motor
    local ok, error = pcall(Config.requireProgram, cfg, 'componentAssembly')
    assert(not ok and error:find('distinct destination', 1, true))
  end
)

print('SUCCESS: ' .. tests .. ' tests (Component Assembly Line)')
