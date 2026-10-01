-- One configuration for the application: shared hardware and per-program fields.
local U = require('assline_util')
local Programs = require('assline_programs')
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
    label = 'Terminal component address',
    help = 'Blank selects the only terminal; otherwise enter its address or unique prefix.',
    default = '',
  },
  {
    key = 'editorAddress',
    label = 'Editor component address',
    help = 'Blank selects the only directly connected ME interface.',
    default = '',
  },
  {
    key = 'dataAddress',
    label = 'Data Card address',
    help = 'Blank selects the only Data Card.',
    default = '',
  },
  {
    key = 'energyPause',
    label = 'Pause work below energy %',
    help = 'Pause component work at this charge level.',
    default = '25',
  },
  {
    key = 'energyResume',
    label = 'Resume work at energy %',
    help = 'At least 10 percentage points above the pause level; at most 95%.',
    default = '75',
  },
}
M.defaults = { version = 2, shared = {}, programs = {} }
for _, f in ipairs(M.fields) do
  M.defaults.shared[f.key] = f.default
end
for _, p in ipairs(Programs.list) do
  local values = {}
  M.defaults.programs[p.id] = values
  for _, f in ipairs(p.fields) do
    values[f.key] = f.default
  end
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
      if f.kind == 'positiveInteger' then
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
  return M.validate(c)
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
  return section == 'shared' and c.shared
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
  if p.formSwitch and p.outputs then
    local selected = M.selected(c.programs[id][p.formSwitch], p.formChoices)
    local needed = {}
    for form, key in pairs(p.outputs) do
      if selected[form] then
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
