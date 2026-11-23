-- Recipe selection and loop checks are pure. OC supplies the installed graph;
-- the normal maker owns layout, sorting, batch resizing and ingredient writes.
local U = require('assline_util')
local Batch = require('assline_batch')
local Planner = require('assline_planner')
local Supply = require('assline_supply')
local M = {}

function M.priority(route, policy)
  if not policy then
    return nil
  end
  local tier = Batch.voltageTier(route.eut)
  local function atMost(limit)
    for _, name in ipairs(Batch.tiers) do
      if name == tier then
        return true
      end
      if name == limit then
        return false
      end
    end
    return false
  end
  for _, group in ipairs({ 'high', 'medium' }) do
    if
      route.heat
      and route.heat < policy[group .. 'Heat']
      and atMost(policy[group .. 'Voltage'])
    then
      return group
    end
  end
  return 'low'
end

function M.routeForm(route, policy)
  local priority = M.priority(route, policy)
  return 'c' .. route.circuit .. (priority and priority ~= 'high' and '_' .. priority or ''),
    priority
end

function M.ingredient(data, index, amount)
  local item = U.clone(U.check(data.items[index], 'Unknown melting ingredient'))
  item.name = U.check(data.names[item.name], 'Unknown melting registry')
  item.size = amount or 1
  return item
end

local function ingredients(data, pairs)
  local result = {}
  for _, pair in ipairs(pairs) do
    result[#result + 1] = M.ingredient(data, pair[1], pair[2])
  end
  return result
end

function M.extractorMatcher(data)
  local fluids = {}
  for _, material in ipairs(data.materials) do
    local fluid = M.ingredient(data, material.fluid).name
    fluids[fluid] = fluids[fluid] or {}
    fluids[fluid][#fluids[fluid] + 1] = material
  end
  local function single(stacks)
    local result, key
    for _, stack in pairs(stacks) do
      local identity = Supply.identity(stack)
      if key and key ~= identity then
        return nil
      end
      if not U.integer(stack.size) or stack.size <= 0 then
        return nil
      end
      if not result then
        result, key = U.clone(stack), identity
      else
        result.size = result.size + stack.size
      end
    end
    return result
  end
  return function(recipe)
    if recipe.kind ~= 'processing' then
      return nil
    end
    local input, output = single(recipe.inputs), single(recipe.outputs)
    if
      not input
      or not output
      or input.type ~= 'item'
      or output.type ~= 'fluid'
      or input.tag
      or output.tag
    then
      return nil
    end
    for _, material in ipairs(fluids[output.name] or {}) do
      local function match(rule)
        local name, damage = rule.name, rule.damage
        if rule.kind == 'meta' then
          damage = rule.prefix + material.dsf
        elseif rule.kind == 'suffix' then
          name, damage = name .. material.exSuffix, 0
        end
        return name == input.name
          and damage == input.damage
          and input.size * rule.amount == output.size * rule.n
      end
      for _, index in ipairs(data.extraction.sets[material.ex]) do
        if match(data.extraction.rules[index]) then
          return output.name
        end
      end
      for _, rule in ipairs(material.exExtra or {}) do
        if match(rule) then
          return output.name
        end
      end
    end
  end
end

function M.coreKeys(data)
  local keys = {}
  for _, material in ipairs(data.materials) do
    local direct = false
    for _, route in ipairs(material.routes) do
      direct = direct or route.rank == 0
    end
    local fluid = M.ingredient(data, material.fluid).name
    local info = { fluid = fluid, migratable = direct and material.rawSource ~= false }
    for _, route in ipairs(material.routes) do
      local outputs = ingredients(data, data.products[route.output])
      local function register(inputs)
        local function remember(values, partial)
          local key = Planner.recipeKey({ kind = 'processing', inputs = inputs, outputs = values })
          if not partial or not keys[key] then
            keys[key] = info
          end
        end
        remember(outputs)
        -- A manually encoded recipe may omit coproducts. Recognize its primary
        -- output for migration; the new pattern still writes the full recipe.
        if #outputs > 1 then
          for _, output in ipairs(outputs) do
            if output.type == 'fluid' and output.name == fluid then
              remember({ output }, true)
              break
            end
          end
        end
      end
      local inputs = ingredients(data, data.feeds[route.feed])
      if route.gas ~= 0 then
        inputs[#inputs + 1] = M.ingredient(data, route.gas, route.gasAmount)
      end
      register(inputs)
      if route.gas ~= 0 then
        register(ingredients(data, data.feeds[route.feed]))
      end
      if route.legacyGas then
        local legacy = {}
        for _, input in ipairs(inputs) do
          if Supply.identity(input) ~= Supply.identity(M.ingredient(data, route.legacyGas)) then
            legacy[#legacy + 1] = input
          end
        end
        register(legacy)
      end
    end
  end
  return keys
end

function M.compile(data, options, graph, retired, owned, checkpoint)
  local manifest = {
    version = 1,
    source = U.clone(data.source),
    policy = {
      mode = 'meltingCore',
      gas = options.gas,
      requestGas = options.requestGas ~= false,
      priority = U.clone(options.priority),
      batch = U.clone(options.batch),
      multiplier = options.multiplier,
      craftableFluids = U.clone(options.craftableFluids),
    },
    recipes = {},
    existingFluids = {},
    invalidFluids = {},
    skipped = {},
    unresolved = {},
    unusedExcluded = 0,
    unclassifiedRecipes = 0,
    tierExcluded = 0,
  }
  local excluded = U.clone(retired or {})
  for origin in pairs(owned or {}) do
    excluded[origin] = true
  end
  local producerExcluded = U.clone(excluded)
  for origin in pairs(options.extractionOrigins or {}) do
    producerExcluded[origin] = true
  end
  local function skip(material, stack, form, reason)
    if form == 'ingot' and options.emitCasting == false then
      return
    end
    manifest.skipped[#manifest.skipped + 1] = {
      material = material.name,
      label = stack.label,
      form = form,
      name = stack.name,
      damage = stack.damage,
      reason = reason,
    }
  end
  local function scaled(material, route, inputs, outputs, form, label, stock)
    local quantities = {}
    for _, stacks in ipairs({ inputs, outputs }) do
      for _, s in ipairs(stacks) do
        quantities[#quantities + 1] = s
      end
    end
    local count, batch = Batch.resolve(
      options.batch,
      material.tier,
      route.eut,
      options.multiplier or 1,
      quantities,
      material.tierSource,
      { cost = route.cost }
    )
    if count == 0 then
      manifest.tierExcluded = manifest.tierExcluded + 1
      return nil, batch.excluded
    end
    if not material.tier then
      manifest.unclassifiedRecipes = manifest.unclassifiedRecipes + 1
    end
    local recipe = {
      kind = 'processing',
      material = material.name,
      outputForm = form,
      outputLabel = label,
      label = material.name .. ' / ' .. label,
      inputs = inputs,
      outputs = outputs,
      stock = stock or {},
      batch = batch,
      heat = route.heat,
    }
    for _, stacks in ipairs({ recipe.inputs, recipe.outputs }) do
      for _, s in ipairs(stacks) do
        s.size = s.size * count
        U.check(
          U.integer(s.size) and s.size > 0,
          'Melting pattern quantity exceeds the supported limit'
        )
      end
    end
    return recipe
  end
  local casts, candidates = {}, {}
  for _, material in ipairs(data.materials) do
    if checkpoint then
      checkpoint()
    end
    local fluid = M.ingredient(data, material.fluid, 144)
    local ingot = M.ingredient(data, material.ingot, 1)
    -- Presence prevents duplicate production. Dependency proofs decide whether
    -- a new route/cast is safe; failing one must never authorize a duplicate.
    local advertised = (options.craftableFluids or {})[fluid.name]
    local native = advertised or graph:hasProducer(fluid, producerExcluded, true)
    if native then
      manifest.existingFluids[fluid.name] = true
    end
    local variant
    local token = material.key
    for _, modifier in ipairs({ 'magnetic', 'attuned' }) do
      if token:sub(1, #modifier) == modifier or token:sub(-#modifier) == modifier then
        variant = modifier
      end
    end
    local selected, reason
    local routes, hasGasRoute, direct = {}, false, false
    for _, route in ipairs(material.routes) do
      direct = direct or route.rank == 0
      hasGasRoute = hasGasRoute or route.rank == 0 and route.gas ~= 0
      local form = M.routeForm(route, options.priority)
      if options.forms[form] and route.rank == 0 then
        routes[#routes + 1] = route
      end
    end
    local invalid = material.rawSource == false
        and 'The scrape has no independent raw-dust source; only recovery/repacking is available.'
      or not direct
        and #material.routes > 0
        and 'Only ore-processing or alternative-material feeds are available; no direct material-dust route.'
    if invalid then
      manifest.invalidFluids[fluid.name] = true
    end
    table.sort(routes, function(a, b)
      local function rank(r)
        local gas = r.gas ~= 0 and M.ingredient(data, r.gas).name or 'none'
        return r.rank * 100 + (gas == options.gas and 0 or gas == 'none' and 10 or 20)
      end
      if rank(a) ~= rank(b) then
        return rank(a) < rank(b)
      end
      if a.ticks ~= b.ticks then
        return a.ticks < b.ticks
      end
      return a.feed < b.feed
    end)
    if not native and not variant and not invalid then
      for _, route in ipairs(routes) do
        local gas = route.gas ~= 0 and M.ingredient(data, route.gas).name or 'none'
        if gas == options.gas or gas == 'none' and not hasGasRoute then
          local inputs = ingredients(data, data.feeds[route.feed])
          if route.gas ~= 0 and options.requestGas ~= false then
            inputs[#inputs + 1] = M.ingredient(data, route.gas, route.gasAmount)
          end
          local outputs = ingredients(data, data.products[route.output])
          local independent = graph:independent(inputs, { fluid, ingot }, excluded)
          if independent then
            local stock = route.circuit ~= 0
                and {
                  {
                    type = 'item',
                    name = 'gregtech:gt.integrated_circuit',
                    damage = route.circuit,
                    size = 1,
                    label = 'Programmed Circuit ' .. route.circuit,
                  },
                }
              or {}
            if route.gas ~= 0 and options.requestGas == false then
              stock[#stock + 1] = M.ingredient(data, route.gas, route.gasAmount)
            end
            local form, priority = M.routeForm(route, options.priority)
            selected, reason = scaled(material, route, inputs, outputs, form, 'Molten', stock)
            if selected then
              selected.priority, selected.primaryFluid = priority, fluid.name
              break
            end
          else
            reason = 'Feed depends on this molten material or its ingot cast; would create a loop.'
          end
        end
      end
      reason = reason
        or 'No enabled route for the selected gas/circuit; no no-gas fallback is installed.'
    else
      reason = variant and ('Fluid Shaper excludes ' .. variant .. ' material variants.')
        or native and (advertised and 'Fluid already craftable in ME; no melting recipe added.' or 'Existing fluid-output pattern; no duplicate melting route added.')
        or invalid
    end
    if selected then
      candidates[#candidates + 1] =
        { recipe = selected, material = material, fluid = fluid, ingot = ingot }
    else
      for _, route in ipairs(material.routes) do
        local form = M.routeForm(route, options.priority)
        if options.forms[form] then
          skip(material, fluid, form, reason)
          break
        end
      end
    end
    if variant then
      if options.forms.ingot then
        skip(material, ingot, 'ingot', reason)
      end
    else
      casts[#casts + 1] = { material = material, fluid = fluid, ingot = ingot }
    end
  end
  -- Production and casting must be checked as one proposed graph. Otherwise an
  -- ingot provided by another new cast can be mistaken for an external input.
  local proposed = {}
  for n, entry in ipairs(candidates) do
    entry.origin = 'new-melting-' .. n
    proposed[#proposed + 1] = entry
  end
  local casting = {}
  if options.forms.ingot then
    for n, entry in ipairs(casts) do
      local material, fluid, ingot = entry.material, entry.fluid, entry.ingot
      local recipe, reason = scaled(
        material,
        { eut = material.castEUt, cost = 1 },
        { U.clone(fluid) },
        { U.clone(ingot) },
        'ingot',
        'Ingot',
        data.ingotMold and { M.ingredient(data, data.ingotMold, 1) } or nil
      )
      if recipe then
        entry.recipe, entry.origin = recipe, 'new-cast-' .. n
        entry.requireProducer = fluid
        proposed[#proposed + 1] = entry
        casting[#casting + 1] = entry
      else
        skip(material, ingot, 'ingot', reason)
      end
    end
  end
  excluded = graph:plan(proposed, excluded)
  local supplied = {}
  for _, list in ipairs({ candidates, casting }) do
    for _, entry in ipairs(list) do
      if excluded[entry.origin] then
        skip(
          entry.material,
          entry.recipe.outputForm == 'ingot' and entry.ingot or entry.fluid,
          entry.recipe.outputForm,
          'No independent supply in the complete melting/casting plan; would create a loop or lacks a liquid producer.'
        )
      else
        if entry.recipe.outputForm ~= 'ingot' or options.emitCasting ~= false then
          manifest.recipes[#manifest.recipes + 1] = entry.recipe
        end
        for _, output in ipairs(entry.recipe.outputs) do
          if output.type == 'fluid' then
            supplied[output.name] = true
          end
        end
        if entry.recipe.outputForm == 'ingot' then
          supplied[entry.fluid.name] = true
        end
      end
    end
  end
  manifest.suppliedFluids = supplied
  return manifest
end

-- Fluid Shaper owns casts. Its normal rule compiler supplies the recipes and
-- batches; the shared graph replaces the historical native-liquid/ME guards.
function M.filterCasts(base, graph, omitted)
  local proposed = {}
  for n, recipe in ipairs(base.recipes) do
    proposed[#proposed + 1] = {
      recipe = recipe,
      origin = 'new-shaper-' .. n,
      requireProducer = recipe.outputForm == 'ingot' and recipe.inputs[1] or nil,
    }
  end
  local excluded = graph:plan(proposed, omitted)
  return M.castManifest(base, function(n)
    return excluded['new-shaper-' .. n]
  end)
end

-- Shared by ordinary previews and destination-sized compilation. Eligibility
-- can be proved with compact graph rows without retaining every full recipe.
function M.castManifest(base, rejected)
  local manifest = {}
  for key, value in pairs(base) do
    manifest[key] = value
  end
  manifest.recipes, manifest.suppliedFluids, manifest.skipped = {}, {}, U.clone(base.skipped)
  for n, recipe in ipairs(base.recipes) do
    if rejected(n) then
      local out = recipe.outputs[1]
      manifest.skipped[#manifest.skipped + 1] = {
        material = recipe.material,
        form = recipe.outputForm,
        label = recipe.label,
        name = out.name,
        damage = out.damage,
        reason = 'No independent installed liquid supply for this cast; would create a loop or lacks a producer.',
      }
    else
      manifest.recipes[#manifest.recipes + 1] = U.clone(recipe)
      if recipe.outputForm == 'ingot' then
        manifest.suppliedFluids[recipe.inputs[1].name] = true
      end
    end
  end
  return manifest
end

return M
