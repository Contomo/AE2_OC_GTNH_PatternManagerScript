-- One fabrication path per plasma output. Upgrade metadata and fusion overlap
-- are compiled on the desktop; normal maker services handle all OC operations.
local U = require('assline_util')
local Batch = require('assline_batch')
local M = {}
M.tierLabels = { 'T1-T3', 'T4-T5', 'Exotic' }

function M.compile(data, options, checkpoint)
  U.check(data.version == 1 and data.materials, 'Unsupported plasma catalog')
  options = options or {}
  local limit, path = options.plasmaTier or 0, options.plasmaFeed or 'fluid'
  U.check(limit == 0 or limit == 1 or limit == 2, 'Invalid maximum plasma tier')
  U.check(path == 'dust' or path == 'fluid', 'Invalid plasma feed preference')
  local manifest = {
    version = 1,
    source = U.clone(data.source),
    policy = {
      mode = 'plasma',
      plasmaTier = limit,
      multistep = options.multistep == true,
      includeFusion = options.includeFusion == true,
      plasmaFeed = path,
      multiplier = options.multiplier or 1,
    },
    recipes = {},
    skipped = {},
    unresolved = {},
    unusedExcluded = 0,
    unclassifiedRecipes = 0,
    tierExcluded = 0,
    details = {
      { 'PLASMA FABRICATOR', 'blue' },
      { 'Maximum plasma tier: ' .. limit .. ' (' .. M.tierLabels[limit + 1] .. ')' },
      { 'Multistep recipes: ' .. (options.multistep and 'enabled' or 'disabled') },
      { 'Regular-fusion products: ' .. (options.includeFusion and 'included' or 'excluded') },
      { 'Preferred feed: ' .. path .. '; use the other only when this path has no recipe.' },
      {
        'Plasma upgrades control eligibility. The fixed multiplier is independent of global tier budgets.',
        'muted',
      },
      { 'Forge controls operating voltage. Displayed recipe EU/t is informational.', 'muted' },
      { '' },
    },
  }
  if options.forms and not options.forms.plasma then
    return manifest
  end
  local function ingredient(pair)
    local item = U.clone(U.check(data.items[pair[1]], 'Unknown plasma ingredient'))
    item.name = U.check(data.names[item.name], 'Unknown plasma registry')
    item.size = pair[2]
    return item
  end
  for _, row in ipairs(data.materials) do
    if checkpoint then
      checkpoint()
    end
    local reason = row.tier > limit and ('Requires plasma tier ' .. row.tier)
      or row.multistep and not options.multistep and 'Requires multistep plasma unlock'
      or row.fusion and not options.includeFusion and 'Also produced by regular Fusion Reactor'
    local preferred = row.paths[path] and path or (path == 'fluid' and 'dust' or 'fluid')
    local input, output =
      ingredient(U.check(row.paths[preferred], 'No verified plasma feed')), ingredient(row.output)
    -- Forge upgrade eligibility is independent of global material/voltage
    -- budgets. Use a fixed batch and keep source voltage informational.
    local count, batch = Batch.resolve(nil, nil, data.eut, options.multiplier or 1)
    batch.context = 'Plasma tier ' .. row.tier .. ' (' .. M.tierLabels[row.tier + 1] .. ')'
    reason = reason or batch.excluded
    if reason then
      manifest.tierExcluded = manifest.tierExcluded + 1
      manifest.skipped[#manifest.skipped + 1] = {
        material = row.label,
        form = 'plasma',
        label = output.label,
        name = output.name,
        reason = reason,
      }
    else
      for _, stack in ipairs({ input, output }) do
        stack.size = stack.size * count
        U.check(
          U.integer(stack.size) and stack.size > 0,
          'Plasma quantity exceeds the supported limit'
        )
      end
      manifest.recipes[#manifest.recipes + 1] = {
        kind = 'processing',
        material = row.label,
        outputForm = 'plasma',
        outputLabel = 'Plasma / from ' .. preferred,
        label = row.label .. ' / Plasma / from ' .. preferred,
        inputs = { input },
        outputs = { output },
        stock = {},
        batch = batch,
        plasmaTier = row.tier,
        multistep = row.multistep,
        fusion = row.fusion,
      }
    end
  end
  return manifest
end

return M
