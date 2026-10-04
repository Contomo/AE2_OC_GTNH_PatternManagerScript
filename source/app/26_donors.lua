-- Park disposable processing recipes in their original donor slots. Discovery,
-- ingredient writes, journaling and recovery are the application's shared ones.
C.donors = {}
local function donorMarker(hw)
  local root = {
    __nbt_type = 'compound',
    __value = {
      ae2ocDonor = { __nbt_type = 'string', __value = 'parked-v1' },
      display = {
        __nbt_type = 'compound',
        __value = { Name = { __nbt_type = 'string', __value = 'OC donor placeholder' } },
      },
    },
  }
  local tag = invoke(hw.data, 'encodeNBT', encodableNBT(root))
  U.check(U.eq(nbt(hw.data, tag), root), 'Donor marker NBT round trip failed')
  local marker = { type = 'item', name = 'minecraft:paper', damage = 0, size = 1, tag = tag }
  return { kind = 'processing', inputs = { marker }, outputs = { U.clone(marker) } }
end
C.donors.marker = donorMarker

function C.donors.scan(c, progress, control)
  local hw = connect(c, progress, control)
  local recipe = donorMarker(hw)
  local plan = {
    kind = 'donorCleanup',
    name = c.shared.donors,
    banks = 0,
    scanned = 0,
    parked = 0,
    skipped = 0,
    cleanups = {},
    entries = {},
    errors = {},
    warnings = {},
    bindings = {
      terminal = hw.terminal.address,
      direct = hw.direct.address,
      data = hw.data.address,
    },
  }
  for _, ref in ipairs(discover(hw, c.shared.donors)) do
    local bank = current(hw, ref)
    U.check(bank.name == c.shared.donors, 'Donor interface renamed during scan')
    U.check(where(bank) ~= where(hw.buffer), 'Donor interface overlaps the pattern editor')
    plan.banks = plan.banks + 1
    for _, slot in ipairs(U.keys(bank.patterns)) do
      gate()
      local p = bank.patterns[slot]
      if U.exists(p) then
        plan.scanned = plan.scanned + 1
        local reason = donorIssue(hw.data, p)
        if not reason and not processing(p) then
          reason = 'Crafting pattern: the editor cannot change its crafting flag.'
        end
        local entry = {
          from = endpoint(bank, slot),
          fingerprint = p.tag and patternFingerprint(hw, p) or U.canonical(compact(p)),
          label = p.label or p.name,
          status = 'skip',
          reason = reason,
        }
        if not reason then
          local observed = effectivePattern(hw.data, p)
          entry.label = U.ingredientSummary(observed.outputs)
          if not next(observed.inputs) or not next(observed.outputs) then
            entry.reason = 'Empty recipe: re-encode it manually before using it as a donor.'
          else
            local goal = compact(observed)
            goal.inputs, goal.outputs = recipe.inputs, recipe.outputs
            if semantic(hw, p, goal) then
              entry.status = 'parked'
              plan.parked = plan.parked + 1
            else
              entry.status = 'park'
              plan.cleanups[#plan.cleanups + 1] = entry
            end
          end
        end
        if entry.status == 'skip' then
          plan.skipped = plan.skipped + 1
        end
        plan.entries[#plan.entries + 1] = entry
      end
    end
    if progress then
      progress('Read donor bank at ' .. U.locationText(bank))
    end
  end
  if plan.banks == 0 then
    plan.errors[#plan.errors + 1] = 'No donor interfaces named "' .. c.shared.donors .. '".'
  end
  if #plan.cleanups > 0 then
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
  return plan, hw, recipe
end

function C.donors.preview(c, progress, control)
  local plan = C.donors.scan(c, progress, control)
  return plan, Preview.report(plan)
end

function C.donors.apply(c, plan, progress, control)
  U.check(#plan.errors == 0, 'Resolve cleanup blockers first')
  local fresh, hw, recipe = C.donors.scan(c, progress, control)
  U.check(U.eq(fresh, plan), 'Donor banks or editor changed since preview. Scan again.')
  writeFile(
    paths.backup,
    { config = U.clone(c), program = 'donorCleanup', cleaned = #plan.cleanups }
  )
  for n, entry in ipairs(plan.cleanups) do
    gate()
    local bank = current(hw, entry.from)
    U.check(bank.name == plan.name, 'Donor interface renamed before cleanup')
    local original = bank.patterns[entry.from.slot]
    U.check(patternFingerprint(hw, original) == entry.fingerprint, 'Donor changed before cleanup')
    U.check(safeDonor(hw.data, original), 'Donor is no longer editable')
    U.check(
      not U.exists(direct(hw, 'getInterfacePattern', plan.workspace.slot)),
      'Pattern editor workspace occupied'
    )
    local op = {
      kind = 'park',
      slot = plan.workspace.slot,
      destination = entry.from,
      original = compact(original),
      recipe = recipe,
    }
    saveOp(hw, op)
    finish(hw, op, progress)
    clearOp()
    if progress then
      progress('Parked donor ' .. n .. ' / ' .. #plan.cleanups)
    end
  end
end
