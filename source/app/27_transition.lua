-- Existing patterns supply both the recipe and the physical pattern. Only the
-- scraped cleanup identities change; all editing uses the shared transaction.
C.transition = {}

local function transitionId(stack)
  return stack.name:lower() .. ((stack.damage or 0) ~= 0 and '@' .. stack.damage or '')
end

local function transitionRecipe(hw, pattern)
  local observed = effectivePattern(hw.data, pattern)
  local recipe = { kind = 'processing', inputs = {}, outputs = {} }
  local removed = { inputs = {}, outputs = {} }
  for _, which in ipairs({ 'inputs', 'outputs' }) do
    for _, index in ipairs(U.keys(observed[which])) do
      local stack = observed[which][index]
      if U.exists(stack) then
        local rules = which == 'inputs' and TransitionRules.explosives or TransitionRules.secondary
        local label = stack.type ~= 'fluid' and rules[transitionId(stack)]
        if label and (which == 'inputs' or #recipe.outputs > 0) then
          local discarded = U.clone(stack)
          discarded.label = label
          removed[which][#removed[which] + 1] = discarded
        else
          recipe[which][#recipe[which] + 1] = U.clone(stack)
        end
      end
    end
  end
  return recipe, removed
end

function C.transition.scan(c, progress, control)
  local settings = c.programs.implosionTransition
  U.check(settings.source ~= settings.destination, 'Old and new interface names must differ')
  for _, name in ipairs({ settings.source, settings.destination }) do
    U.check(
      name ~= c.shared.editor and name ~= c.shared.donors,
      'Transition interfaces must differ from the editor and donor buffer'
    )
  end
  local hw = connect(c, progress, control)
  local plan = {
    kind = 'transition',
    source = settings.source,
    destination = settings.destination,
    sourceBanks = 0,
    targetBanks = 0,
    occupied = 0,
    free = 0,
    scanned = 0,
    skipped = 0,
    entries = {},
    transfers = {},
    targets = {},
    errors = {},
    warnings = {},
    bindings = {
      terminal = hw.terminal.address,
      direct = hw.direct.address,
      data = hw.data.address,
    },
  }
  local free = {}
  for _, ref in ipairs(discover(hw, settings.destination)) do
    local bank = current(hw, ref)
    U.check(bank.name == settings.destination, 'Target interface renamed during scan')
    plan.targetBanks = plan.targetBanks + 1
    local target = { ref = endpoint(bank), patterns = {} }
    for _, slot in ipairs(U.keys(bank.patterns)) do
      local p = bank.patterns[slot]
      if U.exists(p) then
        target.patterns[slot] = U.canonical(compact(p))
        plan.occupied = plan.occupied + 1
      end
    end
    plan.targets[#plan.targets + 1] = target
    for slot = 0, capacity(bank) - 1 do
      if not U.exists(bank.patterns[slot]) then
        free[#free + 1] = endpoint(bank, slot)
      end
    end
  end
  plan.free = #free
  for _, ref in ipairs(discover(hw, settings.source)) do
    local bank = current(hw, ref)
    U.check(bank.name == settings.source, 'Source interface renamed during scan')
    plan.sourceBanks = plan.sourceBanks + 1
    for _, slot in ipairs(U.keys(bank.patterns)) do
      gate()
      local p = bank.patterns[slot]
      if U.exists(p) then
        plan.scanned = plan.scanned + 1
        local reason = donorIssue(hw.data, p)
        if not reason and not processing(p) then
          reason = 'Crafting pattern: cannot change its crafting flag.'
        end
        local entry = {
          from = endpoint(bank, slot),
          fingerprint = U.canonical(compact(p)),
          label = p.label or p.name,
          reason = reason,
        }
        if not reason then
          entry.recipe, entry.removed = transitionRecipe(hw, p)
          entry.label = U.ingredientSummary(entry.recipe.outputs)
          if #entry.recipe.inputs == 0 or #entry.recipe.outputs == 0 then
            entry.reason = 'Cleanup would leave an empty recipe; left in the old interface.'
          else
            entry.to = free[#plan.transfers + 1]
            plan.transfers[#plan.transfers + 1] = entry
          end
        end
        if entry.reason then
          plan.skipped = plan.skipped + 1
        end
        plan.entries[#plan.entries + 1] = entry
      end
    end
    if progress then
      progress('Read old interface at ' .. U.locationText(bank))
    end
  end
  if plan.sourceBanks == 0 then
    plan.errors[#plan.errors + 1] = 'No old interfaces named "' .. settings.source .. '".'
  end
  if plan.targetBanks == 0 then
    plan.errors[#plan.errors + 1] = 'No new interfaces named "' .. settings.destination .. '".'
  end
  if #plan.transfers > #free then
    plan.errors[#plan.errors + 1] = 'Insufficient free target slots: need '
      .. #plan.transfers
      .. ', have '
      .. #free
  end
  plan.capacities =
    Config.capacityReport({ [settings.destination] = plan.occupied + #plan.transfers })
  if #plan.transfers > 0 then
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
  return plan, hw
end

function C.transition.preview(c, progress, control)
  local plan = C.transition.scan(c, progress, control)
  return plan, Preview.report(plan)
end

function C.transition.apply(c, plan, progress, control)
  U.check(#plan.errors == 0, 'Resolve transition blockers first')
  local fresh, hw = C.transition.scan(c, progress, control)
  U.check(U.eq(fresh, plan), 'Interfaces or editor changed since preview. Scan again.')
  writeFile(
    paths.backup,
    { config = U.clone(c), program = 'implosionTransition', moved = #plan.transfers }
  )
  for n, entry in ipairs(plan.transfers) do
    gate()
    local bank = current(hw, entry.from)
    U.check(bank.name == plan.source, 'Source interface renamed before transfer')
    U.check(
      current(hw, entry.to).name == plan.destination,
      'Target interface renamed before transfer'
    )
    local original = bank.patterns[entry.from.slot]
    U.check(
      U.canonical(compact(original)) == entry.fingerprint,
      'Source pattern changed before transfer'
    )
    U.check(safeDonor(hw.data, original), 'Source pattern is no longer editable')
    U.check(
      not U.exists(direct(hw, 'getInterfacePattern', plan.workspace.slot)),
      'Pattern editor workspace occupied'
    )
    local op = {
      kind = 'transition',
      slot = plan.workspace.slot,
      source = entry.from,
      destination = entry.to,
      original = compact(original),
      recipe = entry.recipe,
    }
    saveOp(hw, op)
    finish(hw, op, progress)
    clearOp()
    if progress then
      progress('Transitioned pattern ' .. n .. ' / ' .. #plan.transfers)
    end
  end
end
