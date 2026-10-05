-- Program definitions shared by configuration, navigation and execution.
local Batch = require('assline_batch')
local ComponentData = require('assline_component_data')
local M = {}
local function field(key, label, help, default, kind, optional)
  return {
    key = key,
    label = label,
    help = help,
    default = default or '',
    kind = kind or 'text',
    optional = optional,
  }
end
local function choice(key, label, choices, default, help)
  local f = field(
    key,
    label,
    help or 'Choose the input used for these patterns.',
    default or 'ingot',
    'choice'
  )
  f.choices = choices
  return f
end
local function multiplier()
  return field(
    'multiplier',
    'Pattern multiplier',
    'Fixed batch before material-cost scaling; all requested inputs and outputs scale together.',
    '1',
    'positiveInteger'
  )
end
local benderForms = {
  { 'plate', '1x' },
  { 'plateDouble', '2x' },
  { 'plateTriple', '3x' },
  { 'plateQuadruple', '4x' },
  { 'plateQuintuple', '5x' },
  { 'plateDense', 'Dense (9x)' },
  { 'foil', 'Foil' },
  { 'sheetmetal', 'Sheet metal' },
  { 'springSmall', 'Small spring' },
  { 'spring', 'Spring' },
}
local cableForms = {}
for _, size in ipairs({ 1, 2, 4, 8, 12, 16 }) do
  cableForms[#cableForms + 1] = { 'cable' .. size, size .. 'x Cable' }
end
local shaperForms = {
  { 'ingot', 'Ingot' },
  { 'nugget', 'Nugget' },
  { 'plate', '1x Plate' },
  { 'stick', 'Rod' },
  { 'stickLong', 'Long rod' },
  { 'ring', 'Ring' },
  { 'bolt', 'Bolt' },
  { 'screw', 'Screw' },
  { 'round', 'Round' },
  { 'gearGt', 'Gear' },
  { 'gearGtSmall', 'Small gear' },
  { 'rotor', 'Rotor' },
  { 'itemCasing', 'Item casing' },
  { 'toolHeadDrill', 'Drill head' },
  { 'turbineBlade', 'Turbine blade' },
  { 'pipeTiny', 'Tiny pipe' },
  { 'pipeSmall', 'Small pipe' },
  { 'pipeMedium', 'Medium pipe' },
  { 'pipeLarge', 'Large pipe' },
  { 'pipeHuge', 'Huge pipe' },
}
local function formSwitches(choices, label, help, hidden, default)
  local names = {}
  for _, option in ipairs(choices) do
    names[#names + 1] = option[1]
  end
  local f = field('forms', label, help, default or table.concat(names, ','), 'multiToggle')
  f.choices = choices
  f.hidden = hidden
  return f
end
local shaperOutputs = {}
local shaperFields = {}
for _, entry in ipairs(shaperForms) do
  local key = entry[1]
  if key:match('^pipe') then
    local size = key:sub(5)
    shaperOutputs['pipeFluid' .. size] = key
    shaperOutputs['pipeItem' .. size] = key
  else
    shaperOutputs[key] = key
  end
end
shaperFields[#shaperFields + 1] = formSwitches(
  shaperForms,
  'Enabled Fluid Shaper molds',
  'Only verified Fluid Solidifier routes are included. The reusable mold stays in the machine.',
  true,
  'plate,turbineBlade'
)
shaperFields[#shaperFields + 1] = multiplier()
M.list = {
  {
    id = 'assline',
    name = 'Assembly line renamer',
    description = 'Review duplicate inputs and create their rename patterns.',
    fields = {
      field(
        'target',
        'Assembly line interface',
        'Exact name of the interface containing the patterns to manage.',
        'Advanced Assline (1)'
      ),
      field(
        'itemName',
        'Renamed item template',
        '{label} is the original item name; {n} is the duplicate number.',
        'NAME_{n}'
      ),
      field(
        'renameName',
        'Rename destination template',
        'All interfaces matching the resulting name participate.',
        'Rename NAME_{n}'
      ),
    },
  },
  {
    id = 'insulator',
    name = 'Wire insulator',
    mode = 'coating',
    formChoices = cableForms,
    description = 'Plan insulation patterns in material and cable-size order.',
    fields = {
      choice(
        'polymer',
        'Insulation polymer',
        {
          { 'pvc', 'PVC pulp' },
          { 'pvcSmall', 'Small PVC pulp' },
          { 'pdms', 'PDMS pulp' },
          { 'pdmsSmall', 'Small PDMS pulp' },
          { 'none', 'Nothing' },
        },
        'pvc',
        'Normal piles: batches of 4 cables. Small piles / nothing: 1 cable. PDMS = polydimethylsiloxane.'
      ),
      field(
        'pps',
        'Request PPS',
        'Off means PPS must already be stocked in the machine.',
        'on',
        'toggle'
      ),
      multiplier(),
    },
  },
  {
    id = 'wiremill',
    name = 'Wiremill',
    mode = 'wiremill',
    formChoices = { { 'wire1', '1x wire' }, { 'wireFine', 'Fine wire' } },
    description = 'Create 1x wire and fine-wire patterns in separate destination banks.',
    outputs = { wire1 = 'wire1', wireFine = 'wireFine' },
    sources = { fields = { wire1 = 'wireSource', wireFine = 'fineSource' } },
    fields = {
      choice('wireSource', '1x wire input', { { 'ingot', 'Ingot' }, { 'stick', 'Rod' } }),
      choice(
        'fineSource',
        'Fine wire input',
        { { 'ingot', 'Ingot' }, { 'stick', 'Rod' }, { 'wire1', '1x wire' } }
      ),
      multiplier(),
    },
  },
  {
    id = 'combining',
    name = 'Wire combining',
    unavailable = 'Combining recipe rules are not implemented yet.',
    description = 'Combine wire and cable sizes in a molecular assembler.',
    fields = {},
  },
  {
    id = 'bender',
    name = 'Bending machine',
    mode = 'bender',
    description = 'Scraped plate, foil, sheet-metal and spring routes with selectable inputs.',
    formChoices = benderForms,
    formSwitch = 'forms',
    sources = {
      fixed = { plate = 'ingot', sheetmetal = 'plate', spring = 'stickLong' },
      fields = {
        plateDouble = 'plateSource',
        plateTriple = 'plateSource',
        plateQuadruple = 'plateSource',
        plateQuintuple = 'plateSource',
        plateDense = 'plateSource',
        foil = 'plateSource',
        springSmall = 'springSmallSource',
      },
    },
    fields = {
      formSwitches(benderForms, '', '', true),
      choice(
        'plateSource',
        'Larger plate / foil input',
        { { 'ingot', 'Ingot' }, { 'plate', '1x plate' } },
        'ingot',
        'Applies to 2x, 3x, 4x, 5x and dense plates, plus foil. 1x plates always use ingots.'
      ),
      choice(
        'springSmallSource',
        'Small spring input',
        { { 'stick', 'Rod' }, { 'wire1', '1x wire' } },
        'stick',
        'Large springs always use long rods; sheet metal always uses 1x plates.'
      ),
      multiplier(),
    },
  },
  {
    id = 'fluidShaper',
    name = 'Fluid Shaper',
    mode = 'solidifier',
    description = 'Cast verified solid parts from molten fluid with stocked molds.',
    formChoices = shaperForms,
    formSwitch = 'forms',
    switchByDestination = true,
    outputs = shaperOutputs,
    fields = shaperFields,
  },
}
M.list[#M.list + 1] = {
  id = 'donorCleanup',
  name = 'Clean donor buffer',
  description = 'Replace disposable processing recipes with a tagged donor placeholder.',
  fields = {},
  requiresCapacityVerification = false,
  previewTabs = { { 'changes', 'Patterns' }, { 'details', 'Details' } },
}
M.list[#M.list + 1] = {
  id = 'implosionTransition',
  name = 'Implosion transition',
  description = 'Move existing patterns to electric implosion, removing explosives and tiny byproducts.',
  fields = {
    field(
      'source',
      'Old interface name',
      'All interfaces with this exact terminal name are included.',
      ''
    ),
    field(
      'destination',
      'New interface name',
      'Existing target patterns stay in place; migrated patterns use free slots.',
      ''
    ),
  },
  previewTabs = { { 'changes', 'Patterns' }, { 'capacity', 'Capacity' }, { 'details', 'Details' } },
}
local singularityForms = { { 'singularity', 'Singularities' }, { 'block', 'Blocks' } }
local singularityMultiplier = multiplier()
singularityMultiplier.label = 'Block pattern multiplier'
singularityMultiplier.help =
  'Block recipes only. Singularity patterns always request the exact amount for one output.'
M.list[#M.list + 1] = {
  id = 'singularities',
  name = 'Singularity line',
  mode = 'singularities',
  description = 'The 63 Eternal-chain singularities and their ordinary compressor block recipes.',
  formChoices = singularityForms,
  formSwitch = 'forms',
  switchByDestination = true,
  outputs = { singularity = 'singularity', block = 'block' },
  costForms = { block = true },
  fields = {
    formSwitches(singularityForms, '', '', true),
    choice(
      'unstable',
      'Unstable-block input',
      { { 'mobius', 'Mobius stable ingots' }, { 'unstable', 'Unstable ingots' } },
      'mobius',
      'Select one of the two scraped compressor routes; never installs both.'
    ),
    singularityMultiplier,
  },
}
local casingChoices = {}
for _, name in ipairs(ComponentData.casings) do
  casingChoices[#casingChoices + 1] = { name, name }
end
local casingField = choice(
  'casingTier',
  'Installed component casing tier',
  casingChoices,
  'LuV',
  'Upper limit by machine casing; shared progression and voltage constraints still apply.'
)
casingField.kind, casingField.group = 'select', 'Recipe selection'
local rubberField = choice(
  'rubber',
  'Component rubber',
  { { 'sbr', 'SBR' }, { 'silicone', 'Silicone' }, { 'rubber', 'Rubber (LV-EV only)' } },
  'sbr',
  'Choose one route. Rubber has no pump/conveyor route at IV through UMV.'
)
rubberField.kind, rubberField.group = 'select', 'Recipe selection'
local componentProgram = {
  id = 'componentAssembly',
  name = 'Component Assembly Line',
  mode = 'components',
  description = 'Eight component banks, filtered by installed casing tier.',
  distinctDestinations = true,
  costForms = {},
  outputs = {},
  fields = { casingField, rubberField },
  stockedForms = {},
}
for _, component in ipairs(ComponentData.components) do
  local key = component.key
  componentProgram.outputs[key] = key
  componentProgram.stockedForms[#componentProgram.stockedForms + 1] = { key, component.label }
end
M.list[#M.list + 1] = componentProgram
-- Each output has one editable destination and one switch. Configuration,
-- validation, routing and rendering all consume this same field schema.
local function destinationFields(program, definitions, help)
  local fields = {}
  program.destinationChoices = program.formChoices
  program.formSwitch, program.destinationSwitch, program.switchByDestination =
    'forms', 'forms', true
  for _, definition in ipairs(definitions) do
    local key, subtype, prefix, legacyKey =
      definition[1], definition[2], definition[3], definition[4]
    local f = field(
      key,
      subtype .. ' interface name',
      '',
      (prefix or program.name:gsub('%f[%a]%a', string.upper)) .. ' (' .. subtype .. ')',
      'destination',
      true
    )
    f.group, f.groupHelp, f.legacyKey = 'Interface Names', help, legacyKey
    if program.mode == 'components' then
      for _, component in ipairs(ComponentData.components) do
        if component.key == key then
          f.annotation = 'Circuit ' .. component.circuit
        end
      end
    end
    fields[#fields + 1] = f
  end
  local switch
  for _, f in ipairs(program.fields) do
    if f.key == 'forms' then
      f.hidden, switch = true, f
    end
    fields[#fields + 1] = f
  end
  if not switch then
    fields[#fields + 1] = formSwitches(program.formChoices, '', '', true)
  end
  program.fields = fields
end
local definitions = {
  insulator = {},
  wiremill = { { 'wire1', 'Wires' }, { 'wireFine', 'Fine Wires' } },
  combining = {
    { 'wire', 'Wires', 'Large Molecular Assembler' },
    { 'cable', 'Cables', 'Large Molecular Assembler' },
  },
  bender = {
    { 'plate', 'Plate' },
    { 'plateDouble', 'Double Plate', nil, 'plate' },
    { 'plateTriple', 'Triple Plate', nil, 'plate' },
    { 'plateQuadruple', 'Quadruple Plate', nil, 'plate' },
    { 'plateQuintuple', 'Quintuple Plate', nil, 'plate' },
    { 'plateDense', 'Dense Plate', nil, 'plate' },
    { 'foil', 'Foil' },
    { 'sheetmetal', 'Sheet Metal', nil, 'sheetMetal' },
    { 'springSmall', 'Small Spring', nil, 'spring' },
    { 'spring', 'Spring' },
  },
  fluidShaper = {},
  singularities = {
    { 'singularity', 'Singularities', 'Neutronium Compressor' },
    { 'block', 'Blocks', 'Compressor' },
  },
  componentAssembly = {},
}
for _, entry in ipairs(cableForms) do
  definitions.insulator[#definitions.insulator + 1] = { entry[1], entry[2], nil, 'destination' }
end
for _, entry in ipairs(shaperForms) do
  local subtype = entry[1] == 'plate' and 'Plate' or entry[2]:gsub('%f[%a]%a', string.upper)
  definitions.fluidShaper[#definitions.fluidShaper + 1] = { entry[1], subtype }
end
for _, component in ipairs(ComponentData.components) do
  definitions.componentAssembly[#definitions.componentAssembly + 1] =
    { component.key, component.label }
end
componentProgram.formChoices = componentProgram.stockedForms
for _, program in ipairs(M.list) do
  if program.id == 'insulator' or program.id == 'bender' then
    program.outputs = {}
    for _, entry in ipairs(program.formChoices) do
      program.outputs[entry[1]] = entry[1]
    end
  elseif program.id == 'combining' then
    program.formChoices = { { 'wire', 'Wires' }, { 'cable', 'Cables' } }
    program.outputs = { wire = 'wire', cable = 'cable' }
  end
  if definitions[program.id] then
    local help = program.id == 'fluidShaper'
        and 'Destinations for patterns; keep the matching mold stocked in each machine.'
      or program.id == 'componentAssembly' and 'Separate component banks; circuits stay stocked (IV+). LV-EV recipes need no circuit.'
      or 'Destinations for patterns. Every interface with the same exact name is included.'
    destinationFields(program, definitions[program.id], help)
  end
end
M.byId, M.settings = {}, {}
for _, program in ipairs(M.list) do
  if program.mode and program.formChoices then
    for _, entry in ipairs(program.formChoices) do
      if not program.costForms or program.costForms[entry[1]] then
        local f =
          field(Batch.divisorKey(entry[1]), entry[2], '', '', 'optionalPositiveInteger', true)
        f.costDivisor, f.group, f.compact, f.placeholder = entry[1], 'Batch divisors', true, 'Auto'
        f.tableLabel, f.valueLabel = 'OUTPUT FORM', 'BATCH DIVISOR'
        f.tableHelp =
          'Blank uses material input cost. A divisor of 1 keeps the full batch; 4 quarters it.'
        program.fields[#program.fields + 1] = f
      end
    end
  end
  if program.id == 'bender' or program.id == 'fluidShaper' then
    program.stockedForms = program.formChoices
  end
  M.byId[program.id] = program
  if #program.fields > 0 then
    M.settings[#M.settings + 1] = program
  end
end
function M.switchKey(program, form)
  return program.switchByDestination and program.outputs[form] or form
end
return M
