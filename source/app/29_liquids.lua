-- Coordinated production migration. The dependency graph is read-only; writes
-- use the existing parking, sorting, imprinting and recovery operations.
C.liquids = {}
local indexedData, extractorMatch, coreKeys

local function liquidOrigin(ref, slot)
  return where(ref) .. ':' .. slot
end

local function supplyFingerprint(hw, banks)
  local parts = {}
  for _, bank in ipairs(banks) do
    gate()
    parts[#parts + 1] = dataHash(hw.data, U.canonical(bank))
  end
  return dataHash(hw.data, U.canonical(parts))
end

local function liquidInterfaces(hw)
  local result = invoke(hw.terminal, 'getInterfaces')
  U.check(result and result.getAll, 'Supply checks require metadata-only getAll(false)')
  local refs = {}
  iterate(invoke(result, 'getAll', false), function(ref)
    U.check(ref.patterns == nil, 'Driver ignored metadata-only discovery')
    refs[#refs + 1] = ref
  end)
  table.sort(refs, function(a, b)
    return U.ordered(endpoint(a), endpoint(b))
  end)
  return refs
end

local function liquidScan(c, data, hw, routing, options, progress, id)
  if indexedData ~= data then
    extractorMatch, coreKeys = Melting.extractorMatcher(data), Melting.coreKeys(data)
    indexedData = data
  end
  local graph, retirement, placeholders, owned, baseline, parkedOrigins =
    Supply.new(gate), {}, {}, {}, {}, {}
  local marker = C.donors.markerRecipe(hw)
  local markerKey = recipeKey(hw.data, marker)
  local coreBanks = {}
  for form, name in pairs(routing.destinations) do
    if id == 'meltingCore' and options.forms[form] then
      if form ~= 'ingot' then
        coreBanks[name] = true
      end
    end
  end
  local counts = { banks = 0, patterns = 0, unreadable = 0 }
  for _, ref in ipairs(liquidInterfaces(hw)) do
    gate()
    if where(ref) ~= where(hw.buffer) then
      local bank = current(hw, ref)
      U.check(bank.name == ref.name, 'Interface renamed during supply scan')
      local saved = { name = bank.name, ref = endpoint(bank), patterns = {} }
      counts.banks = counts.banks + 1
      for _, slot in ipairs(U.keys(bank.patterns)) do
        local p = bank.patterns[slot]
        if U.exists(p) then
          gate()
          local value, recipe = compactPattern(hw, p)
          counts.patterns = counts.patterns + 1
          local origin = liquidOrigin(bank, slot)
          saved.patterns[slot] = value.fingerprint
          if recipe then
            for _, which in ipairs({ 'inputs', 'outputs' }) do
              for _, s in pairs(recipe[which]) do
                local tag = tagKey(hw.data, s)
                s.tag = tag ~= '{}' and tag or nil
              end
            end
            -- Classification ignores flags; unsafe flags block retirement
            -- instead of hiding a looping recipe from the cross-comparison.
            local valid, key = pcall(Planner.recipeKey, {
              kind = recipe.kind,
              inputs = recipe.inputs,
              outputs = recipe.outputs,
            })
            local core = valid and coreKeys[key]
            local managed = core
              and (coreBanks[bank.name] or id == 'meltingCore' and core.migratable)
            if managed then
              owned[origin] = true
            end
            local fluid = extractorMatch(recipe)
            local reason = fluid and 'Retire solid-to-fluid extraction'
            if managed then
              fluid = core.fluid
              reason = coreBanks[bank.name] and 'Replace an obsolete or circular Melting Core route'
                or 'Migrate matching molten-production recipe'
            end
            local issue = value.reason
            if not value.donor or recipe.kind ~= 'processing' then
              issue = issue or 'Pattern is not an editable processing pattern.'
            end
            local entry = {
              from = endpoint(bank, slot),
              name = bank.name,
              origin = origin,
              fingerprint = value.fingerprint,
              label = U.ingredientSummary(recipe.outputs),
              reason = issue,
              fluid = fluid,
              action = reason,
              coreKey = managed and key or nil,
            }
            if fluid then
              retirement[#retirement + 1] = entry
            end
            local parked = value.recipeKey == markerKey
              and value.donor
              and recipe.kind == 'processing'
            if parked then
              parkedOrigins[origin] = true
              if bank.name ~= c.shared.donors then
                placeholders[#placeholders + 1] = entry
              end
            end
            if not parked and bank.name ~= c.shared.donors then
              if not value.produces then
                -- Invalid/input-only patterns cannot prove an active supply.
                -- A self edge keeps that output from becoming an assumed leaf.
                graph:add({ inputs = recipe.outputs, outputs = recipe.outputs }, origin, true)
              else
                graph:add(recipe, origin)
              end
            end
          else
            counts.unreadable = counts.unreadable + 1
            local outputs = effectivePattern(hw.data, p).outputs or {}
            if next(outputs) then
              graph:add({ inputs = outputs, outputs = outputs }, origin, true)
            end
          end
        end
      end
      if bank.name ~= c.shared.donors then
        baseline[#baseline + 1] = saved
      end
      if progress then
        progress(
          'Supply scan: ' .. counts.banks .. ' interfaces / ' .. counts.patterns .. ' patterns'
        )
      end
      U.check(
        computer.freeMemory() > 350000,
        'Low memory during supply comparison; stop other OC programs and retry'
      )
    end
  end
  return graph, retirement, placeholders, owned, baseline, counts, parkedOrigins
end

function C.liquids.preview(c, progress, control, id)
  id = id or 'meltingCore'
  Config.requireProgram(c, id)
  local hw = connect(c, progress, control)
  local data = require('assline_liquid_data')
  local routing, options = C.maker.routing(c, id)
  local base
  if id == 'meltingCore' then
    options.gas = c.programs.meltingCore.gas
    options.requestGas = c.programs.meltingCore.requestGas ~= 'off'
    options.priority = {}
    for _, group in ipairs({ 'high', 'medium' }) do
      options.priority[group .. 'Heat'] = tonumber(c.programs.meltingCore[group .. 'Heat'])
      options.priority[group .. 'Voltage'] = c.programs.meltingCore[group .. 'Voltage']
    end
    options.forms.ingot, options.emitCasting = true, false
  else
    options.ingotSupply = 'installed'
    base = Modes.compile(require('assline_data'), 'solidifier', options, gate)
  end
  local graph, candidates, placeholders, owned, baseline, counts, parkedOrigins =
    liquidScan(c, data, hw, routing, options, progress, id)
  local excluded = {}
  options.extractionOrigins = {}
  for _, entry in ipairs(candidates) do
    excluded[entry.origin] = true
    if not entry.coreKey then
      options.extractionOrigins[entry.origin] = true
    end
  end
  local manifest
  local checked, network = {}, nil
  options.craftableFluids = {}
  counts.fluidChecks = 0
  -- Restore extractors for liquids this run will not replace. Repeating only
  -- removes exclusions, so a chain cannot oscillate between migration plans.
  while true do
    manifest = base and Melting.filterCasts(base, graph, excluded)
      or Melting.compile(data, options, graph, excluded, owned, gate)
    local changed = false
    if id == 'meltingCore' then
      for _, recipe in ipairs(manifest.recipes) do
        local name = recipe.primaryFluid
        local fluid = { type = 'fluid', name = name }
        -- A visible owned/retiring pattern already explains ME's craftable
        -- flag. Do not mistake it for a second producer or suppress reuse.
        if checked[name] == nil and not graph:hasProducer(fluid, nil, true) then
          network = network or craftingNetwork(c, hw)
          local available = invoke(
            network,
            'getCraftable',
            { name = name, amount = 1, size = 1 },
            'fluid'
          ) ~= nil
          if not available then
            available = invoke(
              network,
              'getCraftable',
              fluidDrop(hw.data, { name = name, size = 1 }),
              'item'
            ) ~= nil
          end
          checked[name], counts.fluidChecks = available, counts.fluidChecks + 1
          if available then
            options.craftableFluids[name], changed = true, true
          end
        end
      end
    end
    local wanted = {}
    for _, recipe in ipairs(manifest.recipes) do
      wanted[Planner.recipeKey(recipe)] = routing.destinations[recipe.outputForm]
    end
    for _, entry in ipairs(candidates) do
      if
        excluded[entry.origin]
        and (
          not (
            manifest.suppliedFluids[entry.fluid]
            or entry.coreKey and (manifest.existingFluids or {})[entry.fluid]
            or entry.coreKey and (manifest.invalidFluids or {})[entry.fluid]
          ) or entry.coreKey and wanted[entry.coreKey] and not entry.reason
        )
      then
        excluded[entry.origin], changed = nil, true
      end
      if
        entry.coreKey
        and owned[entry.origin]
        and not excluded[entry.origin]
        and not wanted[entry.coreKey]
      then
        owned[entry.origin], changed = nil, true
      end
    end
    if not changed then
      break
    end
  end
  local destinations = {}
  if id == 'meltingCore' then
    local wanted = {}
    for _, recipe in ipairs(manifest.recipes) do
      wanted[Planner.recipeKey(recipe)] = true
    end
    -- Include old priority banks only when they contain a matching route that
    -- will move. Obsolete gas routes can still be reclaimed as ordinary donors.
    routing.reuseDestinations = {}
    for _, entry in ipairs(candidates) do
      if
        entry.coreKey
        and wanted[entry.coreKey]
        and not excluded[entry.origin]
        and not destinations[entry.name]
      then
        destinations[entry.name] = true
        routing.reuseDestinations[#routing.reuseDestinations + 1] = entry.name
      end
    end
    table.sort(routing.reuseDestinations)
  end
  for _, rows in ipairs({ manifest.recipes, manifest.skipped }) do
    for _, row in ipairs(rows) do
      destinations[routing.destinations[row.outputForm or row.form]] = true
    end
  end
  local retirements, errors = {}, {}
  routing.additionalDonors = {}
  for _, entry in ipairs(placeholders) do
    if not destinations[entry.name] then
      routing.additionalDonors[#routing.additionalDonors + 1] = entry
    end
  end
  for _, entry in ipairs(candidates) do
    if excluded[entry.origin] then
      retirements[#retirements + 1] = entry
      if entry.reason then
        errors[#errors + 1] = 'Cannot retire '
          .. entry.name
          .. ' / '
          .. U.locationText(entry.from)
          .. ' slot '
          .. entry.from.slot
          .. ': '
          .. entry.reason
      elseif entry.name ~= c.shared.donors and not destinations[entry.name] then
        routing.additionalDonors[#routing.additionalDonors + 1] = entry
      end
    end
  end
  local plan, snapshot = C.maker.scan(c, manifest, routing, progress, control, true)
  if #retirements > 0 then
    local workspace
    for slot = 0, editorCapacity(hw) - 1 do
      if not U.exists(direct(hw, 'getInterfacePattern', slot)) then
        workspace = slot
        break
      end
    end
    if not workspace then
      errors[#errors + 1] = 'The pattern editor needs one empty slot for retirement.'
    else
      plan.retirementWorkspace = endpoint(hw.buffer, workspace)
    end
  end
  plan.retirements, plan.supplyCounts = retirements, counts
  plan.networkBaseline = supplyFingerprint(hw, baseline)
  for _, err in ipairs(errors) do
    plan.errors[#plan.errors + 1] = err
  end
  local result, report = C.maker.finishPreview(plan, snapshot, manifest, routing)
  return result, report, manifest, routing, hw, { banks = baseline, parked = parkedOrigins }
end

local function unchangedSupply(hw, before, after, retirements)
  local ignored = {}
  for _, entry in ipairs(retirements) do
    U.check(after.parked[entry.origin], 'Retired pattern changed before installation. Scan again.')
    ignored[entry.origin] = true
  end
  local function withoutRetired(proof)
    for _, bank in ipairs(proof.banks) do
      for slot in pairs(bank.patterns) do
        if ignored[liquidOrigin(bank.ref, slot)] then
          bank.patterns[slot] = nil
        end
      end
    end
    return supplyFingerprint(hw, proof.banks)
  end
  return withoutRetired(before) == withoutRetired(after)
end

function C.liquids.apply(c, plan, manifest, progress, control, id)
  id = id or 'meltingCore'
  U.check(#plan.errors == 0, 'Resolve liquid migration blockers first')
  local fresh, _, proposed, freshRouting, hw, proof = C.liquids.preview(c, progress, control, id)
  U.check(
    #fresh.errors == 0
      and fresh.networkBaseline == plan.networkBaseline
      and U.eq(proposed.recipes, manifest.recipes),
    'Production patterns changed since preview. Scan again.'
  )
  writeFile(paths.backup, { config = U.clone(c), program = id, retired = #fresh.retirements })
  if #fresh.retirements == 0 then
    return C.maker.apply(c, id, fresh, proposed, progress, control, freshRouting)
  end
  local marker = C.donors.markerRecipe(hw)
  local workspace = U.check(fresh.retirementWorkspace, 'No retirement workspace').slot
  for n, entry in ipairs(fresh.retirements) do
    gate()
    local bank = current(hw, entry.from)
    local original = bank.patterns[entry.from.slot]
    U.check(
      bank.name == entry.name and patternFingerprint(hw, original) == entry.fingerprint,
      'Extraction pattern changed before retirement'
    )
    U.check(safeDonor(hw.data, original), 'Extraction pattern is no longer editable')
    U.check(
      not U.exists(direct(hw, 'getInterfacePattern', workspace)),
      'Retirement workspace occupied'
    )
    local op = {
      kind = 'park',
      slot = workspace,
      destination = entry.from,
      original = compact(original),
      recipe = marker,
    }
    saveOp(hw, op)
    finish(hw, op, progress)
    clearOp()
    if progress then
      progress('Retired extraction pattern ' .. n .. ' / ' .. #fresh.retirements)
    end
  end
  local ready, _, readyManifest, routing, _, readyProof =
    C.liquids.preview(c, progress, control, id)
  U.check(
    #ready.errors == 0
      and U.eq(readyManifest.recipes, proposed.recipes)
      and unchangedSupply(hw, proof, readyProof, fresh.retirements),
    'Supply changed during retirement. Continue to review a fresh preview.'
  )
  C.maker.apply(c, id, ready, readyManifest, progress, control, routing)
end
