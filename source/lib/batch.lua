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
  'Changing this tier shifts the relative material curve automatically.',
  'select',
  tierChoices
)
field(
  'voltagePolicy',
  'Recipe voltage constraint',
  'cap',
  'Cap limits the material budget by recipe voltage. It never increases an expensive material batch.',
  'choice',
  { { 'off', 'Ignore voltage' }, { 'cap', 'Cap by voltage' } }
)
field(
  'voltageTier',
  'Voltage reference tier',
  'current',
  'Machine voltage used for the voltage constraint; Current follows your progression tier.',
  'select',
  voltageChoices
)
field(
  'maxMultiplier',
  'Maximum tiered multiplier',
  '512',
  'Final ceiling after the tier curve and program multiplier are applied.'
)
field(
  'itemLimit',
  'Maximum items per pattern ingredient',
  '4096',
  'Tiered batches shrink to keep every requested item input and output at or below this amount.'
)
field(
  'fluidLimit',
  'Maximum fluid per pattern ingredient (mB)',
  '589824',
  'Tiered fluid limit. 589824 mB equals 4096 standard ingots; all quantities shrink together.'
)
field(
  'unknownMultiplier',
  'Unclassified material multiplier',
  '1',
  'Fallback when the questbook provides no material progression tier. Never guesses from low EU/t.'
)
field(
  'aboveMultiplier',
  'Materials above your tier',
  '1',
  'Budget for materials in later chapters. This does not exclude their recipes.'
)
local preset = { 4, 32, 64, 256, 320, 400, 448, 512 }
group = 'Relative curve'
for gap = 0, 7 do
  local label = gap == 0 and 'Material at your tier'
    or gap == 7 and 'Material seven or more tiers below'
    or 'Material ' .. gap .. ' tier(s) below'
  field(
    'below' .. gap,
    label,
    tostring(preset[gap + 1]),
    'Relative multiplier. Also used by the optional recipe-voltage constraint.'
  )
end
group = 'Tier overrides'
for _, name in ipairs(M.tiers) do
  field(
    'override' .. name,
    name .. ' material multiplier override',
    '',
    'Blank follows the relative curve. A number fixes this material-tier budget as you advance.',
    'optionalPositiveInteger'
  )
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
end

local function relative(values, current, tier)
  local gap = index[current] - index[tier]
  return tonumber(values[gap < 0 and 'aboveMultiplier' or 'below' .. math.min(gap, 7)])
end

function M.budget(values, tier)
  if not index[tier] then
    return tonumber(values.unknownMultiplier)
  end
  return tonumber(values['override' .. tier]) or relative(values, values.currentTier, tier)
end

-- Called once per requested recipe, before its items/fluids are resolved.
-- Stocked circuits, molds and omitted insulation solids do not constrain a batch.
function M.resolve(values, materialTier, eut, factor, quantities)
  factor = factor or 1
  U.check(U.integer(factor) and factor > 0, 'Pattern multiplier must be a positive whole number')
  local recipeTier = M.voltageTier(eut)
  local detail = { materialTier = materialTier, recipeTier = recipeTier, eut = eut }
  if not values or values.mode == 'fixed' then
    detail.multiplier = factor
    return factor, detail
  end
  M.validate(values)
  detail.materialBudget = M.budget(values, materialTier)
  local target = detail.materialBudget
  if values.voltagePolicy == 'cap' then
    local reference = values.voltageTier == 'current' and values.currentTier or values.voltageTier
    detail.voltageBudget = recipeTier and relative(values, reference, recipeTier)
      or tonumber(values.unknownMultiplier)
    target = math.min(target, detail.voltageBudget)
  end
  target = math.min(target * factor, tonumber(values.maxMultiplier))
  for _, q in ipairs(quantities or {}) do
    local limit = tonumber(values[q.type == 'fluid' and 'fluidLimit' or 'itemLimit'])
    target = math.min(target, math.floor(limit / q.size))
  end
  U.check(target >= 1, 'One recipe batch exceeds the configured item/fluid limit')
  detail.multiplier = target
  return target, detail
end

function M.describe(detail)
  local material = detail.materialTier or 'unclassified'
  local voltage = detail.recipeTier and (detail.recipeTier .. ' / ' .. detail.eut .. ' EU/t')
    or 'unknown voltage'
  return 'Batch ' .. detail.multiplier .. 'x  |  Material ' .. material .. '  |  Recipe ' .. voltage
end
return M
