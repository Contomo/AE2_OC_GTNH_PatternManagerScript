-- Destination-sized work. Only summaries survive between chunks; recipes,
-- snapshots and sorting plans are rebuilt and validated for the active group.
C.chunks = {}

function C.chunks.groups(c, id)
  local program = Programs.byId[id]
  if not program.mode or program.mode == 'meltingCore' or not program.outputs then
    return {}
  end
  local enabled, groups, names, visited = Config.enabledOutputs(c, id), {}, {}, {}
  local function add(form)
    if not enabled[form] or visited[form] then
      return
    end
    visited[form] = true
    local name = c.programs[id][program.outputs[form]]
    local group = names[name]
    if not group then
      group = { name = name, forms = {} }
      names[name], groups[#groups + 1] = group, group
    end
    group.forms[form] = true
  end
  for _, choice in ipairs(program.formChoices or {}) do
    for _, form in ipairs(U.keys(enabled)) do
      if Programs.switchKey(program, form) == choice[1] then
        add(form)
      end
    end
  end
  for _, form in ipairs(U.keys(enabled)) do
    add(form)
  end
  return groups
end

function C.chunks.enabled(c, id)
  return c.shared.chunked == 'on' and #C.chunks.groups(c, id) > 1
end

local function context(c, id, groups, progress, control, ignored, first)
  if id == 'fluidShaper' and Config.enabledOutputs(c, id).ingot then
    return C.liquids.session(c, groups, progress, control, ignored, first)
  end
  return { hw = connect(c, progress, control, true), errors = {} }
end

local function detail(c, preview, index, session, progress, control)
  if progress then
    progress(
      'Destination ' .. index .. ' / ' .. #preview.chunks .. ': ' .. preview.chunks[index].name
    )
  end
  local group = preview.chunks[index]
  local plan, report, manifest, routing, snapshot = C.maker.preview(
    c,
    preview.id,
    progress,
    control,
    { forms = group.forms, index = index, liquid = session.rejected and session or nil }
  )
  return { id = preview.id, plan = plan, report = report, manifest = manifest }, routing, snapshot
end

local function signature(session, item)
  local data = session.hw.data
  local contents = dataHash(data, U.canonical(item.manifest.recipes))
  return dataHash(
    data,
    U.canonical({ item.plan.baseline, contents, item.manifest.unresolved, item.plan.retirements })
  ),
    contents
end

local function summarize(item, stamp, contents)
  local p = item.plan
  return {
    stamp = stamp,
    contents = contents,
    changes = C.runner.hasChanges(item),
    reused = p.reused,
    resize = #p.resizes,
    create = #p.creates,
    move = #p.moves,
    kept = #p.preserved,
    existing = #(p.existing or {}),
    retire = #(p.retirements or {}),
    required = U.clone(p.required),
    available = U.clone(p.available),
    donorBanks = p.donorBanks,
    donorOccupied = p.donorOccupied,
    donorRejected = p.donorRejected,
    capacities = p.capacities,
    errors = p.errors,
    unresolved = item.manifest.unresolved,
  }
end

local function aggregate(preview, session)
  local p = {
    errors = U.clone(session.errors),
    warnings = {},
    capacities = {},
    counts = { resize = 0, create = 0, move = 0, kept = 0, existing = 0, retire = 0 },
    reused = 0,
    resizeCount = 0,
    required = { processing = 0, crafting = 0 },
    available = { processing = 0, crafting = 0 },
    donorBanks = 0,
    donorOccupied = 0,
    donorRejected = 0,
    donorReasons = {},
  }
  p.supplyCounts = session.counts
  local unresolved, seen = {}, {}
  for index = preview.first, #preview.chunks do
    local group = preview.chunks[index]
    local s = group.summary
    for key in pairs(p.counts) do
      p.counts[key] = p.counts[key] + s[key]
    end
    p.reused, p.resizeCount = p.reused + s.reused, p.resizeCount + s.resize
    p.donorBanks, p.donorOccupied, p.donorRejected =
      math.max(p.donorBanks, s.donorBanks),
      math.max(p.donorOccupied, s.donorOccupied),
      math.max(p.donorRejected, s.donorRejected)
    for kind in pairs(p.required) do
      p.required[kind] = p.required[kind] + s.required[kind]
      p.available[kind] = math.max(p.available[kind], s.available[kind])
    end
    for _, capacity in ipairs(s.capacities) do
      p.capacities[#p.capacities + 1] = capacity
    end
    for _, err in ipairs(s.errors) do
      p.errors[#p.errors + 1] = group.name .. ': ' .. err
    end
    for _, name in ipairs(s.unresolved) do
      if not seen[name] then
        seen[name], unresolved[#unresolved + 1] = true, name
      end
    end
  end
  for kind, amount in pairs(p.required) do
    if amount > p.available[kind] then
      p.warnings[#p.warnings + 1] = 'Need '
        .. amount
        .. ' disposable '
        .. kind
        .. ' donors; have '
        .. p.available[kind]
        .. '. Execution will wait for refills.'
    end
  end
  preview.plan, preview.manifest = p, { unresolved = unresolved }
  preview.report = (#preview.chunks - preview.first + 1)
    .. ' destination chunks checked. '
    .. 'Details are loaded one destination at a time.\n'
end

function C.chunks.preview(c, id, progress, control, first)
  startWork(c, progress, control)
  work.chunked = true
  local preview = {
    id = id,
    chunked = true,
    configKey = U.canonical(c),
    chunks = C.chunks.groups(c, id),
    first = first or 1,
  }
  U.check(preview.first >= 1 and preview.first <= #preview.chunks, 'Invalid saved destination')
  local session = context(c, id, preview.chunks, progress, control, nil, preview.first)
  preview.supplyKey = session.network
  for index = preview.first, #preview.chunks do
    local item = detail(c, preview, index, session, progress, control)
    local stamp, contents = signature(session, item)
    preview.chunks[index].summary = summarize(item, stamp, contents)
    item = nil
    releaseChunk()
  end
  aggregate(preview, session)
  local item = detail(c, preview, preview.first, session, progress, control)
  U.check(
    signature(session, item) == preview.chunks[preview.first].summary.stamp,
    'Patterns changed while building the preview. Scan again.'
  )
  preview.current, preview.chunkIndex = item, preview.first
  return preview
end

function C.chunks.select(c, preview, index, progress, control)
  U.check(preview.configKey == U.canonical(c), 'Settings changed; build a new preview')
  U.check(index >= preview.first and index <= #preview.chunks, 'Invalid destination index')
  startWork(c, progress, control)
  work.chunked = true
  preview.current = nil
  releaseChunk()
  local session = context(c, preview.id, preview.chunks, progress, control, nil, preview.first)
  U.check(
    session.network == preview.supplyKey,
    'Production patterns changed since preview. Scan again.'
  )
  local item = detail(c, preview, index, session, progress, control)
  U.check(
    signature(session, item) == preview.chunks[index].summary.stamp,
    'Patterns changed since preview. Scan again.'
  )
  preview.current, preview.chunkIndex = item, index
end

function C.chunks.execute(c, preview, progress, control)
  U.check(
    #preview.plan.errors == 0 and #preview.manifest.unresolved == 0,
    'Resolve preview blockers first'
  )
  startWork(c, progress, control)
  work.chunked = true
  preview.current = nil
  releaseChunk()
  local session = context(c, preview.id, preview.chunks, progress, control, nil, preview.first)
  U.check(
    session.network == preview.supplyKey,
    'Production patterns changed since preview. Scan again.'
  )
  -- Validate every remaining destination before the first pattern write.
  for index = preview.first, #preview.chunks do
    local item = detail(c, preview, index, session, progress, control)
    U.check(
      signature(session, item) == preview.chunks[index].summary.stamp,
      'Patterns changed since preview. Scan again.'
    )
    item = nil
    releaseChunk()
  end
  local retired = session.retirements and #session.retirements > 0
  if retired then
    local ignored = {}
    for _, entry in ipairs(session.retirements) do
      ignored[entry.origin] = true
    end
    local expected, eligibility = session.masked, session.eligibility
    C.liquids.retire(session.hw, session.retirements, session.workspace, progress)
    session = nil
    releaseChunk()
    session = context(c, preview.id, preview.chunks, progress, control, ignored, preview.first)
    U.check(
      session.masked == expected and session.eligibility == eligibility and #session.errors == 0,
      'Supply changed during retirement. Continue to review a fresh preview.'
    )
    for origin in pairs(ignored) do
      U.check(session.parked[origin], 'Retired pattern changed; scan again')
    end
  end
  for index = preview.first, #preview.chunks do
    gate()
    local group = preview.chunks[index]
    writeFile(paths.run, {
      version = 1,
      program = preview.id,
      configKey = preview.configKey,
      chunked = true,
      nextChunk = index,
      destination = group.name,
    })
    local item, routing, snapshot = detail(c, preview, index, session, progress, control)
    local stamp, contents = signature(session, item)
    U.check(
      (
        retired and contents == group.summary.contents
        or not retired and stamp == group.summary.stamp
      ) and #item.plan.errors == 0,
      'Destination changed before its chunk. Scan again.'
    )
    if C.runner.hasChanges(item) then
      C.maker.apply(c, preview.id, item.plan, item.manifest, progress, control, routing, snapshot)
    end
    writeFile(paths.run, {
      version = 1,
      program = preview.id,
      configKey = preview.configKey,
      chunked = true,
      nextChunk = index + 1,
    })
    item, routing, snapshot = nil, nil, nil
    releaseChunk()
    if progress then
      progress('Completed destination ' .. index .. ' / ' .. #preview.chunks .. ': ' .. group.name)
    end
  end
end

function C.chunks.export(c, preview, file, progress, control)
  startWork(c, progress, control)
  work.chunked = true
  preview.current = nil
  releaseChunk()
  local session = context(c, preview.id, preview.chunks, progress, control, nil, preview.first)
  U.check(
    session.network == preview.supplyKey,
    'Production patterns changed since preview. Scan again.'
  )
  for index = preview.first, #preview.chunks do
    local item = detail(c, preview, index, session, progress, control)
    U.check(
      signature(session, item) == preview.chunks[index].summary.stamp,
      'Patterns changed; scan again'
    )
    U.check(file:write(item.report .. '\n'), 'Cannot write preview report')
    item = nil
    releaseChunk()
  end
end
