-- Component recipes have genuinely different ingredients at each tier. Shared
-- identities and alternate-route deltas are scraped; placement is handled by
-- the normal maker. A machine cycle always produces its native stack of 64.
local U = require('assline_util')
local Batch = require('assline_batch')
local M = {}

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
    polymer == 'sbr' or polymer == 'silicone' or polymer == 'rubber',
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
    local output = ingredient(row.output, row.yield)
    local _, batch =
      Batch.resolve(options.batch, row.tier, row.eut, 1, nil, 'component casing', { native = true })
    local reason = row.casing > casingIndex and ('Requires ' .. row.tier .. ' component casings')
      or batch.excluded
    local choices = {}
    if not reason then
      for variantIndex = 0, #row.variants do
        local amounts = {}
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
        local compatible, inputs = true, {}
        for _, index in ipairs(U.keys(amounts)) do
          local material = data.items[index].polymer
          if material and material ~= polymer then
            compatible = false
          end
          inputs[#inputs + 1] = ingredient(index, amounts[index])
        end
        if compatible then
          local stock = {}
          for _, pair in ipairs(row.stock) do
            stock[#stock + 1] = ingredient(pair[1], pair[2])
          end
          choices[#choices + 1] = {
            kind = 'processing',
            material = component.label,
            outputForm = component.key,
            outputLabel = row.tier,
            label = component.label .. ' / ' .. row.tier,
            inputs = inputs,
            outputs = { U.clone(output) },
            stock = stock,
            casingTier = row.tier,
            componentCircuit = component.circuit,
            batch = U.clone(batch),
          }
        end
      end
      if #choices == 0 then
        reason = 'No native route using the selected rubber'
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
  return manifest
end

return M
