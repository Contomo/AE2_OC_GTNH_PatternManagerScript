-- Recipe selection and loop checks are pure. OC supplies the installed graph;
-- the normal maker owns layout, sorting, batch resizing and ingredient writes.
local U = require('assline_util')
local Batch = require('assline_batch')
local Planner = require('assline_planner')
local Supply = require('assline_supply')
local M = {}

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
    for _, route in ipairs(material.routes) do
      local inputs = ingredients(data, data.feeds[route.feed])
      if route.gas ~= 0 then
        inputs[#inputs + 1] = M.ingredient(data, route.gas, route.gasAmount)
      end
      local key = Planner.recipeKey({
        kind = 'processing',
        inputs = inputs,
        outputs = ingredients(data, data.products[route.output]),
      })
      keys[key] = { fluid = M.ingredient(data, material.fluid).name, native = material.native }
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
      batch = U.clone(options.batch),
      multiplier = options.multiplier,
    },
    recipes = {},
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
  local function skip(material, stack, form, reason)
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
    local native = graph:hasProducer(fluid, excluded)
      and graph:independent({ fluid }, { ingot }, excluded)
    local variant
    local token = material.key
    for _, modifier in ipairs({ 'magnetic', 'attuned' }) do
      if token:sub(1, #modifier) == modifier or token:sub(-#modifier) == modifier then
        variant = modifier
      end
    end
    local selected, reason
    local routes = {}
    for _, route in ipairs(material.routes) do
      local form = 'c' .. route.circuit
      if options.forms[form] then
        routes[#routes + 1] = route
      end
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
    if not native and not variant then
      for _, route in ipairs(routes) do
        local gas = route.gas ~= 0 and M.ingredient(data, route.gas).name or 'none'
        if gas == options.gas or gas == 'none' then
          local inputs = ingredients(data, data.feeds[route.feed])
          if route.gas ~= 0 then
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
            selected, reason =
              scaled(material, route, inputs, outputs, 'c' .. route.circuit, 'Molten', stock)
            if selected then
              break
            end
          else
            reason = 'Feed depends on this molten material or its ingot cast; would create a loop.'
          end
        end
      end
      reason = reason or 'No enabled, verified Melting Core feed route.'
    else
      reason = variant and ('Fluid Shaper excludes ' .. variant .. ' material variants.')
        or 'Preserve installed independent liquid production.'
    end
    if selected then
      candidates[#candidates + 1] =
        { recipe = selected, material = material, fluid = fluid, ingot = ingot }
    elseif #routes > 0 then
      skip(material, fluid, 'c' .. routes[1].circuit, reason)
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
  local originalCount = #graph.recipes
  for n, entry in ipairs(candidates) do
    entry.origin = 'new-melting-' .. n
    graph:add(entry.recipe, 'new-melting-' .. n)
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
        graph:add(recipe, entry.origin)
        casting[#casting + 1] = entry
      else
        skip(material, ingot, 'ingot', reason)
      end
    end
  end
  local changed = true
  while changed do
    changed = false
    local unsafe = {}
    for _, entry in ipairs(casting) do
      if not excluded[entry.origin] and not graph:hasProducer(entry.fluid, excluded) then
        unsafe[entry.origin] = true
      end
    end
    for origin in pairs(unsafe) do
      excluded[origin], changed = true, true
    end
    unsafe = {}
    for _, list in ipairs({ candidates, casting }) do
      for _, entry in ipairs(list) do
        if not excluded[entry.origin] then
          local forbidden = U.clone(excluded)
          forbidden[entry.origin] = true
          if not graph:independent(entry.recipe.inputs, entry.recipe.outputs, forbidden) then
            unsafe[entry.origin] = true
          end
        end
      end
    end
    for origin in pairs(unsafe) do
      excluded[origin], changed = true, true
    end
  end
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
        manifest.recipes[#manifest.recipes + 1] = entry.recipe
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
  graph:restore(originalCount)
  return manifest
end

return M
