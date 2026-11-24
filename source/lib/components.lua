-- Component recipes have genuinely different ingredients at each tier. Shared
-- identities and alternate-route deltas are scraped; placement is handled by
-- the normal maker. A machine cycle always produces its native stack of 64;
-- both-rubber patterns combine two verified cycles.
local U = require('assline_util')
local Batch = require('assline_batch')
local M = {}

-- Expand scraped deltas once for every selection mode. Both-rubber batches
-- pair only routes whose other ingredients and quantities are identical.
local function rubberRoutes(data, row, polymer)
  local routes, groups, order = {}, {}, {}
  for variantIndex = 0, #row.variants do
    local amounts, common, kind, compatible = {}, {}, nil, true
    for _, pair in ipairs(row.inputs) do
      amounts[pair[1]] = pair[2]
    end
    if variantIndex > 0 then
      local delta = row.variants[variantIndex]
      for _, index in ipairs(delta.remove) do
        amounts[index] = nil
      end
      for _, pair in ipairs(delta.set) do
        amounts[pair[1]] = pair[2]
      end
    end
    for index, amount in pairs(amounts) do
      local material = data.items[index].polymer
      if material then
        kind = kind and kind ~= material and 'mixed' or material
        if material ~= polymer then
          compatible = false
        end
      else
        common[index] = amount
      end
    end
    if polymer == 'both' and kind then
      if kind == 'sbr' or kind == 'silicone' then
        local key = U.canonical(common)
        if not groups[key] then
          groups[key] = { sbr = {}, silicone = {} }
          order[#order + 1] = groups[key]
        end
        local choices = groups[key][kind]
        choices[#choices + 1] = amounts
      end
    elseif compatible then
      routes[#routes + 1] = { amounts = amounts, cycles = 1 }
    end
  end
  for _, group in ipairs(order) do
    for _, sbr in ipairs(group.sbr) do
      for _, silicone in ipairs(group.silicone) do
        local amounts = U.clone(sbr)
        for index, amount in pairs(silicone) do
          amounts[index] = (amounts[index] or 0) + amount
        end
        routes[#routes + 1] = { amounts = amounts, cycles = 2 }
      end
    end
  end
  return routes
end

function M.compile(data, options, checkpoint)
  U.check(data.version == 1 and data.components and data.recipes, 'Unsupported component catalog')
  options = options or {}
  local casingIndex
  for index, name in ipairs(data.casings) do
    if name == options.casingTier then
      casingIndex = index
    end
  end
  U.check(casingIndex, 'Select the installed Component Assembly Line casing tier')
  local polymer = options.rubber or 'sbr'
  U.check(
    polymer == 'sbr' or polymer == 'silicone' or polymer == 'rubber' or polymer == 'both',
    'Unknown component rubber'
  )
  local manifest = {
    version = 1,
    source = U.clone(data.source),
    policy = {
      mode = 'components',
      casingTier = options.casingTier,
      rubber = polymer,
      batch = U.clone(options.batch),
    },
    recipes = {},
    choices = {},
    skipped = {},
    unresolved = {},
    tierExcluded = 0,
    unusedExcluded = 0,
    unclassifiedRecipes = 0,
  }
  if polymer == 'both' then
    manifest.source.batchPolicy =
      'SBR + silicone pairs combine two native batches; rubber-free recipes use one. Shared tier gates and casing limit apply.'
  end
  local function ingredient(index, amount)
    local item = U.check(data.items[index], 'Unknown component ingredient')
    return {
      type = item.type,
      name = U.check(data.names[item.name], 'Missing component registry'),
      damage = item.damage,
      label = item.label,
      size = amount,
    }
  end
  for _, row in ipairs(data.recipes) do
    if checkpoint then
      checkpoint()
    end
    local component = U.check(data.components[row.component], 'Unknown component group')
    if not options.forms or options.forms[component.key] then
      local output = ingredient(row.output, row.yield)
      local _, batch = Batch.resolve(
        options.batch,
        row.tier,
        row.eut,
        1,
        nil,
        'component casing',
        { native = true }
      )
      local reason = row.casing > casingIndex and ('Requires ' .. row.tier .. ' component casings')
        or batch.excluded
      local choices = {}
      if not reason then
        for _, route in ipairs(rubberRoutes(data, row, polymer)) do
          local inputs = {}
          for _, index in ipairs(U.keys(route.amounts)) do
            inputs[#inputs + 1] = ingredient(index, route.amounts[index])
          end
          local stock = {}
          for _, pair in ipairs(row.stock) do
            stock[#stock + 1] = ingredient(pair[1], pair[2])
          end
          local nativeBatch = U.clone(batch)
          nativeBatch.multiplier = route.cycles
          choices[#choices + 1] = {
            kind = 'processing',
            material = component.label,
            outputForm = component.key,
            outputLabel = row.tier,
            label = component.label .. ' / ' .. row.tier,
            inputs = inputs,
            outputs = { ingredient(row.output, row.yield * route.cycles) },
            stock = stock,
            casingTier = row.tier,
            componentCircuit = component.circuit,
            batch = nativeBatch,
          }
        end
        if #choices == 0 then
          reason = polymer == 'both'
              and 'No matching SBR and silicone routes with identical other inputs'
            or 'No native route using the selected rubber'
        end
      end
      if reason then
        manifest.tierExcluded = manifest.tierExcluded + 1
        manifest.skipped[#manifest.skipped + 1] = {
          material = component.label,
          form = component.key,
          label = output.label,
          name = output.name,
          damage = output.damage,
          reason = reason,
        }
      else
        manifest.recipes[#manifest.recipes + 1] = choices[1]
        manifest.choices[#manifest.recipes] = choices
      end
    end
  end
  return manifest
end

return M
