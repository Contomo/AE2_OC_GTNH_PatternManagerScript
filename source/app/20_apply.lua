-- One durable intent per moved pattern. Recovery completes only that operation;
-- another scan is required before continuing the rest of a batch.
local function rawList(data, p, which)
  local root = nbt(data, p.tag).__value
  local t = root[which == 'inputs' and 'in' or 'out']
  U.check(t and t.__nbt_type == 'list', 'Unsupported encoded pattern layout')
  return t.__value
end
local function expected(data, op)
  local p = compact(effectivePattern(data, op.original))
  if op.kind == 'recipe' or op.kind == 'imprint' or op.kind == 'resize' then
    p.inputs = op.recipe and U.clone(op.recipe.inputs) or { [1] = op.input }
    p.outputs = op.recipe and U.clone(op.recipe.outputs) or { [1] = op.output }
  else
    for _, e in ipairs(op.edits) do
      p.inputs[e.index] = e.after
    end
  end
  return p
end
local function semantic(hw, p, q)
  if not U.exists(p) or not U.exists(q) or p.name ~= q.name or p.damage ~= q.damage then
    return false
  end
  if not U.eq(metadata(hw.data, p), metadata(hw.data, q)) then
    return false
  end
  p = effectivePattern(hw.data, p)
  for _, which in ipairs({ 'inputs', 'outputs' }) do
    local all = {}
    for k in pairs(p[which] or {}) do
      all[k] = true
    end
    for k in pairs(q[which] or {}) do
      all[k] = true
    end
    for k in pairs(all) do
      if not stackEq(hw.data, p[which][k], q[which][k]) then
        return false
      end
    end
  end
  return true
end
local function allowedPartial(hw, p, op)
  U.check(
    U.exists(p) and p.name == op.original.name and p.damage == op.original.damage,
    'Unexpected pattern in buffer'
  )
  U.check(
    U.eq(metadata(hw.data, p), metadata(hw.data, op.original)),
    'Pattern flags or other NBT changed; recovery stopped'
  )
  local final = expected(hw.data, op)
  p = effectivePattern(hw.data, p)
  local original = effectivePattern(hw.data, op.original)
  for _, which in ipairs({ 'inputs', 'outputs' }) do
    local all = {}
    for k in pairs(p[which] or {}) do
      all[k] = true
    end
    for k in pairs(original[which]) do
      all[k] = true
    end
    for k in pairs(final[which]) do
      all[k] = true
    end
    for k in pairs(all) do
      local a = p[which][k]
      local old = original[which][k]
      local new = final[which][k]
      U.check(
        stackEq(hw.data, a, old) or stackEq(hw.data, a, new),
        'Unexpected ' .. which .. ' slot ' .. k .. '; recovery stopped'
      )
    end
  end
end
local function transfer(hw, from, to)
  local ok, slot = invoke(hw.terminal, 'send', from, to)
  U.check(ok == true, 'Pattern transfer failed: ' .. tostring(slot))
  U.check(slot == to.slot, 'Pattern moved to unexpected slot ' .. tostring(slot))
end
local function setEntry(hw, slot, which, index, s)
  local method = which == 'inputs' and 'setInterfacePatternInput' or 'setInterfacePatternOutput'
  if s then
    U.check(
      direct(
        hw,
        method,
        slot,
        index,
        { name = s.name, damage = s.damage, size = s.size, tag = s.tag },
        'item'
      ) == true,
      'Pattern setter returned failure'
    )
  else
    U.check(direct(hw, method, slot, index) == true, 'Pattern clear returned failure')
  end
end
local function finish(hw, op, progress)
  U.check(
    op.version == 1
      and op.direct == hw.direct.address
      and op.terminal == hw.terminal.address
      and op.data == hw.data.address
      and where(op.buffer) == where(hw.buffer),
    'Recovery hardware differs from saved operation'
  )
  local goal = expected(hw.data, op)
  local dest = current(hw, op.destination)
  local remote = current(hw, op.buffer)
  local p = remote.patterns[op.slot]
  U.check(
    patternEq(hw.data, p, direct(hw, 'getInterfacePattern', op.slot)),
    'Direct/terminal buffer mismatch'
  )
  local delivered = dest.patterns[op.destination.slot]
  if not U.exists(p) and U.exists(delivered) and semantic(hw, delivered, goal) then
    return -- A transfer succeeded immediately before the power loss.
  end
  if (op.kind == 'edit' or op.kind == 'resize') and not U.exists(p) then
    U.check(patternEq(hw.data, delivered, op.original), 'Original target pattern changed')
    transfer(hw, op.destination, endpoint(op.buffer, op.slot))
    p = direct(hw, 'getInterfacePattern', op.slot)
    U.check(patternEq(hw.data, p, op.original), 'Moved pattern failed read-back')
  else
    U.check(not U.exists(delivered), 'Destination slot is occupied')
  end
  if op.source and not U.exists(p) then
    local source = current(hw, op.source).patterns[op.source.slot]
    U.check(patternEq(hw.data, source, op.original), 'Donor pattern changed')
    transfer(hw, op.source, endpoint(op.buffer, op.slot))
    p = direct(hw, 'getInterfacePattern', op.slot)
    U.check(patternEq(hw.data, p, op.original), 'Moved donor failed read-back')
  end
  allowedPartial(hw, p, op)
  local observed = effectivePattern(hw.data, p)
  if op.kind == 'recipe' or op.kind == 'imprint' or op.kind == 'resize' then
    -- Clearing removes an NBT list element: ALWAYS clear from the end.
    for _, which in ipairs({ 'inputs', 'outputs' }) do
      local desired = goal[which]
      local entries = rawList(hw.data, p, which)
      for index, s in ipairs(desired) do
        if not stackEq(hw.data, observed[which][index], s) then
          setEntry(hw, op.slot, which, index, s)
        end
      end
      for index = U.largest(entries), #desired + 1, -1 do
        local entry = entries[index]
        U.check(
          entry and entry.__nbt_type == 'compound' and type(entry.__value) == 'table',
          'Invalid pattern list entry'
        )
        -- AE ignores empty compounds. Do not spend a server tick removing every
        -- unused cell in a padded processing donor. Clear nonempty cells only.
        if next(entry.__value) ~= nil then
          setEntry(hw, op.slot, which, index)
        end
      end
    end
  else
    for _, e in ipairs(op.edits) do
      if not stackEq(hw.data, observed.inputs[e.index], e.after) then
        setEntry(hw, op.slot, 'inputs', e.index, e.after)
      end
    end
  end
  p = direct(hw, 'getInterfacePattern', op.slot)
  U.check(semantic(hw, p, goal), 'Edited pattern read-back failed; saved recovery record retained')
  U.check(
    patternEq(hw.data, current(hw, op.buffer).patterns[op.slot], p),
    'Edited direct buffer differs from named terminal buffer'
  )
  local liveDest = current(hw, op.destination)
  U.check(not U.exists(liveDest.patterns[op.destination.slot]), 'Destination filled during edit')
  transfer(hw, endpoint(op.buffer, op.slot), op.destination)
  local after = current(hw, op.destination).patterns[op.destination.slot]
  U.check(semantic(hw, after, goal), 'Destination read-back failed')
  U.check(not U.exists(direct(hw, 'getInterfacePattern', op.slot)), 'Buffer slot did not empty')
  if progress then
    progress('Verified pattern in destination slot ' .. (op.destination.slot + 1))
  end
end
local function saveOp(hw, op)
  U.check(not fs.exists(paths.pending), 'An unfinished operation needs Recover first')
  op.version = 1
  op.direct = hw.direct.address
  op.terminal = hw.terminal.address
  op.data = hw.data.address
  op.buffer = U.clone(hw.buffer)
  writeFile(paths.pending, op)
end
local function clearOp()
  U.check(fs.remove(paths.pending), 'Cannot clear completed recovery record')
  if fs.exists(paths.cursor) then
    U.check(fs.remove(paths.cursor), 'Cannot clear completed recovery progress')
  end
end

-- Donor supply is live, unlike the destination plan. Keep only slot references
-- between operations, and check each physical pattern immediately before use.
-- Both programs use this pool; waiting never creates a recovery intent.
local function donorPool(hw, name, protected, progress)
  local banks, bankIndex, slots, slotIndex = nil, 1, {}, 1
  local function refreshBanks()
    banks = lookup(hw, name, true)
    bankIndex = 1
  end

  return function()
    while true do
      gate()
      local source = slots[slotIndex]
      if source then
        slotIndex = slotIndex + 1
        local bank = current(hw, source)
        U.check(
          not protected[where(bank)] and where(bank) ~= where(hw.buffer),
          'Donor interface overlaps a destination or the editor'
        )
        local pattern = bank.patterns[source.slot]
        if bank.name == name and safeDonor(hw.data, pattern) then
          return source, compact(pattern)
        end
      else
        if not banks then
          refreshBanks()
        end
        local entry = banks[bankIndex]
        if entry then
          bankIndex = bankIndex + 1
          U.check(
            not protected[where(entry)] and where(entry) ~= where(hw.buffer),
            'Donor interface overlaps a destination or the editor'
          )
          local bank = current(hw, entry)
          slots = {}
          slotIndex = 1
          if bank.name == name then
            for _, slot in ipairs(U.keys(bank.patterns)) do
              if safeDonor(hw.data, bank.patterns[slot]) then
                slots[#slots + 1] = endpoint(bank, slot)
              end
            end
          end
        else
          if progress then
            progress(
              'Waiting for processing donors in "'
                .. name
                .. '". Refill buffers to continue; Cancel / Esc to stop.',
              true
            )
          end
          rest(1)
          refreshBanks()
        end
      end
    end
  end
end

local function apply(c, plan, progress, control)
  U.check(not fs.exists(paths.pending), 'Use Recover before applying another scan')
  U.check(#plan.errors == 0, 'Resolve scan blockers first')
  local fresh, hw = scan(c, progress, control)
  local function fixed(p)
    local value = U.clone(p)
    value.available = nil
    value.warnings = nil
    return value
  end
  U.check(
    U.eq(fixed(fresh), fixed(plan)),
    'Patterns or destinations changed since preview. Scan again.'
  )
  fresh = nil
  writeFile(paths.backup, { config = U.clone(c), plan = plan })
  local workspace = plan.empty[1]
  local protected = U.clone(plan.protected)
  protected[where(plan.target)] = true
  local takeDonor = donorPool(hw, c.shared.donors, protected, progress)
  for _, r in ipairs(plan.recipes) do
    if not r.existing then
      U.check(workspace ~= nil, 'No free pattern editor slot')
      local source, original = takeDonor()
      local op = {
        kind = 'recipe',
        slot = workspace,
        source = source,
        original = original,
        destination = r.destination,
        input = r.input,
        output = r.output,
      }
      U.check(
        not U.exists(direct(hw, 'getInterfacePattern', workspace)),
        'Pattern editor workspace occupied'
      )
      saveOp(hw, op)
      finish(hw, op, progress)
      clearOp()
    end
  end
  for _, v in ipairs(plan.changes) do
    -- One fresh snapshot per interface, used only for this target operation.
    -- Check only the recipes used by this target, not the batch's full manifest.
    local required = {}
    for _, e in ipairs(v.edits) do
      required[identity(hw.data, e.after)] = true
    end
    local snapshots = {}
    for _, r in ipairs(plan.recipes) do
      if required[identity(hw.data, r.output)] then
        local e = r.existing or r.destination
        local key = where(e)
        if not snapshots[key] then
          snapshots[key] = current(hw, e)
        end
        U.check(
          pureRecipe(hw.data, snapshots[key].patterns[e.slot], r),
          'Rename recipe removed or changed; scan again'
        )
      end
    end
    U.check(workspace ~= nil, 'No free buffer slot')
    local op = {
      kind = 'edit',
      slot = workspace,
      original = v.original,
      edits = v.edits,
      destination = endpoint(plan.target, v.slot),
    }
    U.check(not U.exists(direct(hw, 'getInterfacePattern', workspace)), 'Buffer workspace occupied')
    saveOp(hw, op)
    finish(hw, op, progress)
    clearOp()
  end
end
local function recover(c, progress, control)
  local op = U.check(readFile(paths.pending), 'No pending operation')
  local hw = connect(c, progress, control)
  if op.kind == 'move' or op.kind == 'sort' then
    U.check(
      op.direct == hw.direct.address
        and op.terminal == hw.terminal.address
        and op.data == hw.data.address
        and where(op.buffer) == where(hw.buffer),
      'Recovery hardware differs from saved operation'
    )
    if op.kind == 'sort' then
      C.maker.finishSort(hw, op, progress)
    else
      C.maker.finishMove(hw, op)
    end
  else
    finish(hw, op, progress)
  end
  clearOp()
end
C.apply = apply
C.recover = recover
C.paths = paths
C.finish = finish
