-- Readable application bundle, generated from the source files named below.
local savedPath=package.path
local function unload()
  for name in pairs(package.loaded) do
    if name:match('^assline_') then package.loaded[name]=nil end
  end
end
unload()
local fs=require('filesystem')
local args=table.pack(...)
local directory=fs.path(require('shell').resolve(require('process').info().path))
if args[1]=='--module-directory' then
  directory=args[2]
  table.remove(args,1);table.remove(args,1);args.n=args.n-2
end
package.path=directory..'?.lua;'..savedPath
local ok,result=pcall(function(...)
local U=(function()
-- Source: source/lib/util.lua
local M = {}

function M.check(ok, why)
  if not ok then
    error(why or 'Operation failed', 0)
  end
  return ok
end

function M.clone(t)
  if type(t) ~= 'table' then
    return t
  end
  local r = {}
  for k, v in pairs(t) do
    r[k] = M.clone(v)
  end
  return r
end

function M.keys(t)
  local r = {}
  for k in pairs(t or {}) do
    r[#r + 1] = k
  end
  table.sort(r, function(a, b)
    if type(a) == type(b) then
      return a < b
    end
    return type(a) < type(b)
  end)
  return r
end

function M.canonical(t)
  if type(t) ~= 'table' then
    return type(t) .. ':' .. string.format('%q', tostring(t))
  end
  local r = {}
  for _, k in ipairs(M.keys(t)) do
    r[#r + 1] = M.canonical(k) .. ':' .. M.canonical(t[k])
  end
  return '{' .. table.concat(r, ',') .. '}'
end

function M.eq(a, b)
  if type(a) ~= type(b) then
    return false
  end
  if type(a) ~= 'table' then
    return a == b
  end
  for k, v in pairs(a) do
    if not M.eq(v, b[k]) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

function M.integer(n)
  return type(n) == 'number' and n == math.floor(n) and math.abs(n) < 2147483648
end

function M.sequence(t, label)
  M.check(type(t) == 'table', label .. ' must be an array')
  local count = 0
  for k in pairs(t) do
    M.check(M.integer(k) and k >= 1 and k <= #t, label .. ' must be a contiguous array')
    count = count + 1
  end
  M.check(count == #t, label .. ' must be a contiguous array')
end

function M.endpoint(i, slot)
  return { location = M.clone(i.location), side = i.side, slot = slot }
end

function M.where(i)
  return M.canonical({ i.location, i.side })
end
function M.locationText(i)
  local l = i.location
  return tostring(l.x)
    .. ','
    .. tostring(l.y)
    .. ','
    .. tostring(l.z)
    .. ' / '
    .. tostring(l.dimId or '?')
    .. ' side '
    .. tostring(i.side)
end

function M.ordered(a, b)
  for _, k in ipairs({ 'dimId', 'x', 'y', 'z' }) do
    local x, y = a.location[k] or 0, b.location[k] or 0
    if x ~= y then
      return x < y
    end
  end
  return a.side < b.side
end

function M.trim(s)
  return tostring(s or ''):match('^%s*(.-)%s*$')
end

function M.truth(x)
  return x == true or x == 1
end

function M.exists(x)
  return type(x) == 'table' and type(x.name) == 'string'
end

-- Encoded stacks have two layouts: older patterns store Count, while newer
-- patterns store Cnt and leave Count at zero. OC's converted size can thus be
-- zero even though the encoded amount is positive.
function M.patternEntry(root, which, index)
  local list = root and root[which == 'inputs' and 'in' or 'out']
  return list and list.__nbt_type == 'list' and list.__value[index]
end

function M.patternCount(stack, entry)
  local fields = entry and entry.__nbt_type == 'compound' and entry.__value
  local function positive(value)
    if type(value) == 'table' then
      value = value.__value
    end
    return M.integer(value) and value > 0 and value or nil
  end
  return positive(fields and fields.Cnt)
    or positive(fields and fields.Count)
    or positive(stack.size)
    or positive(stack.amount)
end

function M.ingredientSummary(list)
  local out = {}
  for _, index in ipairs(M.keys(list or {})) do
    local item = list[index]
    out[#out + 1] = tostring(item.size or item.amount or 1)
      .. (item.type == 'fluid' and ' mB ' or ' x ')
      .. tostring(item.label or item.name)
  end
  return table.concat(out, ', ')
end

function M.largest(t)
  local n = 0
  for k in pairs(t or {}) do
    if type(k) == 'number' and k > n then
      n = k
    end
  end
  return n
end

function M.token(t, label, n)
  return (t:gsub('{label}', function()
    return label
  end):gsub('{n}', tostring(n)))
end

-- Shared row construction for preview and UI text, with one default tone.
function M.rows()
  local result = {}
  local function add(text, tone, guideWidth, guideTone, accent)
    result[#result + 1] = { text, tone or 'text', guideWidth, guideTone, accent }
  end
  return result, add
end

-- One word wrapper for scrollable rows and narrow summary panels. Tree guides
-- repeat on continuation lines; accent positions follow the original text.
function M.wrapRow(row, width, unicode)
  local result = {}
  local prefixLength = math.min(row[3] or 0, width - 1)
  local prefix = unicode.sub(row[1], 1, prefixLength)
  local remaining = unicode.sub(row[1], prefixLength + 1)
  local consumed = prefixLength
  local available = width - unicode.wlen(prefix)
  repeat
    local count = unicode.len(remaining)
    if unicode.wlen(remaining) > available then
      local low, high = 1, count
      while low < high do
        local mid = math.ceil((low + high) / 2)
        if unicode.wlen(unicode.sub(remaining, 1, mid)) <= available then
          low = mid
        else
          high = mid - 1
        end
      end
      count = low
      local part = unicode.sub(remaining, 1, count)
      local boundary = part:match('^.*()%s')
      if boundary then
        local words = unicode.len(part:sub(1, boundary - 1))
        if words > 0 then
          count = words
        end
      end
    end
    local chunk = unicode.sub(remaining, 1, count)
    local accent
    if row[5] then
      local first = math.max(1, row[5].from - consumed)
      local last = math.min(count, row[5].from + row[5].length - 1 - consumed)
      if first <= last then
        accent = { from = prefixLength + first, length = last - first + 1, tier = row[5].tier }
      end
    end
    result[#result + 1] = { prefix .. chunk, row[2], prefixLength, row[4], accent }
    local tail = unicode.sub(remaining, count + 1)
    remaining = tail:gsub('^%s+', '')
    consumed = consumed + count + unicode.len(tail) - unicode.len(remaining)
  until remaining == ''
  return result
end

return M

end)()
local TierDefinitions=(function()
-- Source: source/data/tiers.json
return {["source"]="https://github.com/GTNewHorizons/GT5-Unofficial/blob/5.09.54.133/src/main/java/gregtech/api/enums/GTValues.java",["names"]={"ULV","LV","MV","HV","EV","IV","LuV","ZPM","UV","UHV","UEV","UIV","UMV","UXV","OpV","MAX"},["voltages"]={8,32,128,512,2048,8192,32768,131072,524288,2097152,8388608,33554432,134217728,536870912,2147483640,8589934592},["colorSource"]="RGB colors of pinned GTValues.TIER_COLORS; Minecraft bold/underline formatting has no OC GPU equivalent",["colors"]={16733525,43520,16755200,16777045,5592405,5592575,16733695,5636095,43520,11141120,11141290,170,16733525,11141120,16777215,16777215}}
end)()
local Batch=(function()
-- Source: source/lib/batch.lua
-- Shared batch policy. Tier definitions are built from source/data/tiers.json.
local U = U
local Tiers = TierDefinitions
local M = { tiers = Tiers.names, fields = {} }
local index = {}
for n, name in ipairs(M.tiers) do
  index[name] = n
end

function M.voltageTier(eut)
  if type(eut) ~= 'number' or eut < 0 then
    return nil
  end
  for n, voltage in ipairs(Tiers.voltages) do
    if eut <= voltage then
      return M.tiers[n]
    end
  end
  return 'MAX'
end

local group = 'Policy'
local function field(key, label, default, help, kind, choices)
  M.fields[#M.fields + 1] = {
    key = key,
    label = label,
    default = default,
    help = help,
    kind = kind or 'positiveInteger',
    choices = choices,
    group = group,
    placeholder = kind == 'optionalPositiveInteger' and 'Follow relative curve' or nil,
  }
end
local tierChoices = {}
for _, name in ipairs(M.tiers) do
  tierChoices[#tierChoices + 1] = { name, name }
end
local voltageChoices = { { 'current', 'Current progression tier' } }
for _, option in ipairs(tierChoices) do
  voltageChoices[#voltageChoices + 1] = option
end
field(
  'mode',
  'Batch policy',
  'tiered',
  'Fixed uses each program multiplier. Tiered applies the shared curve and quantity limits.',
  'choice',
  { { 'fixed', 'Fixed' }, { 'tiered', 'Tiered' } }
)
field(
  'currentTier',
  'Current progression tier',
  'LuV',
  'Select your current tier. Later materials are skipped unless enabled.',
  'select',
  tierChoices
)
field(
  'abovePolicy',
  'Include materials above your tier',
  'skip',
  '',
  'choice',
  { { 'skip', 'Skip' }, { 'fixed', 'Include' } }
)
field(
  'aboveMultiplier',
  'Later material multiplier',
  '1',
  'Used only when later materials are included.'
)
field(
  'unknownPolicy',
  'Unclassified materials',
  'voltage',
  'Recipe voltage is an estimate of material tier, not proof of accessibility.',
  'choice',
  { { 'voltage', 'Use recipe voltage' }, { 'fixed', 'Fixed fallback' }, { 'skip', 'Skip' } }
)
field(
  'unknownMultiplier',
  'Unclassified fallback multiplier',
  '1',
  'Also used when recipe voltage is missing.'
)
field(
  'voltagePolicy',
  'Recipe voltage constraint',
  'cap',
  'When enabled, cap batches by voltage and skip recipes above the reference tier.',
  'choice',
  { { 'off', 'Ignore voltage' }, { 'cap', 'Cap by voltage' } }
)
field(
  'voltageTier',
  'Voltage reference tier',
  'current',
  'Follow progression or select the voltage available to your machines.',
  'select',
  voltageChoices
)
field(
  'itemLimit',
  'Maximum items per pattern ingredient',
  '4096',
  'Shrink the whole batch together to preserve proportions.'
)
field(
  'fluidLimit',
  'Maximum fluid per pattern ingredient (mB)',
  '589824',
  'Fluid inputs and outputs share this per-ingredient limit.'
)

group = 'Curve'
field(
  'curveMode',
  'Multiplier curve',
  'generated',
  '',
  'choice',
  { { 'generated', 'Generated curve' }, { 'table', 'Custom table' } }
)
field(
  'curveShape',
  'Generated curve shape',
  'geometric',
  '',
  'choice',
  { { 'geometric', 'Geometric' }, { 'logarithmic', 'Logarithmic' } }
)
field('atTier', 'Current-tier multiplier', '4', 'Starting point of the generated curve.')
field(
  'maxMultiplier',
  'Maximum tiered multiplier',
  '512',
  'End of the generated curve and final ceiling, including tier overrides.'
)
field(
  'curveSpan',
  'Tiers below until maximum',
  '7',
  'Growth follows the selected shape; older tiers stay at maximum.'
)
-- Retain custom points and overrides in the same saved configuration. Their UI
-- is a compact editable table with shared headings, not repeated field help.
local preset = { 4, 8, 16, 32, 64, 128, 256, 512 }
group = 'Curve table'
for gap = 0, 7 do
  field(
    'below' .. gap,
    gap == 0 and 'Current tier' or gap == 7 and '7+ tiers below' or gap .. ' tiers below',
    tostring(preset[gap + 1]),
    ''
  )
end
group = 'Tier overrides'
for _, name in ipairs(M.tiers) do
  field('override' .. name, name, '', '', 'optionalPositiveInteger')
end
for _, f in ipairs(M.fields) do
  if f.key == 'voltagePolicy' or f.key == 'abovePolicy' then
    f.toggleValues = { f.choices[1][1], f.choices[2][1] }
  end
  if f.key ~= 'mode' then
    f.when = { mode = 'tiered' }
  end
  if f.key == 'aboveMultiplier' then
    f.when.abovePolicy = 'fixed'
  end
  if f.key == 'unknownMultiplier' then
    f.when.unknownPolicy = { 'fixed', 'voltage' }
  end
  if f.key == 'voltageTier' then
    f.when.voltagePolicy = 'cap'
  end
  if f.key == 'atTier' or f.key == 'curveSpan' or f.key == 'curveShape' then
    f.when.curveMode = 'generated'
  end
  if f.group == 'Curve table' then
    f.when.curveMode = 'table'
    f.compact = true
  end
  if f.group == 'Tier overrides' then
    f.compact = true
    f.placeholder = ''
  end
end

function M.validate(values)
  U.check(index[values.currentTier], 'Unknown progression tier')
  U.check(
    values.voltageTier == 'current' or index[values.voltageTier],
    'Unknown voltage reference tier'
  )

  for _, f in ipairs(M.fields) do
    if
      f.kind == 'positiveInteger' or f.kind == 'optionalPositiveInteger' and values[f.key] ~= ''
    then
      local value = tonumber(values[f.key])
      U.check(U.integer(value) and value > 0, f.label .. ' must be a positive whole number')
    end
  end
  U.check(
    values.mode ~= 'tiered'
      or values.curveMode ~= 'generated'
      or tonumber(values.atTier) <= tonumber(values.maxMultiplier),
    'Current-tier multiplier must not exceed the maximum'
  )
end

local function relative(values, current, tier)
  local gap = index[current] - index[tier]
  if gap < 0 then
    return values.abovePolicy == 'skip' and 0 or tonumber(values.aboveMultiplier)
  end
  if values.curveMode == 'table' then
    return tonumber(values['below' .. math.min(gap, 7)])
  end
  local first, maximum = tonumber(values.atTier), tonumber(values.maxMultiplier)
  local span = tonumber(values.curveSpan)
  local fraction = math.min(1, gap / span)
  if values.curveShape == 'logarithmic' then
    return math.floor(
      first + (maximum - first) * math.log(1 + math.min(gap, span)) / math.log(1 + span) + 0.5
    )
  end
  return math.floor(first * (maximum / first) ^ fraction + 0.5)
end

function M.budget(values, tier)
  if not index[tier] then
    return tonumber(values.unknownMultiplier)
  end
  if index[tier] > index[values.currentTier] and values.abovePolicy == 'skip' then
    return 0
  end
  return tonumber(values['override' .. tier]) or relative(values, values.currentTier, tier)
end

-- Called once per requested recipe, before its items/fluids are resolved.
-- Stocked circuits, molds and omitted insulation solids do not constrain a batch.
function M.resolve(values, materialTier, eut, factor, quantities, materialSource)
  factor = factor or 1
  U.check(U.integer(factor) and factor > 0, 'Pattern multiplier must be a positive whole number')
  local recipeTier = M.voltageTier(eut)
  local detail = {
    materialTier = materialTier,
    recipeTier = recipeTier,
    eut = eut,
    materialSource = materialSource,
  }
  if not values or values.mode == 'fixed' then
    detail.multiplier = factor
    return factor, detail
  end
  M.validate(values)
  -- Fixed program multipliers are intentionally irrelevant in tiered mode.
  local effectiveTier = materialTier
  if not index[effectiveTier] then
    if values.unknownPolicy == 'skip' then
      detail.excluded = 'Unclassified material: skipped by settings'
    elseif values.unknownPolicy == 'voltage' and recipeTier then
      effectiveTier = recipeTier
      detail.tierSource = 'recipe voltage estimate'
    end
  end
  detail.effectiveTier = effectiveTier
  detail.materialBudget = M.budget(values, effectiveTier)
  if detail.materialBudget == 0 then
    detail.excluded = 'Material tier above current progression'
  end
  local target = detail.materialBudget
  if values.voltagePolicy == 'cap' then
    local reference = values.voltageTier == 'current' and values.currentTier or values.voltageTier
    if recipeTier and index[recipeTier] > index[reference] then
      detail.excluded = 'Recipe voltage above ' .. reference
    end
    detail.voltageBudget = recipeTier and relative(values, reference, recipeTier)
      or tonumber(values.unknownMultiplier)
    target = math.min(target, detail.voltageBudget)
  end
  if detail.excluded then
    detail.multiplier = 0
    return 0, detail
  end
  target = math.min(target, tonumber(values.maxMultiplier))
  for _, q in ipairs(quantities or {}) do
    local limit = tonumber(values[q.type == 'fluid' and 'fluidLimit' or 'itemLimit'])
    target = math.min(target, math.floor(limit / q.size))
  end
  U.check(target >= 1, 'One recipe batch exceeds the configured item/fluid limit')
  detail.multiplier = target
  return target, detail
end

function M.voltageText(detail)
  if not detail.recipeTier then
    return 'Unknown EU/t'
  end
  local digits = string.format('%.0f', detail.eut)
  local grouped = digits:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
  return grouped .. ' EU/t (' .. detail.recipeTier .. ')'
end

function M.describe(detail)
  local material = detail.materialTier
    or (detail.effectiveTier and (detail.effectiveTier .. ' estimated') or 'unclassified')
  if detail.materialTier and detail.materialSource and detail.materialSource ~= 'quest item' then
    material = material .. ' (estimated)'
  end
  return 'Batch '
    .. detail.multiplier
    .. 'x  |  Material '
    .. material
    .. '  |  '
    .. M.voltageText(detail)
end

-- OC accepts RGB, without alpha. Blend tier colors locally when requested.
function M.color(tier, background, opacity)
  local rgb = Tiers.colors[index[tier]] or background
  if not opacity then
    return rgb
  end
  local value = 0
  for _, divisor in ipairs({ 65536, 256, 1 }) do
    local foreground = math.floor(rgb / divisor) % 256
    local back = math.floor(background / divisor) % 256
    value = value + math.floor(foreground * opacity + back * (1 - opacity) + 0.5) * divisor
  end
  return value
end
return M

end)()
local Programs=(function()
-- Source: source/lib/programs.lua
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
    'Fixed policy only: multiply every requested recipe input and output by this amount.',
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
  M.byId[program.id] = program
  if #program.fields > 0 then
    M.settings[#M.settings + 1] = program
  end
end
function M.switchKey(program, form)
  return program.switchByDestination and program.outputs[form] or form
end
return M

end)()
local Config=(function()
-- Source: source/lib/config.lua
-- One configuration for the application: shared hardware and per-program fields.
local U = U
local Programs = Programs
local Batch = Batch
local M = {}
M.destinationSlots = 36
function M.selected(value, choices)
  U.check(type(value) == 'string', 'Missing multi-choice setting')
  local allowed, seen, tokens = {}, {}, {}
  for _, entry in ipairs(choices) do
    allowed[entry[1]] = true
  end
  if value ~= '' then
    for key in value:gmatch('[^,]+') do
      U.check(allowed[key] and not seen[key], 'Invalid or duplicate output switch: ' .. key)
      seen[key] = true
      tokens[#tokens + 1] = key
    end
    U.check(table.concat(tokens, ',') == value, 'Invalid output switch list')
  end
  return seen
end
function M.toggleSelected(value, choices, key)
  local selected = M.selected(value, choices)
  selected[key] = not selected[key]
  local result = {}
  for _, entry in ipairs(choices) do
    if selected[entry[1]] then
      result[#result + 1] = entry[1]
    end
  end
  return table.concat(result, ',')
end
M.fields = {
  {
    key = 'editor',
    label = 'Pattern editor interface',
    help = 'Exact terminal name of the interface connected directly to the OC adapter.',
    default = 'OC Pattern Editor',
  },
  {
    key = 'donors',
    label = 'New pattern buffer name',
    help = 'All remote interfaces with this exact name supply disposable encoded patterns.',
    default = 'OC Pattern Buffer',
  },
  {
    key = 'terminalAddress',
    placeholder = 'auto',
    label = 'Terminal component address',
    help = 'Blank selects the only terminal; otherwise enter its address or unique prefix.',
    default = '',
  },
  {
    key = 'editorAddress',
    placeholder = 'auto',
    label = 'Editor component address',
    help = 'Blank selects the only directly connected ME interface.',
    default = '',
  },
  {
    key = 'dataAddress',
    placeholder = 'auto',
    label = 'Data Card address',
    help = 'Blank selects the only Data Card.',
    default = '',
  },
  {
    key = 'energyPause',
    kind = 'number',
    label = 'Pause work below energy %',
    help = 'Pause component work at this charge level.',
    default = '25',
  },
  {
    key = 'energyResume',
    kind = 'number',
    label = 'Resume work at energy %',
    help = 'At least 10 percentage points above the pause level; at most 95%.',
    default = '75',
  },
}
M.defaults = { version = 2, shared = {}, batch = {}, programs = {} }
for _, f in ipairs(M.fields) do
  M.defaults.shared[f.key] = f.default
end
for _, f in ipairs(Batch.fields) do
  M.defaults.batch[f.key] = f.default
end
M.sections = {
  shared = { name = 'Shared interfaces', fields = M.fields },
  batch = { name = 'Tier multipliers', fields = Batch.fields, pageSize = 9 },
}
function M.section(id)
  return U.check(M.sections[id] or Programs.byId[id], 'Unknown settings section')
end
function M.visibleFields(c, section)
  local result, values = {}, M.values(c, section)
  for _, f in ipairs(M.section(section).fields) do
    local visible = not f.hidden and (f.key ~= 'multiplier' or c.batch.mode == 'fixed')
    for key, expected in pairs(f.when or {}) do
      local match = values[key] == expected
      if type(expected) == 'table' then
        for _, option in ipairs(expected) do
          match = match or values[key] == option
        end
      end
      visible = visible and match
    end
    if visible then
      result[#result + 1] = f
    end
  end
  return result
end
for _, p in ipairs(Programs.list) do
  local values = {}
  M.defaults.programs[p.id] = values
  for _, f in ipairs(p.fields) do
    values[f.key] = f.default
  end
end
-- Expand shorthand only in numeric fields. Runtime consumers continue to read
-- ordinary decimal values; names, addresses and templates are never rewritten.
local function normalizeNumber(value)
  local digits, suffix = U.trim(value):match('^([+-]?%d*%.?%d+)([kKmM])$')
  if not digits then
    return value
  end
  local scale = suffix:lower() == 'k' and 1000 or 1000000
  local number = tonumber(digits) * scale
  if U.integer(number) then
    return string.format('%.0f', number)
  end
  -- Keep fractions for validation, and leave overflow invalid rather than
  -- rounding or accepting a value beyond the existing integer limits.
  return number == number and math.abs(number) < math.huge and tostring(number) or value
end

function M.normalize(c)
  local function fields(values, definitions)
    U.check(type(values) == 'table', 'Missing configuration section')
    for _, f in ipairs(definitions) do
      local value = values[f.key]
      if
        (f.kind == 'number' or f.kind == 'positiveInteger' or f.kind == 'optionalPositiveInteger')
        and type(value) == 'string'
        and not value:find('[%c]')
      then
        values[f.key] = normalizeNumber(value)
      end
    end
  end
  fields(c.shared, M.fields)
  fields(c.batch, Batch.fields)
  for _, p in ipairs(Programs.list) do
    fields(c.programs[p.id], p.fields)
  end
  return c
end

function M.validate(c)
  U.check(
    type(c) == 'table'
      and c.version == 2
      and type(c.shared) == 'table'
      and type(c.programs) == 'table',
    'Invalid configuration'
  )
  local function fields(values, definitions)
    U.check(type(values) == 'table', 'Missing configuration section')
    for _, f in ipairs(definitions) do
      local v = values[f.key]
      U.check(
        type(v) == 'string' and #v <= 512 and not v:find('[%c]'),
        'Invalid setting: ' .. f.label
      )
      if f.kind == 'toggle' then
        U.check(v == 'on' or v == 'off', f.label .. ' must be on or off')
      end
      if f.kind == 'positiveInteger' then
        U.check(
          U.integer(tonumber(v)) and tonumber(v) > 0,
          f.label .. ' must be a positive whole number'
        )
      end
      if f.choices then
        if f.kind == 'multiToggle' then
          M.selected(v, f.choices)
        else
          local found = false
          for _, option in ipairs(f.choices) do
            if option[1] == v then
              found = true
            end
          end
          U.check(found, 'Invalid choice: ' .. f.label)
        end
      end
    end
  end
  fields(c.shared, M.fields)
  fields(c.batch, Batch.fields)
  Batch.validate(c.batch)
  for _, p in ipairs(Programs.list) do
    fields(c.programs[p.id], p.fields)
  end
  local pause, resume = tonumber(c.shared.energyPause), tonumber(c.shared.energyResume)
  U.check(
    pause and resume and pause >= 10 and pause <= 80 and resume >= pause + 10 and resume <= 95,
    'Energy pause must be 10..80%; resume at least 10% higher, up to 95%'
  )
  local a = c.programs.assline
  for _, key in ipairs({ 'itemName', 'renameName' }) do
    U.check(
      not a[key]:gsub('{label}', ''):gsub('{n}', ''):find('[{}]'),
      'Unknown template token: ' .. key
    )
  end
  U.check(a.itemName:find('{n}', 1, true), 'Item name template needs {n}')
  return c
end
function M.migrate(old)
  local c = U.clone(M.defaults)
  if not old then
    return c
  end
  U.check(type(old) == 'table', 'Invalid saved configuration')
  U.check(old.version == nil or old.version == 2, 'Unsupported saved configuration version')
  if old.version == 2 then
    if not old.batch then
      c.batch.mode = 'fixed'
    end
    for _, f in ipairs(Batch.fields) do
      if old.batch and old.batch[f.key] ~= nil then
        c.batch[f.key] = old.batch[f.key]
      end
    end
    if old.batch and not old.batch.curveMode then
      local prior = { 4, 32, 64, 256, 320, 400, 448, 512 }
      for gap = 0, 7 do
        local value = old.batch['below' .. gap]
        if value and tonumber(value) ~= prior[gap + 1] then
          c.batch.curveMode = 'table'
        end
      end
    end
    for _, f in ipairs(M.fields) do
      if old.shared and old.shared[f.key] ~= nil then
        c.shared[f.key] = old.shared[f.key]
      end
    end
    for _, p in ipairs(Programs.list) do
      for _, f in ipairs(p.fields) do
        local values = old.programs and old.programs[p.id]
        if values and values[f.key] ~= nil then
          c.programs[p.id][f.key] = values[f.key]
        end
      end
    end
  else
    c.batch.mode = 'fixed'
    -- The old "buffer" was actually the directly connected editor.
    local shared = {
      editor = 'buffer',
      donors = 'makerDonors',
      terminalAddress = 'terminalAddress',
      editorAddress = 'bufferAddress',
      dataAddress = 'dataAddress',
      energyPause = 'energyPause',
      energyResume = 'energyResume',
    }
    for key, legacy in pairs(shared) do
      if old[legacy] ~= nil and old[legacy] ~= '' then
        c.shared[key] = old[legacy]
      end
    end
    if old.makerWorkspace and old.makerWorkspace ~= '' then
      c.shared.editor = old.makerWorkspace
    end
    for _, key in ipairs({ 'target', 'itemName', 'renameName' }) do
      if old[key] ~= nil then
        c.programs.assline[key] = old[key]
      end
    end
    if old.makerDestination then
      if old.makerMode == 'coating' then
        c.programs.insulator.destination = old.makerDestination
      else
        c.programs.wiremill.wire1 = old.makerDestination
        c.programs.wiremill.wireFine = old.makerDestination
      end
    end
    if old.makerPVC then
      c.programs.insulator.polymer = old.makerPVC == 'off' and 'none' or 'pvcSmall'
    end
    if old.makerPPS then
      c.programs.insulator.pps = old.makerPPS
    end
  end
  local prior = old.programs and old.programs.insulator
  if prior and not prior.polymer and prior.pvc then
    c.programs.insulator.polymer = prior.pvc == 'off' and 'none' or 'pvcSmall'
  end
  return M.validate(M.normalize(c))
end
function M.capacityReport(groups)
  local result = {}
  for _, name in ipairs(U.keys(groups)) do
    local n = groups[name]
    result[#result + 1] =
      { name = name, patterns = n, interfaces = math.ceil(n / M.destinationSlots) }
  end
  return result
end
function M.values(c, section)
  return M.sections[section] and c[section]
    or U.check(c.programs[section], 'Unknown settings section')
end
function M.requireProgram(c, id)
  M.validate(c)
  local p = U.check(Programs.byId[id], 'Unknown program')
  U.check(not p.unavailable, p.unavailable)
  for _, key in ipairs({ 'editor', 'donors' }) do
    U.check(c.shared[key] ~= '', 'Set ' .. key .. ' in Settings > Shared interfaces')
  end
  U.check(
    c.shared.editor ~= c.shared.donors,
    'Pattern editor and new pattern buffer must have different names'
  )
  for _, f in ipairs(p.fields) do
    U.check(
      f.optional or c.programs[id][f.key] ~= '',
      'Set ' .. f.label .. ' in Settings > ' .. p.name
    )
  end
  if p.formSwitch and p.outputs then
    local selected = M.selected(c.programs[id][p.formSwitch], p.formChoices)
    local needed = {}
    for form, key in pairs(p.outputs) do
      if selected[Programs.switchKey(p, form)] then
        needed[key] = true
      end
    end
    for _, f in ipairs(p.fields) do
      if needed[f.key] then
        U.check(c.programs[id][f.key] ~= '', 'Set ' .. f.label .. ' in Settings > ' .. p.name)
      end
    end
  end
  return p
end
return M

end)()
-- Source: source/app/00_core.lua
-- GTNH 2.9 / OpenOS. Terminal pattern slots are ZERO based; direct slots ONE based.
local component = require('component')
local event = require('event')
local computer = require('computer')
local fs = require('filesystem')
local serialization = require('serialization')
local unicode = require('unicode')
local C = {}
C.stopped = 'Work stopped. Continue last operation or start a new preview.'
local U = U
local Programs = Programs
local Config = Config
local defaults = Config.defaults
local cfg = U.clone(defaults)
local work = { pause = 0.25, resume = 0.75 }
local perf
local tagKeys, renameTags, tagCount, renameCount = {}, {}, 0, 0
local function releaseWork()
  perf = nil
  work.progress = nil
  work.control = nil
  work.atomic = false
  tagKeys, renameTags, tagCount, renameCount = {}, {}, 0, 0
end
local function sampleEnergy()
  local t = computer.uptime()
  local e, m = computer.energy(), computer.maxEnergy()
  if perf then
    perf.samples = perf.samples + 1
    perf.sampleTime = perf.sampleTime + computer.uptime() - t
  end
  U.check(type(m) == 'number' and m > 0, 'Computer energy capacity unavailable')
  return e, m
end
local function record(name, elapsed)
  if not perf then
    return
  end
  local v = perf.calls[name] or { 0, 0, 0 }
  perf.calls[name] = v
  v[1] = v[1] + 1
  v[2] = v[2] + elapsed
  v[3] = math.max(v[3], elapsed)
end
local function perfReport(status)
  if not perf then
    return
  end
  local e, m = sampleEnergy()
  local elapsed = computer.uptime() - perf.started
  local callTime = 0
  local out = {
    string.format(
      '\nuptime=%.1fs %s elapsed=%.2fs energy=%.0f/%.0f (%.1f%% -> %.1f%%)',
      computer.uptime(),
      status,
      elapsed,
      e,
      m,
      perf.startPct * 100,
      e / m * 100
    ),
    string.format('free memory=%d -> %d bytes', perf.memory, computer.freeMemory()),
    string.format(
      'energy samples=%d time=%.3fs pauses=%d event.pull yields=%d wait=%.2fs',
      perf.samples,
      perf.sampleTime,
      perf.pauses,
      perf.yields,
      perf.wait
    ),
  }
  for name, v in pairs(perf.calls) do
    callTime = callTime + v[2]
    out[#out + 1] = string.format('%s calls=%d time=%.3fs max=%.3fs', name, v[1], v[2], v[3])
  end
  out[#out + 1] = string.format(
    'other time=%.3fs (Lua planning, file I/O, UI)',
    math.max(0, elapsed - perf.wait - callTime)
  )
  local path = '/home/assline-perf.log'
  if fs.exists(path) and fs.size(path) > 65536 then
    fs.remove(path)
  end
  local f = io.open(path, 'a')
  if f then
    f:write(table.concat(out, '\n') .. '\n')
    f:close()
  end
  releaseWork()
end
local function energyFraction()
  local e, m = sampleEnergy()
  return e / m
end
-- All component gates and waits share one cooperative control path. Stop is
-- deferred inside a journaled transaction; Pause can wait at any call boundary.
local function pollWork(delay)
  local e
  repeat
    local t = computer.uptime()
    e = work.control and (work.control(delay) or {}) or (delay > 0 and { event.pull(delay) } or {})
    if perf then
      if delay > 0 or work.control then
        perf.yields = perf.yields + 1
      end
      if delay > 0 then
        perf.wait = perf.wait + computer.uptime() - t
      end
    end
    if e.stop or e[1] == 'interrupted' or (e[1] == 'key_down' and e[4] == 1) then
      work.stopping = true
      work.stopReason = e.stop and C.stopped
        or 'Work cancelled. Continue last operation or scan again.'
    end
    delay = 0.25
  until not e.paused or work.stopping
  if work.stopping and not work.atomic then
    error(work.stopReason, 0)
  end
  return e
end
local function rest(seconds)
  local deadline = computer.uptime() + seconds
  repeat
    pollWork(math.max(0, math.min(0.25, deadline - computer.uptime())))
  until computer.uptime() >= deadline
end

local function gate()
  pollWork(0)
  if energyFraction() < work.pause then
    if perf then
      perf.pauses = perf.pauses + 1
    end
    local lastGain, lastValue, lastReport = computer.uptime(), computer.energy(), -math.huge
    while energyFraction() < work.resume do
      local now = computer.uptime()
      local value = computer.energy()
      if value > lastValue then
        lastGain = now
      end
      lastValue = value
      U.check(
        energyFraction() >= work.pause / 2,
        'Energy keeps falling; work stopped. Recharge, then Continue last operation / Scan.'
      )
      U.check(
        now - lastGain < 30,
        'No recharge for 30 seconds; work stopped. Check power input, then Continue last operation / Scan.'
      )
      if work.progress and now - lastReport >= 2 then
        work.progress(
          string.format(
            'Waiting for energy: %.0f%% -> %.0f%%. Pause / Resume / Stop.',
            energyFraction() * 100,
            work.resume * 100
          )
        )
        lastReport = now
      end
      rest(0.25)
    end
  end
end
local function startWork(c, progress, control)
  work = {
    pause = tonumber(c.shared.energyPause) / 100,
    resume = tonumber(c.shared.energyResume) / 100,
    progress = progress,
    control = control,
  }
  local e, m = sampleEnergy()
  perf = {
    started = computer.uptime(),
    startPct = e / m,
    memory = computer.freeMemory(),
    samples = 0,
    sampleTime = 0,
    pauses = 0,
    yields = 0,
    wait = 0,
    calls = {},
  }
  tagKeys, renameTags, tagCount, renameCount = {}, {}, 0, 0
end
local paths = {
  config = '/home/assline.cfg',
  pending = '/home/assline.pending',
  cursor = '/home/assline.pending.step',
  run = '/home/assline.run',
  abandoned = '/home/assline.abandoned',
  backup = '/home/assline.last',
}
local function readRaw(path, maximum)
  if not fs.exists(path) then
    return nil
  end
  U.check(fs.size(path) <= (maximum or 400000), 'File too large: ' .. path)
  local f = U.check(io.open(path, 'r'), 'Cannot open ' .. path)
  local s = f:read('*a')
  f:close()
  U.check(s, 'Cannot read ' .. path)
  return s
end
local function readFile(path)
  local s = readRaw(path)
  if not s then
    return nil
  end
  local t = serialization.unserialize(s)
  U.check(type(t) == 'table', 'Invalid file: ' .. path)
  return t
end
local function writeFile(path, t, maximum)
  local s = serialization.serialize(t)
  U.check(
    #s <= (maximum or 400000),
    'Recovery data exceeds disk/memory budget; use a smaller target interface'
  )
  U.check(
    computer.freeMemory() > #s + 131072,
    'Not enough memory to verify saved data; use a smaller target interface'
  )
  local temp = path .. '.tmp'
  local f = U.check(io.open(temp, 'w'), 'Cannot write ' .. temp)
  local ok, err = pcall(function()
    U.check(f:write(s), 'Write failed')
    U.check(f:flush(), 'Flush failed')
  end)
  f:close()
  U.check(ok, err)
  U.check(readRaw(temp, maximum) == s, 'Saved file verification failed')
  if fs.exists(path) then
    U.check(fs.remove(path), 'Cannot replace ' .. path)
  end
  U.check(fs.rename(temp, path), 'Cannot finish saving ' .. path)
end
local validate = Config.validate
local function selectDevice(kind, prefix)
  local matches = {}
  for addr, tp in component.list(kind, true) do
    if tp == kind and (prefix == '' or addr:sub(1, #prefix) == prefix) then
      matches[#matches + 1] = addr
    end
  end
  U.check(
    #matches == 1,
    'Need one ' .. kind .. ' (found ' .. #matches .. '); set its address in Settings'
  )
  return component.proxy(matches[1])
end
local function invoke(p, name, ...)
  U.check(p[name] ~= nil, 'Missing API ' .. name .. '; check GTNH / OpenComputers version')
  gate()
  local t = computer.uptime()
  local a, b, c = p[name](...)
  record(name, computer.uptime() - t)
  return a, b, c
end
local function nbt(data, tag)
  local t = tag and invoke(data, 'decodeNBT', tag) or { __nbt_type = 'compound', __value = {} }
  U.check(
    type(t) == 'table' and t.__nbt_type == 'compound' and type(t.__value) == 'table',
    'Typed NBT support required (GTNH 2.9 Data Card)'
  )
  return t
end
local function tagKey(data, s)
  U.check(
    not U.truth(s.hasTag) or type(s.tag) == 'string',
    'NBT is hidden; enable allowItemStackNBTTags in OC config'
  )
  if not s.tag then
    return '{}'
  end
  if tagKeys[s.tag] then
    return tagKeys[s.tag]
  end
  local decoded = nbt(data, s.tag)
  local key = next(decoded.__value) and U.canonical(decoded) or '{}'
  if tagCount < 32 and #s.tag <= 2048 and #key <= 2048 then
    tagKeys[s.tag] = key
    tagCount = tagCount + 1
  end
  return key
end
local function identity(data, s)
  return s.name .. ':' .. tostring(s.damage or 0) .. ':' .. tagKey(data, s)
end
local function stack(s)
  if not U.exists(s) then
    return nil
  end
  return {
    name = s.name,
    damage = s.damage,
    size = s.size,
    amount = s.amount,
    label = s.label,
    tag = s.tag,
    hasTag = s.hasTag,
  }
end
local function stackEq(data, a, b)
  if not U.exists(a) or not U.exists(b) then
    return not U.exists(a) and not U.exists(b)
  end
  if a.name ~= b.name or a.damage ~= b.damage or a.size ~= b.size or a.amount ~= b.amount then
    return false
  end
  if a.tag == b.tag and (a.tag or (not U.truth(a.hasTag) and not U.truth(b.hasTag))) then
    return true
  end
  return identity(data, a) == identity(data, b) and a.size == b.size and a.amount == b.amount
end
-- GTNH's typed decoder emits string wrappers, but its encoder only accepts
-- bare strings (the parseWithType match has no ("string", value) case).
-- Unwrap strings recursively, including existing names/lore and nested lists.
-- Keep all other NBT type wrappers intact. Never weaken round-trip verification.
local function encodableNBT(t)
  if type(t) ~= 'table' then
    return t
  end
  if t.__nbt_type == 'string' then
    U.check(type(t.__value) == 'string', 'Invalid NBT string value')
    return t.__value
  end
  local r = {}
  for k, v in pairs(t) do
    r[k] = encodableNBT(v)
  end
  return r
end
local function renamed(data, s, name)
  local key = U.canonical({ s.tag or false, name })
  local r = stack(s)
  r.hasTag = true
  r.label = name
  if renameTags[key] then
    r.tag = renameTags[key]
    return r
  end
  local t = nbt(data, s.tag)
  local d = t.__value.display
  if not d then
    d = { __nbt_type = 'compound', __value = {} }
    t.__value.display = d
  end
  U.check(d.__nbt_type == 'compound', 'Invalid display NBT')
  d.__value.Name = { __nbt_type = 'string', __value = name }
  r.tag = U.check(invoke(data, 'encodeNBT', encodableNBT(t)), 'NBT encode failed')
  U.check(U.eq(nbt(data, r.tag), t), 'NBT encode round trip failed')
  if renameCount < 32 and #key <= 2048 and #r.tag <= 2048 then
    renameTags[key] = r.tag
    renameCount = renameCount + 1
  end
  return r
end
local function compact(p)
  if not U.exists(p) then
    return nil
  end
  local r = stack(p)
  r.isCraftable = p.isCraftable
  r.inputs = {}
  r.outputs = {}
  for _, which in ipairs({ 'inputs', 'outputs' }) do
    for k, s in pairs(p[which] or {}) do
      if U.exists(s) then
        r[which][k] = stack(s)
      end
    end
  end
  return r
end
local function patternEq(data, a, b)
  if not U.exists(a) or not U.exists(b) then
    return not U.exists(a) and not U.exists(b)
  end
  return stackEq(data, a, b)
end
local function processing(p)
  return U.exists(p) and p.inputs and p.outputs and (p.isCraftable == false or p.isCraftable == 0)
end
local sides = { down = 0, up = 1, north = 2, south = 3, west = 4, east = 5, unknown = 6 }
local function side(s)
  if type(s) == 'number' then
    return s
  end
  return U.check(sides[tostring(s):lower()], 'Unknown interface side: ' .. tostring(s))
end
local function endpoint(i, slot)
  return U.endpoint({ location = i.location, side = side(i.side) }, slot)
end
local function where(i)
  return U.where(endpoint(i))
end
local function iterate(result, callback)
  U.check(result ~= nil, 'Interface lookup failed')
  if type(result) == 'table' and not getmetatable(result) then
    for _, i in pairs(result) do
      if type(i) == 'table' and i.location then
        callback(i)
      end
    end
  else
    while true do
      gate()
      local t = computer.uptime()
      local i = result()
      record('terminal iterator', computer.uptime() - t)
      if not i then
        break
      end
      callback(i)
    end
  end
end
local function lookup(hw, name, metadata)
  local found = {}
  local result = invoke(hw.terminal, 'getInterfacesByName', name)
  if metadata then
    U.check(result and result.getAll, 'Metadata-only discovery requires getAll(false)')
    result = invoke(result, 'getAll', false)
  end
  iterate(result, function(i)
    U.check(not metadata or i.patterns == nil, 'Driver ignored metadata-only discovery')
    if i.name == name then
      found[#found + 1] = i
    end
  end)
  table.sort(found, function(a, b)
    return U.ordered(endpoint(a), endpoint(b))
  end)
  return found
end
local function unique(hw, name)
  local list = lookup(hw, name)
  U.check(#list == 1, 'Expected one interface named "' .. name .. '", found ' .. #list)
  return list[1]
end
local function current(hw, ref)
  local found
  iterate(invoke(hw.terminal, 'getInterfacesByLocation', ref.location, ref.side), function(i)
    if where(i) == where(ref) then
      U.check(not found, 'Ambiguous interface location')
      found = i
    end
  end)
  return U.check(found, 'Interface unavailable at ' .. where(ref))
end
local function direct(hw, name, slot, ...)
  if hw.buffer.side ~= 6 then
    return invoke(hw.direct, name, hw.buffer.side, slot + 1, ...)
  end
  return invoke(hw.direct, name, slot + 1, ...)
end
local function encodedPattern(data, p)
  if not U.exists(p) or not p.tag or p.isCraftable == nil or not p.inputs or not p.outputs then
    return nil
  end
  local root = nbt(data, p.tag).__value
  -- Ultimate processing patterns omit crafting; OC reads the missing flag as false.
  if
    root['in']
    and root['in'].__nbt_type == 'list'
    and root.out
    and root.out.__nbt_type == 'list'
  then
    return root
  end
end
-- Canonical ingredient identity shared by planning and editor read-back.
-- AE2FC drops encode one mB per item; FluidTag is the fluid's own NBT.
local function patternIngredient(data, s, entry)
  U.check(not U.truth(s.hasTag) or type(s.tag) == 'string', 'Ingredient NBT hidden')
  local count = U.patternCount(s, entry)
  if not count then
    return nil
  end
  local normalized = stack(s)
  normalized.size, normalized.amount = count, nil
  normalized.type = s.damage == nil and 'fluid' or 'item'
  if s.name == 'ae2fc:fluid_drop' then
    local fields = entry and entry.__value
    local tag = fields and fields.tag
    if type(tag) ~= 'table' or tag.__nbt_type ~= 'compound' then
      tag = s.tag and nbt(data, s.tag)
    end
    local fluid = tag and tag.__value and tag.__value.Fluid
    U.check(
      fluid and fluid.__nbt_type == 'string' and fluid.__value ~= '',
      'Fluid drop has no readable Fluid name'
    )
    normalized.type, normalized.name, normalized.damage = 'fluid', fluid.__value:lower(), nil
    normalized.tag, normalized.hasTag = nil, false
    normalized.label = s.label and s.label:gsub('^[Dd]rop of ', '')
    local fluidTag = tag.__value.FluidTag
    if fluidTag and next(fluidTag.__value) then
      normalized.tag = invoke(data, 'encodeNBT', encodableNBT(fluidTag))
      U.check(U.eq(nbt(data, normalized.tag), fluidTag), 'Fluid NBT round trip failed')
      normalized.hasTag = true
    end
  end
  return normalized
end
local function fluidDrop(data, s)
  local root = {
    __nbt_type = 'compound',
    __value = {
      Fluid = { __nbt_type = 'string', __value = s.name },
    },
  }
  if s.tag then
    root.__value.FluidTag = nbt(data, s.tag)
  end
  local tag = invoke(data, 'encodeNBT', encodableNBT(root))
  U.check(U.eq(nbt(data, tag), root), 'Fluid drop NBT round trip failed')
  return { type = 'item', name = 'ae2fc:fluid_drop', damage = 0, size = s.size, tag = tag }
end
local function effectivePattern(data, p)
  if not U.exists(p) then
    return p
  end
  local needsNormalization = p.name == 'ae2fc:encodedPattern'
  for _, which in ipairs({ 'inputs', 'outputs' }) do
    for _, s in pairs(p[which] or {}) do
      if
        U.exists(s)
        and (
          not U.integer(s.size)
          or s.size <= 0
          or s.amount ~= nil
          or s.name == 'ae2fc:fluid_drop'
        )
      then
        needsNormalization = true
        break
      end
    end
  end
  if not needsNormalization then
    return p
  end
  local root = encodedPattern(data, p)
  if not root then
    return p
  end
  local normalized = compact(p)
  for _, which in ipairs({ 'inputs', 'outputs' }) do
    for index, s in pairs(normalized[which]) do
      normalized[which][index] = patternIngredient(data, s, U.patternEntry(root, which, index)) or s
    end
  end
  return normalized
end
local function donorIssue(data, p)
  local root = encodedPattern(data, p)
  if not root then
    return 'Missing encoded input/output lists'
  end
  for _, entry in ipairs({
    { 'substitute', 'Input substitution enabled' },
    { 'beSubstitute', 'Output substitution enabled' },
    { 'tunnel', 'Input-only tunnel pattern' },
    { 'InvalidPattern', 'Pattern marked invalid by AE' },
  }) do
    if root[entry[1]] and U.truth(root[entry[1]].__value) then
      return entry[2], root
    end
  end
  return nil, root
end
local function patternFingerprint(hw, p)
  if not U.exists(p) then
    return nil
  end
  U.check(type(p.tag) == 'string', 'Pattern NBT hidden')
  return U.canonical({ p.name, p.damage, p.size, invoke(hw.data, 'sha256', p.tag) })
end
local function editorCapacity(hw)
  local function valid(n)
    local ok, reason = pcall(direct, hw, 'getInterfacePattern', n - 1)
    if ok then
      return true
    end
    U.check(tostring(reason):find('invalid slot', 1, true), reason)
    return false
  end
  U.check(valid(1), 'Pattern editor has no slots')
  local low, high = 1, 2
  while high <= 512 and valid(high) do
    low = high
    high = high * 2
  end
  if high > 512 then
    U.check(not valid(513), 'Pattern editor exceeds the supported 512 slots')
    high = 513
  end
  while high - low > 1 do
    local mid = math.floor((low + high) / 2)
    if valid(mid) then
      low = mid
    else
      high = mid
    end
  end
  return low
end
local function capacity(i)
  -- The terminal does not expose capacity. User-approved assumption; the UI
  -- requires verification of fully expanded destination interfaces before Apply.
  return Config.destinationSlots
end
local function connect(c, progress, control)
  validate(c)
  startWork(c, progress, control)
  local shared = c.shared
  local hw = {
    terminal = selectDevice('me_interface_terminal', shared.terminalAddress),
    direct = selectDevice('me_interface', shared.editorAddress),
    data = selectDevice('data', shared.dataAddress),
  }
  hw.buffer = endpoint(unique(hw, shared.editor))
  nbt(hw.data, invoke(hw.data, 'encodeNBT', { __nbt_type = 'compound', __value = {} }))
  return hw
end
C.defaults = defaults
C.config = Config
C.programs = Programs
C.capacity = capacity
C.perfReport = perfReport
C.releaseWork = releaseWork

-- Source: source/app/10_plan.lua
local function item(s)
  return U.exists(s)
    and s.damage ~= nil
    and s.amount == nil
    and not s.name:lower():find('fluiddrop', 1, true)
    and not s.name:lower():find('fluid_drop', 1, true)
    and not s.name:lower():find('fluidpacket', 1, true)
    and not s.name:lower():find('fluid_packet', 1, true)
end
local function metadata(data, p)
  local t = nbt(data, p.tag)
  -- AE2FC reads in/out. Its old duplicated Inputs/Outputs lists are preserved
  -- verbatim as metadata; the interface setters do not rewrite those copies.
  t.__value['in'] = nil
  t.__value.out = nil
  return t
end
local function safeDonor(data, p)
  if not processing(p) or not p.tag then
    return false
  end
  return donorIssue(data, p) == nil
end
local function pureRecipe(data, p, r)
  if not safeDonor(data, p) then
    return false
  end
  for _, which in ipairs({ 'inputs', 'outputs' }) do
    for index, s in pairs(p[which]) do
      if U.exists(s) and index ~= 1 then
        return false
      end
    end
  end
  local a, b = p.inputs[1], p.outputs[1]
  return item(a)
    and item(b)
    and a.size > 0
    and a.size == b.size
    and identity(data, a) == identity(data, r.input)
    and identity(data, b) == identity(data, r.output)
end
local function scan(c, progress, control)
  Config.requireProgram(c, 'assline')
  local settings = c.programs.assline
  local hw = connect(c, progress, control)
  local target = unique(hw, settings.target)
  U.check(where(target) ~= where(hw.buffer), 'Target is the pattern editor')
  local buffer = current(hw, hw.buffer)
  local p = {
    target = endpoint(target),
    buffer = hw.buffer,
    changes = {},
    recipes = {},
    errors = {},
    warnings = {},
    scanned = 0,
    skipped = 0,
    empty = {},
    protected = {},
  }
  local function problem(s)
    p.errors[#p.errors + 1] = s
  end
  local wanted = {}
  for _, slot in ipairs(U.keys(target.patterns)) do
    gate()
    local original = target.patterns[slot]
    if U.exists(original) then
      p.scanned = p.scanned + 1
      if processing(original) then
        U.check(
          type(original.tag) == 'string',
          'Pattern NBT is hidden; enable allowItemStackNBTTags'
        )
        local counts, occupied, changes = {}, {}, {}
        for _, s in pairs(original.inputs) do
          if item(s) then
            occupied[identity(hw.data, s)] = true
          end
        end
        for _, index in ipairs(U.keys(original.inputs)) do
          local s = original.inputs[index]
          if item(s) then
            local id = identity(hw.data, s)
            local n = counts[id] or 0
            counts[id] = n + 1
            if n > 0 then
              U.check(
                type(s.size) == 'number' and s.size > 0 and s.size <= 2147483647,
                'Unsupported input amount'
              )
              local output, label
              repeat
                label = U.token(settings.itemName, s.label or s.name, n)
                U.check(
                  unicode.len(label) <= 128,
                  'Generated item name is longer than 128 characters'
                )
                output = renamed(hw.data, s, label)
                if not occupied[identity(hw.data, output)] then
                  break
                end
                n = n + 1
                U.check(n <= 512, 'Cannot allocate unique item names')
              until false
              counts[id] = n + 1
              occupied[identity(hw.data, output)] = true
              changes[#changes + 1] = { index = index, before = stack(s), after = output }
              local destName = U.token(settings.renameName, s.label or s.name, n)
              local recipeKey = U.canonical({ destName, id, identity(hw.data, output) })
              if not wanted[recipeKey] then
                local r = { input = stack(s), output = output, name = destName }
                wanted[recipeKey] = r
                p.recipes[#p.recipes + 1] = r
              end
            end
          end
        end
        if #changes > 0 then
          p.changes[#p.changes + 1] = { slot = slot, original = compact(original), edits = changes }
        end
      else
        p.skipped = p.skipped + 1
      end
    end
    if progress then
      progress('Scanning pattern ' .. tostring(slot + 1))
    end
    U.check(computer.freeMemory() > 160000, 'Low memory; scan a smaller target interface')
  end
  -- Only requested names are fetched; no getAll(true) of a large ME network.
  local groups, used = {}, {}
  for _, r in ipairs(p.recipes) do
    if not groups[r.name] then
      groups[r.name] = lookup(hw, r.name)
      for _, bank in ipairs(groups[r.name]) do
        p.protected[where(bank)] = true
      end
    end
    local group = groups[r.name]
    for _, i in ipairs(group) do
      U.check(
        where(i) ~= where(target) and where(i) ~= where(hw.buffer),
        'Rename interface overlaps target or buffer'
      )
      for _, slot in ipairs(U.keys(i.patterns)) do
        if pureRecipe(hw.data, i.patterns[slot], r) then
          r.existing = endpoint(i, slot)
          break
        end
      end
      if r.existing then
        break
      end
    end
    if not r.existing then
      for _, i in ipairs(group) do
        local key = where(i)
        used[key] = used[key] or {}
        local slots = capacity(i)
        for slot = 0, slots - 1 do
          if not U.exists(i.patterns[slot]) and not used[key][slot] then
            used[key][slot] = true
            r.destination = endpoint(i, slot)
            break
          end
        end
        if r.destination then
          break
        end
      end
      if not r.destination then
        problem(
          'No verified free slot in "' .. r.name .. '" (missing, full, or capacity unavailable)'
        )
      end
    end
    if progress then
      progress('Checking ' .. r.name)
    end
  end
  for slot = 0, editorCapacity(hw) - 1 do
    local remote = buffer.patterns[slot]
    local live = direct(hw, 'getInterfacePattern', slot)
    U.check(
      patternEq(hw.data, remote, live),
      'Direct pattern editor does not match "' .. c.shared.editor .. '" at slot ' .. (slot + 1)
    )
    if not U.exists(remote) then
      p.empty[#p.empty + 1] = slot
    end
  end
  local donors = 0
  for _, bank in ipairs(lookup(hw, c.shared.donors)) do
    U.check(
      not p.protected[where(bank)]
        and where(bank) ~= where(target)
        and where(bank) ~= where(hw.buffer),
      'New pattern buffer overlaps destination or editor'
    )
    for _, slot in ipairs(U.keys(bank.patterns)) do
      local pattern = bank.patterns[slot]
      if safeDonor(hw.data, pattern) then
        donors = donors + 1
      end
    end
  end
  local n = 0
  for _, r in ipairs(p.recipes) do
    if not r.existing then
      n = n + 1
    end
  end
  p.newRecipes = n
  p.available = donors
  if donors < n then
    p.warnings[1] = 'Need '
      .. n
      .. ' disposable processing donors; have '
      .. donors
      .. '. Execution will wait for refills.'
  end
  local requirements = {}
  for name, group in pairs(groups) do
    local needed = 0
    for _, i in ipairs(group) do
      for _, pattern in pairs(i.patterns) do
        if U.exists(pattern) then
          needed = needed + 1
        end
      end
    end
    for _, recipe in ipairs(p.recipes) do
      if recipe.name == name and not recipe.existing then
        needed = needed + 1
      end
    end
    requirements[name] = needed
  end
  p.capacities = Config.capacityReport(requirements)
  if (#p.changes > 0 or n > 0) and #p.empty == 0 then
    problem('Leave one empty pattern slot in ' .. c.shared.editor .. ' for editing')
  end
  return p, hw
end
C.scan = scan

-- Source: source/app/20_apply.lua
-- One durable intent per moved pattern. Recovery completes only that operation;
-- another scan is required before continuing the rest of a batch.
local function rawList(data, p, which)
  local root = nbt(data, p.tag).__value
  local t = root[which == 'inputs' and 'in' or 'out']
  U.check(t and t.__nbt_type == 'list', 'Unsupported encoded pattern layout')
  return t.__value
end
local recipeOperations = { recipe = true, imprint = true, resize = true, park = true }
local function expected(data, op)
  local p = compact(effectivePattern(data, op.original))
  if recipeOperations[op.kind] then
    p.inputs = op.recipe and U.clone(op.recipe.inputs) or { [1] = op.input }
    p.outputs = op.recipe and U.clone(op.recipe.outputs) or { [1] = op.output }
  else
    for _, e in ipairs(op.edits) do
      p.inputs[e.index] = e.after
    end
  end
  return p
end
local function semantic(hw, p, q)
  if not U.exists(p) or not U.exists(q) or p.name ~= q.name or p.damage ~= q.damage then
    return false
  end
  if not U.eq(metadata(hw.data, p), metadata(hw.data, q)) then
    return false
  end
  p = effectivePattern(hw.data, p)
  for _, which in ipairs({ 'inputs', 'outputs' }) do
    local all = {}
    for k in pairs(p[which] or {}) do
      all[k] = true
    end
    for k in pairs(q[which] or {}) do
      all[k] = true
    end
    for k in pairs(all) do
      if not stackEq(hw.data, p[which][k], q[which][k]) then
        return false
      end
    end
  end
  return true
end
local function allowedPartial(hw, p, op)
  U.check(
    U.exists(p) and p.name == op.original.name and p.damage == op.original.damage,
    'Unexpected pattern in buffer'
  )
  U.check(
    U.eq(metadata(hw.data, p), metadata(hw.data, op.original)),
    'Pattern flags or other NBT changed; recovery stopped'
  )
  local final = expected(hw.data, op)
  p = effectivePattern(hw.data, p)
  local original = effectivePattern(hw.data, op.original)
  for _, which in ipairs({ 'inputs', 'outputs' }) do
    local all = {}
    for k in pairs(p[which] or {}) do
      all[k] = true
    end
    for k in pairs(original[which]) do
      all[k] = true
    end
    for k in pairs(final[which]) do
      all[k] = true
    end
    for k in pairs(all) do
      local a = p[which][k]
      local old = original[which][k]
      local new = final[which][k]
      U.check(
        stackEq(hw.data, a, old) or stackEq(hw.data, a, new),
        'Unexpected ' .. which .. ' slot ' .. k .. '; recovery stopped'
      )
    end
  end
end
local function transfer(hw, from, to)
  local ok, slot = invoke(hw.terminal, 'send', from, to)
  local destination = U.locationText(to) .. ' slot ' .. to.slot .. ' (zero based)'
  U.check(ok == true, 'Pattern transfer failed to ' .. destination .. ': ' .. tostring(slot))
  U.check(
    slot == to.slot,
    'Pattern moved to unexpected slot ' .. tostring(slot) .. '; requested ' .. destination
  )
end
local function verifyDelivery(hw, from, to, matches, failure)
  local after = current(hw, to).patterns[to.slot]
  if matches(after) then
    return
  end
  local message = failure
    .. ' at '
    .. U.locationText(to)
    .. ' slot '
    .. to.slot
    .. ' (zero based). '
  if not U.exists(after) then
    message = message
      .. 'Terminal send reported success, but the destination pattern is absent. '
      .. 'Check capacity cards: hidden slots can accept a transfer and then eject the pattern. '
    local source = current(hw, from).patterns[from.slot]
    message = message
      .. (
        U.exists(source) and 'Source still contains a pattern.'
        or 'Source is empty; check the interface and dropped items.'
      )
  else
    message = message .. 'Destination contains a different pattern.'
  end
  error(message .. ' Saved operation retained.', 0)
end
local function setEntry(hw, slot, which, index, s, previous, normalizedPrevious, patternName)
  local method = which == 'inputs' and 'setInterfacePatternInput' or 'setInterfacePatternOutput'
  if s then
    -- Resize old fluid drops without changing their representation or item NBT.
    -- Imprinting a different ingredient still uses the normal typed setter.
    if s.type == 'fluid' and previous and previous.name == 'ae2fc:fluid_drop' then
      local old = normalizedPrevious
      if old and old.name == s.name and tagKey(hw.data, old) == tagKey(hw.data, s) then
        local amount = s.size
        s = U.clone(previous)
        s.type, s.size, s.amount = 'item', amount, nil
      end
    end
    -- Ordinary AE2 patterns use PatternHelper's item-only parser. Their fluid
    -- ingredients must be drops; ultimate and fluid patterns accept native fluids.
    if s.type == 'fluid' and patternName == 'appliedenergistics2:item.ItemEncodedPattern' then
      s = fluidDrop(hw.data, s)
    end
    local detail = s.type == 'fluid'
        and { name = s.name, amount = s.size, size = s.size, tag = s.tag }
      or { name = s.name, damage = s.damage, size = s.size, tag = s.tag }
    U.check(
      direct(hw, method, slot, index, detail, s.type or 'item') == true,
      'Pattern setter returned failure'
    )
  else
    U.check(direct(hw, method, slot, index) == true, 'Pattern clear returned failure')
  end
end
local function finish(hw, op, progress)
  U.check(
    op.version == 1
      and op.direct == hw.direct.address
      and op.terminal == hw.terminal.address
      and op.data == hw.data.address
      and where(op.buffer) == where(hw.buffer),
    'Recovery hardware differs from saved operation'
  )
  local goal = expected(hw.data, op)
  local dest = current(hw, op.destination)
  local remote = current(hw, op.buffer)
  local p = remote.patterns[op.slot]
  U.check(
    patternEq(hw.data, p, direct(hw, 'getInterfacePattern', op.slot)),
    'Direct/terminal buffer mismatch'
  )
  local delivered = dest.patterns[op.destination.slot]
  if not U.exists(p) and U.exists(delivered) and semantic(hw, delivered, goal) then
    return -- A transfer succeeded immediately before the power loss.
  end
  if (op.kind == 'edit' or op.kind == 'resize' or op.kind == 'park') and not U.exists(p) then
    U.check(patternEq(hw.data, delivered, op.original), 'Original target pattern changed')
    transfer(hw, op.destination, endpoint(op.buffer, op.slot))
    p = direct(hw, 'getInterfacePattern', op.slot)
    U.check(patternEq(hw.data, p, op.original), 'Moved pattern failed read-back')
  else
    U.check(not U.exists(delivered), 'Destination slot is occupied')
  end
  if op.source and not U.exists(p) then
    local source = current(hw, op.source).patterns[op.source.slot]
    U.check(patternEq(hw.data, source, op.original), 'Donor pattern changed')
    transfer(hw, op.source, endpoint(op.buffer, op.slot))
    p = direct(hw, 'getInterfacePattern', op.slot)
    U.check(patternEq(hw.data, p, op.original), 'Moved donor failed read-back')
  end
  allowedPartial(hw, p, op)
  local observed = effectivePattern(hw.data, p)
  if recipeOperations[op.kind] then
    -- Clearing removes an NBT list element: ALWAYS clear from the end.
    for _, which in ipairs({ 'inputs', 'outputs' }) do
      local desired = goal[which]
      local entries = rawList(hw.data, p, which)
      for index, s in ipairs(desired) do
        if not stackEq(hw.data, observed[which][index], s) then
          setEntry(hw, op.slot, which, index, s, p[which][index], observed[which][index], p.name)
        end
      end
      for index = U.largest(entries), #desired + 1, -1 do
        local entry = entries[index]
        U.check(
          entry and entry.__nbt_type == 'compound' and type(entry.__value) == 'table',
          'Invalid pattern list entry'
        )
        -- AE ignores empty compounds. Do not spend a server tick removing every
        -- unused cell in a padded processing donor. Clear nonempty cells only.
        if next(entry.__value) ~= nil then
          setEntry(hw, op.slot, which, index)
        end
      end
    end
  else
    for _, e in ipairs(op.edits) do
      if not stackEq(hw.data, observed.inputs[e.index], e.after) then
        setEntry(hw, op.slot, 'inputs', e.index, e.after)
      end
    end
  end
  p = direct(hw, 'getInterfacePattern', op.slot)
  U.check(semantic(hw, p, goal), 'Edited pattern read-back failed; saved recovery record retained')
  U.check(
    patternEq(hw.data, current(hw, op.buffer).patterns[op.slot], p),
    'Edited direct buffer differs from named terminal buffer'
  )
  local liveDest = current(hw, op.destination)
  U.check(not U.exists(liveDest.patterns[op.destination.slot]), 'Destination filled during edit')
  transfer(hw, endpoint(op.buffer, op.slot), op.destination)
  verifyDelivery(hw, endpoint(op.buffer, op.slot), op.destination, function(after)
    return semantic(hw, after, goal)
  end, 'Destination read-back failed')
  U.check(not U.exists(direct(hw, 'getInterfacePattern', op.slot)), 'Buffer slot did not empty')
  if progress then
    progress('Verified pattern in destination slot ' .. (op.destination.slot + 1))
  end
end
local function saveOp(hw, op)
  U.check(not fs.exists(paths.pending), 'Continue or stop the saved operation first')
  op.version = 1
  op.direct = hw.direct.address
  op.terminal = hw.terminal.address
  op.data = hw.data.address
  op.buffer = U.clone(hw.buffer)
  writeFile(paths.pending, op)
  work.atomic = true
end
local function clearOp()
  U.check(fs.remove(paths.pending), 'Cannot clear completed recovery record')
  if fs.exists(paths.cursor) then
    U.check(fs.remove(paths.cursor), 'Cannot clear completed recovery progress')
  end
  work.atomic = false
  gate()
end

-- Donor supply is live, unlike the destination plan. Keep only slot references
-- between operations, and check each physical pattern immediately before use.
-- Both programs use this pool; waiting never creates a recovery intent.
local function donorPool(hw, name, protected, progress)
  local banks, bankIndex, slots, slotIndex = nil, 1, {}, 1
  local function refreshBanks()
    banks = lookup(hw, name, true)
    bankIndex = 1
  end

  return function()
    while true do
      gate()
      local source = slots[slotIndex]
      if source then
        slotIndex = slotIndex + 1
        local bank = current(hw, source)
        U.check(
          not protected[where(bank)] and where(bank) ~= where(hw.buffer),
          'Donor interface overlaps a destination or the editor'
        )
        local pattern = bank.patterns[source.slot]
        if bank.name == name and safeDonor(hw.data, pattern) then
          return source, compact(pattern)
        end
      else
        if not banks then
          refreshBanks()
        end
        local entry = banks[bankIndex]
        if entry then
          bankIndex = bankIndex + 1
          U.check(
            not protected[where(entry)] and where(entry) ~= where(hw.buffer),
            'Donor interface overlaps a destination or the editor'
          )
          local bank = current(hw, entry)
          slots = {}
          slotIndex = 1
          if bank.name == name then
            for _, slot in ipairs(U.keys(bank.patterns)) do
              if safeDonor(hw.data, bank.patterns[slot]) then
                slots[#slots + 1] = endpoint(bank, slot)
              end
            end
          end
        else
          if progress then
            progress(
              'Waiting for processing donors in "'
                .. name
                .. '". Refill buffers to continue; Stop / Esc to stop.',
              true
            )
          end
          rest(1)
          refreshBanks()
        end
      end
    end
  end
end

local function apply(c, plan, progress, control)
  U.check(
    not fs.exists(paths.pending),
    'Continue or stop the saved operation before applying another scan'
  )
  U.check(#plan.errors == 0, 'Resolve scan blockers first')
  local fresh, hw = scan(c, progress, control)
  local function fixed(p)
    local value = U.clone(p)
    value.available = nil
    value.warnings = nil
    return value
  end
  U.check(
    U.eq(fixed(fresh), fixed(plan)),
    'Patterns or destinations changed since preview. Scan again.'
  )
  fresh = nil
  writeFile(paths.backup, { config = U.clone(c), plan = plan })
  local workspace = plan.empty[1]
  local protected = U.clone(plan.protected)
  protected[where(plan.target)] = true
  local takeDonor = donorPool(hw, c.shared.donors, protected, progress)
  for _, r in ipairs(plan.recipes) do
    if not r.existing then
      U.check(workspace ~= nil, 'No free pattern editor slot')
      local source, original = takeDonor()
      local op = {
        kind = 'recipe',
        slot = workspace,
        source = source,
        original = original,
        destination = r.destination,
        input = r.input,
        output = r.output,
      }
      U.check(
        not U.exists(direct(hw, 'getInterfacePattern', workspace)),
        'Pattern editor workspace occupied'
      )
      saveOp(hw, op)
      finish(hw, op, progress)
      clearOp()
    end
  end
  for _, v in ipairs(plan.changes) do
    -- One fresh snapshot per interface, used only for this target operation.
    -- Check only the recipes used by this target, not the batch's full manifest.
    local required = {}
    for _, e in ipairs(v.edits) do
      required[identity(hw.data, e.after)] = true
    end
    local snapshots = {}
    for _, r in ipairs(plan.recipes) do
      if required[identity(hw.data, r.output)] then
        local e = r.existing or r.destination
        local key = where(e)
        if not snapshots[key] then
          snapshots[key] = current(hw, e)
        end
        U.check(
          pureRecipe(hw.data, snapshots[key].patterns[e.slot], r),
          'Rename recipe removed or changed; scan again'
        )
      end
    end
    U.check(workspace ~= nil, 'No free buffer slot')
    local op = {
      kind = 'edit',
      slot = workspace,
      original = v.original,
      edits = v.edits,
      destination = endpoint(plan.target, v.slot),
    }
    U.check(not U.exists(direct(hw, 'getInterfacePattern', workspace)), 'Buffer workspace occupied')
    saveOp(hw, op)
    finish(hw, op, progress)
    clearOp()
  end
end
local function recover(c, progress, control)
  local op = U.check(readFile(paths.pending), 'No pending operation')
  local hw = connect(c, progress, control)
  work.atomic = true
  if op.kind == 'move' or op.kind == 'sort' then
    U.check(
      op.direct == hw.direct.address
        and op.terminal == hw.terminal.address
        and op.data == hw.data.address
        and where(op.buffer) == where(hw.buffer),
      'Recovery hardware differs from saved operation'
    )
    if op.kind == 'sort' then
      C.maker.finishSort(hw, op, progress)
    else
      C.maker.finishMove(hw, op)
    end
  else
    finish(hw, op, progress)
  end
  clearOp()
end
C.apply = apply
C.recover = recover
C.paths = paths
C.finish = finish

local Planner=(function()
-- Source: source/lib/planner.lua
-- Pure pattern placement planner. No component, filesystem or UI calls.
-- Recipe modes provide an ordered manifest; adapters provide compact snapshots.
local M = { version = 1 }
local U = U
local copy, integer, need, sequence, encoded = U.clone, U.integer, U.check, U.sequence, U.canonical
local ref, place, ordered = U.endpoint, U.where, U.ordered
local function address(r)
  return place(r) .. ':' .. r.slot
end
local function validateSnapshot(snapshot)
  need(
    type(snapshot) == 'table' and type(snapshot.interfaces) == 'table',
    'Missing interface snapshot'
  )
  sequence(snapshot.interfaces, 'Interfaces')
  local interfaces, seen = {}, {}
  for _, i in ipairs(snapshot.interfaces) do
    need(type(i.location) == 'table', 'Missing interface location')
    for _, k in ipairs({ 'dimId', 'x', 'y', 'z' }) do
      need(integer(i.location[k]), 'Invalid location ' .. k)
    end
    need(integer(i.side) and i.side >= 0 and i.side <= 6, 'Invalid interface side')
    need(
      integer(i.capacity) and i.capacity >= 1 and i.capacity <= 512,
      'Usable capacity must be 1..512'
    )
    need(type(i.name) == 'string' and i.name ~= '', 'Missing exact interface name')
    need(
      i.role == 'destination' or i.role == 'donor' or i.role == 'workspace',
      'Invalid interface role'
    )
    local id = place(i)
    need(not seen[id], 'Overlapping interface roles or duplicate location: ' .. id)
    seen[id] = true
    need(type(i.patterns) == 'table', 'Missing pattern snapshot')
    for slot, p in pairs(i.patterns) do
      need(integer(slot) and slot >= 0, 'Invalid zero-based pattern slot')
      need(
        type(p) == 'table' and type(p.fingerprint) == 'string' and p.fingerprint ~= '',
        'Missing pattern fingerprint'
      )
      need(
        p.kind == 'crafting' or p.kind == 'processing' or p.kind == 'unknown',
        'Invalid pattern type'
      )
      need(p.recipeKey == nil or type(p.recipeKey) == 'string', 'Invalid recipe key')
      need(p.donor == nil or type(p.donor) == 'boolean', 'Invalid disposable-donor flag')
    end
    interfaces[#interfaces + 1] = i
  end
  table.sort(interfaces, ordered)
  return interfaces
end

-- Processing recipes compare multisets; crafting recipes compare exact grid
-- positions. Processing identity uses proportions across BOTH sides together.
-- Return the batch divisor too, so matching and quantity edits stay separate
-- without storing a second full ingredient signature for each pattern.
function M.recipeKey(recipe)
  need(recipe.kind == 'crafting' or recipe.kind == 'processing', 'Recipe kind must be explicit')
  local function entries(list, grid)
    need(type(list) == 'table', 'Missing recipe ingredients')
    local r = {}
    for index, s in pairs(list) do
      need(integer(index) and index >= 1 and index <= 512, 'Invalid recipe entry index')
      need(
        type(s) == 'table' and type(s.name) == 'string' and s.name ~= '',
        'Missing registry name'
      )
      need(s.type == 'item' or s.type == 'fluid', 'Ingredient type must be explicit')
      local n = s.size
      need(integer(n) and n > 0, 'Ingredient quantity must be a positive integer')
      if s.type == 'item' then
        need(integer(s.damage) and s.damage >= 0, 'Missing item damage')
      end
      need(s.tag == nil or type(s.tag) == 'string', 'NBT must be an exact encoded tag string')
      local id = encoded({ s.type, s.name, s.damage or false, s.tag or false })
      if grid then
        need(
          index <= 9 and s.type == 'item' and n == 1,
          'Crafting inputs must be individual items in a 3x3 grid'
        )
        r[index] = { id, n }
      else
        r[id] = (r[id] or 0) + n
      end
    end
    need(next(r) ~= nil, 'Empty ingredient list')
    return r
  end
  need(
    recipe.substitute == nil or type(recipe.substitute) == 'boolean',
    'Invalid substitution policy'
  )
  need(
    recipe.beSubstitute == nil or type(recipe.beSubstitute) == 'boolean',
    'Invalid output substitution policy'
  )
  local identity = {
    recipe.kind,
    entries(recipe.inputs, recipe.kind == 'crafting'),
    entries(recipe.outputs, false),
    recipe.substitute == true,
    recipe.beSubstitute == true,
  }
  local divisor = 1
  if recipe.kind == 'processing' then
    divisor = 0
    for _, list in ipairs({ identity[2], identity[3] }) do
      for _, quantity in pairs(list) do
        local a, b = divisor, quantity
        while b ~= 0 do
          a, b = b, a % b
        end
        divisor = a
      end
    end
    for _, list in ipairs({ identity[2], identity[3] }) do
      for id, quantity in pairs(list) do
        list[id] = quantity / divisor
      end
    end
  end
  return encoded(identity), divisor
end

function M.plan(request, snapshot, checkpoint)
  need(
    type(request) == 'table' and type(request.recipes) == 'table',
    'Missing ordered recipe manifest'
  )
  sequence(request.recipes, 'Recipes')
  local interfaces = validateSnapshot(snapshot)
  local p = {
    version = 1,
    errors = {},
    warnings = {},
    layout = {},
    moves = {},
    creates = {},
    resizes = {},
    resizeCount = 0,
    preserved = {},
    reused = 0,
    required = { crafting = 0, processing = 0 },
    available = { crafting = 0, processing = 0 },
    donorBanks = 0,
    donorOccupied = 0,
    donorRejected = 0,
    donorReasons = {},
  }
  local problems = {}
  local function block(message)
    if not problems[message] then
      p.errors[#p.errors + 1] = message
      problems[message] = true
    end
  end
  local groups, workspace, tokens, occupied = {}, nil, {}, {}
  for _, i in ipairs(interfaces) do
    if checkpoint then
      checkpoint()
    end
    for slot in pairs(i.patterns) do
      if slot >= i.capacity then
        block('Pattern outside configured usable capacity: ' .. i.name .. ' slot ' .. slot)
      end
    end
    if i.role == 'destination' then
      local g = groups[i.name] or { slots = {}, tokens = {}, wanted = {} }
      groups[i.name] = g
      for slot = 0, i.capacity - 1 do
        local e = ref(i, slot)
        g.slots[#g.slots + 1] = e
        local pattern = i.patterns[slot]
        if pattern then
          local t = { pattern = pattern, current = e }
          tokens[#tokens + 1] = t
          g.tokens[#g.tokens + 1] = t
          occupied[address(e)] = t
        end
      end
    elseif i.role == 'donor' then
      p.donorBanks = p.donorBanks + 1
      for slot = 0, i.capacity - 1 do
        local pattern = i.patterns[slot]
        if pattern then
          p.donorOccupied = p.donorOccupied + 1
          if not pattern.donor then
            p.donorRejected = p.donorRejected + 1
            local reason = pattern.reason or 'Unsupported pattern'
            p.donorReasons[reason] = (p.donorReasons[reason] or 0) + 1
          end
        end
        if pattern and pattern.donor and p.available[pattern.kind] ~= nil then
          p.available[pattern.kind] = p.available[pattern.kind] + 1
        end
      end
    else
      for slot = 0, i.capacity - 1 do
        if not i.patterns[slot] and not workspace then
          workspace = ref(i, slot)
        end
      end
    end
  end
  local seen, groupOrder = {}, {}
  for _, r in ipairs(request.recipes) do
    if checkpoint then
      checkpoint()
    end
    need(
      type(r.key) == 'string' and r.key ~= '' and not seen[r.key],
      'Recipe keys must be unique and nonempty'
    )
    need(
      type(r.destination) == 'string' and r.destination ~= '',
      'Missing recipe destination group'
    )
    need(r.kind == 'crafting' or r.kind == 'processing', 'Invalid requested pattern type')
    seen[r.key] = true
    local g = groups[r.destination]
    if not g then
      block('No destination interfaces named ' .. r.destination)
    else
      if #g.wanted == 0 then
        groupOrder[#groupOrder + 1] = g
      end
      g.wanted[#g.wanted + 1] = r
    end
  end
  for _, g in ipairs(groupOrder) do
    if checkpoint then
      checkpoint()
    end
    for n, r in ipairs(g.wanted) do
      if checkpoint then
        checkpoint()
      end
      local match
      for _, t in ipairs(g.tokens) do
        if not t.selected and t.pattern.recipeKey == r.key and t.pattern.kind == r.kind then
          match = match or t
          if t.pattern.scale == r.scale then
            match = t
            break
          end
        end
      end
      local dest = g.slots[n]
      local entry = {
        key = r.key,
        kind = r.kind,
        group = r.destination,
        destination = dest,
        existing = match ~= nil,
        source = match and copy(match.current) or nil,
        resize = match ~= nil and r.scale ~= nil and match.pattern.scale ~= r.scale,
      }
      p.layout[#p.layout + 1] = entry
      if match then
        match.selected = true
        match.goal = dest
        p.reused = p.reused + 1
        if entry.resize then
          p.resizeCount = p.resizeCount + 1
          entry.oldScale = match.pattern.scale
          entry.newScale = r.scale
          entry.fingerprint = match.pattern.fingerprint
          if not match.pattern.donor then
            block(
              'Cannot resize an existing pattern: '
                .. (match.pattern.reason or 'unsupported metadata')
            )
          end
        end
      else
        p.required[r.kind] = p.required[r.kind] + 1
      end
    end
    local n = #g.wanted
    for _, t in ipairs(g.tokens) do
      if not t.selected then
        n = n + 1
        t.goal = g.slots[n]
        p.preserved[#p.preserved + 1] =
          { from = t.current, to = t.goal, fingerprint = t.pattern.fingerprint }
      end
    end
    if n > #g.slots then
      block(
        'Insufficient capacity in '
          .. g.wanted[1].destination
          .. ': need '
          .. n
          .. ', have '
          .. #g.slots
      )
    end
  end
  -- Destinations containing only excluded outputs stay in place, but still
  -- contribute to existing-pattern counts and capacity reports.
  for _, g in pairs(groups) do
    if #g.wanted == 0 then
      for _, t in ipairs(g.tokens) do
        p.preserved[#p.preserved + 1] =
          { from = t.current, to = t.current, fingerprint = t.pattern.fingerprint }
      end
    end
  end
  for kind, count in pairs(p.available) do
    if count < p.required[kind] then
      p.warnings[#p.warnings + 1] = 'Need '
        .. p.required[kind]
        .. ' disposable '
        .. kind
        .. ' donors; have '
        .. count
        .. '. Execution will wait for refills.'
    end
  end
  local needsMoves = false
  for _, t in ipairs(tokens) do
    if t.goal and address(t.current) ~= address(t.goal) then
      needsMoves = true
    end
  end
  if
    (needsMoves or p.resizeCount > 0 or p.required.crafting + p.required.processing > 0)
    and not workspace
  then
    block('Leave an empty slot in the dedicated editing/workspace interface')
  end
  -- A blocked plan never contains executable operations.
  if #p.errors > 0 then
    return p
  end
  local function move(t, to)
    need(not occupied[address(to)], 'Planner attempted to overwrite an occupied slot')
    p.moves[#p.moves + 1] =
      { from = copy(t.current), to = copy(to), fingerprint = t.pattern.fingerprint }
    occupied[address(t.current)] = nil
    occupied[address(to)] = t
    t.current = to
  end
  while true do
    if checkpoint then
      checkpoint()
    end
    local stuck, advanced = nil, false
    for _, t in ipairs(tokens) do
      if t.goal and address(t.current) ~= address(t.goal) then
        if not occupied[address(t.goal)] then
          move(t, t.goal)
          advanced = true
        else
          stuck = stuck or t
        end
      end
    end
    if not stuck then
      break
    end
    if not advanced then
      need(not occupied[address(workspace)], 'Planner cycle did not release workspace')
      move(stuck, workspace)
    end
  end
  for _, entry in ipairs(p.layout) do
    if entry.resize then
      p.resizes[#p.resizes + 1] = {
        key = entry.key,
        to = copy(entry.destination),
        workspace = copy(workspace),
        fingerprint = entry.fingerprint,
      }
    elseif not entry.existing then
      need(not occupied[address(entry.destination)], 'New recipe destination was not cleared')
      p.creates[#p.creates + 1] = {
        key = entry.key,
        kind = entry.kind,
        to = copy(entry.destination),
        workspace = copy(workspace),
      }
    end
  end
  -- Compact baseline used by an executor to reject stale previews before writes.
  local fixed = {}
  for _, i in ipairs(interfaces) do
    if i.role ~= 'donor' then
      fixed[#fixed + 1] = i
    end
  end
  p.baseline = encoded({ snapshot.terminal, fixed, request })
  return p
end

function M.revalidate(request, snapshot, preview, checkpoint)
  local fresh = M.plan(request, snapshot, checkpoint)
  local function operations(p)
    return encoded({ p.layout, p.moves, p.creates, p.resizes, p.preserved, p.required })
  end
  need(
    #fresh.errors == 0
      and preview.baseline
      and fresh.baseline == preview.baseline
      and operations(fresh) == operations(preview),
    'Patterns, settings or manifest changed; scan again'
  )
  return fresh
end
M.sequence = sequence
return M

end)()
local Modes=(function()
-- Source: source/lib/modes.lua
-- Compact runtime recipe compiler. This module has no component/UI calls.
-- Eligibility uses form capabilities, production flags and rare exceptions.
local U = U
local Planner = Planner
local Batch = Batch
local M = {}
local aliases = {
  rod = 'stick',
  rodLong = 'stickLong',
  gear = 'gearGt',
  gearSmall = 'gearGtSmall',
  casing = 'itemCasing',
  springLarge = 'spring',
  frameBox = 'frameGt',
  boltedCasing = 'casingBolted',
  reboltedCasing = 'casingRebolted',
}
local labels = {
  ingot = 'Ingot',
  nugget = 'Nugget',
  stick = 'Rod',
  ring = 'Ring',
  bolt = 'Bolt',
  screw = 'Screw',
  round = 'Round',
  gearGt = 'Gear',
  gearGtSmall = 'Small gear',
  rotor = 'Rotor',
  itemCasing = 'Item casing',
  toolHeadDrill = 'Drill head',
  dust = 'Dust',
  wireFine = 'Fine wire',
  plate = '1x Plate',
  plateDouble = '2x Plate',
  plateTriple = '3x Plate',
  plateQuadruple = '4x Plate',
  plateQuintuple = '5x Plate',
  plateDense = 'Dense Plate',
  foil = 'Foil',
  sheetmetal = 'Sheet metal',
  springSmall = 'Small spring',
  spring = 'Spring',
  stickLong = 'Long rod',
  wire1 = '1x wire',
  turbineBlade = 'Turbine blade',
}
local function formLabel(form)
  local pipeKind, pipeSize = form:match('^pipe(Fluid)(%a+)$')
  if not pipeKind then
    pipeKind, pipeSize = form:match('^pipe(Item)(%a+)$')
  end
  if pipeKind then
    return pipeSize .. ' ' .. pipeKind:lower() .. ' pipe'
  end
  local kind, size = form:match('^(%a+)(%d+)$')
  if kind == 'wire' or kind == 'cable' then
    return size .. 'x ' .. (kind == 'wire' and 'Wire' or 'Cable')
  end
  return labels[form] or form
end
function M.supports(data, material, form)
  form = aliases[form] or form
  return U.check(data.capabilities[material.a], 'Unknown capability set')[form] == true
end
local function registeredItem(data, item)
  local name = (data.registryNames or {})[item.name:lower()]
  if name then
    item.name = name
  end
  return item,
    name ~= nil or item.name:match('^gregtech:') ~= nil or item.name:match('^minecraft:') ~= nil
end
local function resolveForm(data, material, form)
  form = aliases[form] or form
  U.check(M.supports(data, material, form), 'Material does not support ' .. form)
  local override = (material.overrides or {})[form]
  if override then
    return U.clone(override)
  end
  local kind, size = form:match('^(wire)(%d+)$')
  if not kind then
    kind, size = form:match('^(cable)(%d+)$')
  end
  if kind then
    local offsets = { [1] = 0, [2] = 1, [4] = 2, [8] = 3, [12] = 4, [16] = 5 }
    local item = U.check(material.conductor, 'Missing conductor resolver')
    local offset = U.check(offsets[tonumber(size)], 'Invalid conductor size')
    return { name = item.name, damage = item.base + offset + (kind == 'cable' and 6 or 0) }
  end
  local pipe, variant = form:match('^(pipeFluid)(.+)$')
  if not pipe then
    pipe, variant = form:match('^(pipeItemRestrictive)(.+)$')
  end
  if not pipe then
    pipe, variant = form:match('^(pipeItem)(.+)$')
  end
  if pipe then
    local offsets =
      { Tiny = 0, Small = 1, Medium = 2, Large = 3, Huge = 4, Quadruple = 5, Nonuple = 6 }
    local item = U.check(material[pipe], 'Missing pipe resolver')
    return { name = item.name, damage = item.base + U.check(offsets[variant], 'Invalid pipe size') }
  end
  local family = U.check(data.families[material.family], 'Unknown resolver family')
  local item = U.check(family[form], 'Missing form resolver')
  if item.template then
    return { name = item.template:gsub('%%s', material.dsf), damage = 0 }
  end
  U.check(U.integer(material.dsf), 'Material has no metadata suffix')
  return { name = item.name, damage = item.prefix + material.dsf }
end
function M.resolve(data, material, form)
  local item = registeredItem(data, resolveForm(data, material, form))
  return item
end
function M.eligible(data, material, rule)
  if (material.deny or {})[rule.id] then
    return false
  end
  if rule.mode == 'coating' then
    if material.coating ~= rule.coating then
      return false
    end
  elseif not (data.production[material.p] or {})[rule.process] then
    return false
  end
  for _, form in ipairs(rule.requires) do
    if not M.supports(data, material, form) then
      return false
    end
  end
  if rule.mode == 'solidifier' then
    -- GT's matrix uses suffixes (IronMagnetic, TengamAttuned), while display
    -- names can put these modifiers first. Match either end, not Magnetite.
    local name = material.name:lower():gsub('[^a-z0-9]', '')
    for _, modifier in ipairs({ 'magnetic', 'attuned' }) do
      if name:sub(1, #modifier) == modifier or name:sub(-#modifier) == modifier then
        return false, 'Fluid Shaper excludes ' .. modifier .. ' material variants.'
      end
    end
    if data.source.materialSourcePolicy and rule.outputs[1].f == 'ingot' then
      local sources = (data.origins or {})[material.o] or {}
      if not sources.native_molten then
        if sources.native_ingot then
          return false, 'Ingots have a direct solid route; no native liquid source.'
        end
        return false, 'No verified native liquid source for ingots.'
      end
    end
  end
  if
    data.usage
    and data.source.usagePolicy
    and not (data.usage[material.u] or {})[rule.outputs[1].f]
  then
    return false, 'unused'
  end
  return true
end
function M.compile(data, mode, options, checkpoint)
  options = U.clone(options or {})
  local multiplier = options.multiplier or 1
  U.check(
    U.integer(multiplier) and multiplier > 0,
    'Pattern multiplier must be a positive whole number'
  )
  local polymer = options.polymer or (options.pvc == false and 'none' or 'pvcSmall')
  U.check(
    ({ pvc = true, pvcSmall = true, pdms = true, pdmsSmall = true, none = true })[polymer],
    'Invalid insulation polymer'
  )
  if mode == 'coating' then
    options.pvc = polymer ~= 'none'
    options.pdms = polymer ~= 'none'
  end
  U.check(data.version == 2, 'Unsupported material matrix')
  U.check(
    mode == 'wiremill' or mode == 'coating' or mode == 'bender' or mode == 'solidifier',
    'Mode has no verified recipe rules yet'
  )
  local manifest = {
    version = 1,
    source = U.clone(data.source),
    policy = {
      mode = mode,
      polymer = polymer,
      pps = options.pps ~= false,
      sources = U.clone(options.sources),
      multiplier = multiplier,
      batch = U.clone(options.batch),
    },
    recipes = {},
    unusedExcluded = 0,
    unclassifiedRecipes = 0,
    tierExcluded = 0,
    skipped = {},
  }
  local seen, unresolved, skipped = {}, {}, {}
  manifest.unresolved = {}
  local function exclude(material, rule, reason)
    local out = rule.outputs[1]
    local item = M.resolve(data, material, out.f)
    local key = item.name .. ':' .. item.damage
    if not skipped[key] then
      skipped[key] = true
      manifest.skipped[#manifest.skipped + 1] = {
        material = material.name,
        form = out.f,
        label = material.name .. ' ' .. formLabel(out.f),
        name = item.name,
        damage = item.damage,
        reason = reason,
      }
    end
  end
  for _, material in ipairs(data.materials) do
    if checkpoint then
      checkpoint()
    end
    for ruleIndex, rule in ipairs(data.rules) do
      if
        rule.mode == mode
        and (not options.forms or options.forms[rule.outputs[1].f])
        and (not rule.polymer or rule.polymer == (polymer == 'none' and 'pvcSmall' or polymer))
        and (not options.sources or options.sources[rule.outputs[1].f] == rule.inputs[1].f)
      then
        local eligible, reason = M.eligible(data, material, rule)
        if reason == 'unused' then
          manifest.unusedExcluded = manifest.unusedExcluded + 1
          exclude(material, rule)
        elseif reason then
          exclude(material, rule, reason)
        end
        if eligible then
          if not material.tier then
            manifest.unclassifiedRecipes = manifest.unclassifiedRecipes + 1
          end
          local quantities = {}
          for _, side in ipairs({ 'inputs', 'outputs' }) do
            for _, e in ipairs(rule[side]) do
              local shared = e.i and data.items[e.i]
              if not shared or not shared.option or options[shared.option] ~= false then
                quantities[#quantities + 1] = { type = e.fluid and 'fluid' or 'item', size = e.n }
              end
            end
          end
          local voltage = data.voltages and data.voltages[material.v] or {}
          local eut = voltage[ruleIndex]
          if eut == nil then
            eut = rule.eut
          elseif eut == false then
            eut = nil
          end
          local recipeMultiplier, batch = Batch.resolve(
            options.batch,
            material.tier,
            eut,
            multiplier,
            quantities,
            material.tierSource
          )
          if recipeMultiplier == 0 then
            manifest.tierExcluded = manifest.tierExcluded + 1
            exclude(material, rule, batch.excluded)
          else
            local function resolve(e, stocked)
              if e.fluid == 'material' then
                local fluid =
                  U.check(material.molten, 'Missing verified molten fluid for ' .. material.name)
                local size = e.n * (stocked and 1 or recipeMultiplier)
                U.check(
                  U.integer(size) and size > 0,
                  'Pattern multiplier exceeds the supported fluid quantity'
                )
                return {
                  type = 'fluid',
                  name = fluid,
                  label = 'Molten ' .. material.name,
                  size = size,
                }
              end
              local item
              if e.f then
                item = M.resolve(data, material, e.f)
                item.label = material.name .. ' ' .. formLabel(e.f)
              else
                item = U.clone(U.check(data.items[e.i], 'Unknown shared item'))
              end
              if item.option and options[item.option] == false and not stocked then
                return nil
              end
              item.option = nil
              item.type = 'item'
              item.size = e.n * (stocked and 1 or recipeMultiplier)
              U.check(
                U.integer(item.size) and item.size > 0,
                'Pattern multiplier exceeds the supported ingredient quantity'
              )
              -- Oracle IDs are normalized to lower case. GT/Minecraft families above
              -- have known spelling; other families still need a registry resolver.
              local registered
              item, registered = registeredItem(data, item)
              if not stocked and not registered and not unresolved[item.name] then
                unresolved[item.name] = true
                manifest.unresolved[#manifest.unresolved + 1] = item.name
              end
              return item
            end
            local out = rule.outputs[1]
            local label = formLabel(out.f)
            local source = rule.inputs[1].f
            local route = (mode == 'wiremill' or mode == 'bender')
                and (' / from ' .. (labels[source] or source))
              or ''
            local recipe = {
              kind = 'processing',
              material = material.name,
              outputForm = out.f,
              outputLabel = label,
              inputs = {},
              outputs = {},
              label = material.name .. ' / ' .. label .. route,
              stock = {},
              batch = batch,
            }
            for _, which in ipairs({ 'inputs', 'outputs' }) do
              for _, e in ipairs(rule[which]) do
                local item = resolve(e)
                if item then
                  recipe[which][#recipe[which] + 1] = item
                else
                  recipe.stock[#recipe.stock + 1] = resolve(e, true)
                end
              end
            end
            for _, e in ipairs(rule.stock or {}) do
              recipe.stock[#recipe.stock + 1] = e.fluid and U.clone(e) or resolve(e, true)
            end
            U.check(#recipe.inputs > 0 and #recipe.outputs > 0, 'Rule contains no requested inputs')
            local key = Planner.recipeKey(recipe)
            if not seen[key] then
              manifest.recipes[#manifest.recipes + 1] = recipe
              seen[key] = recipe
            elseif U.canonical(seen[key].stock) ~= U.canonical(recipe.stock) then
              local existing = seen[key]
              existing.stockAlternatives = existing.stockAlternatives or {}
              existing.stockAlternatives[#existing.stockAlternatives + 1] = recipe.stock
            end
          end
        end
      end
    end
  end
  U.check(#manifest.recipes > 0 or #manifest.skipped > 0, 'No verified recipes for this mode')
  return manifest
end
return M

end)()
local Preview=(function()
-- Source: source/lib/preview.lua
-- One renderer for maker previews, on screen and in exported reports.
local U = U
local Planner = Planner
local Batch = Batch
local M = {}
local interfaceTone = 'muted'

local function spacer(rows, add)
  if #rows > 0 and rows[#rows][1] ~= '' then
    add('')
  end
end

local function treeRow(rows, add, prefix, content, tone)
  add(prefix .. content, tone)
  local row = rows[#rows]
  row[3], row[4] = #prefix, interfaceTone
end

function M.planRows(plan, manifest)
  local rows, add = U.rows()
  local details = {}
  for _, recipe in ipairs(manifest.recipes) do
    details[recipe.key or Planner.recipeKey(recipe)] = recipe
  end
  add('PATTERN PLAN', 'blue')
  add(
    string.format(
      '%d reuse   |   %d new   |   %d other patterns kept',
      plan.reused,
      plan.required.processing + plan.required.crafting,
      #plan.preserved
    ),
    'green'
  )
  if manifest.policy and manifest.policy.batch and manifest.policy.batch.mode == 'tiered' then
    add(
      'Tiered batches at '
        .. manifest.policy.batch.currentTier
        .. '; fixed program multipliers do not apply.',
      'muted'
    )
    add(
      (manifest.unclassifiedRecipes or 0)
        .. ' unclassified recipes; policy: '
        .. manifest.policy.batch.unknownPolicy
        .. '.  '
        .. (manifest.tierExcluded or 0)
        .. ' routes excluded by tier settings.',
      'muted'
    )
  elseif manifest.policy then
    add(
      'Batch policy: Fixed  |  Program multiplier ' .. (manifest.policy.multiplier or 1) .. 'x',
      'muted'
    )
  end
  if manifest.source.usagePolicy then
    add(
      manifest.unusedExcluded .. ' recipe routes skipped: output has no non-recycling use.',
      'muted'
    )
  end
  if plan.resizeCount > 0 then
    add(
      plan.resizeCount .. ' reused patterns will be resized to the configured batch.',
      'yellow_lighter1'
    )
  end
  local group, bank, material
  for _, entry in ipairs(plan.layout) do
    local recipe = details[entry.key]
    if group ~= entry.group then
      spacer(rows, add)
      group, bank, material = entry.group, nil, nil
      add('DESTINATION: ' .. tostring(group), 'blue')
    end
    local location = entry.destination and U.where(entry.destination) or 'needs space'
    if bank ~= location then
      if bank then
        spacer(rows, add)
      end
      bank, material = location, nil
      add(
        '  +-- Interface '
          .. (entry.destination and U.locationText(entry.destination) or '(needs space)'),
        interfaceTone
      )
    else
      add('  |', interfaceTone)
    end
    local currentMaterial = recipe.material or recipe.label
    if material ~= currentMaterial then
      material = currentMaterial
      treeRow(rows, add, '  |  ', material, 'blue')
    end
    treeRow(
      rows,
      add,
      '  |    ',
      (entry.resize and 'RESIZE  ' or entry.existing and 'REUSE   ' or 'CREATE  ')
        .. (recipe.outputLabel or recipe.outputForm or '')
        .. (entry.destination and ('   slot ' .. entry.destination.slot) or '   needs space'),
      entry.resize and 'yellow_lighter1' or entry.existing and 'green' or 'yellow'
    )
    if entry.resize then
      treeRow(
        rows,
        add,
        '  |      ',
        'Multiply current quantities by ' .. entry.newScale .. ' / ' .. entry.oldScale,
        'yellow_lighter1'
      )
    end
    treeRow(rows, add, '  |      ', U.ingredientSummary(recipe.inputs))
    treeRow(rows, add, '  |      ', '-> ' .. U.ingredientSummary(recipe.outputs), 'green')
    if recipe.batch then
      local description, voltage = Batch.describe(recipe.batch), Batch.voltageText(recipe.batch)
      treeRow(rows, add, '  |      ', description, 'muted')
      if recipe.batch.recipeTier then
        rows[#rows][5] = {
          from = 10 + #description - #voltage,
          length = #voltage,
          tier = recipe.batch.recipeTier,
        }
      end
    end
  end
  return rows
end

function M.capacityRows(plan)
  local rows, add = U.rows()
  add('DESTINATION SPACE', 'blue')
  add('Assuming 3 capacity cards per interface (36 slots).', 'muted')
  spacer(rows, add)
  for _, group in ipairs(plan.capacities or {}) do
    add(group.name, 'blue')
    add(group.interfaces .. ' interfaces (' .. group.patterns .. ' patterns)')
  end
  spacer(rows, add)
  add('Every matching interface is included, ordered by location.', 'muted')
  add('Existing unrelated patterns count toward required space.', 'muted')
  for _, err in ipairs(plan.errors or {}) do
    add('BLOCKED: ' .. err, 'red')
  end
  return rows
end

function M.existingRows(plan)
  local rows, add = U.rows()
  add('EXISTING DESTINATION PATTERNS', 'blue')
  add(
    #(plan.existing or {})
      .. ' occupied; '
      .. plan.reused
      .. ' reused; '
      .. #plan.preserved
      .. ' kept.',
    'muted'
  )
  local group, bank
  for _, entry in ipairs(plan.existing or {}) do
    local location = U.where(entry.from)
    if group ~= entry.interface then
      spacer(rows, add)
      group, bank = entry.interface, nil
      add('DESTINATION: ' .. group, 'blue')
    end
    if bank ~= location then
      if bank then
        spacer(rows, add)
      end
      bank = location
      add('  +-- Interface ' .. U.locationText(entry.from), interfaceTone)
    else
      add('  |', interfaceTone)
    end
    treeRow(
      rows,
      add,
      '  |  ',
      entry.status .. '  slot ' .. entry.from.slot .. '  ' .. entry.label,
      entry.status == 'RESIZE' and 'yellow_lighter1'
        or entry.status == 'KEEP' and 'yellow'
        or 'green'
    )
    treeRow(rows, add, '  |    ', entry.reason, 'muted')
    if entry.inputs and entry.inputs ~= '' and entry.status == 'KEEP' then
      treeRow(rows, add, '  |    ', 'Encoded inputs: ' .. entry.inputs, 'muted')
    end
    if entry.requestedInputs and entry.status == 'KEEP' then
      treeRow(rows, add, '  |    ', 'Requested inputs: ' .. entry.requestedInputs, 'muted')
    end
    if U.where(entry.from) ~= U.where(entry.to) or entry.from.slot ~= entry.to.slot then
      treeRow(
        rows,
        add,
        '  |    ',
        'Final: ' .. U.locationText(entry.to) .. ' slot ' .. entry.to.slot,
        'muted'
      )
    end
  end
  if #(plan.existing or {}) == 0 then
    add('No patterns in the selected destination interfaces.', 'muted')
  end
  spacer(rows, add)
  add('SORTING MOVES', 'blue')
  for n, move in ipairs(plan.moves) do
    add(
      n .. '/' .. #plan.moves .. '  ' .. ((plan.moveLabels or {})[move.fingerprint] or 'Pattern'),
      'yellow'
    )
    add(
      '  '
        .. U.locationText(move.from)
        .. ' slot '
        .. move.from.slot
        .. ' -> '
        .. U.locationText(move.to)
        .. ' slot '
        .. move.to.slot,
      'muted'
    )
  end
  if #plan.moves == 0 then
    add('No sorting moves needed.', 'muted')
  end
  return rows
end

function M.excludedRows(manifest)
  local rows, add = U.rows()
  add('EXCLUDED OUTPUTS', 'blue')
  add(
    #(manifest.skipped or {}) .. ' output forms excluded by material, use or tier policy.',
    'muted'
  )
  add('Existing patterns for these outputs are kept; see Existing.', 'muted')
  local material
  for _, item in ipairs(manifest.skipped or {}) do
    if material ~= item.material then
      spacer(rows, add)
      material = item.material
      add(material, 'blue')
    end
    add('  ' .. item.label, 'yellow')
    add('    ' .. (item.reason or 'No path to a non-recycling product.'), 'muted')
  end
  if #(manifest.skipped or {}) == 0 then
    add('No selected output forms excluded.', 'green')
  end
  return rows
end

function M.donorRows(plan, section)
  local rows, add = U.rows()
  add('DONOR BUFFER CLEANUP', 'blue')
  add('Terminal name: "' .. plan.name .. '"', 'muted')
  add(
    #plan.cleanups
      .. ' to park; '
      .. plan.parked
      .. ' already parked; '
      .. plan.skipped
      .. ' skipped.'
  )
  add('Replaces the old recipes. Patterns return to their original slots.', 'yellow')
  if section == 'details' then
    spacer(rows, add)
    add('PARKING RECIPE', 'blue')
    add('1 tagged paper -> 1 identical tagged paper')
    add('Tag: ae2ocDonor = parked-v1; name: OC donor placeholder', 'muted')
    add('The tag distinguishes it from ordinary paper; real recipes are removed.')
    add('No paper or other item needs to be supplied. This edits the encoded recipe only.')
    spacer(rows, add)
    add('REUSABILITY', 'blue')
    add('Processing, ultimate and supported fluid patterns retain their item type and metadata.')
    add('The normal donor pool can imprint them again. Already parked patterns are left alone.')
    add('Crafting, substitution, tunnel and invalid patterns are skipped with a reason.')
    add('Empty recipes can acquire a persistent InvalidPattern flag, which this API cannot clear.')
    add('Uses one empty editor slot, shared Pause / Resume / Stop and transaction recovery.')
  else
    local bank
    for _, entry in ipairs(plan.entries) do
      if bank ~= U.where(entry.from) then
        spacer(rows, add)
        bank = U.where(entry.from)
        add('  +-- Interface ' .. U.locationText(entry.from), interfaceTone)
      else
        add('  |', interfaceTone)
      end
      local status = entry.status == 'park' and 'PARK'
        or entry.status == 'parked' and 'ALREADY PARKED'
        or 'SKIP'
      treeRow(
        rows,
        add,
        '  |  ',
        status .. ' slot ' .. entry.from.slot .. '  ' .. entry.label,
        entry.status == 'park' and 'yellow' or entry.status == 'parked' and 'green' or 'muted'
      )
      if entry.reason then
        treeRow(rows, add, '  |    ', entry.reason, 'muted')
      end
    end
  end
  for _, err in ipairs(plan.errors) do
    add('BLOCKED: ' .. err, 'red')
  end
  return rows
end

function M.rows(section, plan, manifest)
  if plan.kind == 'donorCleanup' then
    return M.donorRows(plan, section)
  end
  if section == 'existing' then
    return M.existingRows(plan)
  end
  if section == 'skipped' then
    return M.excludedRows(manifest)
  end
  if section == 'capacity' then
    return M.capacityRows(plan)
  end
  return M.planRows(plan, manifest)
end

function M.report(plan, manifest)
  local lines = {}
  local function append(rows)
    for _, row in ipairs(rows) do
      lines[#lines + 1] = row[1]
    end
    lines[#lines + 1] = ''
  end
  if plan.kind == 'donorCleanup' then
    append(M.donorRows(plan))
    append(M.donorRows(plan, 'details'))
    return table.concat(lines, '\n') .. '\n'
  end
  append(M.capacityRows(plan))
  append(M.planRows(plan, manifest))
  for _, warning in ipairs(plan.warnings) do
    lines[#lines + 1] = 'NOTE: ' .. warning
  end
  lines[#lines + 1] = ''
  append(M.existingRows(plan))
  append(M.excludedRows(manifest))
  return table.concat(lines, '\n') .. '\n'
end

return M

end)()
-- Source: source/app/25_maker.lua
-- Shared named-interface adapter. Planning is read-only; execution uses the
-- same editor, durable operations and recovery as the assembly-line program.
-- Pattern reads are performed one interface at a time; metadata discovery never
-- converts an entire network's pattern inventories into Lua tables.
local function discover(hw, name)
  return lookup(hw, name, true)
end
local function recipeKey(data, recipe)
  local normalized = U.clone(recipe)
  for _, which in ipairs({ 'inputs', 'outputs' }) do
    for _, s in pairs(normalized[which]) do
      local key = tagKey(data, s)
      s.tag = key ~= '{}' and key or nil
    end
  end
  return Planner.recipeKey(normalized)
end
local function patternRecipe(data, p, root)
  U.check(type(p.tag) == 'string', 'Pattern NBT hidden; enable allowItemStackNBTTags')
  local crafting = U.truth(p.isCraftable)
  U.check(p.isCraftable ~= nil and p.inputs and p.outputs, 'Unsupported encoded pattern')
  local r = {
    kind = crafting and 'crafting' or 'processing',
    inputs = {},
    outputs = {},
    substitute = root.substitute and U.truth(root.substitute.__value) or false,
    beSubstitute = root.beSubstitute and U.truth(root.beSubstitute.__value) or false,
  }
  for _, which in ipairs({ 'inputs', 'outputs' }) do
    for index, s in pairs(p[which]) do
      if U.exists(s) then
        local ingredient = patternIngredient(data, s, U.patternEntry(root, which, index))
        if not ingredient then
          return nil, 'Encoded ' .. which .. ' slot ' .. index .. ' has no readable count'
        end
        r[which][index] = ingredient
      end
    end
  end
  return r
end
local function explainExisting(plan, snapshot, request, manifest)
  local function itemKey(item)
    return item and item.name and (item.name .. ':' .. tostring(item.damage or 0))
  end
  local function slotKey(entry)
    return where(entry) .. ':' .. entry.slot
  end
  local skipped, wantedOutputs, wantedKeys = {}, {}, {}
  for _, item in ipairs(manifest.skipped or {}) do
    skipped[itemKey(item)] = item
  end
  for index, recipe in ipairs(manifest.recipes) do
    local desired = request.recipes[index]
    wantedKeys[desired.destination .. ':' .. desired.key] = true
    for _, output in pairs(recipe.outputs) do
      wantedOutputs[itemKey(output)] = {
        label = recipe.label,
        destination = desired.destination,
        inputs = U.ingredientSummary(recipe.inputs),
      }
    end
  end
  local reused, kept = {}, {}
  for _, entry in ipairs(plan.layout) do
    if entry.source then
      reused[slotKey(entry.source)] = entry
    end
  end
  for _, entry in ipairs(plan.preserved) do
    kept[slotKey(entry.from)] = entry
  end
  local destinations = {}
  for _, interface in ipairs(snapshot.interfaces) do
    if interface.role == 'destination' then
      destinations[#destinations + 1] = interface
    end
  end
  table.sort(destinations, U.ordered)
  plan.existing, plan.moveLabels = {}, {}
  for _, interface in ipairs(destinations) do
    for _, slot in ipairs(U.keys(interface.patterns)) do
      local pattern = interface.patterns[slot]
      local from = U.endpoint(interface, slot)
      local key = slotKey(from)
      local reusedEntry, keptEntry = reused[key], kept[key]
      local outputKey = itemKey(pattern.output)
      local skippedItem = skipped[outputKey]
      local wantedOutput = wantedOutputs[outputKey]
      local label = skippedItem and skippedItem.label
        or wantedOutput and wantedOutput.label
        or pattern.output and pattern.output.label
        or outputKey
        or 'Unknown output'
      local reason
      if reusedEntry then
        reason = reusedEntry.resize and 'Recipe matches; batch will be resized.'
          or 'Recipe matches the selected route.'
      elseif skippedItem then
        reason = 'Skipped: '
          .. (skippedItem.reason or 'no path to a non-recycling product in the recipe export.')
      elseif wantedKeys[interface.name .. ':' .. tostring(pattern.recipeKey)] then
        reason = 'Duplicate of a selected recipe; kept after the planned patterns.'
      elseif wantedOutput and wantedOutput.destination ~= interface.name then
        reason = 'Selected output belongs in interface ' .. wantedOutput.destination .. '.'
      elseif wantedOutput then
        reason = pattern.reason and ('Output selected; ' .. pattern.reason .. '.')
          or 'Recipe differs: inputs, ratio, NBT or flags.'
      elseif pattern.matchIssue then
        reason = pattern.matchIssue
      else
        reason = 'Output not requested by this program or its current settings.'
      end
      local entry = {
        interface = interface.name,
        from = from,
        to = reusedEntry and reusedEntry.destination or keptEntry and keptEntry.to or from,
        status = reusedEntry and (reusedEntry.resize and 'RESIZE' or 'REUSE') or 'KEEP',
        label = label,
        output = pattern.output,
        inputs = pattern.inputSummary,
        requestedInputs = wantedOutput and wantedOutput.inputs or nil,
        reason = reason,
      }
      plan.existing[#plan.existing + 1] = entry
      plan.moveLabels[pattern.fingerprint] = label
    end
  end
end
local function scanManifest(c, manifest, routing, progress, control, started)
  validate(c)
  if not started then
    startWork(c, progress, control)
  end
  local groups, names = {}, {}
  local function group(name, role)
    U.check(
      type(name) == 'string' and name ~= '',
      'Set the ' .. role .. ' interface name in Settings'
    )
    U.check(not names[name] or names[name] == role, 'Interface roles overlap: ' .. name)
    if not names[name] then
      groups[#groups + 1] = { name = name, role = role }
      names[name] = role
    end
  end
  local function destination(recipe)
    return routing.destinations and routing.destinations[recipe.outputForm or recipe.form]
      or routing.destination
  end
  U.check(
    manifest.version == 1 and type(manifest.recipes) == 'table',
    'Unsupported manifest schema'
  )
  Planner.sequence(manifest.recipes, 'Recipes')
  U.check(
    type(manifest.source) == 'table'
      and type(manifest.source.recipeVersion) == 'string'
      and type(manifest.source.targetVersion) == 'string',
    'Manifest must identify recipe and target versions'
  )
  for _, recipe in ipairs(manifest.recipes) do
    group(destination(recipe), 'destination')
  end
  for _, item in ipairs(manifest.skipped or {}) do
    group(destination(item), 'destination')
  end
  group(routing.donors, 'donor')
  group(routing.workspace, 'workspace')
  local hw = {
    terminal = selectDevice('me_interface_terminal', c.shared.terminalAddress),
    data = selectDevice('data', c.shared.dataAddress),
  }
  local snapshot = { terminal = hw.terminal.address, interfaces = {} }
  for _, g in ipairs(groups) do
    local found = discover(hw, g.name)
    for _, entry in ipairs(found) do
      local i = current(hw, endpoint(entry))
      U.check(i.name == g.name, 'Interface renamed while scanning; scan again')
      local slots = capacity(i)
      -- Donor capacity is irrelevant: include every occupied pattern, even when
      -- the buffer is a larger inventory than a standard destination interface.
      if g.role == 'donor' then
        slots = math.max(1, U.largest(i.patterns) + 1)
      end
      local compacted = {
        name = i.name,
        location = U.clone(i.location),
        side = side(i.side),
        role = g.role,
        capacity = slots,
        patterns = {},
      }
      for slot, p in pairs(i.patterns or {}) do
        if U.exists(p) then
          U.check(type(p.tag) == 'string', 'Pattern NBT hidden in ' .. g.name)
          local reason, root = donorIssue(hw.data, p)
          local value =
            { kind = 'unknown', fingerprint = patternFingerprint(hw, p), reason = reason }
          local output = p.outputs and p.outputs[1]
          if U.exists(output) then
            value.output = {
              name = output.name,
              damage = output.damage,
              size = U.patternCount(output, U.patternEntry(root, 'outputs', 1)),
              label = output.label,
            }
          end
          local inputLabels = {}
          for _, index in ipairs(U.keys(p.inputs)) do
            local input = p.inputs[index]
            if U.exists(input) then
              inputLabels[#inputLabels + 1] = tostring(
                U.patternCount(input, U.patternEntry(root, 'inputs', index)) or '?'
              ) .. ' x ' .. tostring(input.label or input.name)
            end
          end
          value.inputSummary = table.concat(inputLabels, ', ')
          if root then
            local r, issue = patternRecipe(hw.data, p, root)
            if r then
              value.kind = r.kind
              value.inputSummary = U.ingredientSummary(r.inputs)
              if r.outputs[1] then
                value.output = U.clone(r.outputs[1])
              end
              local valid, key, scale = pcall(recipeKey, hw.data, r)
              if valid then
                value.recipeKey = key
                value.scale = scale
              else
                value.matchIssue = 'Encoded ingredients could not be compared'
              end
              value.donor = value.reason == nil
            else
              value.matchIssue = issue
              value.reason = value.reason or issue
            end
          end
          compacted.patterns[slot] = value
        end
      end
      snapshot.interfaces[#snapshot.interfaces + 1] = compacted
      if progress then
        progress('Read ' .. i.name .. ' at ' .. U.locationText(i))
      end
      U.check(
        computer.freeMemory() > 160000,
        'Low memory while collecting compact interface snapshot'
      )
    end
  end
  local request = {
    recipes = {},
    source = U.clone(manifest.source),
    policy = U.clone(manifest.policy or {}),
    unresolved = U.clone(manifest.unresolved),
  }
  local labels = {}
  for _, r in ipairs(manifest.recipes) do
    local key, scale = recipeKey(hw.data, r)
    r.key = key
    request.recipes[#request.recipes + 1] = {
      key = key,
      scale = scale,
      kind = r.kind,
      destination = destination(r),
      stock = U.clone(r.stock),
      stockAlternatives = U.clone(r.stockAlternatives),
    }
    labels[key] = r.label or r.id or r.outputs[1].name
  end
  local plan = Planner.plan(request, snapshot, function()
    gate()
    U.check(computer.freeMemory() > 160000, 'Low memory while planning')
  end)
  explainExisting(plan, snapshot, request, manifest)
  return plan, snapshot, request, labels
end
C.maker = {
  planner = Planner,
  scan = scanManifest,
  report = Preview.report,
  rows = Preview.planRows,
  discover = discover,
}
local function programRouting(c, id)
  local program = Config.requireProgram(c, id)
  local values = c.programs[id]
  local routing =
    { donors = c.shared.donors, workspace = c.shared.editor, destination = values.destination }
  local forms
  if program.outputs then
    forms = {}
    routing.destinations = {}
    for form, key in pairs(program.outputs) do
      forms[form] = true
      routing.destinations[form] = values[key]
    end
    if program.formSwitch then
      local selected = Config.selected(values[program.formSwitch], program.formChoices)
      for form in pairs(forms) do
        forms[form] = selected[Programs.switchKey(program, form)] == true
      end
    end
  end
  local sources
  if program.sources then
    sources = {}
    for form, source in pairs(program.sources.fixed or {}) do
      sources[form] = source
    end
    for form, key in pairs(program.sources.fields or {}) do
      sources[form] = values[key]
    end
  end
  return routing,
    {
      polymer = values.polymer,
      multiplier = tonumber(values.multiplier),
      batch = c.batch,
      pps = values.pps ~= 'off',
      forms = forms,
      sources = sources,
    },
    program
end
function C.maker.preview(c, id, progress, control)
  validate(c)
  startWork(c, progress, control)
  local routing, options, program = programRouting(c, id)
  local manifest = Modes.compile(require('assline_data'), program.mode, options, gate)
  local plan, snapshot, _, labels = scanManifest(c, manifest, routing, progress, control, true)
  local groups = {}
  for _, recipe in ipairs(manifest.recipes) do
    local name = routing.destinations and routing.destinations[recipe.outputForm or recipe.form]
      or routing.destination
    groups[name] = (groups[name] or 0) + 1
  end
  local banks = {}
  for _, i in ipairs(snapshot.interfaces) do
    banks[where(i)] = i.name
  end
  for _, entry in ipairs(plan.preserved) do
    local name = banks[where(entry.from)]
    groups[name] = (groups[name] or 0) + 1
  end
  plan.capacities = Config.capacityReport(groups)
  local report = Preview.report(plan, manifest)
  return plan, report, manifest
end

function C.maker.finishMove(hw, op)
  local source = current(hw, op.source).patterns[op.source.slot]
  local destination = current(hw, op.destination).patterns[op.destination.slot]
  local function matches(p)
    return op.fingerprint and patternFingerprint(hw, p) == op.fingerprint
      or op.original and patternEq(hw.data, p, op.original)
  end
  if not U.exists(source) and matches(destination) then
    return
  end
  U.check(matches(source), 'Sorting source changed; recovery stopped')
  U.check(not U.exists(destination), 'Sorting destination is occupied')
  transfer(hw, op.source, op.destination)
  verifyDelivery(hw, op.source, op.destination, matches, 'Sorted pattern read-back failed')
end

function C.maker.finishSort(hw, op, progress)
  local cursor = U.check(readFile(paths.cursor), 'Missing sorting recovery progress')
  U.check(
    cursor.id == op.id
      and U.integer(cursor.index)
      and cursor.index >= 1
      and cursor.index <= #op.moves + 1,
    'Invalid sorting recovery progress'
  )
  local parked = false
  local function track(move)
    if where(move.to) == where(hw.buffer) then
      parked = true
    end
    if where(move.from) == where(hw.buffer) then
      parked = false
    end
  end
  -- An interrupted cycle may already have a pattern in its workspace.
  for n = 1, cursor.index - 1 do
    track(op.moves[n])
  end
  for n = cursor.index, #op.moves do
    local move = op.moves[n]
    C.maker.finishMove(
      hw,
      { source = move.from, destination = move.to, fingerprint = move.fingerprint }
    )
    writeFile(paths.cursor, { id = op.id, index = n + 1 })
    track(move)
    -- Stop only when the cycle has returned its parked pattern. The cursor
    -- retains the remaining moves without holding an editor slot hostage.
    if not parked then
      work.atomic = false
      gate()
      work.atomic = true
    end
    if progress then
      progress('Sorted pattern ' .. n .. ' / ' .. #op.moves)
    end
  end
end

function C.maker.apply(c, id, plan, manifest, progress, control)
  U.check(
    not fs.exists(paths.pending),
    'Continue or stop the saved operation before executing another preview'
  )
  U.check(#plan.errors == 0, 'Resolve preview blockers first')
  U.check(
    not manifest.unresolved or #manifest.unresolved == 0,
    'Resolve unverified registry spellings before execution'
  )
  local routing = programRouting(c, id)
  local baseline = U.clone(plan)
  baseline.capacities = nil
  local _, snapshot, request = scanManifest(c, manifest, routing, progress, control)
  Planner.revalidate(request, snapshot, baseline, gate)
  local hw = connect(c, progress, control)
  local editor = current(hw, hw.buffer)
  local firstEdit = plan.resizes[1] or plan.creates[1]
  local slot = firstEdit and firstEdit.workspace.slot
  if slot then
    U.check(
      where(firstEdit.workspace) == where(hw.buffer),
      'Planned workspace is not the shared pattern editor'
    )
    U.check(slot < editorCapacity(hw), 'Editor workspace slot is unavailable')
    U.check(
      patternEq(hw.data, editor.patterns[slot], direct(hw, 'getInterfacePattern', slot)),
      'Direct pattern editor does not match the terminal'
    )
    U.check(not U.exists(editor.patterns[slot]), 'Pattern editor workspace occupied')
  end
  writeFile(paths.backup, {
    config = U.clone(c),
    program = id,
    created = #plan.creates,
    resized = #plan.resizes,
    sorted = #plan.moves,
  })
  if #plan.moves > 0 then
    -- Keep the whole sorting stage durable. A cycle can temporarily park a
    -- pattern in the editor; continuation finishes that cycle before replanning.
    local op =
      { kind = 'sort', moves = plan.moves, id = invoke(hw.data, 'sha256', U.canonical(plan.moves)) }
    writeFile(paths.cursor, { id = op.id, index = 1 })
    saveOp(hw, op)
    C.maker.finishSort(hw, op, progress)
    clearOp()
  end
  local recipes = {}
  for _, recipe in ipairs(manifest.recipes) do
    recipes[recipe.key or Planner.recipeKey(recipe)] = recipe
  end
  local protected = {}
  for _, i in ipairs(snapshot.interfaces) do
    if i.role ~= 'donor' then
      protected[where(i)] = true
    end
  end
  local takeDonor = donorPool(hw, c.shared.donors, protected, progress)
  local function imprint(entry, resize)
    local recipe = recipes[entry.key]
    U.check(recipe and recipe.kind == 'processing', 'Unsupported pattern kind')
    for _, which in ipairs({ 'inputs', 'outputs' }) do
      for _, s in ipairs(recipe[which]) do
        U.check(s.type == 'item' or s.type == 'fluid', 'Unsupported ingredient type')
      end
    end
    local source, original
    if resize then
      original = current(hw, entry.to).patterns[entry.to.slot]
      U.check(
        patternFingerprint(hw, original) == entry.fingerprint,
        'Existing pattern changed before resizing'
      )
      U.check(
        safeDonor(hw.data, original),
        'Existing pattern cannot be resized with its current metadata'
      )
      original = compact(original)
    else
      source, original = takeDonor()
    end
    U.check(
      not U.exists(direct(hw, 'getInterfacePattern', entry.workspace.slot)),
      'Pattern editor workspace occupied'
    )
    local op = {
      kind = resize and 'resize' or 'imprint',
      source = source,
      slot = entry.workspace.slot,
      destination = entry.to,
      original = original,
      recipe = recipe,
    }
    saveOp(hw, op)
    finish(hw, op, progress)
    clearOp()
    if progress then
      progress((resize and 'Resized ' or 'Installed ') .. recipe.label)
    end
  end
  for _, entry in ipairs(plan.resizes) do
    imprint(entry, true)
  end
  for _, entry in ipairs(plan.creates) do
    imprint(entry, false)
  end
end

C.runner = {}
function C.runner.hasChanges(preview)
  local plan = preview.plan
  if plan.kind == 'donorCleanup' then
    return #plan.cleanups > 0
  end
  return preview.id == 'assline' and #plan.changes > 0
    or preview.id ~= 'assline' and (#plan.moves + #plan.creates + #plan.resizes) > 0
end
function C.runner.requiresVerification(preview)
  return Programs.byId[preview.id].requiresCapacityVerification ~= false
end
function C.runner.preview(c, id, progress, control)
  Config.requireProgram(c, id)
  local preview = { id = id, configKey = U.canonical(c) }
  if id == 'assline' then
    preview.plan = scan(c, progress, control)
  elseif id == 'donorCleanup' then
    preview.plan, preview.report = C.donors.preview(c, progress, control)
  else
    preview.plan, preview.report, preview.manifest = C.maker.preview(c, id, progress, control)
  end
  return preview
end
function C.runner.execute(c, preview, progress, control)
  U.check(preview and preview.configKey == U.canonical(c), 'Settings changed; build a new preview')
  Config.requireProgram(c, preview.id)
  U.check(not fs.exists(paths.pending), 'Continue or stop the saved operation before executing')
  writeFile(paths.run, { version = 1, program = preview.id, configKey = U.canonical(c) })
  if preview.id == 'assline' then
    apply(c, preview.plan, progress, control)
  elseif preview.id == 'donorCleanup' then
    C.donors.apply(c, preview.plan, progress, control)
  else
    C.maker.apply(c, preview.id, preview.plan, preview.manifest, progress, control)
  end
  U.check(fs.remove(paths.run), 'Cannot clear completed program run')
end

function C.runner.hasSaved()
  return fs.exists(paths.run) or fs.exists(paths.pending)
end

function C.runner.continue(c, progress, control)
  local saved, op = readFile(paths.run), readFile(paths.pending)
  U.check(saved or op, 'No saved operation')
  local backup = readFile(paths.backup)
  local id = saved and saved.program
    or op and (op.kind == 'edit' or op.kind == 'recipe') and 'assline'
    or backup and backup.program
  if id and not saved then
    writeFile(paths.run, { version = 1, program = id, configKey = U.canonical(c) })
  end
  if op then
    recover(c, progress, control)
  end
  -- A fresh plan recognizes the finished patterns and checks today's interface
  -- contents/settings. Never replay an old full plan after a stop or restart.
  if id then
    local preview = C.runner.preview(c, id, progress, control)
    preview.continuedWithChangedSettings = saved and saved.configKey ~= U.canonical(c) or false
    if
      not C.runner.hasChanges(preview)
      and #preview.plan.errors == 0
      and (not preview.manifest or #preview.manifest.unresolved == 0)
    then
      U.check(fs.remove(paths.run), 'Cannot clear completed program run')
    end
    return preview
  end
end

function C.runner.discard()
  U.check(C.runner.hasSaved(), 'No saved operation')
  -- One bounded archive may contain both 400 KB records plus the small cursor.
  writeFile(paths.abandoned, {
    operation = readFile(paths.pending),
    step = readFile(paths.cursor),
    run = readFile(paths.run),
  }, 900000)
  for _, path in ipairs({ paths.pending, paths.cursor, paths.run }) do
    if fs.exists(path) then
      U.check(fs.remove(path), 'Cannot discard ' .. path)
    end
  end
end

-- Source: source/app/26_donors.lua
-- Park disposable processing recipes in their original donor slots. Discovery,
-- ingredient writes, journaling and recovery are the application's shared ones.
C.donors = {}
local function donorMarker(hw)
  local root = {
    __nbt_type = 'compound',
    __value = {
      ae2ocDonor = { __nbt_type = 'string', __value = 'parked-v1' },
      display = {
        __nbt_type = 'compound',
        __value = { Name = { __nbt_type = 'string', __value = 'OC donor placeholder' } },
      },
    },
  }
  local tag = invoke(hw.data, 'encodeNBT', encodableNBT(root))
  U.check(U.eq(nbt(hw.data, tag), root), 'Donor marker NBT round trip failed')
  local marker = { type = 'item', name = 'minecraft:paper', damage = 0, size = 1, tag = tag }
  return { kind = 'processing', inputs = { marker }, outputs = { U.clone(marker) } }
end

function C.donors.scan(c, progress, control)
  local hw = connect(c, progress, control)
  local recipe = donorMarker(hw)
  local plan = {
    kind = 'donorCleanup',
    name = c.shared.donors,
    banks = 0,
    scanned = 0,
    parked = 0,
    skipped = 0,
    cleanups = {},
    entries = {},
    errors = {},
    warnings = {},
    bindings = {
      terminal = hw.terminal.address,
      direct = hw.direct.address,
      data = hw.data.address,
    },
  }
  for _, ref in ipairs(discover(hw, c.shared.donors)) do
    local bank = current(hw, ref)
    U.check(bank.name == c.shared.donors, 'Donor interface renamed during scan')
    U.check(where(bank) ~= where(hw.buffer), 'Donor interface overlaps the pattern editor')
    plan.banks = plan.banks + 1
    for _, slot in ipairs(U.keys(bank.patterns)) do
      gate()
      local p = bank.patterns[slot]
      if U.exists(p) then
        plan.scanned = plan.scanned + 1
        local reason = donorIssue(hw.data, p)
        if not reason and not processing(p) then
          reason = 'Crafting pattern: the editor cannot change its crafting flag.'
        end
        local entry = {
          from = endpoint(bank, slot),
          fingerprint = p.tag and patternFingerprint(hw, p) or U.canonical(compact(p)),
          label = p.label or p.name,
          status = 'skip',
          reason = reason,
        }
        if not reason then
          local observed = effectivePattern(hw.data, p)
          entry.label = U.ingredientSummary(observed.outputs)
          if not next(observed.inputs) or not next(observed.outputs) then
            entry.reason = 'Empty recipe: re-encode it manually before using it as a donor.'
          else
            local goal = compact(observed)
            goal.inputs, goal.outputs = recipe.inputs, recipe.outputs
            if semantic(hw, p, goal) then
              entry.status = 'parked'
              plan.parked = plan.parked + 1
            else
              entry.status = 'park'
              plan.cleanups[#plan.cleanups + 1] = entry
            end
          end
        end
        if entry.status == 'skip' then
          plan.skipped = plan.skipped + 1
        end
        plan.entries[#plan.entries + 1] = entry
      end
    end
    if progress then
      progress('Read donor bank at ' .. U.locationText(bank))
    end
  end
  if plan.banks == 0 then
    plan.errors[#plan.errors + 1] = 'No donor interfaces named "' .. c.shared.donors .. '".'
  end
  if #plan.cleanups > 0 then
    for slot = 0, editorCapacity(hw) - 1 do
      if not U.exists(direct(hw, 'getInterfacePattern', slot)) then
        plan.workspace = endpoint(hw.buffer, slot)
        break
      end
    end
    if not plan.workspace then
      plan.errors[#plan.errors + 1] = 'The pattern editor needs one empty slot.'
    end
  end
  return plan, hw, recipe
end

function C.donors.preview(c, progress, control)
  local plan = C.donors.scan(c, progress, control)
  return plan, Preview.report(plan)
end

function C.donors.apply(c, plan, progress, control)
  U.check(#plan.errors == 0, 'Resolve cleanup blockers first')
  local fresh, hw, recipe = C.donors.scan(c, progress, control)
  U.check(U.eq(fresh, plan), 'Donor banks or editor changed since preview. Scan again.')
  writeFile(
    paths.backup,
    { config = U.clone(c), program = 'donorCleanup', cleaned = #plan.cleanups }
  )
  for n, entry in ipairs(plan.cleanups) do
    gate()
    local bank = current(hw, entry.from)
    U.check(bank.name == plan.name, 'Donor interface renamed before cleanup')
    local original = bank.patterns[entry.from.slot]
    U.check(patternFingerprint(hw, original) == entry.fingerprint, 'Donor changed before cleanup')
    U.check(safeDonor(hw.data, original), 'Donor is no longer editable')
    U.check(
      not U.exists(direct(hw, 'getInterfacePattern', plan.workspace.slot)),
      'Pattern editor workspace occupied'
    )
    local op = {
      kind = 'park',
      slot = plan.workspace.slot,
      destination = entry.from,
      original = compact(original),
      recipe = recipe,
    }
    saveOp(hw, op)
    finish(hw, op, progress)
    clearOp()
    if progress then
      progress('Parked donor ' .. n .. ' / ' .. #plan.cleanups)
    end
  end
end

-- Source: source/app/30_ui.lua
local function runUI()
  local gpu = component.gpu
  U.check(gpu, 'GPU required')
  local term, keyboard = require('term'), require('keyboard')
  local oldW, oldH = gpu.getResolution()
  local oldFG, oldBG = gpu.getForeground(), gpu.getBackground()
  local maxW, maxH = gpu.maxResolution()
  U.check(maxW >= 160 and maxH >= 50, 'Use a tier 3 GPU and screen with 160x50 resolution') -- the fuck
  local w, h = 160, 50
  -- OC can report char=0 for keypad keys (notably with Num Lock off).
  -- The physical key code still identifies the intended digit.
  local keypad = {
    [0x52] = '0',
    [0x4F] = '1',
    [0x50] = '2',
    [0x51] = '3',
    [0x4B] = '4',
    [0x4C] = '5',
    [0x4D] = '6',
    [0x47] = '7',
    [0x48] = '8',
    [0x49] = '9',
    [0x53] = '.',
    [0xB3] = ',',
  }
  local colors = {
    bg = 0x101A26,
    panel = 0x1A2A3C,
    text = 0xDCE6EF,
    muted = 0x8297AB,
    blue = 0x5AC8FA,
    green = 0x72D69A,
    yellow = 0xFFD277,
    yellow_lighter1 = 0xFFF09E,
    red = 0xFF8585,
    button = 0x27465E,
    selected = 0x246B47,
  }
  local state = {
    page = 'programs',
    settings = 'shared',
    settingsPage = 1,
    selected = nil,
    section = 'changes',
    offset = 0,
    status = 'Choose a program, then Preview selected. Configure shared interfaces in Settings.',
    tone = 'muted',
    running = true,
  }
  local buttons, paintCache, paintKey, edit = {}, {}, nil, nil
  local buttonWidths, scrollbar = {}, nil
  local contentKey, contentRows
  local draw, handle, action, commitEdit, navigate
  local function text(x, y, s, width, tone, bg, guideWidth, guideTone, accent)
    width = math.min(width or w - x + 1, w - x + 1)
    if width < 1 then
      return
    end
    s = unicode.sub(tostring(s or ''):gsub('\194\167.', ''):gsub('[%c]', ' '), 1, width)
    local key = x .. ':' .. y
    local value = width
      .. ':'
      .. s
      .. ':'
      .. tostring(tone)
      .. ':'
      .. tostring(bg)
      .. ':'
      .. tostring(guideWidth)
      .. ':'
      .. tostring(guideTone)
      .. U.canonical(accent)
    if paintCache[key] == value then
      return
    end
    paintCache[key] = value
    gpu.setForeground(colors[tone or 'text'])
    gpu.setBackground(colors[bg or 'bg'])
    gpu.set(x, y, s .. string.rep(' ', math.max(0, width - unicode.wlen(s))))
    if guideWidth and guideWidth > 0 then
      gpu.setForeground(colors[guideTone or tone or 'text'])
      gpu.set(x, y, unicode.sub(s, 1, guideWidth))
    end
    if accent then
      local first, last = math.max(1, accent.from), math.min(width, accent.from + accent.length - 1)
      if last >= first then
        gpu.setForeground(Batch.color(accent.tier, colors.text, 0.5))
        gpu.setBackground(colors[bg or 'bg'])
        gpu.set(x + first - 1, y, unicode.sub(s, first, last))
      end
    end
  end
  local function button(x, y, label, callback, enabled, selected)
    local content = '[ ' .. label .. ' ]'
    local length = unicode.wlen(content)
    local key = x .. ':' .. y
    local previous = buttonWidths[key]
    if previous and previous ~= length then
      text(x, y, '', math.max(previous, length))
    end
    buttonWidths[key] = length
    text(
      x,
      y,
      content,
      length,
      enabled == false and 'muted' or 'text',
      selected and enabled ~= false and 'selected' or 'button'
    )
    if enabled ~= false then
      buttons[#buttons + 1] = { x = x, y = y, w = length, action = callback }
    end
    return x + length + 2
  end
  local function toggleButton(x, y, selected, callback, enabled, label)
    local marker = selected and 'X' or ' '
    return button(x, y, marker .. (label and (' ' .. label) or ''), callback, enabled, selected)
  end
  local function nav(y, label, selected, callback, enabled)
    text(
      3,
      y,
      (selected and '> ' or '  ') .. label,
      26,
      selected and 'blue' or 'text',
      selected and 'panel' or 'bg'
    )
    if enabled ~= false then
      buttons[#buttons + 1] = { x = 3, y = y, w = 26, action = callback }
    end
  end
  local function status(message, tone)
    state.status = message
    state.tone = tone or 'muted'
  end
  local function invalidate()
    state.preview = nil
    state.verified = false
  end
  local function saveConfig(value)
    Config.validate(Config.normalize(value))
    writeFile(paths.config, value)
    cfg = value
    invalidate()
  end
  local function fields()
    return Config.visibleFields(cfg, state.settings)
  end
  local function values()
    return Config.values(cfg, state.settings)
  end
  local function chooseValue(key, value)
    commitEdit()
    local trial = U.clone(cfg)
    Config.values(trial, state.settings)[key] = value
    saveConfig(trial)
    state.choice = nil
    status('Settings saved.', 'green')
  end
  commitEdit = function()
    if not edit then
      return
    end
    local trial = U.clone(cfg)
    Config.values(trial, edit.section)[edit.key] = U.trim(edit.value)
    saveConfig(trial)
    edit = nil
    status('Settings saved. Choose a program to build a new preview.', 'green')
  end
  local function toggleForm(key, choices, choice)
    commitEdit()
    local trial = U.clone(cfg)
    local v = Config.values(trial, state.settings)
    v[key] = Config.toggleSelected(v[key], choices, choice)
    saveConfig(trial)
    status('Settings saved.', 'green')
  end
  navigate = function(page, section)
    commitEdit()
    state.page = page
    state.offset = 0
    state.scrollDrag = nil
    if section then
      state.settings = section
      state.settingsPage = 1
    end
    if page == 'history' then
      action('history')
    end
  end
  local function editorRow(x, y, width, f)
    local value = values()[f.key]
    local first, cursor = 1, nil
    if edit and edit.key == f.key and edit.section == state.settings then
      first = math.max(1, edit.cursor - width + 3)
      cursor = edit.cursor
      value = unicode.sub(edit.value, first, edit.cursor - 1)
        .. '|'
        .. unicode.sub(edit.value, edit.cursor)
      text(x, y, value, width, edit.selectAll and 'yellow' or 'blue', 'panel')
    else
      text(
        x,
        y,
        value == '' and (f.placeholder or '(not configured)') or value,
        width,
        value == '' and 'muted' or 'text',
        'panel'
      )
    end
    if state.busy then
      return
    end
    buttons[#buttons + 1] = {
      x = x,
      y = y,
      w = width,
      editKey = f.key,
      section = state.settings,
      action = function(clickX)
        local at = first + clickX - x
        if cursor and at > cursor then
          at = at - 1
        end
        if not edit then
          edit = { section = state.settings, key = f.key, value = values()[f.key] }
        end
        edit.cursor = math.max(1, math.min(at, unicode.len(edit.value) + 1))
        edit.selectAll = false
      end,
    }
  end
  local function history()
    local f = io.open('/home/assline-perf.log', 'r')
    local groups = {}
    if f then
      f:seek('set', math.max(0, fs.size('/home/assline-perf.log') - 16384))
      local raw = f:read('*a') or ''
      f:close()
      for block in raw:gmatch('uptime=[^\n]*\n.-\n\n') do
        groups[#groups + 1] = block
      end
      if #groups == 0 or raw:sub(-2) ~= '\n\n' then
        local last = raw:match('.*\n(uptime=.*)') or (raw:match('^uptime=') and raw)
        if last then
          groups[#groups + 1] = last
        end
      end
    end
    state.history = {}
    for n = #groups, 1, -1 do
      for line in groups[n]:gmatch('[^\n]+') do
        state.history[#state.history + 1] = line
      end
      state.history[#state.history + 1] = ''
    end
  end
  local function description(s)
    return tostring(s.size or '?') .. ' x ' .. tostring(s.label or s.name)
  end
  local function lines()
    local rows, add = U.rows()
    local preview = state.preview
    local p = preview and preview.plan
    if state.page == 'preview' and state.error then
      add('LAST ERROR', 'red')
      add(state.error, 'red')
      add('')
    end
    if state.page == 'history' then
      add('RECENT OPERATIONS (newest first)', 'blue')
      add('/home/assline-perf.log; most recent 16 KB.', 'muted')
      add('')
      for _, line in ipairs(state.history or {}) do
        add(line)
      end
      if not state.history or #state.history == 0 then
        add('No operations recorded yet.', 'muted')
      end
    elseif state.page == 'help' then
      add('SHARED SETUP', 'blue')
      add('Set the pattern editor and new pattern buffer in Settings > Shared interfaces.')
      add('The editor is connected directly to OC. Buffer banks are found by exact terminal name.')
      add('Every matching buffer is included. Use disposable encoded patterns; keep machines idle.')
      add('Enable allowItemStackNBTTags. Use a tier 1+ Data Card and an Internet Card for updates.')
      add('')
      add('RUN A PROGRAM', 'blue')
      add('Run program opens the chooser. Select a program and press Preview selected.')
      add('Review changes, required interfaces, existing-pattern sorting and donors.')
      add('Verify destination interfaces have all 36 slots available, then Execute preview.')
      add(
        'Assembly line, insulator, wiremill, bender and Fluid Shaper share the editor and recovery.'
      )
      add('Wire combining remains unavailable until its recipes have been verified.')
      add('')
      add('SETTINGS AND RECOVERY', 'blue')
      add('Fields save when accepted or when you navigate away. Esc cancels only the active edit.')
      add(
        'Continue last operation finishes an interrupted transaction and previews the remaining work.'
      )
      add(
        'History retains timing and memory reports. Updates preserve configuration and recovery files.'
      )
    elseif not p then
      add(
        state.busy and 'Program running. See progress below.'
          or C.runner.hasSaved() and 'Continue last operation, or choose a program to build a new preview.'
          or 'Choose a program to build a preview.',
        'muted'
      )
    elseif p.kind == 'donorCleanup' then
      for _, row in ipairs(Preview.rows(state.section, p)) do
        add(row[1], row[2], row[3], row[4], row[5])
      end
    elseif preview.manifest and (state.section == 'existing' or state.section == 'skipped') then
      for _, row in ipairs(Preview.rows(state.section, p, preview.manifest)) do
        add(row[1], row[2], row[3], row[4], row[5])
      end
    elseif state.section == 'details' and preview.manifest then
      if preview.id == 'bender' or preview.id == 'fluidShaper' then
        add('STOCKED IN MACHINE', 'blue')
        add('These reusable items stay in the machine and are omitted from patterns.')
        local stocked = {}
        local program = Programs.byId[preview.id]
        for _, recipe in ipairs(preview.manifest.recipes) do
          local key = Programs.switchKey(program, recipe.outputForm)
          stocked[key] = stocked[key]
            or {
              label = recipe.outputLabel,
              items = recipe.stock or {},
            }
        end
        for _, entry in ipairs(program.formChoices) do
          local group = stocked[entry[1]]
          if group and #group.items > 0 then
            local names = {}
            for _, item in ipairs(group.items) do
              names[#names + 1] = item.name == 'gregtech:gt.integrated_circuit'
                  and ('circuit ' .. item.damage)
                or tostring(item.label or item.name)
            end
            add(
              (program.switchByDestination and entry[2] or group.label or entry[2])
                .. ': '
                .. table.concat(names, ', ')
            )
          end
        end
        add('')
      end
      add('BUFFER DISCOVERY', 'blue')
      add('Terminal lookup: "' .. cfg.shared.donors .. '"')
      add(p.donorBanks .. ' matching interfaces; ' .. p.donorOccupied .. ' occupied pattern slots.')
      add(
        p.available.processing
          .. ' usable processing; '
          .. p.available.crafting
          .. ' usable crafting; '
          .. p.donorRejected
          .. ' rejected.'
      )
      for _, reason in ipairs(U.keys(p.donorReasons or {})) do
        add(p.donorReasons[reason] .. ': ' .. reason, 'yellow')
      end
      add('')
      add('SORTING', 'blue')
      add(
        #p.moves
          .. ' moves before creating patterns; '
          .. #p.preserved
          .. ' unrelated/duplicate patterns preserved.'
      )
      add('See Existing for each pattern and labeled move.', 'muted')
      add('')
      add('SOURCE COVERAGE', 'blue')
      add('Recipes outside the supported material forms (whole imported dataset):', 'muted')
      for _, label in ipairs(U.keys(preview.manifest.source.excludedOutputs or {})) do
        add(label .. ': ' .. preview.manifest.source.excludedOutputs[label] .. ' source recipes')
      end
      for _, name in ipairs(preview.manifest.unresolved or {}) do
        add('Registry spelling still unresolved: ' .. name, 'red')
      end
    elseif state.section == 'capacity' then
      for _, row in ipairs(Preview.capacityRows(p)) do
        add(row[1], row[2], row[3], row[4], row[5])
      end
    elseif preview.id ~= 'assline' then
      for _, row in ipairs(Preview.planRows(p, preview.manifest)) do
        add(row[1], row[2], row[3], row[4], row[5])
      end
    elseif state.section == 'recipes' then
      for _, r in ipairs(p.recipes) do
        add((r.existing and 'REUSE  ' or 'CREATE ') .. r.name, r.existing and 'green' or 'yellow')
        add('  ' .. description(r.input) .. ' -> ' .. description(r.output))
        local e = r.existing or r.destination
        if e then
          add('  Slot ' .. (e.slot + 1) .. ' at ' .. U.locationText(e), 'muted')
        end
      end
      if #p.recipes == 0 then
        add('No rename recipes required.', 'green')
      end
    else
      for _, v in ipairs(p.changes) do
        local out = v.original.outputs[1]
        add(
          'PATTERN ' .. (v.slot + 1) .. '  ' .. (out and description(out) or '(no first output)'),
          'blue'
        )
        for _, e in ipairs(v.edits) do
          add('  Input ' .. e.index .. ': ' .. description(e.before))
          add('        -> ' .. description(e.after), 'green')
        end
      end
      if #p.changes == 0 then
        add('No duplicate item inputs found.', 'green')
      end
    end
    return rows
  end
  local function scrollRows(x, y, width, room)
    local key = state.page
      .. state.section
      .. tostring(state.preview)
      .. tostring(state.history)
      .. tostring(state.error)
      .. width
    if key ~= contentKey then
      contentKey = key
      contentRows = {}
      for _, r in ipairs(lines()) do
        for _, row in ipairs(U.wrapRow(r, width, unicode)) do
          contentRows[#contentRows + 1] = row
        end
      end
    end
    local rows = contentRows
    state.offset = math.max(0, math.min(state.offset, math.max(0, #rows - room)))
    for n = 1, room do
      local r = rows[state.offset + n]
      text(
        x,
        y + n - 1,
        r and r[1] or '',
        width,
        r and r[2] or 'text',
        nil,
        r and r[3],
        r and r[4],
        r and r[5]
      )
    end
    local maximum = math.max(0, #rows - room)
    local thumb = maximum == 0 and room or math.max(1, math.floor(room * room / #rows))
    local top = y
      + (maximum == 0 and 0 or math.floor(state.offset / maximum * (room - thumb) + 0.5))
    scrollbar =
      { x = x + width + 1, y = y, room = room, maximum = maximum, thumb = thumb, top = top }
    for row = y, y + room - 1 do
      text(scrollbar.x, row, '', 2, 'text', row >= top and row < top + thumb and 'blue' or 'panel')
    end
    text(
      x,
      44,
      'Rows '
        .. math.min(#rows, state.offset + 1)
        .. '-'
        .. math.min(#rows, state.offset + room)
        .. ' / '
        .. #rows
        .. '  (wheel / PgUp / PgDn)',
      width,
      'muted'
    )
  end
  local function executable()
    local preview = state.preview
    if
      not preview
      or state.busy
      or fs.exists(paths.pending)
      or (C.runner.requiresVerification(preview) and not state.verified)
    then
      return false
    end
    local p = preview.plan
    if #p.errors > 0 or (preview.manifest and #preview.manifest.unresolved > 0) then
      return false
    end
    return C.runner.hasChanges(preview)
  end
  draw = function()
    local key = state.page
      .. tostring(cfg)
      .. state.settings
      .. tostring(state.settingsPage)
      .. tostring(state.choice)
      .. tostring(state.selected)
      .. state.section
      .. tostring(state.preview)
      .. tostring(state.busy)
      .. tostring(state.paused)
      .. tostring(state.stopRequested)
      .. tostring(state.verified)
      -- Transactions create/clear these files for every pattern. While busy,
      -- they do not change the layout and must not invalidate the paint cache.
      .. tostring(not state.busy and fs.exists(paths.pending))
      .. tostring(not state.busy and fs.exists(paths.run))
    if key ~= paintKey then
      gpu.setBackground(colors.bg)
      gpu.fill(1, 1, w, h, ' ')
      paintCache = {}
      buttonWidths = {}
      paintKey = key
    end
    buttons = {}
    scrollbar = nil
    text(3, 2, 'AE2 / GTNH PATTERN MANAGER', 95, 'blue')
    text(
      111,
      2,
      string.format(
        '%.0f%% energy  |  %d KB free',
        energyFraction() * 100,
        math.floor(computer.freeMemory() / 1024)
      ),
      47,
      'muted'
    )
    text(3, 4, string.rep('-', 155), 155, 'muted')
    nav(7, 'Programs', state.page == 'programs', function()
      navigate('programs')
    end, not state.busy)
    nav(10, 'Settings', state.page == 'settings', function()
      navigate('settings')
    end, not state.busy)
    nav(13, 'History', state.page == 'history', function()
      navigate('history')
    end)
    nav(16, 'Help', state.page == 'help', function()
      navigate('help')
    end)
    if state.preview then
      nav(
        state.page == 'settings' and 44 or 19,
        'Current preview',
        state.page == 'preview',
        function()
          navigate('preview')
        end
      )
    end
    if state.page == 'settings' then
      text(3, 19, 'SETTINGS SECTIONS', 26, 'muted')
      nav(21, 'Tier multipliers', state.settings == 'batch', function()
        navigate('settings', 'batch')
      end)
      nav(24, 'Shared interfaces', state.settings == 'shared', function()
        navigate('settings', 'shared')
      end)
      for n, p in ipairs(Programs.settings) do
        local id = p.id
        nav(24 + n * 3, p.name, state.settings == id, function()
          navigate('settings', id)
        end)
      end
      local section = Config.section(state.settings)
      local pages = { {} }
      for _, f in ipairs(fields()) do
        local page = pages[#pages]
        if
          #page > 0
          and (#page >= (f.compact and 16 or section.pageSize or 8) or page[1].group ~= f.group)
        then
          page = {}
          pages[#pages + 1] = page
        end
        page[#page + 1] = f
      end
      state.settingsPage = math.min(state.settingsPage, #pages)
      local page = pages[state.settingsPage]
      text(
        34,
        7,
        'SETTINGS / '
          .. section.name
          .. (page[1] and page[1].group and (' / ' .. page[1].group) or ''),
        124,
        'blue'
      )
      text(
        34,
        8,
        'Accept a field or navigate away to save. Numbers accept k / M shorthand.',
        124,
        'muted'
      )
      local y = section.pageSize == 9 and 10 or 11
      local compact = page[1] and page[1].compact
      if compact then
        local overrides = page[1].group == 'Tier overrides'
        text(34, 10, overrides and 'MATERIAL TIER' or 'RELATIVE TIER', 42, 'blue')
        text(80, 10, overrides and 'OVERRIDE' or 'MULTIPLIER', 22, 'blue')
        if overrides then
          text(115, 10, 'EFFECTIVE', 40, 'blue')
        end
        text(
          34,
          44,
          overrides and 'Blank follows the curve. Later tiers remain skipped unless enabled.'
            or 'One multiplier per relative tier. Maximum and quantity limits still apply.',
          124,
          'muted'
        )
        y = 12
      end
      for _, f in ipairs(page) do
        if compact then
          text(34, y, f.label, 42, 'text')
          editorRow(80, y, 22, f)
          if page[1].group == 'Tier overrides' then
            local budget = Batch.budget(cfg.batch, f.label)
            text(115, y, budget == 0 and 'Skipped' or budget .. 'x', 40, 'muted')
          end
          y = y + 2
        else
          local helpY, height = y + 2, 4
          text(34, y, f.label, 124, 'blue')
          if f.kind == 'multiToggle' then
            local x, row = 34, y + 1
            local selected = Config.selected(values()[f.key], f.choices)
            for _, option in ipairs(f.choices) do
              local key, choice = f.key, option[1]
              if x + unicode.wlen('[ X ' .. option[2] .. ' ]') - 1 > 157 then
                x, row = 34, row + 1
              end
              x = toggleButton(x, row, selected[choice], function()
                toggleForm(key, f.choices, choice)
              end, true, option[2])
            end
            helpY, height = row + 1, row - y + 4
          elseif f.enableForm then
            local program = Programs.byId[state.settings]
            local choice = f.enableForm
            local selected = Config.selected(values()[program.formSwitch], program.formChoices)
            toggleButton(34, y + 1, selected[choice], function()
              toggleForm(program.formSwitch, program.formChoices, choice)
            end, true)
            editorRow(42, y + 1, 116, f)
          elseif f.kind == 'select' then
            local label, selected = values()[f.key], 1
            for n, option in ipairs(f.choices) do
              if option[1] == values()[f.key] then
                label, selected = option[2], n
              end
            end
            button(34, y + 1, label, function()
              commitEdit()
              state.choice =
                { key = f.key, label = f.label, choices = f.choices, selected = selected }
            end)
          elseif f.toggleValues or f.kind == 'toggle' then
            local key = f.key
            local choices = f.toggleValues or { 'off', 'on' }
            toggleButton(34, y + 1, values()[key] == choices[2], function()
              chooseValue(key, values()[key] == choices[2] and choices[1] or choices[2])
            end)
          elseif f.choices then
            local x = 34
            for _, option in ipairs(f.choices) do
              local key, value = f.key, option[1]
              x = button(x, y + 1, option[2], function()
                chooseValue(key, value)
              end, true, values()[key] == value)
            end
          else
            editorRow(34, y + 1, 124, f)
          end
          text(34, helpY, f.help, 124, 'muted')
          y = y + height
        end
      end
      if #pages > 1 then
        local pageRow = section.pageSize == 9 and 45 or 44
        text(34, pageRow, 'Settings page ' .. state.settingsPage .. '/' .. #pages, 30, 'muted')
        button(111, pageRow, 'Previous', function()
          commitEdit()
          state.settingsPage = state.settingsPage - 1
        end, state.settingsPage > 1)
        button(133, pageRow, 'Next', function()
          commitEdit()
          state.settingsPage = state.settingsPage + 1
        end, state.settingsPage < #pages)
      end
      button(34, 47, 'Run program', function()
        navigate('programs')
      end)
      if state.settings == 'batch' and cfg.batch.mode == 'tiered' then
        button(54, 47, 'Effective tiers', function()
          commitEdit()
          state.choice = { label = 'Material budgets at ' .. cfg.batch.currentTier, budgets = true }
        end)
      end
    elseif state.page == 'programs' then
      text(34, 7, 'RUN A PROGRAM', 124, 'blue')
      text(
        34,
        8,
        'Select what to do. Preview selected builds a plan without changing patterns.',
        124,
        'muted'
      )
      local y = 11
      for _, p in ipairs(Programs.list) do
        local id = p.id
        button(34, y, (state.selected == id and '* ' or '') .. p.name, function()
          commitEdit()
          state.selected = id
        end)
        text(38, y + 1, p.description, 120, 'text')
        if p.unavailable then
          text(38, y + 2, p.unavailable, 120, 'muted')
          y = y + 1
        end
        y = y + 3
      end
      local selected = state.selected and Programs.byId[state.selected]
      local x = button(34, 47, 'Preview selected', function()
        action('preview')
      end, selected ~= nil and not selected.unavailable)
      button(x, 47, 'Program settings', function()
        navigate('settings', state.selected)
      end, selected ~= nil and #selected.fields > 0)
    elseif state.page == 'preview' then
      local preview = state.preview
      local p = preview and preview.plan
      local current = preview and preview.id or state.selected
      text(34, 7, 'Preview - ' .. (current and Programs.byId[current].name or ''), 124, 'blue')
      local x = 34
      local tabs = current and Programs.byId[current].previewTabs
        or preview and preview.id == 'assline' and {
          { 'changes', 'Input changes' },
          { 'recipes', 'Rename recipes' },
          {
            'capacity',
            'Capacity',
          },
        }
        or {
          { 'changes', 'Patterns' },
          { 'existing', 'Existing' },
          { 'skipped', 'Excluded' },
          { 'capacity', 'Capacity' },
          { 'details', 'Details' },
        }
      for _, tab in ipairs(tabs) do
        local section = tab[1]
        x = button(x, 9, (state.section == section and '* ' or '') .. tab[2], function()
          state.section = section
          state.offset = 0
        end)
      end
      scrollRows(34, 12, 74, 31)
      text(113, 12, 'Summary', 45, 'blue')
      if p then
        if p.kind == 'donorCleanup' then
          text(113, 14, p.banks .. ' donor interfaces', 45, 'muted')
          text(113, 15, p.scanned .. ' encoded patterns scanned', 45)
          text(113, 16, #p.cleanups .. ' recipes to park', 45, 'yellow')
          text(113, 17, p.parked .. ' already parked', 45, 'green')
          text(113, 18, p.skipped .. ' skipped; see Patterns', 45, 'muted')
        elseif preview.id == 'assline' then
          --todo remove and unify this
          text(113, 14, p.scanned .. 'existing patterns scanned', 45)
          text(113, 15, #p.changes .. 'existing patterns to update', 45, 'green')
          text(113, 16, p.newRecipes .. ' donor patterns needed', 45, 'yellow')
          text(113, 17, (#p.recipes - p.newRecipes) .. ' rename recipes reused', 45, 'green')
          text(113, 18, p.available .. ' processing donors available', 45, 'muted')
        else
          text(113, 13, #(p.existing or {}) .. ' existing patterns scanned', 45, 'muted')
          text(113, 14, p.reused .. ' reused patterns recipes', 45, 'green')
          text(
            113,
            15,
            p.resizeCount .. ' reused patterns to resize',
            45,
            p.resizeCount > 0 and 'yellow_lighter1' or 'muted'
          )
          text(113, 16, #p.preserved .. ' unrelated kept', 45, 'muted')
          text(
            113,
            18,
            p.required.processing
              .. '/'
              .. p.available.processing
              .. ' proc/ultimate pattern donors to be used',
            45,
            p.required.processing < p.available.processing and 'green' or 'red'
          )
          text(113, 20, #p.moves .. ' sorting moves first', 45)
        end
        local y = 22
        text(
          113,
          y,
          state.busy and (state.paused and 'Paused' or 'Executing preview')
            or fs.exists(paths.pending) and 'Saved transaction still open'
            or #p.errors == 0 and 'Ready to execute'
            or 'BLOCKED: ' .. #p.errors .. ' issue(s)',
          45,
          (state.busy or fs.exists(paths.pending)) and 'yellow'
            or #p.errors == 0 and 'green'
            or 'red'
        )
        local function summaryRow(message, tone)
          for _, row in ipairs(U.wrapRow({ message, tone }, 45, unicode)) do
            if y < 32 then
              y = y + 1
              text(113, y, row[1], 45, tone)
            end
          end
        end
        if not state.busy and fs.exists(paths.pending) then
          summaryRow('Continue or stop the saved operation before Execute.', 'yellow')
        end
        for _, err in ipairs(p.errors) do
          summaryRow(err, 'red')
        end
        for _, warning in ipairs(p.warnings or {}) do
          summaryRow(warning, 'yellow')
        end
        if preview.manifest and #preview.manifest.unresolved > 0 then
          text(113, 34, 'Registry names need verification.', 45, 'red')
        end
        if C.runner.requiresVerification(preview) then
          text(113, 36, 'Destination assumption: 36 slots each.', 45, 'yellow')
          text(113, 37, 'Verify expanded interfaces in the game.', 45, 'muted')
          button(113, 39, state.verified and '36 slots verified' or 'Verify 36 slots', function()
            state.verified = not state.verified
          end, not state.busy)
        else
          text(113, 36, 'Returns donors to their original slots.', 45, 'muted')
          text(113, 37, 'Only the shared editor needs free space.', 45, 'muted')
        end
      end
      local x = button(34, 47, 'Scan', function()
        action('preview')
      end, not state.busy)
      x = button(x, 47, 'Execute preview', function()
        action('execute')
      end, executable())
      x = button(x, 47, 'Program settings', function()
        navigate('settings', preview.id)
      end, not state.busy and preview ~= nil and #Programs.byId[preview.id].fields > 0)
      button(x, 47, 'Run program', function()
        navigate('programs')
      end, not state.busy)
      if preview and preview.report and not state.busy then
        button(34, 45, 'Export report', function()
          local path = '/home/assline-preview.txt'
          local ok, why = pcall(function()
            local file, err = io.open(path, 'w')
            U.check(file, err or 'Cannot open report file')
            local written, writeError = file:write(preview.report)
            local closed, closeError = file:close()
            U.check(written and closed, writeError or closeError or 'Cannot save report')
          end)
          status(
            ok and 'Saved preview report to ' .. path or 'Report export failed: ' .. tostring(why),
            ok and 'green' or 'red'
          )
        end, not state.busy)
      end
    else
      text(34, 7, state.page == 'history' and 'HISTORY' or 'HELP', 124, 'blue')
      scrollRows(34, 12, 124, 31)
      button(34, 47, 'Run program', function()
        navigate('programs')
      end, not state.busy)
    end
    if state.busy then
      button(113, 47, state.paused and 'Resume' or 'Pause', function()
        state.paused = not state.paused
        status(
          state.paused and 'Paused. Resume continues this run; Stop ends it.' or 'Resuming work.',
          'yellow'
        )
      end, not state.stopRequested)
      button(127, 47, 'Stop', function()
        state.stopRequested, state.paused = true, false
        status('Stopping after the current pattern transaction / sorting cycle.', 'yellow')
      end)
    elseif C.runner.hasSaved() then
      if state.page ~= 'settings' then
        button(113, 45, 'Continue last operation', function()
          action('continue')
        end)
      end
      button(135, 47, 'Stop saved', function()
        state.choice = { label = 'Stop saved operation', discard = true }
      end)
    end
    button(151, 47, 'Quit', function()
      commitEdit()
      state.stopRequested, state.paused = true, false
      state.running = false
    end)
    text(3, 46, string.rep('-', 155), 155, 'muted')
    text(3, 49, state.status, 155, state.tone)
    if C.runner.hasSaved() and not state.busy then
      text(
        3,
        5,
        'Saved operation available. Continue it, or Stop saved to start fresh.',
        155,
        'muted'
      )
    end
    if state.choice then
      -- Modal controls replace the underlying hit areas, so clicks cannot leak
      -- through to settings or Execute. Closing it repaints the underlying page.
      buttons = {}
      scrollbar = nil
      if not state.choice.painted then
        gpu.setBackground(colors.panel)
        gpu.fill(48, 9, 104, 29, ' ')
        state.choice.painted = true
      end
      text(51, 10, state.choice.label, 98, 'blue', 'panel')
      text(
        51,
        12,
        state.choice.discard and 'Discard the saved run and unfinished transaction record.'
          or state.choice.budgets and 'Material budgets before recipe voltage and quantity limits.'
          or 'Choose a tier. Escape cancels.',
        98,
        'muted',
        'panel'
      )
      if state.choice.discard then
        text(
          51,
          15,
          'Completed edits and moves stay in place. Nothing is undone.',
          98,
          'yellow',
          'panel'
        )
        text(
          51,
          17,
          'Any pattern left in the editor stays there; occupied slots are kept.',
          98,
          'muted',
          'panel'
        )
        text(
          51,
          19,
          'The discarded record is saved in /home/assline.abandoned.',
          98,
          'muted',
          'panel'
        )
        button(51, 23, 'Discard saved operation', function()
          action('discard')
          state.choice = nil
        end)
      end
      local entries = state.choice.discard and {} or state.choice.choices or Batch.tiers
      for n, entry in ipairs(entries) do
        local x = n <= 9 and 51 or 101
        local y = 14 + ((n - 1) % 9) * 2
        if state.choice.budgets then
          local budget = Batch.budget(cfg.batch, entry)
          text(
            x,
            y,
            entry .. '  ' .. (budget == 0 and 'Skipped' or budget .. 'x'),
            45,
            'text',
            'panel',
            nil,
            nil,
            { from = 1, length = #entry, tier = entry }
          )
        else
          local value, label = entry[1], entry[2]
          button(x, y, label, function()
            chooseValue(state.choice.key, value)
          end, true, state.choice.selected == n)
        end
      end
      button(51, 35, 'Close', function()
        state.choice = nil
      end)
    end
  end
  local lastProgress, lastPoll = 0, -math.huge
  local function progress(message, immediate)
    if state.paused or state.stopRequested then
      return
    end
    if immediate or computer.uptime() - lastProgress >= 1 then
      status(message, 'yellow')
      text(3, 49, message, 155, 'yellow')
      lastProgress = computer.uptime()
    end
  end
  local function control(delay)
    local pulled
    if delay > 0 or computer.uptime() - lastPoll >= 0.1 then
      draw()
      pulled = { event.pull(delay) }
      handle(pulled)
      lastPoll = computer.uptime()
    end
    return { paused = state.paused, stop = state.stopRequested }
  end
  action = function(name)
    commitEdit()
    local isWork = name == 'preview' or name == 'execute' or name == 'continue'
    U.check(not isWork or not state.busy, 'Work already running')
    if name == 'execute' then
      U.check(executable(), 'Review and verify the preview first')
    end
    if isWork then
      state.error = nil
      state.busy = true
      state.stopRequested, state.paused = false, false
      lastPoll = computer.uptime()
      status('Working: ' .. name .. ' (Pause / Resume / Stop; Esc stops)', 'yellow')
    end
    local ok, why = pcall(function()
      if name == 'history' then
        history()
      elseif name == 'preview' then
        local id = state.page == 'preview' and state.preview and state.preview.id or state.selected
        U.check(id, 'Choose a program first')
        invalidate()
        state.page = 'preview'
        state.section = 'changes'
        state.offset = 0
        state.preview = C.runner.preview(cfg, id, progress, control)
        status(
          C.runner.requiresVerification(state.preview)
              and 'Preview ready. Review the plan and verify destination capacity before Execute preview.'
            or 'Preview ready. Review which disposable donor recipes will be replaced before Execute preview.',
          'green'
        )
      elseif name == 'execute' then
        local preview = state.preview
        C.runner.execute(cfg, preview, progress, control)
        status('Program completed. Build a new preview to check the result.', 'green')
      elseif name == 'continue' then
        invalidate()
        state.preview = C.runner.continue(cfg, progress, control)
        if state.preview then
          state.page, state.section, state.offset = 'preview', 'changes', 0
          state.selected = state.preview.id
        end
        status(
          state.preview
              and not C.runner.hasChanges(state.preview)
              and #state.preview.plan.errors == 0
              and 'No remaining changes for the current settings.'
            or state.preview and state.preview.continuedWithChangedSettings and 'Settings changed since the saved run. Review the updated preview before executing.'
            or state.preview and 'Remaining work previewed with current settings. Review and Execute to continue.'
            or 'Saved transaction completed. Choose a program to preview the remaining work.',
          'green'
        )
      elseif name == 'discard' then
        C.runner.discard()
        invalidate()
        status(
          'Saved operation discarded. Existing patterns stay as they are. Build a new preview.',
          'muted'
        )
      end
    end)
    if name == 'execute' then
      invalidate()
    end
    if isWork then
      state.busy = false
    end
    if not ok and why == C.stopped then
      state.paused = false
      status(C.stopped, 'muted')
    else
      U.check(ok, why)
    end
    if isWork then
      perfReport(ok and (name .. ' complete') or 'stopped by user')
      releaseWork()
      if state.page == 'history' then
        history()
      end
    end
  end
  local function insert(s)
    s = s:gsub('[\r\n]', ' '):gsub('%z', '')
    if edit.selectAll then
      edit.value = ''
      edit.cursor = 1
      edit.selectAll = false
    end
    edit.value = unicode.sub(edit.value, 1, edit.cursor - 1)
      .. s
      .. unicode.sub(edit.value, edit.cursor)
    edit.cursor = edit.cursor + unicode.len(s)
  end
  local function scrollTo(y)
    local drag = state.scrollDrag
    if not drag or not scrollbar then
      return
    end
    local travel = scrollbar.room - scrollbar.thumb
    if travel > 0 then
      state.offset = math.floor(
        math.max(0, math.min(1, (y - scrollbar.y - drag.grab) / travel)) * scrollbar.maximum + 0.5
      )
    end
  end
  local function ownsDrag(e)
    local d = state.scrollDrag
    return d
      and d.screen == e[2]
      and d.button == e[5]
      and d.player == e[6]
      and d.page == state.page
      and d.section == state.section
  end
  handle = function(e)
    if state.choice then
      if e[1] == 'key_down' then
        local key = e[4]
        if key == 1 then
          state.choice = nil
        elseif state.choice.choices then
          if key == 200 or key == 208 then
            state.choice.selected = math.max(
              1,
              math.min(#state.choice.choices, state.choice.selected + (key == 200 and -1 or 1))
            )
          elseif key == 28 or key == 0x9C then
            chooseValue(state.choice.key, state.choice.choices[state.choice.selected][1])
          end
        end
        return
      elseif e[1] ~= 'touch' and e[1] ~= 'interrupted' then
        return
      end
    end
    if e[1] == 'interrupted' then
      state.stopRequested, state.paused = true, false
      state.running = false
    elseif e[1] == 'touch' then
      state.scrollDrag = nil
      if
        scrollbar
        and scrollbar.maximum > 0
        and e[5] == 0
        and e[3] >= scrollbar.x
        and e[3] < scrollbar.x + 2
        and e[4] >= scrollbar.y
        and e[4] < scrollbar.y + scrollbar.room
      then
        local onThumb = e[4] >= scrollbar.top and e[4] < scrollbar.top + scrollbar.thumb
        state.scrollDrag = {
          screen = e[2],
          button = e[5],
          player = e[6],
          page = state.page,
          section = state.section,
          grab = onThumb and e[4] - scrollbar.top or math.floor(scrollbar.thumb / 2),
        }
        if not onThumb then
          scrollTo(e[4])
        end
        return
      end
      for _, b in ipairs(buttons) do
        if e[3] >= b.x and e[3] < b.x + b.w and e[4] == b.y then
          if edit and (b.editKey ~= edit.key or b.section ~= edit.section) then
            commitEdit()
          end
          b.action(e[3], e[4])
          break
        end
      end
    elseif e[1] == 'drag' then
      if ownsDrag(e) then
        scrollTo(e[4])
      end
    elseif e[1] == 'drop' then
      if ownsDrag(e) then
        state.scrollDrag = nil
      end
    elseif e[1] == 'scroll' and not edit then
      state.scrollDrag = nil
      state.offset = state.offset - e[5] * 3
    elseif e[1] == 'clipboard' and edit then
      insert(e[3])
    elseif e[1] == 'key_down' then
      local char, key = e[3], e[4]
      if state.busy and (key == 1 or char == 113) then
        state.stopRequested, state.paused = true, false
        if char == 113 then
          state.running = false
        end
      elseif edit then
        if key == 28 or key == 0x9C then
          commitEdit()
        elseif key == 1 then
          edit = nil
        elseif key == 30 and keyboard.isControlDown() then
          edit.selectAll = true
        elseif key == 203 then
          edit.cursor = math.max(1, edit.cursor - 1)
          edit.selectAll = false
        elseif key == 205 then
          edit.cursor = math.min(unicode.len(edit.value) + 1, edit.cursor + 1)
          edit.selectAll = false
        elseif key == 199 then
          edit.cursor = 1
          edit.selectAll = false
        elseif key == 207 then
          edit.cursor = unicode.len(edit.value) + 1
          edit.selectAll = false
        elseif key == 14 or key == 211 then
          if edit.selectAll then
            edit.value = ''
            edit.cursor = 1
            edit.selectAll = false
          else
            local at = key == 14 and edit.cursor - 1 or edit.cursor
            if at >= 1 then
              edit.value = unicode.sub(edit.value, 1, at - 1) .. unicode.sub(edit.value, at + 1)
              edit.cursor = at
            end
          end
        elseif not keyboard.isControlDown() then
          local value = char and char >= 32 and unicode.char(char) or keypad[key]
          if value then
            insert(value)
          end
        end
      elseif key == 201 then
        state.offset = state.offset - 31
      elseif key == 209 then
        state.offset = state.offset + 31
      elseif char == 113 then
        state.running = false
      elseif char == 115 and state.page == 'preview' then
        action('preview')
      end
    end
  end
  local ok, err = pcall(function()
    gpu.setResolution(w, h)
    cfg = Config.migrate(readFile(paths.config))
    while state.running do
      draw()
      local e = { event.pull(1) }
      local success, why = pcall(handle, e)
      if not success then
        status(tostring(why), 'red')
        state.error = state.status
        state.busy = false
        state.offset = 0
        pcall(perfReport, 'stopped: ' .. state.status)
        releaseWork()
        if state.page == 'history' then
          pcall(history)
        end
      end
    end
  end)
  releaseWork()
  state.preview = nil
  state.history = nil
  buttons = {}
  paintCache = {}
  contentRows = nil
  edit = nil
  gpu.setResolution(oldW, oldH)
  gpu.setForeground(oldFG)
  gpu.setBackground(oldBG)
  term.clear()
  term.setCursor(1, 1)
  if not ok then
    error(err, 0)
  end
end
C.runUI = runUI

-- Source: source/app/90_main.lua
if ... == '--test' then
  return C
end
runUI()

end,table.unpack(args,1,args.n))
package.path=savedPath
if args[1]~='--test' then unload() end
if not ok then error(result,0) end
return result
