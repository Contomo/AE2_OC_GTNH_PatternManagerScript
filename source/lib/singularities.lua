-- Solid machine routes traced from Eternal's extreme-crafting dependency chain.
-- Shared item identities and compressor rules are resolved here; placement,
-- deduplication, resizing and execution remain the normal maker's responsibility.
local U = require('assline_util')
local Batch = require('assline_batch')
local M = {}

function M.compile(data, options, checkpoint)
  U.check(data.version == 1 and data.source and data.materials, 'Unsupported singularity catalog')
  options = options or {}
  local manifest = {
    version = 1,
    source = U.clone(data.source),
    policy = {
      mode = 'singularities',
      multiplier = options.multiplier or 1,
      batch = U.clone(options.batch),
      unstable = options.unstable or 'mobius',
    },
    recipes = {},
    skipped = {},
    unresolved = {},
    unusedExcluded = 0,
    unclassifiedRecipes = 0,
    tierExcluded = 0,
  }
  local function ingredient(index, amount)
    local item = U.clone(U.check(data.items[index], 'Unknown singularity item'))
    item.name = U.check(data.names[item.name], 'Unknown singularity registry name')
    item.type, item.size = 'item', amount
    U.check(U.integer(amount) and amount > 0, 'Invalid singularity ingredient quantity')
    return item
  end
  for _, row in ipairs(data.materials) do
    if checkpoint then
      checkpoint()
    end
    local raw, compressor = row.raw, row.compressor
    if row.alternatives then
      local selected
      for _, alternative in ipairs(row.alternatives) do
        if alternative.key == manifest.policy.unstable then
          selected = alternative
        end
      end
      U.check(selected, 'Unknown unstable ingot route')
      raw, compressor = selected.raw, selected.compressor
    end
    local function add(form, input, inputCount, output, outputCount, eut, batchValues, cost)
      if options.forms and not options.forms[form] then
        return
      end
      local multiplier, batch = Batch.resolve(
        batchValues,
        row.tier,
        eut,
        form == 'singularity' and 1 or options.multiplier,
        { { type = 'item', size = inputCount }, { type = 'item', size = outputCount } },
        row.tierSource,
        { cost = cost, divisor = tonumber((options.formDivisors or {})[form]) }
      )
      if multiplier == 0 then
        local item = ingredient(output, outputCount)
        manifest.tierExcluded = manifest.tierExcluded + 1
        manifest.skipped[#manifest.skipped + 1] = {
          material = row.label,
          form = form,
          label = item.label,
          name = item.name,
          damage = item.damage,
          reason = batch.excluded,
        }
        return
      end
      local label = form == 'singularity' and 'Singularity' or 'Block'
      manifest.recipes[#manifest.recipes + 1] = {
        kind = 'processing',
        material = row.label,
        outputForm = form,
        outputLabel = label,
        label = row.label .. ' / ' .. label,
        inputs = { ingredient(input, inputCount * multiplier) },
        outputs = { ingredient(output, outputCount * multiplier) },
        stock = {},
        batch = batch,
        chainGroup = data.groups[row.group],
      }
      if form == 'block' and not row.tier then
        manifest.unclassifiedRecipes = manifest.unclassifiedRecipes + 1
      end
    end
    -- A single singularity can require more than the global per-item limit.
    -- Its recipe is indivisible: never clamp or scale down those requirements.
    add('singularity', row.block, row.blocks, row.singularity, row.yield, row.eut)
    local rule = U.check(data.rules[compressor], 'Missing compressor rule')
    add('block', raw, rule.input, row.block, rule.output, rule.eut, options.batch, rule.input)
  end
  return manifest
end

return M
