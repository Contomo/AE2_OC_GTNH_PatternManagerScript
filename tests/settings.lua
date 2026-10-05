package.path = 'tests/lib/?.lua;' .. package.path
local Settings = require('assline_settings')
local Config = require('assline_config')
local Programs = require('assline_programs')
local Components = require('assline_components')
local U = require('assline_util')
local unicode = { wlen = function(s) return #s end, len = function(s) return #s end, sub = string.sub }
local tests = 0
local function test(name, run)
  run()
  tests = tests + 1
  print('PASS ' .. name)
end
local function config()
  local c = U.clone(Config.defaults)
  c.batch.mode, c.batch.costScaling = 'fixed', 'off'
  return c
end

test('all recipe destinations share prefilled fields and one checkbox schema', function()
  local c = config()
  for _, program in ipairs(Programs.list) do
    if program.destinationSwitch then
      local found = {}
      for _, f in ipairs(program.fields) do
        if f.kind == 'destination' then
          assert(f.group == 'Interface Names' and f.help == '' and f.optional)
          assert(f.default:match('^[^()]+ %([^()]+%)$'))
          assert(Config.destinationEnabled(c, program.id, f.key) ~= nil)
          assert(not found[f.key]); found[f.key] = true
        end
      end
      for _, choice in ipairs(program.destinationChoices) do assert(found[choice[1]]) end
    end
  end
  assert(c.programs.bender.plate == 'Bending Machine (Plate)')
  assert(c.programs.bender.plateDouble == 'Bending Machine (Double Plate)')
  assert(c.programs.fluidShaper.ingot == 'Fluid Shaper (Ingot)')
  assert(c.programs.componentAssembly.motor == 'Component Assembly Line (Motor)')
end)

test('each bending output has an independent checkbox and destination name', function()
  local c = config()
  c.programs.bender.forms = 'foil'
  c.programs.bender.plate = ''
  c.programs.bender.plateDouble = ''
  local selected = Config.enabledOutputs(c, 'bender')
  assert(not selected.plateDouble and not selected.plateDense and selected.foil)
  assert(Config.requireProgram(c, 'bender'))
  c.programs.bender.forms = 'plateDouble,foil'
  assert(not pcall(Config.requireProgram, c, 'bender'))
  c.programs.bender.plateDouble = 'Custom Double Plates'
  selected = Config.enabledOutputs(c, 'bender')
  assert(selected.plateDouble and not selected.plateDense and not selected.plate)
  assert(Config.requireProgram(c, 'bender'))
end)

test('component selection excludes disabled groups before allocating recipes and diagnostics', function()
  local c = config()
  c.programs.componentAssembly.forms = 'motor'
  c.programs.componentAssembly.piston = ''
  assert(Config.requireProgram(c, 'componentAssembly'))
  local manifest = Components.compile(require('assline_component_data'), {
    casingTier = 'IV', forms = Config.enabledOutputs(c, 'componentAssembly'),
  })
  assert(#manifest.recipes == 5 and #manifest.skipped == 8 and #manifest.choices == 5)
  for _, recipe in ipairs(manifest.recipes) do assert(recipe.outputForm == 'motor') end
  for _, skipped in ipairs(manifest.skipped) do assert(skipped.form == 'motor') end
end)

test('migration keeps custom names and selections while prefilling blanks and new switches', function()
  local c = config()
  c.programs.bender.plate = 'Old Plate Bank'
  c.programs.bender.forms = 'plateDouble,foil'
  c.programs.bender.plateDouble = nil
  c.programs.bender.plateDense = nil
  c.programs.bender.sheetmetal = nil
  c.programs.bender.sheetMetal = 'Old Sheet Bank'
  c.programs.insulator.destination = 'Old Cable Bank'
  for _, entry in ipairs(Programs.byId.insulator.formChoices) do c.programs.insulator[entry[1]] = nil end
  c.programs.bender.foil = ''
  c.programs.fluidShaper.forms = 'plate'
  c.programs.componentAssembly.forms = nil
  c.programs.componentAssembly.motor = 'Legacy Motor Bank'
  local migrated = Config.migrate(c)
  assert(migrated.programs.bender.plate == 'Old Plate Bank')
  assert(migrated.programs.bender.plateDouble == 'Old Plate Bank')
  assert(migrated.programs.bender.plateDense == 'Old Plate Bank')
  assert(migrated.programs.bender.sheetmetal == 'Old Sheet Bank')
  assert(migrated.programs.insulator.cable16 == 'Old Cable Bank')
  assert(migrated.programs.bender.foil == 'Bending Machine (Foil)')
  assert(migrated.programs.bender.forms == 'plateDouble,foil')
  assert(migrated.programs.fluidShaper.forms == 'plate')
  assert(migrated.programs.componentAssembly.motor == 'Legacy Motor Bank')
  assert(Config.enabledOutputs(migrated, 'bender').plateDouble)
  assert(Config.enabledOutputs(migrated, 'componentAssembly').sensor)
  assert(U.eq(Config.migrate(migrated), migrated))
end)

test('twenty Fluid Shaper destinations and the component list fit one measured page', function()
  local c = config()
  for _, id in ipairs({ 'fluidShaper', 'componentAssembly', 'bender', 'wiremill' }) do
    local pages = Settings.pages(Config.visibleFields(c, id), 124, 37, unicode)
    assert(#pages == 1, id .. ' unnecessarily paginated')
    local destinations, headings = 0, 0
    for _, block in ipairs(pages[1].blocks) do
      assert(block.row + block.height <= 37)
      if block.kind == 'destination' then destinations = destinations + 1 end
      if block.label == 'Interface Names' then headings = headings + 1 end
    end
    assert(headings == 1)
    assert(destinations == #Programs.byId[id].destinationChoices)
  end
end)

test('pagination measures wrapped help and option rows and repeats list headings when needed', function()
  local fields = {
    { key = 'a', kind = 'destination', group = 'Interface Names', groupHelp = 'Help for this list.' },
    { key = 'b', kind = 'destination', group = 'Interface Names', groupHelp = 'Help for this list.' },
    { key = 'c', kind = 'destination', group = 'Interface Names', groupHelp = 'Help for this list.' },
  }
  local pages = Settings.pages(fields, 30, 5, unicode)
  assert(#pages == 2 and pages[1].height == 5 and pages[2].height == 4)
  assert(pages[2].blocks[1].label == 'Interface Names')
  local field = { label = 'Choose a route', kind = 'choice', help = string.rep('many words ', 8),
    choices = { { 'one', 'First' }, { 'two', 'Second' }, { 'three', 'Third' } } }
  local block = Settings.measure(field, 20, unicode)
  assert(#block.help > 1 and block.options[3].row > 0)
  assert(block.height == block.helpRow + #block.help + 1)
  assert(not pcall(Settings.pages, { field }, 20, 2, unicode))
end)

test('every configuration page stays within its measured area under both batch policies', function()
  local c = config()
  for _, mode in ipairs({ 'fixed', 'tiered' }) do
    for _, scaling in ipairs({ 'off', 'on' }) do
      c.batch.mode, c.batch.costScaling = mode, scaling
      local ids = { 'shared', 'batch' }
      for _, program in ipairs(Programs.settings) do ids[#ids + 1] = program.id end
      for _, id in ipairs(ids) do
        for _, page in ipairs(Settings.pages(Config.visibleFields(c, id), 124, 37, unicode)) do
          assert(page.height <= 37)
          local previous = 0
          for _, block in ipairs(page.blocks) do
            assert(block.row >= previous)
            previous = block.row + block.height
          end
          assert(previous <= 37)
        end
      end
    end
  end
end)

print('SUCCESS: ' .. tests .. ' tests (settings layout and destination switches)')
