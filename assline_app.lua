-- Readable application bundle, generated from the source files named below.
local savedPath=package.path
local function unload()
  for name in pairs(package.loaded) do
    if name:match('^assline_') then package.loaded[name]=nil end
  end
end
unload()
local fs=require('filesystem')
local args=table.pack(...)
local directory=fs.path(require('shell').resolve(require('process').info().path))
if args[1]=='--module-directory' then
  directory=args[2]
  table.remove(args,1);table.remove(args,1);args.n=args.n-2
end
package.path=directory..'?.lua;'..savedPath
local ok,result=pcall(function(...)
local U=(function()
-- Source: lib/util.lua
local M = {}

function M.check(ok, why)
  if not ok then
    error(why or 'Operation failed', 0)
  end
  return ok
end

function M.clone(t)
  if type(t) ~= 'table' then
    return t
  end
  local r = {}
  for k, v in pairs(t) do
    r[k] = M.clone(v)
  end
  return r
end

function M.keys(t)
  local r = {}
  for k in pairs(t or {}) do
    r[#r + 1] = k
  end
  table.sort(r, function(a, b)
    if type(a) == type(b) then
      return a < b
    end
    return type(a) < type(b)
  end)
  return r
end

function M.canonical(t)
  if type(t) ~= 'table' then
    return type(t) .. ':' .. string.format('%q', tostring(t))
  end
  local r = {}
  for _, k in ipairs(M.keys(t)) do
    r[#r + 1] = M.canonical(k) .. ':' .. M.canonical(t[k])
  end
  return '{' .. table.concat(r, ',') .. '}'
end

function M.eq(a, b)
  if type(a) ~= type(b) then
    return false
  end
  if type(a) ~= 'table' then
    return a == b
  end
  for k, v in pairs(a) do
    if not M.eq(v, b[k]) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

function M.integer(n)
  return type(n) == 'number' and n == math.floor(n) and math.abs(n) < 2147483648
end

function M.sequence(t, label)
  M.check(type(t) == 'table', label .. ' must be an array')
  local count = 0
  for k in pairs(t) do
    M.check(M.integer(k) and k >= 1 and k <= #t, label .. ' must be a contiguous array')
    count = count + 1
  end
  M.check(count == #t, label .. ' must be a contiguous array')
end

function M.endpoint(i, slot)
  return { location = M.clone(i.location), side = i.side, slot = slot }
end

function M.where(i)
  return M.canonical({ i.location, i.side })
end
function M.locationText(i)
  local l = i.location
  return tostring(l.x)
    .. ','
    .. tostring(l.y)
    .. ','
    .. tostring(l.z)
    .. ' / '
    .. tostring(l.dimId or '?')
    .. ' side '
    .. tostring(i.side)
end

function M.ordered(a, b)
  for _, k in ipairs({ 'dimId', 'x', 'y', 'z' }) do
    local x, y = a.location[k] or 0, b.location[k] or 0
    if x ~= y then
      return x < y
    end
  end
  return a.side < b.side
end

function M.trim(s)
  return tostring(s or ''):match('^%s*(.-)%s*$')
end

function M.truth(x)
  return x == true or x == 1
end

function M.exists(x)
  return type(x) == 'table' and type(x.name) == 'string'
end

function M.largest(t)
  local n = 0
  for k in pairs(t or {}) do
    if type(k) == 'number' and k > n then
      n = k
    end
  end
  return n
end

function M.token(t, label, n)
  return (t:gsub('{label}', function()
    return label
  end):gsub('{n}', tostring(n)))
end

-- Shared row construction for preview and UI text, with one default tone.
function M.rows()
  local result = {}
  local function add(text, tone)
    result[#result + 1] = { text, tone or 'text' }
  end
  return result, add
end

return M

end)()
local Programs=(function()
-- Source: lib/programs.lua
-- Program definitions shared by configuration, navigation and execution.
local M = {}
local function field(key, label, help, default, kind)
  return { key = key, label = label, help = help, default = default or '', kind = kind or 'text' }
end
local function choice(key, label, choices, default, help)
  local f = field(
    key,
    label,
    help or 'Choose the input used for these patterns.',
    default or 'ingot',
    'choice'
  )
  f.choices = choices
  return f
end
local function multiplier()
  return field(
    'multiplier',
    'Pattern multiplier',
    'Whole-number batch multiplier. 1 keeps the selected recipe batch; 256 makes it 256 times larger.',
    '1',
    'positiveInteger'
  )
end
M.list = {
  {
    id = 'assline',
    name = 'Assembly line renamer',
    description = 'Review duplicate inputs and create their rename patterns.',
    fields = {
      field(
        'target',
        'Assembly line interface',
        'Exact name of the interface containing the patterns to manage.',
        'Advanced Assline (1)'
      ),
      field(
        'itemName',
        'Renamed item template',
        '{label} is the original item name; {n} is the duplicate number.',
        'NAME_{n}'
      ),
      field(
        'renameName',
        'Rename destination template',
        'All interfaces matching the resulting name participate.',
        'Rename NAME_{n}'
      ),
    },
  },
  {
    id = 'insulator',
    name = 'Wire insulator',
    mode = 'coating',
    description = 'Plan insulation patterns in material and cable-size order.',
    fields = {
      field(
        'destination',
        'Insulator interface name',
        'All interfaces with this exact name receive insulation patterns.'
      ),
      choice(
        'polymer',
        'Insulation polymer',
        {
          { 'pvc', 'PVC pulp' },
          { 'pvcSmall', 'Small PVC pulp' },
          { 'pdms', 'PDMS pulp' },
          { 'pdmsSmall', 'Small PDMS pulp' },
          { 'none', 'Nothing' },
        },
        'pvc',
        'Normal piles: batches of 4 cables. Small piles / nothing: 1 cable. PDMS = polydimethylsiloxane.'
      ),
      field(
        'pps',
        'Request PPS',
        'Off means PPS must already be stocked in the machine.',
        'on',
        'toggle'
      ),
      multiplier(),
    },
  },
  {
    id = 'wiremill',
    name = 'Wiremill',
    mode = 'wiremill',
    description = 'Create 1x wire and fine-wire patterns in separate destination banks.',
    outputs = { wire1 = 'wire1', wireFine = 'wireFine' },
    fields = {
      field(
        'wire1',
        '1x wire interface name',
        'All matching interfaces receive recipes producing 1x wire.'
      ),
      field(
        'wireFine',
        'Fine wire interface name',
        'All matching interfaces receive recipes producing fine wire.'
      ),
      choice('wireSource', '1x wire input', { { 'ingot', 'Ingot' }, { 'stick', 'Rod' } }),
      choice(
        'fineSource',
        'Fine wire input',
        { { 'ingot', 'Ingot' }, { 'stick', 'Rod' }, { 'wire1', '1x wire' } }
      ),
      multiplier(),
    },
  },
  {
    id = 'combining',
    name = 'Wire combining',
    unavailable = 'Combining recipe rules are not implemented yet.',
    description = 'Combine wire and cable sizes in a molecular assembler.',
    fields = {
      field('wire', 'Bare wire interface name', 'Destination bank for combined bare-wire sizes.'),
      field(
        'cable',
        'Insulated cable interface name',
        'Destination bank for combined insulated-cable sizes.'
      ),
    },
  },
  {
    id = 'bender',
    name = 'Bending machine',
    unavailable = 'Bending recipe rules are not implemented yet.',
    description = 'Separate destinations for plates, foil and sheet metal.',
    fields = {
      field('plate', 'Plate interface name', 'Destination bank for plate recipes.'),
      field('foil', 'Foil interface name', 'Destination bank for foil recipes.'),
      field(
        'sheetMetal',
        'Sheet metal interface name',
        'Destination bank for sheet-metal recipes.'
      ),
    },
  },
}
M.byId = {}
for _, program in ipairs(M.list) do
  M.byId[program.id] = program
end
return M

end)()
local Config=(function()
-- Source: lib/config.lua
-- One configuration for the application: shared hardware and per-program fields.
local U = U
local Programs = Programs
local M = {}
M.destinationSlots = 36
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
    U.check(c.programs[id][f.key] ~= '', 'Set ' .. f.label .. ' in Settings > ' .. p.name)
  end
  return p
end
return M

end)()
-- Source: src/00_core.lua
-- GTNH 2.9 / OpenOS. Terminal pattern slots are ZERO based; direct slots ONE based.
local component = require('component')
local event = require('event')
local computer = require('computer')
local fs = require('filesystem')
local serialization = require('serialization')
local unicode = require('unicode')
local C = {}
local U = U
local Programs = Programs
local Config = Config
local defaults = Config.defaults
local cfg = U.clone(defaults)
local work = { pause = 0.25, resume = 0.75 }
local perf
local tagKeys, renameTags, tagCount, renameCount = {}, {}, 0, 0
local function releaseWork()
  perf = nil
  work.progress = nil
  work.control = nil
  tagKeys, renameTags, tagCount, renameCount = {}, {}, 0, 0
end
local function sampleEnergy()
  local t = computer.uptime()
  local e, m = computer.energy(), computer.maxEnergy()
  if perf then
    perf.samples = perf.samples + 1
    perf.sampleTime = perf.sampleTime + computer.uptime() - t
  end
  U.check(type(m) == 'number' and m > 0, 'Computer energy capacity unavailable')
  return e, m
end
local function record(name, elapsed)
  if not perf then
    return
  end
  local v = perf.calls[name] or { 0, 0, 0 }
  perf.calls[name] = v
  v[1] = v[1] + 1
  v[2] = v[2] + elapsed
  v[3] = math.max(v[3], elapsed)
end
local function perfReport(status)
  if not perf then
    return
  end
  local e, m = sampleEnergy()
  local elapsed = computer.uptime() - perf.started
  local callTime = 0
  local out = {
    string.format(
      '\nuptime=%.1fs %s elapsed=%.2fs energy=%.0f/%.0f (%.1f%% -> %.1f%%)',
      computer.uptime(),
      status,
      elapsed,
      e,
      m,
      perf.startPct * 100,
      e / m * 100
    ),
    string.format('free memory=%d -> %d bytes', perf.memory, computer.freeMemory()),
    string.format(
      'energy samples=%d time=%.3fs pauses=%d event.pull yields=%d wait=%.2fs',
      perf.samples,
      perf.sampleTime,
      perf.pauses,
      perf.yields,
      perf.wait
    ),
  }
  for name, v in pairs(perf.calls) do
    callTime = callTime + v[2]
    out[#out + 1] = string.format('%s calls=%d time=%.3fs max=%.3fs', name, v[1], v[2], v[3])
  end
  out[#out + 1] = string.format(
    'other time=%.3fs (Lua planning, file I/O, UI)',
    math.max(0, elapsed - perf.wait - callTime)
  )
  local path = '/home/assline-perf.log'
  if fs.exists(path) and fs.size(path) > 65536 then
    fs.remove(path)
  end
  local f = io.open(path, 'a')
  if f then
    f:write(table.concat(out, '\n') .. '\n')
    f:close()
  end
  releaseWork()
end
local function energyFraction()
  local e, m = sampleEnergy()
  return e / m
end
local function rest(seconds)
  local deadline = computer.uptime() + seconds
  repeat
    if perf then
      perf.yields = perf.yields + 1
    end
    local t = computer.uptime()
    local delay = math.max(0, math.min(0.25, deadline - computer.uptime()))
    local e = work.control and (work.control(delay) or {}) or { event.pull(delay) }
    if perf then
      perf.wait = perf.wait + computer.uptime() - t
    end
    U.check(
      e[1] ~= 'interrupted' and not (e[1] == 'key_down' and e[4] == 1),
      'Work cancelled. Use Recover if an operation is pending; otherwise scan again.'
    )
  until computer.uptime() >= deadline
end
local function gate()
  if work.control and work.control(0) and perf then
    perf.yields = perf.yields + 1
  end
  if energyFraction() < work.pause then
    if perf then
      perf.pauses = perf.pauses + 1
    end
    local lastGain, lastValue, lastReport = computer.uptime(), computer.energy(), -math.huge
    while energyFraction() < work.resume do
      local now = computer.uptime()
      local value = computer.energy()
      if value > lastValue then
        lastGain = now
      end
      lastValue = value
      U.check(
        energyFraction() >= work.pause / 2,
        'Energy keeps falling; work stopped. Recharge, then Recover / Scan.'
      )
      U.check(
        now - lastGain < 30,
        'No recharge for 30 seconds; work stopped. Check power input, then Recover / Scan.'
      )
      if work.progress and now - lastReport >= 2 then
        work.progress(
          string.format(
            'Waiting for energy: %.0f%% -> %.0f%%. Esc cancels.',
            energyFraction() * 100,
            work.resume * 100
          )
        )
        lastReport = now
      end
      rest(0.25)
    end
  end
end
local function startWork(c, progress, control)
  work = {
    pause = tonumber(c.shared.energyPause) / 100,
    resume = tonumber(c.shared.energyResume) / 100,
    progress = progress,
    control = control,
  }
  local e, m = sampleEnergy()
  perf = {
    started = computer.uptime(),
    startPct = e / m,
    memory = computer.freeMemory(),
    samples = 0,
    sampleTime = 0,
    pauses = 0,
    yields = 0,
    wait = 0,
    calls = {},
  }
  tagKeys, renameTags, tagCount, renameCount = {}, {}, 0, 0
end
local paths = {
  config = '/home/assline.cfg',
  pending = '/home/assline.pending',
  cursor = '/home/assline.pending.step',
  backup = '/home/assline.last',
}
local function readRaw(path)
  if not fs.exists(path) then
    return nil
  end
  U.check(fs.size(path) <= 400000, 'File too large: ' .. path)
  local f = U.check(io.open(path, 'r'), 'Cannot open ' .. path)
  local s = f:read('*a')
  f:close()
  U.check(s, 'Cannot read ' .. path)
  return s
end
local function readFile(path)
  local s = readRaw(path)
  if not s then
    return nil
  end
  local t = serialization.unserialize(s)
  U.check(type(t) == 'table', 'Invalid file: ' .. path)
  return t
end
local function writeFile(path, t)
  local s = serialization.serialize(t)
  U.check(#s <= 400000, 'Recovery data exceeds disk/memory budget; use a smaller target interface')
  U.check(
    computer.freeMemory() > #s + 131072,
    'Not enough memory to verify saved data; use a smaller target interface'
  )
  local temp = path .. '.tmp'
  local f = U.check(io.open(temp, 'w'), 'Cannot write ' .. temp)
  local ok, err = pcall(function()
    U.check(f:write(s), 'Write failed')
    U.check(f:flush(), 'Flush failed')
  end)
  f:close()
  U.check(ok, err)
  U.check(readRaw(temp) == s, 'Saved file verification failed')
  if fs.exists(path) then
    U.check(fs.remove(path), 'Cannot replace ' .. path)
  end
  U.check(fs.rename(temp, path), 'Cannot finish saving ' .. path)
end
local validate = Config.validate
local function selectDevice(kind, prefix)
  local matches = {}
  for addr, tp in component.list(kind, true) do
    if tp == kind and (prefix == '' or addr:sub(1, #prefix) == prefix) then
      matches[#matches + 1] = addr
    end
  end
  U.check(
    #matches == 1,
    'Need one ' .. kind .. ' (found ' .. #matches .. '); set its address in Settings'
  )
  return component.proxy(matches[1])
end
local function invoke(p, name, ...)
  U.check(p[name] ~= nil, 'Missing API ' .. name .. '; check GTNH / OpenComputers version')
  gate()
  local t = computer.uptime()
  local a, b, c = p[name](...)
  record(name, computer.uptime() - t)
  return a, b, c
end
local function nbt(data, tag)
  local t = tag and invoke(data, 'decodeNBT', tag) or { __nbt_type = 'compound', __value = {} }
  U.check(
    type(t) == 'table' and t.__nbt_type == 'compound' and type(t.__value) == 'table',
    'Typed NBT support required (GTNH 2.9 Data Card)'
  )
  return t
end
local function tagKey(data, s)
  U.check(
    not U.truth(s.hasTag) or type(s.tag) == 'string',
    'NBT is hidden; enable allowItemStackNBTTags in OC config'
  )
  if not s.tag then
    return '{}'
  end
  if tagKeys[s.tag] then
    return tagKeys[s.tag]
  end
  local decoded = nbt(data, s.tag)
  local key = next(decoded.__value) and U.canonical(decoded) or '{}'
  if tagCount < 32 and #s.tag <= 2048 and #key <= 2048 then
    tagKeys[s.tag] = key
    tagCount = tagCount + 1
  end
  return key
end
local function identity(data, s)
  return s.name .. ':' .. tostring(s.damage or 0) .. ':' .. tagKey(data, s)
end
local function stack(s)
  if not U.exists(s) then
    return nil
  end
  return {
    name = s.name,
    damage = s.damage,
    size = s.size,
    amount = s.amount,
    label = s.label,
    tag = s.tag,
    hasTag = s.hasTag,
  }
end
local function stackEq(data, a, b)
  if not U.exists(a) or not U.exists(b) then
    return not U.exists(a) and not U.exists(b)
  end
  if a.name ~= b.name or a.damage ~= b.damage or a.size ~= b.size or a.amount ~= b.amount then
    return false
  end
  if a.tag == b.tag and (a.tag or (not U.truth(a.hasTag) and not U.truth(b.hasTag))) then
    return true
  end
  return identity(data, a) == identity(data, b) and a.size == b.size and a.amount == b.amount
end
-- GTNH's typed decoder emits string wrappers, but its encoder only accepts
-- bare strings (the parseWithType match has no ("string", value) case).
-- Unwrap strings recursively, including existing names/lore and nested lists.
-- Keep all other NBT type wrappers intact. Never weaken round-trip verification.
local function encodableNBT(t)
  if type(t) ~= 'table' then
    return t
  end
  if t.__nbt_type == 'string' then
    U.check(type(t.__value) == 'string', 'Invalid NBT string value')
    return t.__value
  end
  local r = {}
  for k, v in pairs(t) do
    r[k] = encodableNBT(v)
  end
  return r
end
local function renamed(data, s, name)
  local key = U.canonical({ s.tag or false, name })
  local r = stack(s)
  r.hasTag = true
  r.label = name
  if renameTags[key] then
    r.tag = renameTags[key]
    return r
  end
  local t = nbt(data, s.tag)
  local d = t.__value.display
  if not d then
    d = { __nbt_type = 'compound', __value = {} }
    t.__value.display = d
  end
  U.check(d.__nbt_type == 'compound', 'Invalid display NBT')
  d.__value.Name = { __nbt_type = 'string', __value = name }
  r.tag = U.check(invoke(data, 'encodeNBT', encodableNBT(t)), 'NBT encode failed')
  U.check(U.eq(nbt(data, r.tag), t), 'NBT encode round trip failed')
  if renameCount < 32 and #key <= 2048 and #r.tag <= 2048 then
    renameTags[key] = r.tag
    renameCount = renameCount + 1
  end
  return r
end
local function compact(p)
  if not U.exists(p) then
    return nil
  end
  local r = stack(p)
  r.isCraftable = p.isCraftable
  r.inputs = {}
  r.outputs = {}
  for _, which in ipairs({ 'inputs', 'outputs' }) do
    for k, s in pairs(p[which] or {}) do
      if U.exists(s) then
        r[which][k] = stack(s)
      end
    end
  end
  return r
end
local function patternEq(data, a, b)
  if not U.exists(a) or not U.exists(b) then
    return not U.exists(a) and not U.exists(b)
  end
  return stackEq(data, a, b)
end
local function processing(p)
  return U.exists(p) and p.inputs and p.outputs and (p.isCraftable == false or p.isCraftable == 0)
end
local sides = { down = 0, up = 1, north = 2, south = 3, west = 4, east = 5, unknown = 6 }
local function side(s)
  if type(s) == 'number' then
    return s
  end
  return U.check(sides[tostring(s):lower()], 'Unknown interface side: ' .. tostring(s))
end
local function endpoint(i, slot)
  return U.endpoint({ location = i.location, side = side(i.side) }, slot)
end
local function where(i)
  return U.where(endpoint(i))
end
local function iterate(result, callback)
  U.check(result ~= nil, 'Interface lookup failed')
  if type(result) == 'table' and not getmetatable(result) then
    for _, i in pairs(result) do
      if type(i) == 'table' and i.location then
        callback(i)
      end
    end
  else
    while true do
      gate()
      local t = computer.uptime()
      local i = result()
      record('terminal iterator', computer.uptime() - t)
      if not i then
        break
      end
      callback(i)
    end
  end
end
local function lookup(hw, name, metadata)
  local found = {}
  local result = invoke(hw.terminal, 'getInterfacesByName', name)
  if metadata then
    U.check(result and result.getAll, 'Metadata-only discovery requires getAll(false)')
    result = invoke(result, 'getAll', false)
  end
  iterate(result, function(i)
    U.check(not metadata or i.patterns == nil, 'Driver ignored metadata-only discovery')
    if i.name == name then
      found[#found + 1] = i
    end
  end)
  table.sort(found, function(a, b)
    return U.ordered(endpoint(a), endpoint(b))
  end)
  return found
end
local function unique(hw, name)
  local list = lookup(hw, name)
  U.check(#list == 1, 'Expected one interface named "' .. name .. '", found ' .. #list)
  return list[1]
end
local function current(hw, ref)
  local found
  iterate(invoke(hw.terminal, 'getInterfacesByLocation', ref.location, ref.side), function(i)
    if where(i) == where(ref) then
      U.check(not found, 'Ambiguous interface location')
      found = i
    end
  end)
  return U.check(found, 'Interface unavailable at ' .. where(ref))
end
local function direct(hw, name, slot, ...)
  if hw.buffer.side ~= 6 then
    return invoke(hw.direct, name, hw.buffer.side, slot + 1, ...)
  end
  return invoke(hw.direct, name, slot + 1, ...)
end
local function encodedPattern(data, p)
  if not U.exists(p) or not p.tag or p.isCraftable == nil or not p.inputs or not p.outputs then
    return nil
  end
  local root = nbt(data, p.tag).__value
  -- Ultimate processing patterns omit crafting; OC reads the missing flag as false.
  if
    root['in']
    and root['in'].__nbt_type == 'list'
    and root.out
    and root.out.__nbt_type == 'list'
  then
    return root
  end
end
local function donorIssue(data, p)
  local root = encodedPattern(data, p)
  if not root then
    return 'Missing encoded input/output lists'
  end
  for _, entry in ipairs({
    { 'substitute', 'Input substitution enabled' },
    { 'beSubstitute', 'Output substitution enabled' },
    { 'tunnel', 'Input-only tunnel pattern' },
    { 'InvalidPattern', 'Pattern marked invalid by AE' },
  }) do
    if root[entry[1]] and U.truth(root[entry[1]].__value) then
      return entry[2], root
    end
  end
  return nil, root
end
local function patternFingerprint(hw, p)
  if not U.exists(p) then
    return nil
  end
  U.check(type(p.tag) == 'string', 'Pattern NBT hidden')
  return U.canonical({ p.name, p.damage, p.size, invoke(hw.data, 'sha256', p.tag) })
end
local function editorCapacity(hw)
  local function valid(n)
    local ok, reason = pcall(direct, hw, 'getInterfacePattern', n - 1)
    if ok then
      return true
    end
    U.check(tostring(reason):find('invalid slot', 1, true), reason)
    return false
  end
  U.check(valid(1), 'Pattern editor has no slots')
  local low, high = 1, 2
  while high <= 512 and valid(high) do
    low = high
    high = high * 2
  end
  if high > 512 then
    U.check(not valid(513), 'Pattern editor exceeds the supported 512 slots')
    high = 513
  end
  while high - low > 1 do
    local mid = math.floor((low + high) / 2)
    if valid(mid) then
      low = mid
    else
      high = mid
    end
  end
  return low
end
local function capacity(i)
  -- The terminal does not expose capacity. User-approved assumption; the UI
  -- requires verification of fully expanded destination interfaces before Apply.
  return Config.destinationSlots
end
local function connect(c, progress, control)
  validate(c)
  startWork(c, progress, control)
  local shared = c.shared
  local hw = {
    terminal = selectDevice('me_interface_terminal', shared.terminalAddress),
    direct = selectDevice('me_interface', shared.editorAddress),
    data = selectDevice('data', shared.dataAddress),
  }
  hw.buffer = endpoint(unique(hw, shared.editor))
  nbt(hw.data, invoke(hw.data, 'encodeNBT', { __nbt_type = 'compound', __value = {} }))
  return hw
end
C.defaults = defaults
C.config = Config
C.programs = Programs
C.capacity = capacity
C.perfReport = perfReport
C.releaseWork = releaseWork

-- Source: src/10_plan.lua
local function item(s)
  return U.exists(s)
    and s.damage ~= nil
    and s.amount == nil
    and not s.name:lower():find('fluiddrop', 1, true)
    and not s.name:lower():find('fluid_drop', 1, true)
    and not s.name:lower():find('fluidpacket', 1, true)
    and not s.name:lower():find('fluid_packet', 1, true)
end
local function metadata(data, p)
  local t = nbt(data, p.tag)
  t.__value['in'] = nil
  t.__value.out = nil
  return t
end
local function safeDonor(data, p)
  if not processing(p) or not p.tag then
    return false
  end
  return donorIssue(data, p) == nil
end
local function pureRecipe(data, p, r)
  if not safeDonor(data, p) then
    return false
  end
  for _, which in ipairs({ 'inputs', 'outputs' }) do
    for index, s in pairs(p[which]) do
      if U.exists(s) and index ~= 1 then
        return false
      end
    end
  end
  local a, b = p.inputs[1], p.outputs[1]
  return item(a)
    and item(b)
    and a.size > 0
    and a.size == b.size
    and identity(data, a) == identity(data, r.input)
    and identity(data, b) == identity(data, r.output)
end
local function scan(c, progress, control)
  Config.requireProgram(c, 'assline')
  local settings = c.programs.assline
  local hw = connect(c, progress, control)
  local target = unique(hw, settings.target)
  U.check(where(target) ~= where(hw.buffer), 'Target is the pattern editor')
  local buffer = current(hw, hw.buffer)
  local p = {
    target = endpoint(target),
    buffer = hw.buffer,
    changes = {},
    recipes = {},
    errors = {},
    warnings = {},
    scanned = 0,
    skipped = 0,
    empty = {},
    protected = {},
  }
  local function problem(s)
    p.errors[#p.errors + 1] = s
  end
  local wanted = {}
  for _, slot in ipairs(U.keys(target.patterns)) do
    gate()
    local original = target.patterns[slot]
    if U.exists(original) then
      p.scanned = p.scanned + 1
      if processing(original) then
        U.check(
          type(original.tag) == 'string',
          'Pattern NBT is hidden; enable allowItemStackNBTTags'
        )
        local counts, occupied, changes = {}, {}, {}
        for _, s in pairs(original.inputs) do
          if item(s) then
            occupied[identity(hw.data, s)] = true
          end
        end
        for _, index in ipairs(U.keys(original.inputs)) do
          local s = original.inputs[index]
          if item(s) then
            local id = identity(hw.data, s)
            local n = counts[id] or 0
            counts[id] = n + 1
            if n > 0 then
              U.check(
                type(s.size) == 'number' and s.size > 0 and s.size <= 2147483647,
                'Unsupported input amount'
              )
              local output, label
              repeat
                label = U.token(settings.itemName, s.label or s.name, n)
                U.check(
                  unicode.len(label) <= 128,
                  'Generated item name is longer than 128 characters'
                )
                output = renamed(hw.data, s, label)
                if not occupied[identity(hw.data, output)] then
                  break
                end
                n = n + 1
                U.check(n <= 512, 'Cannot allocate unique item names')
              until false
              counts[id] = n + 1
              occupied[identity(hw.data, output)] = true
              changes[#changes + 1] = { index = index, before = stack(s), after = output }
              local destName = U.token(settings.renameName, s.label or s.name, n)
              local recipeKey = U.canonical({ destName, id, identity(hw.data, output) })
              if not wanted[recipeKey] then
                local r = { input = stack(s), output = output, name = destName }
                wanted[recipeKey] = r
                p.recipes[#p.recipes + 1] = r
              end
            end
          end
        end
        if #changes > 0 then
          p.changes[#p.changes + 1] = { slot = slot, original = compact(original), edits = changes }
        end
      else
        p.skipped = p.skipped + 1
      end
    end
    if progress then
      progress('Scanning pattern ' .. tostring(slot + 1))
    end
    U.check(computer.freeMemory() > 160000, 'Low memory; scan a smaller target interface')
  end
  -- Only requested names are fetched; no getAll(true) of a large ME network.
  local groups, used = {}, {}
  for _, r in ipairs(p.recipes) do
    if not groups[r.name] then
      groups[r.name] = lookup(hw, r.name)
      for _, bank in ipairs(groups[r.name]) do
        p.protected[where(bank)] = true
      end
    end
    local group = groups[r.name]
    for _, i in ipairs(group) do
      U.check(
        where(i) ~= where(target) and where(i) ~= where(hw.buffer),
        'Rename interface overlaps target or buffer'
      )
      for _, slot in ipairs(U.keys(i.patterns)) do
        if pureRecipe(hw.data, i.patterns[slot], r) then
          r.existing = endpoint(i, slot)
          break
        end
      end
      if r.existing then
        break
      end
    end
    if not r.existing then
      for _, i in ipairs(group) do
        local key = where(i)
        used[key] = used[key] or {}
        local slots = capacity(i)
        for slot = 0, slots - 1 do
          if not U.exists(i.patterns[slot]) and not used[key][slot] then
            used[key][slot] = true
            r.destination = endpoint(i, slot)
            break
          end
        end
        if r.destination then
          break
        end
      end
      if not r.destination then
        problem(
          'No verified free slot in "' .. r.name .. '" (missing, full, or capacity unavailable)'
        )
      end
    end
    if progress then
      progress('Checking ' .. r.name)
    end
  end
  for slot = 0, editorCapacity(hw) - 1 do
    local remote = buffer.patterns[slot]
    local live = direct(hw, 'getInterfacePattern', slot)
    U.check(
      patternEq(hw.data, remote, live),
      'Direct pattern editor does not match "' .. c.shared.editor .. '" at slot ' .. (slot + 1)
    )
    if not U.exists(remote) then
      p.empty[#p.empty + 1] = slot
    end
  end
  local donors = 0
  for _, bank in ipairs(lookup(hw, c.shared.donors)) do
    U.check(
      not p.protected[where(bank)]
        and where(bank) ~= where(target)
        and where(bank) ~= where(hw.buffer),
      'New pattern buffer overlaps destination or editor'
    )
    for _, slot in ipairs(U.keys(bank.patterns)) do
      local pattern = bank.patterns[slot]
      if safeDonor(hw.data, pattern) then
        donors = donors + 1
      end
    end
  end
  local n = 0
  for _, r in ipairs(p.recipes) do
    if not r.existing then
      n = n + 1
    end
  end
  p.newRecipes = n
  p.available = donors
  if donors < n then
    p.warnings[1] = 'Need '
      .. n
      .. ' disposable processing donors; have '
      .. donors
      .. '. Execution will wait for refills.'
  end
  local requirements = {}
  for name, group in pairs(groups) do
    local needed = 0
    for _, i in ipairs(group) do
      for _, pattern in pairs(i.patterns) do
        if U.exists(pattern) then
          needed = needed + 1
        end
      end
    end
    for _, recipe in ipairs(p.recipes) do
      if recipe.name == name and not recipe.existing then
        needed = needed + 1
      end
    end
    requirements[name] = needed
  end
  p.capacities = Config.capacityReport(requirements)
  if (#p.changes > 0 or n > 0) and #p.empty == 0 then
    problem('Leave one empty pattern slot in ' .. c.shared.editor .. ' for editing')
  end
  return p, hw
end
C.scan = scan

-- Source: src/20_apply.lua
-- One durable intent per moved pattern. Recovery completes only that operation;
-- another scan is required before continuing the rest of a batch.
local function rawList(data, p, which)
  local root = nbt(data, p.tag).__value
  local t = root[which == 'inputs' and 'in' or 'out']
  U.check(t and t.__nbt_type == 'list', 'Unsupported encoded pattern layout')
  return t.__value
end
local function expected(op)
  local p = compact(op.original)
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
  local final = expected(op)
  for _, which in ipairs({ 'inputs', 'outputs' }) do
    local all = {}
    for k in pairs(p[which] or {}) do
      all[k] = true
    end
    for k in pairs(op.original[which]) do
      all[k] = true
    end
    for k in pairs(final[which]) do
      all[k] = true
    end
    for k in pairs(all) do
      local a = p[which][k]
      local old = op.original[which][k]
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
  local goal = expected(op)
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
  if op.kind == 'recipe' or op.kind == 'imprint' or op.kind == 'resize' then
    -- Clearing removes an NBT list element: ALWAYS clear from the end.
    for _, which in ipairs({ 'inputs', 'outputs' }) do
      local desired = goal[which]
      local entries = rawList(hw.data, p, which)
      for index, s in ipairs(desired) do
        if not stackEq(hw.data, p[which][index], s) then
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
      if not stackEq(hw.data, p.inputs[e.index], e.after) then
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

local Planner=(function()
-- Source: maker/planner.lua
-- Pure pattern placement planner. No component, filesystem or UI calls.
-- Recipe modes provide an ordered manifest; adapters provide compact snapshots.
local M = { version = 1 }
local U = U
local copy, integer, need, sequence, encoded = U.clone, U.integer, U.check, U.sequence, U.canonical
local ref, place, ordered = U.endpoint, U.where, U.ordered
local function address(r)
  return place(r) .. ':' .. r.slot
end
local function validateSnapshot(snapshot)
  need(
    type(snapshot) == 'table' and type(snapshot.interfaces) == 'table',
    'Missing interface snapshot'
  )
  sequence(snapshot.interfaces, 'Interfaces')
  local interfaces, seen = {}, {}
  for _, i in ipairs(snapshot.interfaces) do
    need(type(i.location) == 'table', 'Missing interface location')
    for _, k in ipairs({ 'dimId', 'x', 'y', 'z' }) do
      need(integer(i.location[k]), 'Invalid location ' .. k)
    end
    need(integer(i.side) and i.side >= 0 and i.side <= 6, 'Invalid interface side')
    need(
      integer(i.capacity) and i.capacity >= 1 and i.capacity <= 512,
      'Usable capacity must be 1..512'
    )
    need(type(i.name) == 'string' and i.name ~= '', 'Missing exact interface name')
    need(
      i.role == 'destination' or i.role == 'donor' or i.role == 'workspace',
      'Invalid interface role'
    )
    local id = place(i)
    need(not seen[id], 'Overlapping interface roles or duplicate location: ' .. id)
    seen[id] = true
    need(type(i.patterns) == 'table', 'Missing pattern snapshot')
    for slot, p in pairs(i.patterns) do
      need(integer(slot) and slot >= 0, 'Invalid zero-based pattern slot')
      need(
        type(p) == 'table' and type(p.fingerprint) == 'string' and p.fingerprint ~= '',
        'Missing pattern fingerprint'
      )
      need(
        p.kind == 'crafting' or p.kind == 'processing' or p.kind == 'unknown',
        'Invalid pattern type'
      )
      need(p.recipeKey == nil or type(p.recipeKey) == 'string', 'Invalid recipe key')
      need(p.donor == nil or type(p.donor) == 'boolean', 'Invalid disposable-donor flag')
    end
    interfaces[#interfaces + 1] = i
  end
  table.sort(interfaces, ordered)
  return interfaces
end

-- Processing recipes compare multisets; crafting recipes compare exact grid
-- positions. Processing identity uses proportions across BOTH sides together.
-- Return the batch divisor too, so matching and quantity edits stay separate
-- without storing a second full ingredient signature for each pattern.
function M.recipeKey(recipe)
  need(recipe.kind == 'crafting' or recipe.kind == 'processing', 'Recipe kind must be explicit')
  local function entries(list, grid)
    need(type(list) == 'table', 'Missing recipe ingredients')
    local r = {}
    for index, s in pairs(list) do
      need(integer(index) and index >= 1 and index <= 512, 'Invalid recipe entry index')
      need(
        type(s) == 'table' and type(s.name) == 'string' and s.name ~= '',
        'Missing registry name'
      )
      need(s.type == 'item' or s.type == 'fluid', 'Ingredient type must be explicit')
      local n = s.size
      need(integer(n) and n > 0, 'Ingredient quantity must be a positive integer')
      if s.type == 'item' then
        need(integer(s.damage) and s.damage >= 0, 'Missing item damage')
      end
      need(s.tag == nil or type(s.tag) == 'string', 'NBT must be an exact encoded tag string')
      local id = encoded({ s.type, s.name, s.damage or false, s.tag or false })
      if grid then
        need(
          index <= 9 and s.type == 'item' and n == 1,
          'Crafting inputs must be individual items in a 3x3 grid'
        )
        r[index] = { id, n }
      else
        r[id] = (r[id] or 0) + n
      end
    end
    need(next(r) ~= nil, 'Empty ingredient list')
    return r
  end
  need(
    recipe.substitute == nil or type(recipe.substitute) == 'boolean',
    'Invalid substitution policy'
  )
  need(
    recipe.beSubstitute == nil or type(recipe.beSubstitute) == 'boolean',
    'Invalid output substitution policy'
  )
  local identity = {
    recipe.kind,
    entries(recipe.inputs, recipe.kind == 'crafting'),
    entries(recipe.outputs, false),
    recipe.substitute == true,
    recipe.beSubstitute == true,
  }
  local divisor = 1
  if recipe.kind == 'processing' then
    divisor = 0
    for _, list in ipairs({ identity[2], identity[3] }) do
      for _, quantity in pairs(list) do
        local a, b = divisor, quantity
        while b ~= 0 do
          a, b = b, a % b
        end
        divisor = a
      end
    end
    for _, list in ipairs({ identity[2], identity[3] }) do
      for id, quantity in pairs(list) do
        list[id] = quantity / divisor
      end
    end
  end
  return encoded(identity), divisor
end

function M.plan(request, snapshot, checkpoint)
  need(
    type(request) == 'table' and type(request.recipes) == 'table',
    'Missing ordered recipe manifest'
  )
  sequence(request.recipes, 'Recipes')
  need(#request.recipes > 0, 'Manifest contains no recipes')
  local interfaces = validateSnapshot(snapshot)
  local p = {
    version = 1,
    errors = {},
    warnings = {},
    layout = {},
    moves = {},
    creates = {},
    resizes = {},
    resizeCount = 0,
    preserved = {},
    reused = 0,
    required = { crafting = 0, processing = 0 },
    available = { crafting = 0, processing = 0 },
    donorBanks = 0,
    donorOccupied = 0,
    donorRejected = 0,
    donorReasons = {},
  }
  local problems = {}
  local function block(message)
    if not problems[message] then
      p.errors[#p.errors + 1] = message
      problems[message] = true
    end
  end
  local groups, workspace, tokens, occupied = {}, nil, {}, {}
  for _, i in ipairs(interfaces) do
    if checkpoint then
      checkpoint()
    end
    for slot in pairs(i.patterns) do
      if slot >= i.capacity then
        block('Pattern outside configured usable capacity: ' .. i.name .. ' slot ' .. slot)
      end
    end
    if i.role == 'destination' then
      local g = groups[i.name] or { slots = {}, tokens = {}, wanted = {} }
      groups[i.name] = g
      for slot = 0, i.capacity - 1 do
        local e = ref(i, slot)
        g.slots[#g.slots + 1] = e
        local pattern = i.patterns[slot]
        if pattern then
          local t = { pattern = pattern, current = e }
          tokens[#tokens + 1] = t
          g.tokens[#g.tokens + 1] = t
          occupied[address(e)] = t
        end
      end
    elseif i.role == 'donor' then
      p.donorBanks = p.donorBanks + 1
      for slot = 0, i.capacity - 1 do
        local pattern = i.patterns[slot]
        if pattern then
          p.donorOccupied = p.donorOccupied + 1
          if not pattern.donor then
            p.donorRejected = p.donorRejected + 1
            local reason = pattern.reason or 'Unsupported pattern'
            p.donorReasons[reason] = (p.donorReasons[reason] or 0) + 1
          end
        end
        if pattern and pattern.donor and p.available[pattern.kind] ~= nil then
          p.available[pattern.kind] = p.available[pattern.kind] + 1
        end
      end
    else
      for slot = 0, i.capacity - 1 do
        if not i.patterns[slot] and not workspace then
          workspace = ref(i, slot)
        end
      end
    end
  end
  local seen, groupOrder = {}, {}
  for _, r in ipairs(request.recipes) do
    if checkpoint then
      checkpoint()
    end
    need(
      type(r.key) == 'string' and r.key ~= '' and not seen[r.key],
      'Recipe keys must be unique and nonempty'
    )
    need(
      type(r.destination) == 'string' and r.destination ~= '',
      'Missing recipe destination group'
    )
    need(r.kind == 'crafting' or r.kind == 'processing', 'Invalid requested pattern type')
    seen[r.key] = true
    local g = groups[r.destination]
    if not g then
      block('No destination interfaces named ' .. r.destination)
    else
      if #g.wanted == 0 then
        groupOrder[#groupOrder + 1] = g
      end
      g.wanted[#g.wanted + 1] = r
    end
  end
  for _, g in ipairs(groupOrder) do
    if checkpoint then
      checkpoint()
    end
    for n, r in ipairs(g.wanted) do
      if checkpoint then
        checkpoint()
      end
      local match
      for _, t in ipairs(g.tokens) do
        if not t.selected and t.pattern.recipeKey == r.key and t.pattern.kind == r.kind then
          match = match or t
          if t.pattern.scale == r.scale then
            match = t
            break
          end
        end
      end
      local dest = g.slots[n]
      local entry = {
        key = r.key,
        kind = r.kind,
        group = r.destination,
        destination = dest,
        existing = match ~= nil,
        resize = match ~= nil and r.scale ~= nil and match.pattern.scale ~= r.scale,
      }
      p.layout[#p.layout + 1] = entry
      if match then
        match.selected = true
        match.goal = dest
        p.reused = p.reused + 1
        if entry.resize then
          p.resizeCount = p.resizeCount + 1
          entry.oldScale = match.pattern.scale
          entry.newScale = r.scale
          entry.fingerprint = match.pattern.fingerprint
          if not match.pattern.donor then
            block(
              'Cannot resize an existing pattern: '
                .. (match.pattern.reason or 'unsupported metadata')
            )
          end
        end
      else
        p.required[r.kind] = p.required[r.kind] + 1
      end
    end
    local n = #g.wanted
    for _, t in ipairs(g.tokens) do
      if not t.selected then
        n = n + 1
        t.goal = g.slots[n]
        p.preserved[#p.preserved + 1] =
          { from = t.current, to = t.goal, fingerprint = t.pattern.fingerprint }
      end
    end
    if n > #g.slots then
      block(
        'Insufficient capacity in '
          .. g.wanted[1].destination
          .. ': need '
          .. n
          .. ', have '
          .. #g.slots
      )
    end
  end
  for kind, count in pairs(p.available) do
    if count < p.required[kind] then
      p.warnings[#p.warnings + 1] = 'Need '
        .. p.required[kind]
        .. ' disposable '
        .. kind
        .. ' donors; have '
        .. count
        .. '. Execution will wait for refills.'
    end
  end
  local needsMoves = false
  for _, t in ipairs(tokens) do
    if t.goal and address(t.current) ~= address(t.goal) then
      needsMoves = true
    end
  end
  if
    (needsMoves or p.resizeCount > 0 or p.required.crafting + p.required.processing > 0)
    and not workspace
  then
    block('Leave an empty slot in the dedicated editing/workspace interface')
  end
  -- A blocked plan never contains executable operations.
  if #p.errors > 0 then
    return p
  end
  local function move(t, to)
    need(not occupied[address(to)], 'Planner attempted to overwrite an occupied slot')
    p.moves[#p.moves + 1] =
      { from = copy(t.current), to = copy(to), fingerprint = t.pattern.fingerprint }
    occupied[address(t.current)] = nil
    occupied[address(to)] = t
    t.current = to
  end
  while true do
    if checkpoint then
      checkpoint()
    end
    local stuck, advanced = nil, false
    for _, t in ipairs(tokens) do
      if t.goal and address(t.current) ~= address(t.goal) then
        if not occupied[address(t.goal)] then
          move(t, t.goal)
          advanced = true
        else
          stuck = stuck or t
        end
      end
    end
    if not stuck then
      break
    end
    if not advanced then
      need(not occupied[address(workspace)], 'Planner cycle did not release workspace')
      move(stuck, workspace)
    end
  end
  for _, entry in ipairs(p.layout) do
    if entry.resize then
      p.resizes[#p.resizes + 1] = {
        key = entry.key,
        to = copy(entry.destination),
        workspace = copy(workspace),
        fingerprint = entry.fingerprint,
      }
    elseif not entry.existing then
      need(not occupied[address(entry.destination)], 'New recipe destination was not cleared')
      p.creates[#p.creates + 1] = {
        key = entry.key,
        kind = entry.kind,
        to = copy(entry.destination),
        workspace = copy(workspace),
      }
    end
  end
  -- Compact baseline used by an executor to reject stale previews before writes.
  local fixed = {}
  for _, i in ipairs(interfaces) do
    if i.role ~= 'donor' then
      fixed[#fixed + 1] = i
    end
  end
  p.baseline = encoded({ snapshot.terminal, fixed, request })
  return p
end

function M.revalidate(request, snapshot, preview, checkpoint)
  local fresh = M.plan(request, snapshot, checkpoint)
  local function operations(p)
    return encoded({ p.layout, p.moves, p.creates, p.resizes, p.preserved, p.required })
  end
  need(
    #fresh.errors == 0
      and preview.baseline
      and fresh.baseline == preview.baseline
      and operations(fresh) == operations(preview),
    'Patterns, settings or manifest changed; scan again'
  )
  return fresh
end
M.sequence = sequence
return M

end)()
local Modes=(function()
-- Source: maker/modes.lua
-- Compact runtime recipe compiler. This module has no component/UI calls.
-- Eligibility uses form capabilities, production flags and rare exceptions.
local U = U
local Planner = Planner
local M = {}
local aliases = {
  rod = 'stick',
  rodLong = 'stickLong',
  gear = 'gearGt',
  gearSmall = 'gearGtSmall',
  casing = 'itemCasing',
  springLarge = 'spring',
  frameBox = 'frameGt',
  boltedCasing = 'casingBolted',
  reboltedCasing = 'casingRebolted',
}
local labels = { ingot = 'Ingot', stick = 'Rod', dust = 'Dust', wireFine = 'Fine wire' }
local function formLabel(form)
  local kind, size = form:match('^(%a+)(%d+)$')
  if kind == 'wire' or kind == 'cable' then
    return size .. 'x ' .. (kind == 'wire' and 'Wire' or 'Cable')
  end
  return labels[form] or form
end
function M.supports(data, material, form)
  form = aliases[form] or form
  return U.check(data.capabilities[material.a], 'Unknown capability set')[form] == true
end
local function registeredItem(data, item)
  local name = (data.registryNames or {})[item.name:lower()]
  if name then
    item.name = name
  end
  return item,
    name ~= nil or item.name:match('^gregtech:') ~= nil or item.name:match('^minecraft:') ~= nil
end
local function resolveForm(data, material, form)
  form = aliases[form] or form
  U.check(M.supports(data, material, form), 'Material does not support ' .. form)
  local override = (material.overrides or {})[form]
  if override then
    return U.clone(override)
  end
  local kind, size = form:match('^(wire)(%d+)$')
  if not kind then
    kind, size = form:match('^(cable)(%d+)$')
  end
  if kind then
    local offsets = { [1] = 0, [2] = 1, [4] = 2, [8] = 3, [12] = 4, [16] = 5 }
    local item = U.check(material.conductor, 'Missing conductor resolver')
    local offset = U.check(offsets[tonumber(size)], 'Invalid conductor size')
    return { name = item.name, damage = item.base + offset + (kind == 'cable' and 6 or 0) }
  end
  local pipe, variant = form:match('^(pipeFluid)(.+)$')
  if not pipe then
    pipe, variant = form:match('^(pipeItemRestrictive)(.+)$')
  end
  if not pipe then
    pipe, variant = form:match('^(pipeItem)(.+)$')
  end
  if pipe then
    local offsets =
      { Tiny = 0, Small = 1, Medium = 2, Large = 3, Huge = 4, Quadruple = 5, Nonuple = 6 }
    local item = U.check(material[pipe], 'Missing pipe resolver')
    return { name = item.name, damage = item.base + U.check(offsets[variant], 'Invalid pipe size') }
  end
  local family = U.check(data.families[material.family], 'Unknown resolver family')
  local item = U.check(family[form], 'Missing form resolver')
  if item.template then
    return { name = item.template:gsub('%%s', material.dsf), damage = 0 }
  end
  U.check(U.integer(material.dsf), 'Material has no metadata suffix')
  return { name = item.name, damage = item.prefix + material.dsf }
end
function M.resolve(data, material, form)
  local item = registeredItem(data, resolveForm(data, material, form))
  return item
end
function M.eligible(data, material, rule)
  if (material.deny or {})[rule.id] then
    return false
  end
  if rule.mode == 'coating' then
    if material.coating ~= rule.coating then
      return false
    end
  elseif not (data.production[material.p] or {})[rule.process] then
    return false
  end
  for _, form in ipairs(rule.requires) do
    if not M.supports(data, material, form) then
      return false
    end
  end
  return true
end
function M.compile(data, mode, options, checkpoint)
  options = U.clone(options or {})
  local multiplier = options.multiplier or 1
  U.check(
    U.integer(multiplier) and multiplier > 0,
    'Pattern multiplier must be a positive whole number'
  )
  local polymer = options.polymer or (options.pvc == false and 'none' or 'pvcSmall')
  U.check(
    ({ pvc = true, pvcSmall = true, pdms = true, pdmsSmall = true, none = true })[polymer],
    'Invalid insulation polymer'
  )
  if mode == 'coating' then
    options.pvc = polymer ~= 'none'
    options.pdms = polymer ~= 'none'
  end
  U.check(data.version == 2, 'Unsupported material matrix')
  U.check(mode == 'wiremill' or mode == 'coating', 'Mode has no verified recipe rules yet')
  local manifest = {
    version = 1,
    source = U.clone(data.source),
    policy = {
      mode = mode,
      polymer = polymer,
      pps = options.pps ~= false,
      sources = U.clone(options.sources),
      multiplier = multiplier,
    },
    recipes = {},
  }
  local seen, unresolved = {}, {}
  manifest.unresolved = {}
  for _, material in ipairs(data.materials) do
    if checkpoint then
      checkpoint()
    end
    for _, rule in ipairs(data.rules) do
      if
        rule.mode == mode
        and (not options.forms or options.forms[rule.outputs[1].f])
        and (not rule.polymer or rule.polymer == (polymer == 'none' and 'pvcSmall' or polymer))
        and (not options.sources or options.sources[rule.outputs[1].f] == rule.inputs[1].f)
        and M.eligible(data, material, rule)
      then
        local function resolve(e, stocked)
          local item
          if e.f then
            item = M.resolve(data, material, e.f)
            item.label = material.name .. ' ' .. formLabel(e.f)
          else
            item = U.clone(U.check(data.items[e.i], 'Unknown shared item'))
          end
          if item.option and options[item.option] == false and not stocked then
            return nil
          end
          item.option = nil
          item.type = 'item'
          item.size = e.n * (stocked and 1 or multiplier)
          U.check(
            U.integer(item.size) and item.size > 0,
            'Pattern multiplier exceeds the supported ingredient quantity'
          )
          -- Oracle IDs are normalized to lower case. GT/Minecraft families above
          -- have known spelling; other families still need a registry resolver.
          local registered
          item, registered = registeredItem(data, item)
          if not stocked and not registered and not unresolved[item.name] then
            unresolved[item.name] = true
            manifest.unresolved[#manifest.unresolved + 1] = item.name
          end
          return item
        end
        local out = rule.outputs[1]
        local label = formLabel(out.f)
        local source = rule.inputs[1].f
        local route = mode == 'wiremill' and (' / from ' .. (labels[source] or source)) or ''
        local recipe = {
          kind = 'processing',
          material = material.name,
          outputForm = out.f,
          outputLabel = label,
          inputs = {},
          outputs = {},
          label = material.name .. ' / ' .. label .. route,
          stock = {},
        }
        for _, which in ipairs({ 'inputs', 'outputs' }) do
          for _, e in ipairs(rule[which]) do
            local item = resolve(e)
            if item then
              recipe[which][#recipe[which] + 1] = item
            else
              recipe.stock[#recipe.stock + 1] = resolve(e, true)
            end
          end
        end
        for _, e in ipairs(rule.stock or {}) do
          recipe.stock[#recipe.stock + 1] = e.fluid and U.clone(e) or resolve(e, true)
        end
        U.check(#recipe.inputs > 0 and #recipe.outputs > 0, 'Rule contains no consumed solids')
        local key = Planner.recipeKey(recipe)
        if not seen[key] then
          manifest.recipes[#manifest.recipes + 1] = recipe
          seen[key] = recipe
        elseif U.canonical(seen[key].stock) ~= U.canonical(recipe.stock) then
          local existing = seen[key]
          existing.stockAlternatives = existing.stockAlternatives or {}
          existing.stockAlternatives[#existing.stockAlternatives + 1] = recipe.stock
        end
      end
    end
  end
  U.check(#manifest.recipes > 0, 'No verified recipes for this mode')
  return manifest
end
return M

end)()
-- Source: maker/scan.lua
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
local function patternRecipe(p, root)
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
        U.check(not U.truth(s.hasTag) or type(s.tag) == 'string', 'Ingredient NBT hidden')
        r[which][index] = {
          type = s.damage ~= nil and s.amount == nil and 'item' or 'fluid',
          name = s.name,
          damage = s.damage,
          size = s.amount or s.size,
          tag = s.tag,
        }
      end
    end
  end
  return r
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
    return routing.destinations and routing.destinations[recipe.outputForm] or routing.destination
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
          if root then
            local r = patternRecipe(p, root)
            value.kind = r.kind
            local valid, key, scale = pcall(recipeKey, hw.data, r)
            if valid then
              value.recipeKey = key
              value.scale = scale
            end
            value.donor = value.reason == nil
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
  return plan, snapshot, request, labels
end
local function previewRows(plan, manifest, labels)
  local rows, add = U.rows()
  local details = {}
  local function ingredients(list)
    local out = {}
    for _, s in ipairs(list) do
      out[#out + 1] = s.size .. ' x ' .. (s.label or s.name)
    end
    return table.concat(out, ', ')
  end
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
  add('')
  if plan.resizeCount > 0 then
    add(plan.resizeCount .. ' reused patterns will be resized to the configured batch.', 'yellow')
    add('')
  end
  local group, bank, material
  for _, r in ipairs(plan.layout) do
    local recipe = details[r.key]
    if group ~= r.group then
      group = r.group
      bank = nil
      material = nil
      add('')
      add('DESTINATION: ' .. tostring(group), 'blue')
    end
    local location = r.destination and where(r.destination)
    if location and bank ~= location then
      bank = location
      add('Interface: ' .. U.locationText(r.destination), 'muted')
    end
    if material ~= (recipe.material or recipe.label) then
      material = recipe.material or recipe.label
      add('')
      add(material, 'blue')
    end
    add(
      (r.resize and 'RESIZE  ' or r.existing and 'REUSE   ' or 'CREATE  ')
        .. (recipe.outputLabel or recipe.outputForm or '')
        .. (r.destination and ('   slot ' .. r.destination.slot) or '   needs space'),
      r.existing and not r.resize and 'green' or 'yellow'
    )
    if r.resize then
      add('  Multiply current quantities by ' .. r.newScale .. ' / ' .. r.oldScale, 'muted')
    end
    add('  ' .. ingredients(recipe.inputs))
    add('  -> ' .. ingredients(recipe.outputs), 'green')
    add('')
  end
  return rows
end
local function previewReport(plan, manifest, labels)
  local lines = {}
  for _, r in ipairs(previewRows(plan, manifest, labels)) do
    lines[#lines + 1] = r[1]
  end
  for _, err in ipairs(plan.errors) do
    lines[#lines + 1] = 'BLOCKED: ' .. err
  end
  for _, warning in ipairs(plan.warnings) do
    lines[#lines + 1] = 'NOTE: ' .. warning
  end
  return table.concat(lines, '\n') .. '\n'
end

C.maker = {
  planner = Planner,
  scan = scanManifest,
  report = previewReport,
  rows = previewRows,
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
  end
  return routing,
    {
      polymer = values.polymer,
      multiplier = tonumber(values.multiplier),
      pps = values.pps ~= 'off',
      forms = forms,
      sources = id == 'wiremill' and { wire1 = values.wireSource, wireFine = values.fineSource }
        or nil,
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
    local name = routing.destinations and routing.destinations[recipe.outputForm]
      or routing.destination
    groups[name] = (groups[name] or 0) + 1
  end
  local banks = {}
  for _, i in ipairs(snapshot.interfaces) do
    banks[where(i)] = i.name
  end
  for _, entry in ipairs(plan.preserved) do
    local name = banks[where(entry.from)]
    groups[name] = groups[name] + 1
  end
  plan.capacities = Config.capacityReport(groups)
  local report = previewReport(plan, manifest, labels)
  for _, g in ipairs(plan.capacities) do
    report = string.format(
      '%s: %d total slots needed; at least %d fully expanded interface(s).\n',
      g.name,
      g.patterns,
      g.interfaces
    ) .. report
  end
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
  U.check(
    matches(current(hw, op.destination).patterns[op.destination.slot]),
    'Sorted pattern read-back failed'
  )
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
  for n = cursor.index, #op.moves do
    local move = op.moves[n]
    C.maker.finishMove(
      hw,
      { source = move.from, destination = move.to, fingerprint = move.fingerprint }
    )
    writeFile(paths.cursor, { id = op.id, index = n + 1 })
    if progress then
      progress('Sorted pattern ' .. n .. ' / ' .. #op.moves)
    end
  end
end

function C.maker.apply(c, id, plan, manifest, progress, control)
  U.check(not fs.exists(paths.pending), 'Use Recover before executing another preview')
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
    -- pattern in the editor; Recover must finish the cycle before a new scan.
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
        U.check(s.type == 'item', 'Only solid ingredients are supported')
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
function C.runner.preview(c, id, progress, control)
  Config.requireProgram(c, id)
  local preview = { id = id, configKey = U.canonical(c) }
  if id == 'assline' then
    preview.plan = scan(c, progress, control)
  else
    preview.plan, preview.report, preview.manifest = C.maker.preview(c, id, progress, control)
  end
  return preview
end
function C.runner.execute(c, preview, progress, control)
  U.check(preview and preview.configKey == U.canonical(c), 'Settings changed; build a new preview')
  Config.requireProgram(c, preview.id)
  if preview.id == 'assline' then
    apply(c, preview.plan, progress, control)
  else
    C.maker.apply(c, preview.id, preview.plan, preview.manifest, progress, control)
  end
end

-- Source: src/30_ui.lua
local function runUI()
  local gpu = component.gpu
  U.check(gpu, 'GPU required')
  local term, keyboard = require('term'), require('keyboard')
  local oldW, oldH = gpu.getResolution()
  local oldFG, oldBG = gpu.getForeground(), gpu.getBackground()
  local maxW, maxH = gpu.maxResolution()
  U.check(maxW >= 160 and maxH >= 50, 'Use a tier 3 GPU and screen with 160x50 resolution')
  local w, h = 160, 50
  local colors = {
    bg = 0x101A26,
    panel = 0x1A2A3C,
    text = 0xDCE6EF,
    muted = 0x8297AB,
    blue = 0x5AC8FA,
    green = 0x72D69A,
    yellow = 0xFFD277,
    red = 0xFF8585,
    button = 0x27465E,
    selected = 0x246B47,
  }
  local state = {
    page = 'programs',
    settings = 'shared',
    selected = nil,
    section = 'changes',
    offset = 0,
    status = 'Choose a program, then Preview selected. Configure shared interfaces in Settings.',
    tone = 'muted',
    running = true,
  }
  local buttons, paintCache, paintKey, edit = {}, {}, nil, nil
  local buttonWidths, scrollbar = {}, nil
  local contentKey, contentRows
  local draw, handle, action, commitEdit, navigate
  local function text(x, y, s, width, tone, bg)
    width = math.min(width or w - x + 1, w - x + 1)
    if width < 1 then
      return
    end
    s = unicode.sub(tostring(s or ''):gsub('\194\167.', ''):gsub('[%c]', ' '), 1, width)
    local key = x .. ':' .. y
    local value = width .. ':' .. s .. ':' .. tostring(tone) .. ':' .. tostring(bg)
    if paintCache[key] == value then
      return
    end
    paintCache[key] = value
    gpu.setForeground(colors[tone or 'text'])
    gpu.setBackground(colors[bg or 'bg'])
    gpu.set(x, y, s .. string.rep(' ', math.max(0, width - unicode.wlen(s))))
  end
  local function button(x, y, label, callback, enabled, selected)
    local content = '[ ' .. label .. ' ]'
    local length = unicode.wlen(content)
    local key = x .. ':' .. y
    local previous = buttonWidths[key]
    if previous and previous ~= length then
      text(x, y, '', math.max(previous, length))
    end
    buttonWidths[key] = length
    text(
      x,
      y,
      content,
      length,
      enabled == false and 'muted' or 'text',
      selected and enabled ~= false and 'selected' or 'button'
    )
    if enabled ~= false then
      buttons[#buttons + 1] = { x = x, y = y, w = length, action = callback }
    end
    return x + length + 2
  end
  local function nav(y, label, selected, callback, enabled)
    text(
      3,
      y,
      (selected and '> ' or '  ') .. label,
      26,
      selected and 'blue' or 'text',
      selected and 'panel' or 'bg'
    )
    if enabled ~= false then
      buttons[#buttons + 1] = { x = 3, y = y, w = 26, action = callback }
    end
  end
  local function status(message, tone)
    state.status = message
    state.tone = tone or 'muted'
  end
  local function invalidate()
    state.preview = nil
    state.verified = false
  end
  local function saveConfig(value)
    Config.validate(value)
    writeFile(paths.config, value)
    cfg = value
    invalidate()
  end
  local function fields()
    return state.settings == 'shared' and Config.fields or Programs.byId[state.settings].fields
  end
  local function values()
    return Config.values(cfg, state.settings)
  end
  commitEdit = function()
    if not edit then
      return
    end
    local trial = U.clone(cfg)
    Config.values(trial, edit.section)[edit.key] = U.trim(edit.value)
    saveConfig(trial)
    edit = nil
    status('Settings saved. Choose a program to build a new preview.', 'green')
  end
  navigate = function(page, section)
    commitEdit()
    state.page = page
    state.offset = 0
    state.scrollDrag = nil
    if section then
      state.settings = section
    end
    if page == 'history' then
      action('history')
    end
  end
  local function editorRow(x, y, width, f)
    local value = values()[f.key]
    local first, cursor = 1, nil
    if edit and edit.key == f.key and edit.section == state.settings then
      first = math.max(1, edit.cursor - width + 3)
      cursor = edit.cursor
      value = unicode.sub(edit.value, first, edit.cursor - 1)
        .. '|'
        .. unicode.sub(edit.value, edit.cursor)
      text(x, y, value, width, edit.selectAll and 'yellow' or 'blue', 'panel')
    else
      text(x, y, value == '' and '(not configured)' or value, width, 'text', 'panel')
    end
    if state.busy then
      return
    end
    buttons[#buttons + 1] = {
      x = x,
      y = y,
      w = width,
      editKey = f.key,
      section = state.settings,
      action = function(clickX)
        local at = first + clickX - x
        if cursor and at > cursor then
          at = at - 1
        end
        if not edit then
          edit = { section = state.settings, key = f.key, value = values()[f.key] }
        end
        edit.cursor = math.max(1, math.min(at, unicode.len(edit.value) + 1))
        edit.selectAll = false
      end,
    }
  end
  local function history()
    local f = io.open('/home/assline-perf.log', 'r')
    local groups = {}
    if f then
      f:seek('set', math.max(0, fs.size('/home/assline-perf.log') - 16384))
      local raw = f:read('*a') or ''
      f:close()
      for block in raw:gmatch('uptime=[^\n]*\n.-\n\n') do
        groups[#groups + 1] = block
      end
      if #groups == 0 or raw:sub(-2) ~= '\n\n' then
        local last = raw:match('.*\n(uptime=.*)') or (raw:match('^uptime=') and raw)
        if last then
          groups[#groups + 1] = last
        end
      end
    end
    state.history = {}
    for n = #groups, 1, -1 do
      for line in groups[n]:gmatch('[^\n]+') do
        state.history[#state.history + 1] = line
      end
      state.history[#state.history + 1] = ''
    end
  end
  local function description(s)
    return tostring(s.size or '?') .. ' x ' .. tostring(s.label or s.name)
  end
  local function lines()
    local rows, add = U.rows()
    local preview = state.preview
    local p = preview and preview.plan
    if state.page == 'preview' and state.error then
      add('LAST ERROR', 'red')
      add(state.error, 'red')
      add('')
    end
    if state.page == 'history' then
      add('RECENT OPERATIONS (newest first)', 'blue')
      add('/home/assline-perf.log; most recent 16 KB.', 'muted')
      add('')
      for _, line in ipairs(state.history or {}) do
        add(line)
      end
      if not state.history or #state.history == 0 then
        add('No operations recorded yet.', 'muted')
      end
    elseif state.page == 'help' then
      add('SHARED SETUP', 'blue')
      add('Set the pattern editor and new pattern buffer in Settings > Shared interfaces.')
      add('The editor is connected directly to OC. Buffer banks are found by exact terminal name.')
      add('Every matching buffer is included. Use disposable encoded patterns; keep machines idle.')
      add('Enable allowItemStackNBTTags. Use a tier 1+ Data Card and an Internet Card for updates.')
      add('')
      add('RUN A PROGRAM', 'blue')
      add('Run program opens the chooser. Select a program and press Preview selected.')
      add('Review changes, required interfaces, existing-pattern sorting and donors.')
      add('Verify destination interfaces have all 36 slots available, then Execute preview.')
      add('Assembly line, insulator and wiremill share settings, editor and recovery.')
      add('Wire combining and bending have settings reserved for their upcoming recipe rules.')
      add('')
      add('SETTINGS AND RECOVERY', 'blue')
      add('Fields save when accepted or when you navigate away. Esc cancels only the active edit.')
      add('After interruption, leave patterns in place and Recover; then build a new preview.')
      add(
        'History retains timing and memory reports. Updates preserve configuration and recovery files.'
      )
    elseif not p then
      add(
        state.busy and 'Program running. See progress below.'
          or 'Choose a program to build a preview.',
        'muted'
      )
    elseif state.section == 'details' and preview.manifest then
      add('BUFFER DISCOVERY', 'blue')
      add('Terminal lookup: "' .. cfg.shared.donors .. '"')
      add(p.donorBanks .. ' matching interfaces; ' .. p.donorOccupied .. ' occupied pattern slots.')
      add(
        p.available.processing
          .. ' usable processing; '
          .. p.available.crafting
          .. ' usable crafting; '
          .. p.donorRejected
          .. ' rejected.'
      )
      for _, reason in ipairs(U.keys(p.donorReasons or {})) do
        add(p.donorReasons[reason] .. ': ' .. reason, 'yellow')
      end
      add('')
      add('SORTING', 'blue')
      add(
        #p.moves
          .. ' moves before creating patterns; '
          .. #p.preserved
          .. ' unrelated/duplicate patterns preserved.'
      )
      for _, move in ipairs(p.moves) do
        add(
          U.locationText(move.from)
            .. ' slot '
            .. move.from.slot
            .. ' -> '
            .. U.locationText(move.to)
            .. ' slot '
            .. move.to.slot,
          'muted'
        )
      end
      add('')
      add('SOURCE COVERAGE', 'blue')
      add('Recipes outside the supported material forms (whole imported dataset):', 'muted')
      for _, label in ipairs(U.keys(preview.manifest.source.excludedOutputs or {})) do
        add(label .. ': ' .. preview.manifest.source.excludedOutputs[label] .. ' source recipes')
      end
      for _, name in ipairs(preview.manifest.unresolved or {}) do
        add('Registry spelling still unresolved: ' .. name, 'red')
      end
    elseif state.section == 'capacity' then
      add('DESTINATION SPACE', 'blue')
      add('Assuming 36 usable slots per destination interface.', 'yellow')
      add('')
      for _, g in ipairs(p.capacities or {}) do
        add(g.name, 'blue')
        add(
          g.patterns
            .. ' total slots needed; at least '
            .. g.interfaces
            .. ' fully expanded interface(s).'
        )
      end
      add('')
      add('Every matching interface is included, ordered by location.', 'muted')
      add('Existing unrelated patterns count toward required space.', 'muted')
      for _, err in ipairs(p.errors) do
        add('BLOCKED: ' .. err, 'red')
      end
    elseif preview.id ~= 'assline' then
      for _, row in ipairs(C.maker.rows(p, preview.manifest)) do
        add(row[1], row[2])
      end
    elseif state.section == 'recipes' then
      for _, r in ipairs(p.recipes) do
        add((r.existing and 'REUSE  ' or 'CREATE ') .. r.name, r.existing and 'green' or 'yellow')
        add('  ' .. description(r.input) .. ' -> ' .. description(r.output))
        local e = r.existing or r.destination
        if e then
          add('  Slot ' .. (e.slot + 1) .. ' at ' .. U.locationText(e), 'muted')
        end
      end
      if #p.recipes == 0 then
        add('No rename recipes required.', 'green')
      end
    else
      for _, v in ipairs(p.changes) do
        local out = v.original.outputs[1]
        add(
          'PATTERN ' .. (v.slot + 1) .. '  ' .. (out and description(out) or '(no first output)'),
          'blue'
        )
        for _, e in ipairs(v.edits) do
          add('  Input ' .. e.index .. ': ' .. description(e.before))
          add('        -> ' .. description(e.after), 'green')
        end
      end
      if #p.changes == 0 then
        add('No duplicate item inputs found.', 'green')
      end
    end
    return rows
  end
  local function scrollRows(x, y, width, room)
    local key = state.page
      .. state.section
      .. tostring(state.preview)
      .. tostring(state.history)
      .. tostring(state.error)
      .. width
    if key ~= contentKey then
      contentKey = key
      contentRows = {}
      for _, r in ipairs(lines()) do
        local remaining = r[1]
        while unicode.len(remaining) > width do
          local prefix = unicode.sub(remaining, 1, width)
          local at = prefix:match('^.*()%s')
          local count = at and unicode.len(prefix:sub(1, at - 1)) or width
          if count == 0 then
            count = width
          end
          contentRows[#contentRows + 1] = { unicode.sub(remaining, 1, count), r[2] }
          remaining = unicode.sub(remaining, count + 1):gsub('^%s+', '')
        end
        contentRows[#contentRows + 1] = { remaining, r[2] }
      end
    end
    local rows = contentRows
    state.offset = math.max(0, math.min(state.offset, math.max(0, #rows - room)))
    for n = 1, room do
      local r = rows[state.offset + n]
      text(x, y + n - 1, r and r[1] or '', width, r and r[2] or 'text')
    end
    local maximum = math.max(0, #rows - room)
    local thumb = maximum == 0 and room or math.max(1, math.floor(room * room / #rows))
    local top = y
      + (maximum == 0 and 0 or math.floor(state.offset / maximum * (room - thumb) + 0.5))
    scrollbar =
      { x = x + width + 1, y = y, room = room, maximum = maximum, thumb = thumb, top = top }
    for row = y, y + room - 1 do
      text(scrollbar.x, row, '', 2, 'text', row >= top and row < top + thumb and 'blue' or 'panel')
    end
    text(
      x,
      44,
      'Rows '
        .. math.min(#rows, state.offset + 1)
        .. '-'
        .. math.min(#rows, state.offset + room)
        .. ' / '
        .. #rows
        .. '  (wheel / PgUp / PgDn)',
      width,
      'muted'
    )
  end
  local function executable()
    local preview = state.preview
    if not preview or state.busy or fs.exists(paths.pending) or not state.verified then
      return false
    end
    local p = preview.plan
    if #p.errors > 0 or (preview.manifest and #preview.manifest.unresolved > 0) then
      return false
    end
    return preview.id == 'assline' and #p.changes > 0
      or preview.id ~= 'assline' and (#p.moves + #p.creates) > 0
  end
  draw = function()
    local key = state.page
      .. state.settings
      .. tostring(state.selected)
      .. state.section
      .. tostring(state.preview)
      .. tostring(state.busy)
      .. tostring(state.verified)
      .. tostring(fs.exists(paths.pending))
    if key ~= paintKey then
      gpu.setBackground(colors.bg)
      gpu.fill(1, 1, w, h, ' ')
      paintCache = {}
      buttonWidths = {}
      paintKey = key
    end
    buttons = {}
    scrollbar = nil
    text(3, 2, 'AE2 / GTNH PATTERN MANAGER', 95, 'blue')
    text(
      111,
      2,
      string.format(
        '%.0f%% energy  |  %d KB free',
        energyFraction() * 100,
        math.floor(computer.freeMemory() / 1024)
      ),
      47,
      'muted'
    )
    text(3, 4, string.rep('-', 155), 155, 'muted')
    nav(7, 'Programs', state.page == 'programs', function()
      navigate('programs')
    end, not state.busy)
    nav(10, 'Settings', state.page == 'settings', function()
      navigate('settings')
    end, not state.busy)
    nav(13, 'History', state.page == 'history', function()
      navigate('history')
    end)
    nav(16, 'Help', state.page == 'help', function()
      navigate('help')
    end)
    if state.preview then
      nav(19, 'Current preview', state.page == 'preview', function()
        navigate('preview')
      end)
    end
    if state.page == 'settings' then
      text(3, 22, 'SETTINGS SECTIONS', 26, 'muted')
      nav(25, 'Shared interfaces', state.settings == 'shared', function()
        navigate('settings', 'shared')
      end)
      for n, p in ipairs(Programs.list) do
        local id = p.id
        nav(25 + n * 3, p.name, state.settings == id, function()
          navigate('settings', id)
        end)
      end
      local name = state.settings == 'shared' and 'Shared interfaces'
        or Programs.byId[state.settings].name
      text(34, 7, 'SETTINGS / ' .. name, 124, 'blue')
      text(34, 8, 'Changes save when you accept a field or navigate away.', 124, 'muted')
      for n, f in ipairs(fields()) do
        local y = 11 + (n - 1) * 4
        text(34, y, f.label, 124, 'blue')
        if f.choices then
          local x = 34
          for _, option in ipairs(f.choices) do
            local key, value = f.key, option[1]
            x = button(x, y + 1, option[2], function()
              commitEdit()
              local trial = U.clone(cfg)
              Config.values(trial, state.settings)[key] = value
              saveConfig(trial)
              status('Settings saved.', 'green')
            end, true, values()[key] == value)
          end
        elseif f.kind == 'toggle' then
          button(34, y + 1, values()[f.key] == 'on' and 'On' or 'Off', function()
            commitEdit()
            local trial = U.clone(cfg)
            local v = Config.values(trial, state.settings)
            v[f.key] = v[f.key] == 'on' and 'off' or 'on'
            saveConfig(trial)
            status('Settings saved.', 'green')
          end, true, values()[f.key] == 'on')
        else
          editorRow(34, y + 1, 124, f)
        end
        text(34, y + 2, f.help, 124, 'muted')
      end
      local x = button(34, 47, 'Save settings', function()
        action('save')
      end)
      button(x, 47, 'Run program', function()
        navigate('programs')
      end)
    elseif state.page == 'programs' then
      text(34, 7, 'RUN A PROGRAM', 124, 'blue')
      text(
        34,
        8,
        'Select what to do. Preview selected builds a plan without changing patterns.',
        124,
        'muted'
      )
      for n, p in ipairs(Programs.list) do
        local y = 11 + (n - 1) * 6
        local id = p.id
        button(34, y, (state.selected == id and '* ' or '') .. p.name, function()
          commitEdit()
          state.selected = id
        end)
        text(38, y + 1, p.description, 120, 'text')
        text(
          38,
          y + 2,
          p.unavailable or 'Preview and execute',
          120,
          p.unavailable and 'muted' or 'green'
        )
      end
      local selected = state.selected and Programs.byId[state.selected]
      local x = button(34, 47, 'Preview selected', function()
        action('preview')
      end, selected ~= nil and not selected.unavailable and not fs.exists(paths.pending))
      button(x, 47, 'Program settings', function()
        navigate('settings', state.selected)
      end, selected ~= nil)
    elseif state.page == 'preview' then
      local preview = state.preview
      local p = preview and preview.plan
      local current = preview and preview.id or state.selected
      text(34, 7, 'PREVIEW / ' .. (current and Programs.byId[current].name or ''), 124, 'blue')
      local x = 34
      local tabs = preview
          and preview.id == 'assline'
          and {
            { 'changes', 'Input changes' },
            { 'recipes', 'Rename recipes' },
            {
              'capacity',
              'Capacity',
            },
          }
        or { { 'changes', 'Patterns' }, { 'capacity', 'Capacity' }, { 'details', 'Details' } }
      for _, tab in ipairs(tabs) do
        local section = tab[1]
        x = button(x, 9, (state.section == section and '* ' or '') .. tab[2], function()
          state.section = section
          state.offset = 0
        end)
      end
      scrollRows(34, 12, 74, 31)
      text(113, 12, 'WHAT WILL HAPPEN', 45, 'blue')
      if p then
        if preview.id == 'assline' then
          text(113, 14, p.scanned .. ' patterns scanned', 45)
          text(113, 15, #p.changes .. ' patterns to update', 45, 'green')
          text(113, 16, p.newRecipes .. ' donor patterns needed', 45, 'yellow')
          text(113, 17, (#p.recipes - p.newRecipes) .. ' rename recipes reused', 45, 'green')
          text(113, 18, p.available .. ' processing donors available', 45, 'muted')
        else
          text(113, 14, p.reused .. ' existing patterns reused', 45, 'green')
          text(113, 15, p.required.processing .. ' new patterns needed', 45, 'yellow')
          text(113, 16, #p.moves .. ' sorting moves first', 45)
          text(113, 17, p.available.processing .. ' processing donors available', 45, 'muted')
          text(113, 18, p.donorBanks .. ' buffer interfaces found via terminal', 45, 'muted')
          text(113, 19, p.donorRejected .. ' occupied buffer slots unusable', 45, 'muted')
          text(
            113,
            20,
            p.resizeCount .. ' reused patterns to resize',
            45,
            p.resizeCount > 0 and 'yellow' or 'muted'
          )
        end
        local y = 21
        text(
          113,
          y,
          #p.errors == 0 and 'Ready to execute' or 'BLOCKED: ' .. #p.errors .. ' issue(s)',
          45,
          #p.errors == 0 and 'green' or 'red'
        )
        for _, err in ipairs(p.errors) do
          for pos = 1, unicode.len(err), 45 do
            if y < 32 then
              y = y + 1
              text(113, y, unicode.sub(err, pos, pos + 44), 45, 'red')
            end
          end
        end
        for _, warning in ipairs(p.warnings or {}) do
          for pos = 1, unicode.len(warning), 45 do
            if y < 32 then
              y = y + 1
              text(113, y, unicode.sub(warning, pos, pos + 44), 45, 'yellow')
            end
          end
        end
        if preview.manifest and #preview.manifest.unresolved > 0 then
          text(113, 34, 'Registry names need verification.', 45, 'red')
        end
        text(113, 36, 'Destination assumption: 36 slots each.', 45, 'yellow')
        text(113, 37, 'Verify expanded interfaces in the game.', 45, 'muted')
        button(113, 39, state.verified and '36 slots verified' or 'Verify 36 slots', function()
          state.verified = not state.verified
        end, not state.busy)
      end
      local x = button(34, 47, 'Scan', function()
        action('preview')
      end, not state.busy and not fs.exists(paths.pending))
      x = button(x, 47, 'Execute preview', function()
        action('execute')
      end, executable())
      x = button(x, 47, 'Program settings', function()
        navigate('settings', preview.id)
      end, not state.busy and preview ~= nil)
      button(x, 47, 'Run program', function()
        navigate('programs')
      end, not state.busy)
    else
      text(34, 7, state.page == 'history' and 'HISTORY' or 'HELP', 124, 'blue')
      scrollRows(34, 12, 124, 31)
      button(34, 47, 'Run program', function()
        navigate('programs')
      end, not state.busy)
    end
    if state.busy then
      button(113, 47, 'Cancel', function()
        state.cancelled = true
      end)
    else
      button(135, 47, 'Recover', function()
        action('recover')
      end, fs.exists(paths.pending))
    end
    button(151, 47, 'Quit', function()
      commitEdit()
      state.cancelled = true
      state.running = false
    end)
    text(3, 46, string.rep('-', 155), 155, 'muted')
    text(3, 49, state.status, 155, state.tone)
    if fs.exists(paths.pending) then
      text(3, 43, 'Pending operation: Recover', 26, 'red')
    end
  end
  local lastProgress, lastPoll = 0, -math.huge
  local function progress(message, immediate)
    if immediate or computer.uptime() - lastProgress >= 1 then
      status(message, 'yellow')
      text(3, 49, message, 155, 'yellow')
      lastProgress = computer.uptime()
    end
  end
  local function control(delay)
    local pulled
    if delay > 0 or computer.uptime() - lastPoll >= 0.1 then
      draw()
      pulled = { event.pull(delay) }
      handle(pulled)
      lastPoll = computer.uptime()
    end
    U.check(
      not state.cancelled,
      'Work cancelled. Use Recover if an operation is pending; otherwise preview again.'
    )
    return pulled
  end
  action = function(name)
    commitEdit()
    local isWork = name == 'preview' or name == 'execute' or name == 'recover'
    U.check(not isWork or not state.busy, 'Work already running')
    if name == 'execute' then
      U.check(executable(), 'Review and verify the preview first')
    end
    if isWork then
      state.error = nil
      state.busy = true
      state.cancelled = false
      lastPoll = computer.uptime()
      status('Working: ' .. name .. ' (Esc cancels)', 'yellow')
    end
    local ok, why = pcall(function()
      if name == 'history' then
        history()
      elseif name == 'save' then
        Config.validate(cfg)
        writeFile(paths.config, cfg)
        status('Settings saved.', 'green')
      elseif name == 'preview' then
        U.check(not fs.exists(paths.pending), 'Recover the pending operation before previewing')
        local id = state.page == 'preview' and state.preview and state.preview.id or state.selected
        U.check(id, 'Choose a program first')
        invalidate()
        state.page = 'preview'
        state.section = 'changes'
        state.offset = 0
        state.preview = C.runner.preview(cfg, id, progress, control)
        status(
          'Preview ready. Review the plan and verify destination capacity before Execute preview.',
          'green'
        )
      elseif name == 'execute' then
        local preview = state.preview
        state.preview = nil
        C.runner.execute(cfg, preview, progress, control)
        status('Program completed. Build a new preview to check the result.', 'green')
      elseif name == 'recover' then
        invalidate()
        recover(cfg, progress, control)
        status('Saved operation completed. Build a new preview to continue.', 'green')
      end
    end)
    if isWork then
      state.busy = false
    end
    U.check(ok, why)
    if isWork then
      perfReport(name .. ' complete')
      releaseWork()
      if state.page == 'history' then
        history()
      end
    end
  end
  local function insert(s)
    s = s:gsub('[\r\n]', ' '):gsub('%z', '')
    if edit.selectAll then
      edit.value = ''
      edit.cursor = 1
      edit.selectAll = false
    end
    edit.value = unicode.sub(edit.value, 1, edit.cursor - 1)
      .. s
      .. unicode.sub(edit.value, edit.cursor)
    edit.cursor = edit.cursor + unicode.len(s)
  end
  local function scrollTo(y)
    local drag = state.scrollDrag
    if not drag or not scrollbar then
      return
    end
    local travel = scrollbar.room - scrollbar.thumb
    if travel > 0 then
      state.offset = math.floor(
        math.max(0, math.min(1, (y - scrollbar.y - drag.grab) / travel)) * scrollbar.maximum + 0.5
      )
    end
  end
  local function ownsDrag(e)
    local d = state.scrollDrag
    return d
      and d.screen == e[2]
      and d.button == e[5]
      and d.player == e[6]
      and d.page == state.page
      and d.section == state.section
  end
  handle = function(e)
    if e[1] == 'interrupted' then
      state.cancelled = true
      state.running = false
    elseif e[1] == 'touch' then
      state.scrollDrag = nil
      if
        scrollbar
        and scrollbar.maximum > 0
        and e[5] == 0
        and e[3] >= scrollbar.x
        and e[3] < scrollbar.x + 2
        and e[4] >= scrollbar.y
        and e[4] < scrollbar.y + scrollbar.room
      then
        local onThumb = e[4] >= scrollbar.top and e[4] < scrollbar.top + scrollbar.thumb
        state.scrollDrag = {
          screen = e[2],
          button = e[5],
          player = e[6],
          page = state.page,
          section = state.section,
          grab = onThumb and e[4] - scrollbar.top or math.floor(scrollbar.thumb / 2),
        }
        if not onThumb then
          scrollTo(e[4])
        end
        return
      end
      for _, b in ipairs(buttons) do
        if e[3] >= b.x and e[3] < b.x + b.w and e[4] == b.y then
          if edit and (b.editKey ~= edit.key or b.section ~= edit.section) then
            commitEdit()
          end
          b.action(e[3], e[4])
          break
        end
      end
    elseif e[1] == 'drag' then
      if ownsDrag(e) then
        scrollTo(e[4])
      end
    elseif e[1] == 'drop' then
      if ownsDrag(e) then
        state.scrollDrag = nil
      end
    elseif e[1] == 'scroll' and not edit then
      state.scrollDrag = nil
      state.offset = state.offset - e[5] * 3
    elseif e[1] == 'clipboard' and edit then
      insert(e[3])
    elseif e[1] == 'key_down' then
      local char, key = e[3], e[4]
      if state.busy and (key == 1 or char == 113) then
        state.cancelled = true
        if char == 113 then
          state.running = false
        end
      elseif edit then
        if key == 28 then
          commitEdit()
        elseif key == 1 then
          edit = nil
        elseif key == 30 and keyboard.isControlDown() then
          edit.selectAll = true
        elseif key == 203 then
          edit.cursor = math.max(1, edit.cursor - 1)
          edit.selectAll = false
        elseif key == 205 then
          edit.cursor = math.min(unicode.len(edit.value) + 1, edit.cursor + 1)
          edit.selectAll = false
        elseif key == 199 then
          edit.cursor = 1
          edit.selectAll = false
        elseif key == 207 then
          edit.cursor = unicode.len(edit.value) + 1
          edit.selectAll = false
        elseif key == 14 or key == 211 then
          if edit.selectAll then
            edit.value = ''
            edit.cursor = 1
            edit.selectAll = false
          else
            local at = key == 14 and edit.cursor - 1 or edit.cursor
            if at >= 1 then
              edit.value = unicode.sub(edit.value, 1, at - 1) .. unicode.sub(edit.value, at + 1)
              edit.cursor = at
            end
          end
        elseif char and char >= 32 and not keyboard.isControlDown() then
          insert(unicode.char(char))
        end
      elseif key == 201 then
        state.offset = state.offset - 31
      elseif key == 209 then
        state.offset = state.offset + 31
      elseif char == 113 then
        state.running = false
      elseif char == 115 and state.page == 'preview' and not fs.exists(paths.pending) then
        action('preview')
      end
    end
  end
  local ok, err = pcall(function()
    gpu.setResolution(w, h)
    cfg = Config.migrate(readFile(paths.config))
    while state.running do
      draw()
      local e = { event.pull(1) }
      local success, why = pcall(handle, e)
      if not success then
        status(tostring(why), 'red')
        state.error = state.status
        state.busy = false
        state.offset = 0
        pcall(perfReport, 'stopped: ' .. state.status)
        releaseWork()
        if state.page == 'history' then
          pcall(history)
        end
      end
    end
  end)
  releaseWork()
  state.preview = nil
  state.history = nil
  buttons = {}
  paintCache = {}
  contentRows = nil
  edit = nil
  gpu.setResolution(oldW, oldH)
  gpu.setForeground(oldFG)
  gpu.setBackground(oldBG)
  term.clear()
  term.setCursor(1, 1)
  if not ok then
    error(err, 0)
  end
end
C.runUI = runUI

-- Source: src/90_main.lua
if ... == '--test' then
  return C
end
runUI()

end,table.unpack(args,1,args.n))
package.path=savedPath
if args[1]~='--test' then unload() end
if not ok then error(result,0) end
return result
