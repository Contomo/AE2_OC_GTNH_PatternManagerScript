-- One renderer for maker previews, on screen and in exported reports.
local U = require('assline_util')
local Planner = require('assline_planner')
local Batch = require('assline_batch')
local M = {}
local interfaceTone = 'muted'
local function destinationRow(add, name)
  add('DESTINATION: ' .. tostring(name), 'blue', nil, nil, nil, { destination = name })
end

local function spacer(rows, add)
  if #rows > 0 and rows[#rows][1] ~= '' then
    add('')
  end
end

local function treeRow(rows, add, prefix, content, tone)
  add(prefix .. content, tone)
  local row = rows[#rows]
  row[3], row[4] = #prefix, interfaceTone
end

function M.planRows(plan, manifest)
  local rows, add = U.rows()
  local details = {}
  for _, recipe in ipairs(manifest.recipes) do
    details[recipe.key or Planner.recipeKey(recipe)] = recipe
  end
  add('PATTERN PLAN', 'blue')
  add(
    string.format(
      '%d reuse   |   %d new   |   %d other patterns kept',
      plan.reused,
      plan.required.processing + plan.required.crafting,
      #plan.preserved
    ),
    'green'
  )
  if manifest.source.batchPolicy then
    add(manifest.source.batchPolicy, 'muted')
    if (manifest.tierExcluded or 0) > 0 then
      add(manifest.tierExcluded .. ' routes excluded by settings; see Excluded.', 'yellow')
    end
  elseif manifest.policy and manifest.policy.batch and manifest.policy.batch.mode == 'tiered' then
    add(
      'Tiered batches at '
        .. manifest.policy.batch.currentTier
        .. '; fixed program multipliers do not apply.',
      'muted'
    )
    add(
      (manifest.unclassifiedRecipes or 0)
        .. ' unclassified recipes; policy: '
        .. manifest.policy.batch.unknownPolicy
        .. '.  '
        .. (manifest.tierExcluded or 0)
        .. ' routes excluded by tier settings.',
      'muted'
    )
  elseif manifest.policy then
    add(
      'Batch policy: Fixed  |  Program multiplier ' .. (manifest.policy.multiplier or 1) .. 'x',
      'muted'
    )
  end
  if manifest.source.usagePolicy then
    add(
      manifest.unusedExcluded .. ' recipe routes skipped: output has no non-recycling use.',
      'muted'
    )
  end
  if plan.resizeCount > 0 then
    add(
      plan.resizeCount .. ' reused patterns will be resized to the configured batch.',
      'yellow_lighter1'
    )
  end
  local group, bank, material
  for _, entry in ipairs(plan.layout) do
    local recipe = details[entry.key]
    if group ~= entry.group then
      spacer(rows, add)
      group, bank, material = entry.group, nil, nil
      destinationRow(add, group)
    end
    local location = entry.destination and U.where(entry.destination) or 'needs space'
    if bank ~= location then
      if bank then
        spacer(rows, add)
      end
      bank, material = location, nil
      add(
        '  +-- Interface '
          .. (entry.destination and U.locationText(entry.destination) or '(needs space)'),
        interfaceTone
      )
    else
      add('  |', interfaceTone)
    end
    local currentMaterial = recipe.material or recipe.label
    if material ~= currentMaterial then
      material = currentMaterial
      treeRow(rows, add, '  |  ', material, 'blue')
    end
    treeRow(
      rows,
      add,
      '  |    ',
      (entry.resize and 'RESIZE  ' or entry.existing and 'REUSE   ' or 'CREATE  ')
        .. (recipe.outputLabel or recipe.outputForm or '')
        .. (entry.destination and ('   slot ' .. entry.destination.slot) or '   needs space'),
      entry.resize and 'yellow_lighter1' or entry.existing and 'green' or 'yellow'
    )
    if entry.resize then
      treeRow(
        rows,
        add,
        '  |      ',
        'Multiply current quantities by ' .. entry.newScale .. ' / ' .. entry.oldScale,
        'yellow_lighter1'
      )
    end
    treeRow(rows, add, '  |      ', U.ingredientSummary(recipe.inputs))
    treeRow(rows, add, '  |      ', '-> ' .. U.ingredientSummary(recipe.outputs), 'green')
    if recipe.batch then
      local description, voltage = Batch.describe(recipe.batch), Batch.voltageText(recipe.batch)
      treeRow(rows, add, '  |      ', description, 'muted')
      if recipe.batch.recipeTier then
        rows[#rows][5] = {
          from = 10 + #description - #voltage,
          length = #voltage,
          tier = recipe.batch.recipeTier,
        }
      end
    end
  end
  return rows
end

function M.capacityRows(plan)
  local rows, add = U.rows()
  add('DESTINATION SPACE', 'blue')
  add('Assuming 3 capacity cards per interface (36 slots).', 'muted')
  spacer(rows, add)
  for _, group in ipairs(plan.capacities or {}) do
    add(group.name, 'blue')
    add(group.interfaces .. ' interfaces (' .. group.patterns .. ' patterns)')
  end
  spacer(rows, add)
  add('Every matching interface is included, ordered by location.', 'muted')
  add('Existing unrelated patterns count toward required space.', 'muted')
  for _, err in ipairs(plan.errors or {}) do
    add('BLOCKED: ' .. err, 'red')
  end
  return rows
end

function M.existingRows(plan)
  local rows, add = U.rows()
  add('EXISTING DESTINATION PATTERNS', 'blue')
  add(
    #(plan.existing or {})
      .. ' occupied; '
      .. plan.reused
      .. ' reused; '
      .. #plan.preserved
      .. ' kept.',
    'muted'
  )
  local group, bank
  for _, entry in ipairs(plan.existing or {}) do
    local location = U.where(entry.from)
    if group ~= entry.interface then
      spacer(rows, add)
      group, bank = entry.interface, nil
      destinationRow(add, group)
    end
    if bank ~= location then
      if bank then
        spacer(rows, add)
      end
      bank = location
      add('  +-- Interface ' .. U.locationText(entry.from), interfaceTone)
    else
      add('  |', interfaceTone)
    end
    treeRow(
      rows,
      add,
      '  |  ',
      entry.status .. '  slot ' .. entry.from.slot .. '  ' .. entry.label,
      entry.status == 'RESIZE' and 'yellow_lighter1'
        or entry.status == 'KEEP' and 'yellow'
        or 'green'
    )
    treeRow(rows, add, '  |    ', entry.reason, 'muted')
    if entry.inputs and entry.inputs ~= '' and entry.status == 'KEEP' then
      treeRow(rows, add, '  |    ', 'Encoded inputs: ' .. entry.inputs, 'muted')
    end
    if entry.requestedInputs and entry.status == 'KEEP' then
      treeRow(rows, add, '  |    ', 'Requested inputs: ' .. entry.requestedInputs, 'muted')
    end
    if U.where(entry.from) ~= U.where(entry.to) or entry.from.slot ~= entry.to.slot then
      treeRow(
        rows,
        add,
        '  |    ',
        'Final: ' .. U.locationText(entry.to) .. ' slot ' .. entry.to.slot,
        'muted'
      )
    end
  end
  if #(plan.existing or {}) == 0 then
    add('No patterns in the selected destination interfaces.', 'muted')
  end
  spacer(rows, add)
  add('SORTING MOVES', 'blue')
  for n, move in ipairs(plan.moves) do
    add(
      n .. '/' .. #plan.moves .. '  ' .. ((plan.moveLabels or {})[move.fingerprint] or 'Pattern'),
      'yellow'
    )
    add(
      '  '
        .. U.locationText(move.from)
        .. ' slot '
        .. move.from.slot
        .. ' -> '
        .. U.locationText(move.to)
        .. ' slot '
        .. move.to.slot,
      'muted'
    )
  end
  if #plan.moves == 0 then
    add('No sorting moves needed.', 'muted')
  end
  return rows
end

function M.excludedRows(manifest)
  local rows, add = U.rows()
  add('EXCLUDED OUTPUTS', 'blue')
  add(
    #(manifest.skipped or {}) .. ' output forms excluded by material, use or tier policy.',
    'muted'
  )
  add('Existing patterns for these outputs are kept; see Existing.', 'muted')
  local material
  for _, item in ipairs(manifest.skipped or {}) do
    if material ~= item.material then
      spacer(rows, add)
      material = item.material
      add(material, 'blue')
    end
    add('  ' .. item.label, 'yellow')
    add('    ' .. (item.reason or 'No path to a non-recycling product.'), 'muted')
  end
  if #(manifest.skipped or {}) == 0 then
    add('No selected output forms excluded.', 'green')
  end
  return rows
end

function M.donorRows(plan, section)
  local rows, add = U.rows()
  add('DONOR BUFFER CLEANUP', 'blue')
  add('Terminal name: "' .. plan.name .. '"', 'muted')
  add(
    #plan.cleanups
      .. ' to park; '
      .. plan.parked
      .. ' already parked; '
      .. plan.skipped
      .. ' skipped.'
  )
  add('Replaces the old recipes. Patterns return to their original slots.', 'yellow')
  if section == 'details' then
    spacer(rows, add)
    add('PARKING RECIPE', 'blue')
    add('1 tagged paper -> 1 identical tagged paper')
    add('Tag: ae2ocDonor = parked-v1; name: OC donor placeholder', 'muted')
    add('The tag distinguishes it from ordinary paper; real recipes are removed.')
    add('No paper or other item needs to be supplied. This edits the encoded recipe only.')
    spacer(rows, add)
    add('REUSABILITY', 'blue')
    add('Processing, ultimate and supported fluid patterns retain their item type and metadata.')
    add('The normal donor pool can imprint them again. Already parked patterns are left alone.')
    add('Crafting, substitution, tunnel and invalid patterns are skipped with a reason.')
    add('Empty recipes can acquire a persistent InvalidPattern flag, which this API cannot clear.')
    add('Uses one empty editor slot, shared Pause / Resume / Stop and transaction recovery.')
  else
    local bank
    for _, entry in ipairs(plan.entries) do
      if bank ~= U.where(entry.from) then
        spacer(rows, add)
        bank = U.where(entry.from)
        add('  +-- Interface ' .. U.locationText(entry.from), interfaceTone)
      else
        add('  |', interfaceTone)
      end
      local status = entry.status == 'park' and 'PARK'
        or entry.status == 'parked' and 'ALREADY PARKED'
        or 'SKIP'
      treeRow(
        rows,
        add,
        '  |  ',
        status .. ' slot ' .. entry.from.slot .. '  ' .. entry.label,
        entry.status == 'park' and 'yellow' or entry.status == 'parked' and 'green' or 'muted'
      )
      if entry.reason then
        treeRow(rows, add, '  |    ', entry.reason, 'muted')
      end
    end
  end
  for _, err in ipairs(plan.errors) do
    add('BLOCKED: ' .. err, 'red')
  end
  return rows
end

function M.transitionRows(plan, section)
  if section == 'capacity' then
    return M.capacityRows(plan)
  end
  local rows, add = U.rows()
  add('IMPLOSION TRANSITION', 'blue')
  add('FROM: ' .. plan.source, 'muted')
  destinationRow(add, plan.destination)
  if section == 'details' then
    add('Moves the same encoded patterns; no disposable donors are needed.')
    add('Preserves quantities, item type and supported pattern metadata.')
    add('Removes TNT, industrial TNT, dynamite and powderbarrels.', 'yellow')
    add('Omits known secondary tiny dust / ash outputs. The primary output stays.')
    add('The machine may still produce these byproducts; AE will not request them.', 'muted')
    add('Existing target patterns stay in place. Free slots fill in interface / slot order.')
    add('Skipped patterns remain in the old interfaces; their reasons appear under Patterns.')
    add('Pause / Resume / Stop and Continue use the shared operation journal.', 'muted')
  else
    local bank
    for _, entry in ipairs(plan.entries) do
      if bank ~= U.where(entry.from) then
        spacer(rows, add)
        bank = U.where(entry.from)
        add('  +-- Old interface ' .. U.locationText(entry.from), interfaceTone)
      else
        add('  |', interfaceTone)
      end
      treeRow(
        rows,
        add,
        '  |  ',
        (entry.reason and 'SKIP' or 'MOVE') .. ' slot ' .. entry.from.slot .. '  ' .. entry.label,
        entry.reason and 'muted' or 'green'
      )
      if entry.reason then
        treeRow(rows, add, '  |    ', entry.reason, 'muted')
      else
        treeRow(
          rows,
          add,
          '  |    ',
          'Inputs: ' .. U.ingredientSummary(entry.recipe.inputs),
          'text'
        )
        treeRow(
          rows,
          add,
          '  |    ',
          'Outputs: ' .. U.ingredientSummary(entry.recipe.outputs),
          'text'
        )
        for _, which in ipairs({ 'inputs', 'outputs' }) do
          if #entry.removed[which] > 0 then
            treeRow(
              rows,
              add,
              '  |    ',
              'Remove ' .. which .. ': ' .. U.ingredientSummary(entry.removed[which]),
              'yellow'
            )
          end
        end
        treeRow(
          rows,
          add,
          '  |    ',
          entry.to and ('To ' .. U.locationText(entry.to) .. ' slot ' .. entry.to.slot)
            or 'Needs a free target slot',
          'muted'
        )
      end
    end
  end
  for _, err in ipairs(plan.errors) do
    add('BLOCKED: ' .. err, 'red')
  end
  return rows
end

function M.rows(section, plan, manifest)
  if plan.kind == 'transition' then
    return M.transitionRows(plan, section)
  end
  if plan.kind == 'donorCleanup' then
    return M.donorRows(plan, section)
  end
  if section == 'existing' then
    return M.existingRows(plan)
  end
  if section == 'skipped' then
    return M.excludedRows(manifest)
  end
  if section == 'capacity' then
    return M.capacityRows(plan)
  end
  return M.planRows(plan, manifest)
end

function M.report(plan, manifest)
  local lines = {}
  local function append(rows)
    for _, row in ipairs(rows) do
      lines[#lines + 1] = row[1]
    end
    lines[#lines + 1] = ''
  end
  if plan.kind == 'transition' then
    for _, section in ipairs({ 'changes', 'capacity', 'details' }) do
      append(M.rows(section, plan))
    end
    return table.concat(lines, '\n') .. '\n'
  end
  if plan.kind == 'donorCleanup' then
    append(M.donorRows(plan))
    append(M.donorRows(plan, 'details'))
    return table.concat(lines, '\n') .. '\n'
  end
  append(M.capacityRows(plan))
  append(M.planRows(plan, manifest))
  for _, warning in ipairs(plan.warnings) do
    lines[#lines + 1] = 'NOTE: ' .. warning
  end
  lines[#lines + 1] = ''
  append(M.existingRows(plan))
  append(M.excludedRows(manifest))
  return table.concat(lines, '\n') .. '\n'
end

return M
