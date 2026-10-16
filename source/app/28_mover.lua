-- Wildcard discovery loads metadata only. Only participating banks are read;
-- patterns are transferred intact through the shared durable move operation.
C.mover = {}

local function moverLabel(pattern)
  local labels = {}
  for _, slot in ipairs(U.keys(pattern.outputs)) do
    local output = pattern.outputs[slot]
    if U.exists(output) then
      labels[#labels + 1] = output.label or output.name
    end
  end
  return #labels > 0 and table.concat(labels, ', ') or pattern.label or pattern.name
end

function C.mover.scan(c, progress, control)
  local settings = c.programs.patternMover
  local match = Wildcard.compile(settings.source, settings.destination)
  local hw = connect(c, progress, control)
  local plan = {
    kind = 'patternMover',
    source = settings.source,
    destination = settings.destination,
    sourceBanks = 0,
    targetBanks = 0,
    free = 0,
    groups = {},
    moves = {},
    banks = {},
    errors = {},
    warnings = {},
    bindings = {
      terminal = hw.terminal.address,
      direct = hw.direct.address,
      data = hw.data.address,
      editor = hw.buffer,
    },
  }
  local names, routes, sourceLocations = {}, {}, {}
  local result = invoke(hw.terminal, 'getInterfaces')
  U.check(result and result.getAll, 'Wildcard discovery requires getAll(false)')
  iterate(invoke(result, 'getAll', false), function(ref)
    U.check(ref.patterns == nil, 'Driver ignored metadata-only discovery')
    names[ref.name] = names[ref.name] or {}
    names[ref.name][#names[ref.name] + 1] = ref
    local target = match(ref.name)
    if target then
      routes[ref.name] = target
      sourceLocations[where(ref)] = true
    end
  end)
  for _, refs in pairs(names) do
    table.sort(refs, function(a, b)
      return U.ordered(endpoint(a), endpoint(b))
    end)
  end

  local destinations = {}
  for _, source in ipairs(U.keys(routes)) do
    local destination = routes[source]
    if not destinations[destination] then
      destinations[destination] = { name = destination, sourceNames = {} }
    end
    local sources = destinations[destination].sourceNames
    sources[#sources + 1] = source
  end
  if not next(routes) then
    plan.errors[#plan.errors + 1] = 'No source interfaces match "' .. settings.source .. '".'
  end

  local function readBank(ref, role)
    U.check(
      ref.name ~= c.shared.editor and ref.name ~= c.shared.donors,
      'Mover interfaces must differ from the editor and donor buffer: ' .. ref.name
    )
    local bank = current(hw, ref)
    U.check(bank.name == ref.name, 'Interface renamed during scan')
    local saved = { ref = endpoint(bank), name = bank.name, role = role, patterns = {} }
    for _, slot in ipairs(U.keys(bank.patterns)) do
      if U.exists(bank.patterns[slot]) then
        -- Raw identity: no decoding, quantity normalization or flag restrictions.
        saved.patterns[slot] = patternFingerprint(hw, bank.patterns[slot])
      end
    end
    plan.banks[#plan.banks + 1] = saved
    if progress then
      progress('Read ' .. role .. ' interface ' .. bank.name .. ' at ' .. U.locationText(bank))
    end
    return bank, saved
  end

  local requirements = {}
  for _, name in ipairs(U.keys(destinations)) do
    local group = destinations[name]
    group.sourceBanks, group.targetBanks, group.occupied, group.patterns =
      0, #(names[name] or {}), 0, 0
    group.first = #plan.moves + 1
    local free = {}
    for _, ref in ipairs(names[name] or {}) do
      U.check(not sourceLocations[where(ref)], 'Source and target groups overlap: ' .. name)
      local bank, saved = readBank(ref, 'target')
      for _ in pairs(saved.patterns) do
        group.occupied = group.occupied + 1
      end
      for slot = 0, capacity(bank) - 1 do
        if not U.exists(bank.patterns[slot]) then
          free[#free + 1] = endpoint(bank, slot)
        end
      end
    end
    for _, source in ipairs(group.sourceNames) do
      for _, ref in ipairs(names[source]) do
        local bank, saved = readBank(ref, 'source')
        group.sourceBanks = group.sourceBanks + 1
        for _, slot in ipairs(U.keys(saved.patterns)) do
          gate()
          group.patterns = group.patterns + 1
          plan.moves[#plan.moves + 1] = {
            from = endpoint(bank, slot),
            to = free[group.patterns],
            sourceName = source,
            destinationName = name,
            fingerprint = saved.patterns[slot],
            label = moverLabel(bank.patterns[slot]),
          }
        end
      end
    end
    group.last = #plan.moves
    group.free = #free
    plan.sourceBanks = plan.sourceBanks + group.sourceBanks
    plan.targetBanks = plan.targetBanks + group.targetBanks
    plan.free = plan.free + group.free
    plan.groups[#plan.groups + 1] = group
    requirements[name] = group.occupied + group.patterns
    if group.targetBanks == 0 then
      plan.errors[#plan.errors + 1] = 'No target interfaces named "' .. name .. '".'
    elseif group.patterns > group.free then
      plan.errors[#plan.errors + 1] = 'Insufficient free slots in "'
        .. name
        .. '": need '
        .. group.patterns
        .. ', have '
        .. group.free
        .. '.'
    end
  end
  plan.capacities = Config.capacityReport(requirements)
  for index, group in ipairs(plan.groups) do
    local report = plan.capacities[index]
    report.availableInterfaces = group.targetBanks
    report.incoming, report.occupied, report.free = group.patterns, group.occupied, group.free
  end
  return plan, hw
end

function C.mover.preview(c, progress, control)
  local plan = C.mover.scan(c, progress, control)
  return plan, Preview.report(plan)
end

function C.mover.apply(c, plan, progress, control)
  U.check(#plan.errors == 0, 'Resolve mover blockers first')
  local fresh, hw = C.mover.scan(c, progress, control)
  U.check(U.eq(fresh, plan), 'Interfaces changed since preview. Scan again.')
  writeFile(paths.backup, { config = U.clone(c), program = 'patternMover', moved = #plan.moves })
  for n, move in ipairs(plan.moves) do
    gate()
    local op = {
      kind = 'move',
      source = move.from,
      destination = move.to,
      sourceName = move.sourceName,
      destinationName = move.destinationName,
      fingerprint = move.fingerprint,
    }
    saveOp(hw, op)
    C.maker.finishMove(hw, op)
    clearOp()
    if progress then
      progress('Moved pattern ' .. n .. ' / ' .. #plan.moves)
    end
  end
end
