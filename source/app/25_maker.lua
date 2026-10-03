-- Shared named-interface adapter. Planning is read-only; execution uses the
-- same editor, durable operations and recovery as the assembly-line program.
-- Pattern reads are performed one interface at a time; metadata discovery never
-- converts an entire network's pattern inventories into Lua tables.
local function discover(hw, name)
  return lookup(hw, name, true)
end
local function recipeKey(data, recipe)
  local normalized = U.clone(recipe)
  for _, which in ipairs({ 'inputs', 'outputs' }) do
    for _, s in pairs(normalized[which]) do
      local key = tagKey(data, s)
      s.tag = key ~= '{}' and key or nil
    end
  end
  return Planner.recipeKey(normalized)
end
local function patternRecipe(data, p, root)
  U.check(type(p.tag) == 'string', 'Pattern NBT hidden; enable allowItemStackNBTTags')
  local crafting = U.truth(p.isCraftable)
  U.check(p.isCraftable ~= nil and p.inputs and p.outputs, 'Unsupported encoded pattern')
  local r = {
    kind = crafting and 'crafting' or 'processing',
    inputs = {},
    outputs = {},
    substitute = root.substitute and U.truth(root.substitute.__value) or false,
    beSubstitute = root.beSubstitute and U.truth(root.beSubstitute.__value) or false,
  }
  for _, which in ipairs({ 'inputs', 'outputs' }) do
    for index, s in pairs(p[which]) do
      if U.exists(s) then
        local ingredient = patternIngredient(data, s, U.patternEntry(root, which, index))
        if not ingredient then
          return nil, 'Encoded ' .. which .. ' slot ' .. index .. ' has no readable count'
        end
        r[which][index] = ingredient
      end
    end
  end
  return r
end
local function explainExisting(plan, snapshot, request, manifest)
  local function itemKey(item)
    return item and item.name and (item.name .. ':' .. tostring(item.damage or 0))
  end
  local function slotKey(entry)
    return where(entry) .. ':' .. entry.slot
  end
  local skipped, wantedOutputs, wantedKeys = {}, {}, {}
  for _, item in ipairs(manifest.skipped or {}) do
    skipped[itemKey(item)] = item
  end
  for index, recipe in ipairs(manifest.recipes) do
    local desired = request.recipes[index]
    wantedKeys[desired.destination .. ':' .. desired.key] = true
    for _, output in pairs(recipe.outputs) do
      wantedOutputs[itemKey(output)] = {
        label = recipe.label,
        destination = desired.destination,
        inputs = U.ingredientSummary(recipe.inputs),
      }
    end
  end
  local reused, kept = {}, {}
  for _, entry in ipairs(plan.layout) do
    if entry.source then
      reused[slotKey(entry.source)] = entry
    end
  end
  for _, entry in ipairs(plan.preserved) do
    kept[slotKey(entry.from)] = entry
  end
  local destinations = {}
  for _, interface in ipairs(snapshot.interfaces) do
    if interface.role == 'destination' then
      destinations[#destinations + 1] = interface
    end
  end
  table.sort(destinations, U.ordered)
  plan.existing, plan.moveLabels = {}, {}
  for _, interface in ipairs(destinations) do
    for _, slot in ipairs(U.keys(interface.patterns)) do
      local pattern = interface.patterns[slot]
      local from = U.endpoint(interface, slot)
      local key = slotKey(from)
      local reusedEntry, keptEntry = reused[key], kept[key]
      local outputKey = itemKey(pattern.output)
      local skippedItem = skipped[outputKey]
      local wantedOutput = wantedOutputs[outputKey]
      local label = skippedItem and skippedItem.label
        or wantedOutput and wantedOutput.label
        or pattern.output and pattern.output.label
        or outputKey
        or 'Unknown output'
      local reason
      if reusedEntry then
        reason = reusedEntry.resize and 'Recipe matches; batch will be resized.'
          or 'Recipe matches the selected route.'
      elseif skippedItem then
        reason = 'Skipped: '
          .. (skippedItem.reason or 'no path to a non-recycling product in the recipe export.')
      elseif wantedKeys[interface.name .. ':' .. tostring(pattern.recipeKey)] then
        reason = 'Duplicate of a selected recipe; kept after the planned patterns.'
      elseif wantedOutput and wantedOutput.destination ~= interface.name then
        reason = 'Selected output belongs in interface ' .. wantedOutput.destination .. '.'
      elseif wantedOutput then
        reason = pattern.reason and ('Output selected; ' .. pattern.reason .. '.')
          or 'Recipe differs: inputs, ratio, NBT or flags.'
      elseif pattern.matchIssue then
        reason = pattern.matchIssue
      else
        reason = 'Output not requested by this program or its current settings.'
      end
      local entry = {
        interface = interface.name,
        from = from,
        to = reusedEntry and reusedEntry.destination or keptEntry and keptEntry.to or from,
        status = reusedEntry and (reusedEntry.resize and 'RESIZE' or 'REUSE') or 'KEEP',
        label = label,
        output = pattern.output,
        inputs = pattern.inputSummary,
        requestedInputs = wantedOutput and wantedOutput.inputs or nil,
        reason = reason,
      }
      plan.existing[#plan.existing + 1] = entry
      plan.moveLabels[pattern.fingerprint] = label
    end
  end
end
local function scanManifest(c, manifest, routing, progress, control, started)
  validate(c)
  if not started then
    startWork(c, progress, control)
  end
  local groups, names = {}, {}
  local function group(name, role)
    U.check(
      type(name) == 'string' and name ~= '',
      'Set the ' .. role .. ' interface name in Settings'
    )
    U.check(not names[name] or names[name] == role, 'Interface roles overlap: ' .. name)
    if not names[name] then
      groups[#groups + 1] = { name = name, role = role }
      names[name] = role
    end
  end
  local function destination(recipe)
    return routing.destinations and routing.destinations[recipe.outputForm or recipe.form]
      or routing.destination
  end
  U.check(
    manifest.version == 1 and type(manifest.recipes) == 'table',
    'Unsupported manifest schema'
  )
  Planner.sequence(manifest.recipes, 'Recipes')
  U.check(
    type(manifest.source) == 'table'
      and type(manifest.source.recipeVersion) == 'string'
      and type(manifest.source.targetVersion) == 'string',
    'Manifest must identify recipe and target versions'
  )
  for _, recipe in ipairs(manifest.recipes) do
    group(destination(recipe), 'destination')
  end
  for _, item in ipairs(manifest.skipped or {}) do
    group(destination(item), 'destination')
  end
  group(routing.donors, 'donor')
  group(routing.workspace, 'workspace')
  local hw = {
    terminal = selectDevice('me_interface_terminal', c.shared.terminalAddress),
    data = selectDevice('data', c.shared.dataAddress),
  }
  local snapshot = { terminal = hw.terminal.address, interfaces = {} }
  for _, g in ipairs(groups) do
    local found = discover(hw, g.name)
    for _, entry in ipairs(found) do
      local i = current(hw, endpoint(entry))
      U.check(i.name == g.name, 'Interface renamed while scanning; scan again')
      local slots = capacity(i)
      -- Donor capacity is irrelevant: include every occupied pattern, even when
      -- the buffer is a larger inventory than a standard destination interface.
      if g.role == 'donor' then
        slots = math.max(1, U.largest(i.patterns) + 1)
      end
      local compacted = {
        name = i.name,
        location = U.clone(i.location),
        side = side(i.side),
        role = g.role,
        capacity = slots,
        patterns = {},
      }
      for slot, p in pairs(i.patterns or {}) do
        if U.exists(p) then
          U.check(type(p.tag) == 'string', 'Pattern NBT hidden in ' .. g.name)
          local reason, root = donorIssue(hw.data, p)
          local value =
            { kind = 'unknown', fingerprint = patternFingerprint(hw, p), reason = reason }
          local output = p.outputs and p.outputs[1]
          if U.exists(output) then
            value.output = {
              name = output.name,
              damage = output.damage,
              size = U.patternCount(output, U.patternEntry(root, 'outputs', 1)),
              label = output.label,
            }
          end
          local inputLabels = {}
          for _, index in ipairs(U.keys(p.inputs)) do
            local input = p.inputs[index]
            if U.exists(input) then
              inputLabels[#inputLabels + 1] = tostring(
                U.patternCount(input, U.patternEntry(root, 'inputs', index)) or '?'
              ) .. ' x ' .. tostring(input.label or input.name)
            end
          end
          value.inputSummary = table.concat(inputLabels, ', ')
          if root then
            local r, issue = patternRecipe(hw.data, p, root)
            if r then
              value.kind = r.kind
              value.inputSummary = U.ingredientSummary(r.inputs)
              if r.outputs[1] then
                value.output = U.clone(r.outputs[1])
              end
              local valid, key, scale = pcall(recipeKey, hw.data, r)
              if valid then
                value.recipeKey = key
                value.scale = scale
              else
                value.matchIssue = 'Encoded ingredients could not be compared'
              end
              value.donor = value.reason == nil
            else
              value.matchIssue = issue
              value.reason = value.reason or issue
            end
          end
          compacted.patterns[slot] = value
        end
      end
      snapshot.interfaces[#snapshot.interfaces + 1] = compacted
      if progress then
        progress('Read ' .. i.name .. ' at ' .. U.locationText(i))
      end
      U.check(
        computer.freeMemory() > 160000,
        'Low memory while collecting compact interface snapshot'
      )
    end
  end
  local request = {
    recipes = {},
    source = U.clone(manifest.source),
    policy = U.clone(manifest.policy or {}),
    unresolved = U.clone(manifest.unresolved),
  }
  local labels = {}
  for _, r in ipairs(manifest.recipes) do
    local key, scale = recipeKey(hw.data, r)
    r.key = key
    request.recipes[#request.recipes + 1] = {
      key = key,
      scale = scale,
      kind = r.kind,
      destination = destination(r),
      stock = U.clone(r.stock),
      stockAlternatives = U.clone(r.stockAlternatives),
    }
    labels[key] = r.label or r.id or r.outputs[1].name
  end
  local plan = Planner.plan(request, snapshot, function()
    gate()
    U.check(computer.freeMemory() > 160000, 'Low memory while planning')
  end)
  explainExisting(plan, snapshot, request, manifest)
  return plan, snapshot, request, labels
end
C.maker = {
  planner = Planner,
  scan = scanManifest,
  report = Preview.report,
  rows = Preview.planRows,
  discover = discover,
}
local function programRouting(c, id)
  local program = Config.requireProgram(c, id)
  local values = c.programs[id]
  local routing =
    { donors = c.shared.donors, workspace = c.shared.editor, destination = values.destination }
  local forms
  if program.outputs then
    forms = {}
    routing.destinations = {}
    for form, key in pairs(program.outputs) do
      forms[form] = true
      routing.destinations[form] = values[key]
    end
    if program.formSwitch then
      local selected = Config.selected(values[program.formSwitch], program.formChoices)
      for form in pairs(forms) do
        forms[form] = selected[Programs.switchKey(program, form)] == true
      end
    end
  end
  local sources
  if program.sources then
    sources = {}
    for form, source in pairs(program.sources.fixed or {}) do
      sources[form] = source
    end
    for form, key in pairs(program.sources.fields or {}) do
      sources[form] = values[key]
    end
  end
  local formDivisors = {}
  for _, field in ipairs(program.fields) do
    if field.costDivisor then
      formDivisors[field.costDivisor] = tonumber(values[field.key])
    end
  end
  return routing,
    {
      polymer = values.polymer,
      multiplier = tonumber(values.multiplier),
      batch = c.batch,
      pps = values.pps ~= 'off',
      forms = forms,
      sources = sources,
      formDivisors = formDivisors,
    },
    program
end
function C.maker.preview(c, id, progress, control)
  validate(c)
  startWork(c, progress, control)
  local routing, options, program = programRouting(c, id)
  local manifest = Modes.compile(require('assline_data'), program.mode, options, gate)
  local plan, snapshot, _, labels = scanManifest(c, manifest, routing, progress, control, true)
  local groups = {}
  for _, recipe in ipairs(manifest.recipes) do
    local name = routing.destinations and routing.destinations[recipe.outputForm or recipe.form]
      or routing.destination
    groups[name] = (groups[name] or 0) + 1
  end
  local banks = {}
  for _, i in ipairs(snapshot.interfaces) do
    banks[where(i)] = i.name
  end
  for _, entry in ipairs(plan.preserved) do
    local name = banks[where(entry.from)]
    groups[name] = (groups[name] or 0) + 1
  end
  plan.capacities = Config.capacityReport(groups)
  local report = Preview.report(plan, manifest)
  return plan, report, manifest
end

function C.maker.finishMove(hw, op)
  local source = current(hw, op.source).patterns[op.source.slot]
  local destination = current(hw, op.destination).patterns[op.destination.slot]
  local function matches(p)
    return op.fingerprint and patternFingerprint(hw, p) == op.fingerprint
      or op.original and patternEq(hw.data, p, op.original)
  end
  if not U.exists(source) and matches(destination) then
    return
  end
  U.check(matches(source), 'Sorting source changed; recovery stopped')
  U.check(not U.exists(destination), 'Sorting destination is occupied')
  transfer(hw, op.source, op.destination)
  verifyDelivery(hw, op.source, op.destination, matches, 'Sorted pattern read-back failed')
end

function C.maker.finishSort(hw, op, progress)
  local cursor = U.check(readFile(paths.cursor), 'Missing sorting recovery progress')
  U.check(
    cursor.id == op.id
      and U.integer(cursor.index)
      and cursor.index >= 1
      and cursor.index <= #op.moves + 1,
    'Invalid sorting recovery progress'
  )
  local parked = false
  local function track(move)
    if where(move.to) == where(hw.buffer) then
      parked = true
    end
    if where(move.from) == where(hw.buffer) then
      parked = false
    end
  end
  -- An interrupted cycle may already have a pattern in its workspace.
  for n = 1, cursor.index - 1 do
    track(op.moves[n])
  end
  for n = cursor.index, #op.moves do
    local move = op.moves[n]
    C.maker.finishMove(
      hw,
      { source = move.from, destination = move.to, fingerprint = move.fingerprint }
    )
    writeFile(paths.cursor, { id = op.id, index = n + 1 })
    track(move)
    -- Stop only when the cycle has returned its parked pattern. The cursor
    -- retains the remaining moves without holding an editor slot hostage.
    if not parked then
      work.atomic = false
      gate()
      work.atomic = true
    end
    if progress then
      progress('Sorted pattern ' .. n .. ' / ' .. #op.moves)
    end
  end
end

function C.maker.apply(c, id, plan, manifest, progress, control)
  U.check(
    not fs.exists(paths.pending),
    'Continue or stop the saved operation before executing another preview'
  )
  U.check(#plan.errors == 0, 'Resolve preview blockers first')
  U.check(
    not manifest.unresolved or #manifest.unresolved == 0,
    'Resolve unverified registry spellings before execution'
  )
  local routing = programRouting(c, id)
  local baseline = U.clone(plan)
  baseline.capacities = nil
  local _, snapshot, request = scanManifest(c, manifest, routing, progress, control)
  Planner.revalidate(request, snapshot, baseline, gate)
  local hw = connect(c, progress, control)
  local editor = current(hw, hw.buffer)
  local firstEdit = plan.resizes[1] or plan.creates[1]
  local slot = firstEdit and firstEdit.workspace.slot
  if slot then
    U.check(
      where(firstEdit.workspace) == where(hw.buffer),
      'Planned workspace is not the shared pattern editor'
    )
    U.check(slot < editorCapacity(hw), 'Editor workspace slot is unavailable')
    U.check(
      patternEq(hw.data, editor.patterns[slot], direct(hw, 'getInterfacePattern', slot)),
      'Direct pattern editor does not match the terminal'
    )
    U.check(not U.exists(editor.patterns[slot]), 'Pattern editor workspace occupied')
  end
  writeFile(paths.backup, {
    config = U.clone(c),
    program = id,
    created = #plan.creates,
    resized = #plan.resizes,
    sorted = #plan.moves,
  })
  if #plan.moves > 0 then
    -- Keep the whole sorting stage durable. A cycle can temporarily park a
    -- pattern in the editor; continuation finishes that cycle before replanning.
    local op =
      { kind = 'sort', moves = plan.moves, id = invoke(hw.data, 'sha256', U.canonical(plan.moves)) }
    writeFile(paths.cursor, { id = op.id, index = 1 })
    saveOp(hw, op)
    C.maker.finishSort(hw, op, progress)
    clearOp()
  end
  local recipes = {}
  for _, recipe in ipairs(manifest.recipes) do
    recipes[recipe.key or Planner.recipeKey(recipe)] = recipe
  end
  local protected = {}
  for _, i in ipairs(snapshot.interfaces) do
    if i.role ~= 'donor' then
      protected[where(i)] = true
    end
  end
  local takeDonor = donorPool(hw, c.shared.donors, protected, progress)
  local function imprint(entry, resize)
    local recipe = recipes[entry.key]
    U.check(recipe and recipe.kind == 'processing', 'Unsupported pattern kind')
    for _, which in ipairs({ 'inputs', 'outputs' }) do
      for _, s in ipairs(recipe[which]) do
        U.check(s.type == 'item' or s.type == 'fluid', 'Unsupported ingredient type')
      end
    end
    local source, original
    if resize then
      original = current(hw, entry.to).patterns[entry.to.slot]
      U.check(
        patternFingerprint(hw, original) == entry.fingerprint,
        'Existing pattern changed before resizing'
      )
      U.check(
        safeDonor(hw.data, original),
        'Existing pattern cannot be resized with its current metadata'
      )
      original = compact(original)
    else
      source, original = takeDonor()
    end
    U.check(
      not U.exists(direct(hw, 'getInterfacePattern', entry.workspace.slot)),
      'Pattern editor workspace occupied'
    )
    local op = {
      kind = resize and 'resize' or 'imprint',
      source = source,
      slot = entry.workspace.slot,
      destination = entry.to,
      original = original,
      recipe = recipe,
    }
    saveOp(hw, op)
    finish(hw, op, progress)
    clearOp()
    if progress then
      progress((resize and 'Resized ' or 'Installed ') .. recipe.label)
    end
  end
  for _, entry in ipairs(plan.resizes) do
    imprint(entry, true)
  end
  for _, entry in ipairs(plan.creates) do
    imprint(entry, false)
  end
end

C.runner = {}
function C.runner.hasChanges(preview)
  local plan = preview.plan
  if plan.kind == 'donorCleanup' then
    return #plan.cleanups > 0
  end
  return preview.id == 'assline' and #plan.changes > 0
    or preview.id ~= 'assline' and (#plan.moves + #plan.creates + #plan.resizes) > 0
end
function C.runner.requiresVerification(preview)
  return Programs.byId[preview.id].requiresCapacityVerification ~= false
end
function C.runner.preview(c, id, progress, control)
  Config.requireProgram(c, id)
  local preview = { id = id, configKey = U.canonical(c) }
  if id == 'assline' then
    preview.plan = scan(c, progress, control)
  elseif id == 'donorCleanup' then
    preview.plan, preview.report = C.donors.preview(c, progress, control)
  else
    preview.plan, preview.report, preview.manifest = C.maker.preview(c, id, progress, control)
  end
  return preview
end
function C.runner.execute(c, preview, progress, control)
  U.check(preview and preview.configKey == U.canonical(c), 'Settings changed; build a new preview')
  Config.requireProgram(c, preview.id)
  U.check(not fs.exists(paths.pending), 'Continue or stop the saved operation before executing')
  writeFile(paths.run, { version = 1, program = preview.id, configKey = U.canonical(c) })
  if preview.id == 'assline' then
    apply(c, preview.plan, progress, control)
  elseif preview.id == 'donorCleanup' then
    C.donors.apply(c, preview.plan, progress, control)
  else
    C.maker.apply(c, preview.id, preview.plan, preview.manifest, progress, control)
  end
  U.check(fs.remove(paths.run), 'Cannot clear completed program run')
end

function C.runner.hasSaved()
  return fs.exists(paths.run) or fs.exists(paths.pending)
end

function C.runner.continue(c, progress, control)
  local saved, op = readFile(paths.run), readFile(paths.pending)
  U.check(saved or op, 'No saved operation')
  local backup = readFile(paths.backup)
  local id = saved and saved.program
    or op and (op.kind == 'edit' or op.kind == 'recipe') and 'assline'
    or backup and backup.program
  if id and not saved then
    writeFile(paths.run, { version = 1, program = id, configKey = U.canonical(c) })
  end
  if op then
    recover(c, progress, control)
  end
  -- A fresh plan recognizes the finished patterns and checks today's interface
  -- contents/settings. Never replay an old full plan after a stop or restart.
  if id then
    local preview = C.runner.preview(c, id, progress, control)
    preview.continuedWithChangedSettings = saved and saved.configKey ~= U.canonical(c) or false
    if
      not C.runner.hasChanges(preview)
      and #preview.plan.errors == 0
      and (not preview.manifest or #preview.manifest.unresolved == 0)
    then
      U.check(fs.remove(paths.run), 'Cannot clear completed program run')
    end
    return preview
  end
end

function C.runner.discard()
  U.check(C.runner.hasSaved(), 'No saved operation')
  -- One bounded archive may contain both 400 KB records plus the small cursor.
  writeFile(paths.abandoned, {
    operation = readFile(paths.pending),
    step = readFile(paths.cursor),
    run = readFile(paths.run),
  }, 900000)
  for _, path in ipairs({ paths.pending, paths.cursor, paths.run }) do
    if fs.exists(path) then
      U.check(fs.remove(path), 'Cannot discard ' .. path)
    end
  end
end
