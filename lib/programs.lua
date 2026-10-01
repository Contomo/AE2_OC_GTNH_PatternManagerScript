-- Program definitions shared by configuration, navigation and execution.
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
    'Whole-number batch multiplier. 1 keeps the selected recipe batch; 256 makes it 256 times larger.',
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
local function formSwitches()
  local names = {}
  for _, option in ipairs(benderForms) do
    names[#names + 1] = option[1]
  end
  local f = field(
    'forms',
    'Enabled bending outputs',
    'Only scraped routes for the selected inputs are included. Foil yields 4 per ingot or plate.',
    table.concat(names, ','),
    'multiToggle'
  )
  f.choices = benderForms
  return f
end
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
      formSwitches(),
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
}
M.byId = {}
for _, program in ipairs(M.list) do
  M.byId[program.id] = program
end
return M
