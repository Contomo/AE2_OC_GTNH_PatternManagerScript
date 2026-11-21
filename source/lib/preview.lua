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
  if plan.retirements then
    add(
      #plan.retirements .. ' old liquid recipes will be retired before installing patterns.',
      'yellow'
    )
    add('Retired patterns are reused first; see Retirements for their locations.', 'muted')
  end
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
    if recipe.heat and recipe.heat > 0 then
      treeRow(
        rows,
        add,
        '  |      ',
        'Required heat: '
          .. recipe.heat
          .. ' K'
          .. (recipe.priority and (' / Priority: ' .. recipe.priority) or ''),
        'muted'
      )
    end
    if recipe.plasmaTier then
      treeRow(
        rows,
        add,
        '  |      ',
        'Multistep: '
          .. (recipe.multistep and 'Yes' or 'No')
          .. ' / Regular fusion: '
          .. (recipe.fusion and 'Yes' or 'No'),
        'muted'
      )
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
    if group.availableInterfaces then
      add(
        group.availableInterfaces .. ' target interfaces present; ' .. group.free .. ' free slots.',
        'muted'
      )
      add(group.occupied .. ' existing + ' .. group.incoming .. ' incoming patterns.')
    end
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

function M.moverRows(plan, section)
  if section == 'capacity' then
    return M.capacityRows(plan)
  end
  local rows, add = U.rows()
  add('PATTERN MOVER', 'blue')
  add('SOURCE: ' .. plan.source, 'muted')
  add('TARGET: ' .. plan.destination, 'muted')
  if section == 'details' then
    add('One * matches any text, including spaces or an empty suffix.')
    add('Names match in full and are case-sensitive. All other characters are literal.')
    add('The target * inserts the text captured by the source *.')
    add('Large Assembler #* -> Mass Assembler #* maps #1 to #1, #2 to #2, etc.', 'muted')
    add('A target without * combines all matched source groups into that exact name.')
    add('All interfaces sharing each name participate, ordered by location and slot.')
    add('Existing target patterns stay in place; incoming patterns fill free slots.')
    add('Each target group needs enough space for its own incoming patterns.', 'yellow')
    add('Crafting, processing and fluid patterns move intact: no recipe or NBT edits.')
    add('No disposable donors or empty editor slot are needed.')
    add('Pause / Resume / Stop and Continue use the shared operation journal.', 'muted')
  else
    for _, group in ipairs(plan.groups) do
      spacer(rows, add)
      destinationRow(add, group.name)
      add('  FROM: ' .. table.concat(group.sourceNames, ', '), 'muted')
      add(
        '  ' .. group.sourceBanks .. ' source / ' .. group.targetBanks .. ' target interfaces',
        'muted'
      )
      add(
        '  ' .. group.patterns .. ' patterns to move; ' .. group.free .. ' free target slots.',
        'green'
      )
      local bank
      for index = group.first, group.last do
        local entry = plan.moves[index]
        if bank ~= U.where(entry.from) then
          spacer(rows, add)
          bank = U.where(entry.from)
          add('  +-- ' .. entry.sourceName .. ' / ' .. U.locationText(entry.from), interfaceTone)
        else
          add('  |', interfaceTone)
        end
        treeRow(rows, add, '  |  ', 'MOVE slot ' .. entry.from.slot .. '  ' .. entry.label, 'green')
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

function M.retirementRows(plan)
  local rows, add = U.rows()
  add('LIQUID RECIPES TO RETIRE', 'blue')
  add('Old recipes become tagged donor placeholders before new casts are installed.', 'muted')
  local bank
  for _, entry in ipairs(plan.retirements or {}) do
    local location = U.where(entry.from)
    if bank ~= location then
      spacer(rows, add)
      bank = location
      add('  +-- ' .. entry.name .. ' / ' .. U.locationText(entry.from), interfaceTone)
    else
      add('  |', interfaceTone)
    end
    treeRow(rows, add, '  |  ', 'RETIRE slot ' .. entry.from.slot .. '  ' .. entry.label, 'yellow')
    treeRow(rows, add, '  |    ', entry.action, 'muted')
    if entry.reason then
      treeRow(rows, add, '  |    ', 'BLOCKED: ' .. entry.reason, 'red')
    end
  end
  if #(plan.retirements or {}) == 0 then
    add('No old liquid recipes need retirement.', 'green')
  end
  return rows
end

function M.liquidDetails(plan, manifest)
  local rows, add = U.rows()
  local melting = manifest.policy.mode == 'meltingCore'
  add(melting and 'MELTING CORE MIGRATION' or 'FLUID SHAPER SUPPLY CHECK', 'blue')
  add('1. Retire matched extraction and obsolete remelting recipes.')
  add('2. Reuse those patterns, then ordinary buffer donors, for the planned recipes.')
  add(
    melting and '3. Install molten production. Configure casts separately in Fluid Shaper.'
      or '3. Install casts backed by independent liquid production already in the network.'
  )
  spacer(rows, add)
  add('DEPENDENCY CHECK', 'blue')
  add(
    plan.supplyCounts.banks
      .. ' interfaces / '
      .. plan.supplyCounts.patterns
      .. ' installed patterns compared.'
  )
  add('Existing fluid-output patterns prevent duplicate Melting Core recipes.')
  if melting then
    add(
      (plan.supplyCounts.fluidChecks or 0)
        .. ' candidate fluids checked against live ME crafting availability.'
    )
  end
  add('A dust feed must have a path that does not require its own molten product or cast ingot.')
  add(
    'Unpatterned inputs are external supplies; this checks dependencies, not stock or machine readiness.',
    'muted'
  )
  add(
    'Dependency checks use terminal-visible patterns. Live ME lookup also checks new fluid outputs.',
    'yellow'
  )
  add(
    plan.supplyCounts.unreadable
      .. ' patterns could not be decoded; their visible outputs do not prove supply.',
    'muted'
  )
  spacer(rows, add)
  add('MACHINE SETUP', 'blue')
  if melting then
    add('Each enabled circuit destination needs its circuit stocked in its own input buffer.')
    add('The No Circuit destination must not contain a programmed circuit.')
    add('Selected optional gas: ' .. manifest.policy.gas)
    add(
      manifest.policy.requestGas and 'Process gas is requested in patterns.'
        or 'Process gas is supplied externally; the selected gas-assisted recipe and circuit are retained.'
    )
    add('Required reaction fluids are always requested.')
    add(
      'The module needs sufficient heat and power; recipe EU/t and shared tier limits are shown in Patterns.'
    )
  else
    add('Keep the matching mold stocked in each Fluid Shaper destination.')
    add(
      'Ingot casts require independent installed liquid supply, including Melting Core, ABS or DTPF recipes.'
    )
  end
  add(
    'Pause / Stop / Continue use the shared transaction journal. Retirement is completed before casting begins.',
    'muted'
  )
  return rows
end

function M.rows(section, plan, manifest)
  if section == 'retirements' then
    return M.retirementRows(plan)
  end
  if section == 'details' and plan.supplyCounts then
    return M.liquidDetails(plan, manifest)
  end
  if plan.kind == 'patternMover' then
    return M.moverRows(plan, section)
  end
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
  if plan.kind == 'transition' or plan.kind == 'patternMover' then
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
  if manifest.details then
    append(manifest.details)
  end
  append(M.planRows(plan, manifest))
  if plan.retirements then
    append(M.retirementRows(plan))
    append(M.liquidDetails(plan, manifest))
  end
  for _, warning in ipairs(plan.warnings) do
    lines[#lines + 1] = 'NOTE: ' .. warning
  end
  lines[#lines + 1] = ''
  append(M.existingRows(plan))
  append(M.excludedRows(manifest))
  return table.concat(lines, '\n') .. '\n'
end

return M
