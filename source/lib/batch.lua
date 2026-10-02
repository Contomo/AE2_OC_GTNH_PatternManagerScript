-- Shared batch policy. Tier definitions are built from source/data/tiers.json.
local U = require('assline_util')
local Tiers = require('assline_tier_definitions')
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
  'Materials above your tier',
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
  'Cap also skips recipes above the reference tier. Ignore removes this constraint.',
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

-- OC accepts RGB, without alpha. Blend tier backgrounds locally instead.
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
