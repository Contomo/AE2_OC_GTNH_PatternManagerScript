-- One configuration for the application: shared hardware and per-program fields.
local U = require('assline_util')
local Programs = require('assline_programs')
local Batch = require('assline_batch')
local M = {}
M.destinationSlots = 36
function M.selected(value, choices)
  U.check(type(value) == 'string', 'Missing multi-choice setting')
  local allowed, seen, tokens = {}, {}, {}
  for _, entry in ipairs(choices) do
    allowed[entry[1]] = true
  end
  if value ~= '' then
    for key in value:gmatch('[^,]+') do
      U.check(allowed[key] and not seen[key], 'Invalid or duplicate output switch: ' .. key)
      seen[key] = true
      tokens[#tokens + 1] = key
    end
    U.check(table.concat(tokens, ',') == value, 'Invalid output switch list')
  end
  return seen
end
function M.toggleSelected(value, choices, key)
  local selected = M.selected(value, choices)
  selected[key] = not selected[key]
  local result = {}
  for _, entry in ipairs(choices) do
    if selected[entry[1]] then
      result[#result + 1] = entry[1]
    end
  end
  return table.concat(result, ',')
end
M.fields = {
  {
    key = 'editor',
    label = 'Pattern editor interface',
    help = 'Exact terminal name of the interface connected directly to the OC adapter.',
    default = 'OC Pattern Editor',
  },
  {
    key = 'donors',
    label = 'New pattern buffer name',
    help = 'All remote interfaces with this exact name supply disposable encoded patterns.',
    default = 'OC Pattern Buffer',
  },
  {
    key = 'terminalAddress',
    placeholder = 'auto',
    label = 'Terminal component address',
    help = 'Blank selects the only terminal; otherwise enter its address or unique prefix.',
    default = '',
  },
  {
    key = 'editorAddress',
    placeholder = 'auto',
    label = 'Editor component address',
    help = 'Blank selects the only directly connected ME interface.',
    default = '',
  },
  {
    key = 'dataAddress',
    placeholder = 'auto',
    label = 'Data Card address',
    help = 'Blank selects the only Data Card.',
    default = '',
  },
  {
    key = 'energyPause',
    kind = 'number',
    label = 'Pause work below energy %',
    help = 'Pause component work at this charge level.',
    default = '25',
  },
  {
    key = 'energyResume',
    kind = 'number',
    label = 'Resume work at energy %',
    help = 'At least 10 percentage points above the pause level; at most 95%.',
    default = '75',
  },
  {
    key = 'networkAddress',
    placeholder = 'auto',
    label = 'ME network component address',
    help = 'Ingot checks: blank uses the block editor or sole ME controller; otherwise enter a controller/block interface address prefix.',
    default = '',
  },
}
M.defaults = { version = 2, shared = {}, batch = {}, programs = {} }
for _, f in ipairs(M.fields) do
  M.defaults.shared[f.key] = f.default
end
for _, f in ipairs(Batch.fields) do
  M.defaults.batch[f.key] = f.default
end
M.sections = {
  shared = { name = 'Shared interfaces', fields = M.fields },
  batch = { name = 'Tier multipliers', fields = Batch.fields, pageSize = 9 },
}
function M.section(id)
  return U.check(M.sections[id] or Programs.byId[id], 'Unknown settings section')
end
function M.visibleFields(c, section)
  local result, values = {}, M.values(c, section)
  for _, f in ipairs(M.section(section).fields) do
    local visible = not f.hidden and (f.key ~= 'multiplier' or c.batch.mode == 'fixed')
    if f.costDivisor then
      visible = visible and c.batch.costScaling == 'on'
    end
    for key, expected in pairs(f.when or {}) do
      local match = values[key] == expected
      if type(expected) == 'table' then
        for _, option in ipairs(expected) do
          match = match or values[key] == option
        end
      end
      visible = visible and match
    end
    if visible then
      result[#result + 1] = f
    end
  end
  return result
end
for _, p in ipairs(Programs.list) do
  local values = {}
  M.defaults.programs[p.id] = values
  for _, f in ipairs(p.fields) do
    values[f.key] = f.default
  end
end
-- Expand shorthand only in numeric fields. Runtime consumers continue to read
-- ordinary decimal values; names, addresses and templates are never rewritten.
local function normalizeNumber(value)
  local digits, suffix = U.trim(value):match('^([+-]?%d*%.?%d+)([kKmM])$')
  if not digits then
    return value
  end
  local scale = suffix:lower() == 'k' and 1000 or 1000000
  local number = tonumber(digits) * scale
  if U.integer(number) then
    return string.format('%.0f', number)
  end
  -- Keep fractions for validation, and leave overflow invalid rather than
  -- rounding or accepting a value beyond the existing integer limits.
  return number == number and math.abs(number) < math.huge and tostring(number) or value
end

function M.normalize(c)
  local function fields(values, definitions)
    U.check(type(values) == 'table', 'Missing configuration section')
    for _, f in ipairs(definitions) do
      local value = values[f.key]
      if
        (f.kind == 'number' or f.kind == 'positiveInteger' or f.kind == 'optionalPositiveInteger')
        and type(value) == 'string'
        and not value:find('[%c]')
      then
        values[f.key] = normalizeNumber(value)
      end
    end
  end
  fields(c.shared, M.fields)
  fields(c.batch, Batch.fields)
  for _, p in ipairs(Programs.list) do
    fields(c.programs[p.id], p.fields)
  end
  return c
end

function M.validate(c)
  U.check(
    type(c) == 'table'
      and c.version == 2
      and type(c.shared) == 'table'
      and type(c.programs) == 'table',
    'Invalid configuration'
  )
  local function fields(values, definitions)
    U.check(type(values) == 'table', 'Missing configuration section')
    for _, f in ipairs(definitions) do
      local v = values[f.key]
      U.check(
        type(v) == 'string' and #v <= 512 and not v:find('[%c]'),
        'Invalid setting: ' .. f.label
      )
      if f.kind == 'toggle' then
        U.check(v == 'on' or v == 'off', f.label .. ' must be on or off')
      end
      if f.kind == 'positiveInteger' or f.kind == 'optionalPositiveInteger' and v ~= '' then
        U.check(
          U.integer(tonumber(v)) and tonumber(v) > 0,
          f.label .. ' must be a positive whole number'
        )
      end
      if f.choices then
        if f.kind == 'multiToggle' then
          M.selected(v, f.choices)
        else
          local found = false
          for _, option in ipairs(f.choices) do
            if option[1] == v then
              found = true
            end
          end
          U.check(found, 'Invalid choice: ' .. f.label)
        end
      end
    end
  end
  fields(c.shared, M.fields)
  fields(c.batch, Batch.fields)
  Batch.validate(c.batch)
  for _, p in ipairs(Programs.list) do
    fields(c.programs[p.id], p.fields)
  end
  local pause, resume = tonumber(c.shared.energyPause), tonumber(c.shared.energyResume)
  U.check(
    pause and resume and pause >= 10 and pause <= 80 and resume >= pause + 10 and resume <= 95,
    'Energy pause must be 10..80%; resume at least 10% higher, up to 95%'
  )
  local a = c.programs.assline
  for _, key in ipairs({ 'itemName', 'renameName' }) do
    U.check(
      not a[key]:gsub('{label}', ''):gsub('{n}', ''):find('[{}]'),
      'Unknown template token: ' .. key
    )
  end
  U.check(a.itemName:find('{n}', 1, true), 'Item name template needs {n}')
  return c
end
function M.migrate(old)
  local c = U.clone(M.defaults)
  if not old then
    return c
  end
  U.check(type(old) == 'table', 'Invalid saved configuration')
  U.check(old.version == nil or old.version == 2, 'Unsupported saved configuration version')
  if old.version == 2 then
    if not old.batch then
      c.batch.mode = 'fixed'
    end
    for _, f in ipairs(Batch.fields) do
      if old.batch and old.batch[f.key] ~= nil then
        c.batch[f.key] = old.batch[f.key]
      end
    end
    if old.batch and not old.batch.curveMode then
      local prior = { 4, 32, 64, 256, 320, 400, 448, 512 }
      for gap = 0, 7 do
        local value = old.batch['below' .. gap]
        if value and tonumber(value) ~= prior[gap + 1] then
          c.batch.curveMode = 'table'
        end
      end
    end
    for _, f in ipairs(M.fields) do
      if old.shared and old.shared[f.key] ~= nil then
        c.shared[f.key] = old.shared[f.key]
      end
    end
    for _, p in ipairs(Programs.list) do
      for _, f in ipairs(p.fields) do
        local values = old.programs and old.programs[p.id]
        if values and values[f.key] ~= nil then
          c.programs[p.id][f.key] = values[f.key]
        end
      end
    end
  else
    c.batch.mode = 'fixed'
    -- The old "buffer" was actually the directly connected editor.
    local shared = {
      editor = 'buffer',
      donors = 'makerDonors',
      terminalAddress = 'terminalAddress',
      editorAddress = 'bufferAddress',
      dataAddress = 'dataAddress',
      energyPause = 'energyPause',
      energyResume = 'energyResume',
    }
    for key, legacy in pairs(shared) do
      if old[legacy] ~= nil and old[legacy] ~= '' then
        c.shared[key] = old[legacy]
      end
    end
    if old.makerWorkspace and old.makerWorkspace ~= '' then
      c.shared.editor = old.makerWorkspace
    end
    for _, key in ipairs({ 'target', 'itemName', 'renameName' }) do
      if old[key] ~= nil then
        c.programs.assline[key] = old[key]
      end
    end
    if old.makerDestination then
      if old.makerMode == 'coating' then
        c.programs.insulator.destination = old.makerDestination
      else
        c.programs.wiremill.wire1 = old.makerDestination
        c.programs.wiremill.wireFine = old.makerDestination
      end
    end
    if old.makerPVC then
      c.programs.insulator.polymer = old.makerPVC == 'off' and 'none' or 'pvcSmall'
    end
    if old.makerPPS then
      c.programs.insulator.pps = old.makerPPS
    end
  end
  local prior = old.programs and old.programs.insulator
  if prior and not prior.polymer and prior.pvc then
    c.programs.insulator.polymer = prior.pvc == 'off' and 'none' or 'pvcSmall'
  end
  return M.validate(M.normalize(c))
end
function M.capacityReport(groups)
  local result = {}
  for _, name in ipairs(U.keys(groups)) do
    local n = groups[name]
    result[#result + 1] =
      { name = name, patterns = n, interfaces = math.ceil(n / M.destinationSlots) }
  end
  return result
end
function M.values(c, section)
  return M.sections[section] and c[section]
    or U.check(c.programs[section], 'Unknown settings section')
end
function M.requireProgram(c, id)
  M.validate(c)
  local p = U.check(Programs.byId[id], 'Unknown program')
  U.check(not p.unavailable, p.unavailable)
  for _, key in ipairs({ 'editor', 'donors' }) do
    U.check(c.shared[key] ~= '', 'Set ' .. key .. ' in Settings > Shared interfaces')
  end
  U.check(
    c.shared.editor ~= c.shared.donors,
    'Pattern editor and new pattern buffer must have different names'
  )
  for _, f in ipairs(p.fields) do
    U.check(
      f.optional or c.programs[id][f.key] ~= '',
      'Set ' .. f.label .. ' in Settings > ' .. p.name
    )
  end
  if p.distinctDestinations then
    local assigned = {}
    for _, key in pairs(p.outputs) do
      local name = c.programs[id][key]
      U.check(not assigned[name], 'Each component needs a distinct destination name: ' .. name)
      assigned[name] = true
    end
  end
  if p.formSwitch and p.outputs then
    local selected = M.selected(c.programs[id][p.formSwitch], p.formChoices)
    local needed = {}
    for form, key in pairs(p.outputs) do
      if selected[Programs.switchKey(p, form)] then
        needed[key] = true
      end
    end
    for _, f in ipairs(p.fields) do
      if needed[f.key] then
        U.check(c.programs[id][f.key] ~= '', 'Set ' .. f.label .. ' in Settings > ' .. p.name)
      end
    end
  end
  return p
end
return M
