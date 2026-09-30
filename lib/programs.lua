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
  { 'foil', 'Foil (1 to 4)' },
}
local function formSwitches()
  local names = {}
  for _, option in ipairs(benderForms) do
    names[#names + 1] = option[1]
  end
  local f = field(
    'forms',
    'Enabled ingot routes',
    'Each switch independently includes an ingot-input recipe when that material has one.',
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
    description = 'Ingot-input plates and foil, with independent output switches.',
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
        'Destination bank for ingot to foil patterns.',
        '',
        'text',
        true
      ),
      field(
        'sheetMetal',
        'Sheet metal interface name',
        'Reserved for a later plate-input mode: no ingot to sheet metal recipe was found in the scrape.',
        '',
        'text',
        true
      ),
      formSwitches(),
      multiplier(),
    },
  },
}
M.byId = {}
for _, program in ipairs(M.list) do
  M.byId[program.id] = program
end
return M
