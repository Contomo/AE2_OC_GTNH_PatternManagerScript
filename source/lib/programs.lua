-- Program definitions shared by configuration, navigation and execution.
local Batch = require('assline_batch')
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
local function enabledDestination(form, label, help)
  local f = field(form, label, help, '', 'text', true)
  f.enableForm = form
  return f
end
local shaperOutputs = {}
local shaperFields = {}
for _, entry in ipairs(shaperForms) do
  local key, label = entry[1], entry[2]
  shaperFields[#shaperFields + 1] = enabledDestination(
    key,
    label .. ' interface name',
    'Destination for ' .. label:lower() .. ' patterns; keep its mold stocked in the machine.'
  )
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
shaperFields[#shaperFields + 1] = field(
  'preferSolidIngots',
  'Prefer solid ingot production',
  'Skip ingot casts with a verified solid route. Off permits native ABS/liquid routes; the live ME check still applies.',
  'on',
  'toggle'
)
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
      field(
        'destination',
        'Insulator interface name',
        'All interfaces with this exact name receive insulation patterns.'
      ),
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
      field(
        'wire1',
        '1x wire interface name',
        'All matching interfaces receive recipes producing 1x wire.'
      ),
      field(
        'wireFine',
        'Fine wire interface name',
        'All matching interfaces receive recipes producing fine wire.'
      ),
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
    fields = {
      field('wire', 'Bare wire interface name', 'Destination bank for combined bare-wire sizes.'),
      field(
        'cable',
        'Insulated cable interface name',
        'Destination bank for combined insulated-cable sizes.'
      ),
    },
  },
  {
    id = 'bender',
    name = 'Bending machine',
    mode = 'bender',
    description = 'Scraped plate, foil, sheet-metal and spring routes with selectable inputs.',
    formChoices = benderForms,
    formSwitch = 'forms',
    outputs = {
      plate = 'plate',
      plateDouble = 'plate',
      plateTriple = 'plate',
      plateQuadruple = 'plate',
      plateQuintuple = 'plate',
      plateDense = 'plate',
      foil = 'foil',
      sheetmetal = 'sheetMetal',
      springSmall = 'spring',
      spring = 'spring',
    },
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
      field(
        'plate',
        'Plate interface name',
        'All enabled plate sizes share this destination.',
        '',
        'text',
        true
      ),
      field(
        'foil',
        'Foil interface name',
        'Destination bank for the selected foil input route.',
        '',
        'text',
        true
      ),
      field(
        'sheetMetal',
        'Sheet metal interface name',
        'Destination bank for plate to sheet-metal patterns.',
        '',
        'text',
        true
      ),
      formSwitches(
        benderForms,
        'Enabled bending outputs',
        'Only scraped routes for the selected inputs are included. Foil yields 4 per ingot or plate.'
      ),
      field(
        'spring',
        'Spring interface name',
        'Destination bank for enabled small and large springs.',
        '',
        'text',
        true
      ),
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
M.byId, M.settings = {}, {}
for _, program in ipairs(M.list) do
  if program.mode and program.formChoices then
    for _, entry in ipairs(program.formChoices) do
      local f = field(Batch.divisorKey(entry[1]), entry[2], '', '', 'optionalPositiveInteger', true)
      f.costDivisor, f.group, f.compact, f.placeholder = entry[1], 'Batch divisors', true, 'Auto'
      f.tableLabel, f.valueLabel = 'OUTPUT FORM', 'BATCH DIVISOR'
      f.tableHelp =
        'Blank uses material input cost. A divisor of 1 keeps the full batch; 4 quarters it.'
      program.fields[#program.fields + 1] = f
    end
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
