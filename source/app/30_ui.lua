local function runUI()
  local gpu = component.gpu
  U.check(gpu, 'GPU required')
  local term, keyboard = require('term'), require('keyboard')
  local oldW, oldH = gpu.getResolution()
  local oldFG, oldBG = gpu.getForeground(), gpu.getBackground()
  local maxW, maxH = gpu.maxResolution()
  U.check(maxW >= 160 and maxH >= 50, 'Use a tier 3 GPU and screen with 160x50 resolution') -- the fuck
  local w, h = 160, 50
  -- OC can report char=0 for keypad keys (notably with Num Lock off).
  -- The physical key code still identifies the intended digit.
  local keypad = {
    [0x52] = '0',
    [0x4F] = '1',
    [0x50] = '2',
    [0x51] = '3',
    [0x4B] = '4',
    [0x4C] = '5',
    [0x4D] = '6',
    [0x47] = '7',
    [0x48] = '8',
    [0x49] = '9',
    [0x53] = '.',
    [0xB3] = ',',
  }
  local colors = {
    bg = 0x101A26,
    panel = 0x1A2A3C,
    text = 0xDCE6EF,
    muted = 0x8297AB,
    blue = 0x5AC8FA,
    green = 0x72D69A,
    yellow = 0xFFD277,
    yellow_lighter1 = 0xFFF09E,
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
      add('Assembly line, insulator, wiremill and bender share settings, editor and recovery.')
      add('Wire combining remains unavailable until its recipes have been verified.')
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
    elseif preview.manifest and (state.section == 'existing' or state.section == 'skipped') then
      for _, row in ipairs(Preview.rows(state.section, p, preview.manifest)) do
        add(row[1], row[2])
      end
    elseif state.section == 'details' and preview.manifest then
      if preview.id == 'bender' then
        add('BENDER CIRCUITS', 'blue')
        add(
          'Keep these circuits stocked in the machine; patterns request the selected solids only.'
        )
        local circuits, labels = {}, {}
        for _, recipe in ipairs(preview.manifest.recipes) do
          for _, stock in ipairs(recipe.stock or {}) do
            if stock.name == 'gregtech:gt.integrated_circuit' then
              circuits[recipe.outputForm] = stock.damage
              labels[recipe.outputForm] = recipe.outputLabel
            end
          end
        end
        for _, entry in ipairs(Programs.byId.bender.formChoices) do
          local circuit = circuits[entry[1]]
          if circuit then
            add((labels[entry[1]] or entry[2]) .. ': circuit ' .. circuit)
          end
        end
        add('')
      end
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
      add('See Existing for each pattern and labeled move.', 'muted')
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
      for _, row in ipairs(Preview.capacityRows(p)) do
        add(row[1], row[2])
      end
    elseif preview.id ~= 'assline' then
      for _, row in ipairs(Preview.planRows(p, preview.manifest)) do
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
      or preview.id ~= 'assline' and (#p.moves + #p.creates + #p.resizes) > 0
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
      local y = 11
      for _, f in ipairs(fields()) do
        local helpY, height = y + 2, 4
        text(34, y, f.label, 124, 'blue')
        if f.kind == 'multiToggle' then
          local x, row = 34, y + 1
          local selected = Config.selected(values()[f.key], f.choices)
          for _, option in ipairs(f.choices) do
            local key, choice = f.key, option[1]
            if x + unicode.wlen('[ ' .. option[2] .. ' ]') - 1 > 157 then
              x, row = 34, row + 1
            end
            x = button(x, row, option[2], function()
              commitEdit()
              local trial = U.clone(cfg)
              local v = Config.values(trial, state.settings)
              v[key] = Config.toggleSelected(v[key], f.choices, choice)
              saveConfig(trial)
              status('Settings saved.', 'green')
            end, true, selected[choice])
          end
          helpY, height = row + 1, row - y + 4
        elseif f.choices then
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
        text(34, helpY, f.help, 124, 'muted')
        y = y + height
      end
      button(34, 47, 'Run program', function()
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
      text(34, 7, 'Preview - ' .. (current and Programs.byId[current].name or ''), 124, 'blue')
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
        or {
          { 'changes', 'Patterns' },
          { 'existing', 'Existing' },
          { 'skipped', 'Excluded' },
          { 'capacity', 'Capacity' },
          { 'details', 'Details' },
        }
      for _, tab in ipairs(tabs) do
        local section = tab[1]
        x = button(x, 9, (state.section == section and '* ' or '') .. tab[2], function()
          state.section = section
          state.offset = 0
        end)
      end
      scrollRows(34, 12, 74, 31)
      text(113, 12, 'Summary', 45, 'blue')
      if p then
        if preview.id == 'assline' then
          --todo remove and unify this
          text(113, 14, p.scanned .. 'existing patterns scanned', 45)
          text(113, 15, #p.changes .. 'existing patterns to update', 45, 'green')
          text(113, 16, p.newRecipes .. ' donor patterns needed', 45, 'yellow')
          text(113, 17, (#p.recipes - p.newRecipes) .. ' rename recipes reused', 45, 'green')
          text(113, 18, p.available .. ' processing donors available', 45, 'muted')
        else
          text(113, 13, #(p.existing or {}) .. ' existing patterns scanned', 45, 'muted')
          text(113, 14, p.reused .. ' reused patterns recipes', 45, 'green')
          text(113, 15, p.resizeCount .. ' reused patterns to resize', 45,
                        p.resizeCount > 0 and 'yellow_lighter1' or 'muted')
          text(113, 16, #p.preserved .. ' unrelated kept', 45, 'muted')
          text(113, 18, p.required.processing .. '/' .. p.available.processing .. ' proc/ultimate pattern donors to be used', 45,
                        p.required.processing < p.available.processing and 'green' or 'red')
          text(113, 20, #p.moves .. ' sorting moves first', 45)
        end
        local y = 22
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
      if preview and preview.report then
        button(34, 45, 'Export report', function()
          local path = '/home/assline-preview.txt'
          local ok, why = pcall(function()
            local file, err = io.open(path, 'w')
            U.check(file, err or 'Cannot open report file')
            local written, writeError = file:write(preview.report)
            local closed, closeError = file:close()
            U.check(written and closed, writeError or closeError or 'Cannot save report')
          end)
          status(ok and 'Saved preview report to ' .. path or 'Report export failed: ' .. tostring(why),
            ok and 'green' or 'red')
        end, not state.busy)
      end
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
        if key == 28 or key == 0x9C then
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
        elseif not keyboard.isControlDown() then
          local value = char and char >= 32 and unicode.char(char) or keypad[key]
          if value then
            insert(value)
          end
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
