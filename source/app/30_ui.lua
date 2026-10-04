local function runUI()
  local gpu = component.gpu
  U.check(gpu, 'GPU required')
  local term, keyboard = require('term'), require('keyboard')
  local oldW, oldH = gpu.getResolution()
  local oldFG, oldBG = gpu.getForeground(), gpu.getBackground()
  local maxW, maxH = gpu.maxResolution()
  U.check(maxW >= 160 and maxH >= 50, 'Use a tier 3 GPU and screen with 160x50 resolution') -- the fuck
  local w, h = 160, 50
  local layout = {
    title = 2,
    subtitle = 3,
    tabs = 4,
    body = 7,
    bodyBottom = 42,
    scrollFooter = 44,
    separator = 46,
    actions = 47,
    notice = 48,
    status = 49,
    metrics = 50,
  }
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
    settingsPage = 1,
    selected = nil,
    section = 'changes',
    offset = 0,
    status = 'Choose a program, then Preview selected. Configure shared interfaces in Settings.',
    tone = 'muted',
    running = true,
  }
  local buttons, paintCache, paintKey, edit = {}, {}, nil, nil
  local buttonWidths, scrollbar = {}, nil
  local contentKey, contentRows, destinations
  local draw, handle, action, commitEdit, navigate
  local function text(x, y, s, width, tone, bg, guideWidth, guideTone, accent)
    width = math.min(width or w - x + 1, w - x + 1)
    if width < 1 then
      return
    end
    s = unicode.sub(tostring(s or ''):gsub('\194\167.', ''):gsub('[%c]', ' '), 1, width)
    local key = x .. ':' .. y
    local value = width
      .. ':'
      .. s
      .. ':'
      .. tostring(tone)
      .. ':'
      .. tostring(bg)
      .. ':'
      .. tostring(guideWidth)
      .. ':'
      .. tostring(guideTone)
      .. U.canonical(accent)
    if paintCache[key] == value then
      return
    end
    paintCache[key] = value
    gpu.setForeground(colors[tone or 'text'])
    gpu.setBackground(colors[bg or 'bg'])
    gpu.set(x, y, s .. string.rep(' ', math.max(0, width - unicode.wlen(s))))
    if guideWidth and guideWidth > 0 then
      gpu.setForeground(colors[guideTone or tone or 'text'])
      gpu.set(x, y, unicode.sub(s, 1, guideWidth))
    end
    if accent then
      local first, last = math.max(1, accent.from), math.min(width, accent.from + accent.length - 1)
      if last >= first then
        gpu.setForeground(Batch.color(accent.tier, colors.text, 0.5))
        gpu.setBackground(colors[bg or 'bg'])
        gpu.set(x + first - 1, y, unicode.sub(s, first, last))
      end
    end
  end
  local function control(x, y, content, callback, enabled, selected)
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
  local function button(x, y, label, callback, enabled, selected)
    return control(x, y, '[ ' .. label .. ' ]', callback, enabled, selected)
  end
  local function toggleButton(x, y, selected, callback, enabled, label)
    local marker = selected and 'X' or ' '
    return button(x, y, marker .. (label and (' ' .. label) or ''), callback, enabled, selected)
  end
  local function checkbox(x, y, label, selected, callback)
    return control(
      x,
      y,
      '[ ' .. (selected and 'X' or ' ') .. ' ] ' .. label,
      callback,
      true,
      selected
    )
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
    Config.validate(Config.normalize(value))
    writeFile(paths.config, value)
    cfg = value
    invalidate()
  end
  local function fields()
    return Config.visibleFields(cfg, state.settings)
  end
  local function values()
    return Config.values(cfg, state.settings)
  end
  local function chooseValue(key, value)
    commitEdit()
    local trial = U.clone(cfg)
    Config.values(trial, state.settings)[key] = value
    saveConfig(trial)
    state.choice = nil
    status('Settings saved.', 'green')
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
  local function toggleForm(key, choices, choice)
    commitEdit()
    local trial = U.clone(cfg)
    local v = Config.values(trial, state.settings)
    v[key] = Config.toggleSelected(v[key], choices, choice)
    saveConfig(trial)
    status('Settings saved.', 'green')
  end
  navigate = function(page, section)
    commitEdit()
    state.page = page
    state.offset = 0
    state.scrollDrag = nil
    if section then
      state.settings = section
      state.settingsPage = 1
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
      text(
        x,
        y,
        value == '' and (f.placeholder or '(not configured)') or value,
        width,
        value == '' and 'muted' or 'text',
        'panel'
      )
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
      add(
        'Assembly line, insulator, wiremill, bender and Fluid Shaper share the editor and recovery.'
      )
      add('Wire combining remains unavailable until its recipes have been verified.')
      add('')
      add('SETTINGS AND RECOVERY', 'blue')
      add('Fields save when accepted or when you navigate away. Esc cancels only the active edit.')
      add(
        'Continue last operation finishes an interrupted transaction and previews the remaining work.'
      )
      add(
        'History retains timing and memory reports. Updates preserve configuration and recovery files.'
      )
    elseif not p then
      add(
        state.busy and 'Program running. See progress below.'
          or C.runner.hasSaved() and 'Continue last operation, or choose a program to build a new preview.'
          or 'Choose a program to build a preview.',
        'muted'
      )
    elseif p.kind == 'donorCleanup' then
      for _, row in ipairs(Preview.rows(state.section, p)) do
        add(row[1], row[2], row[3], row[4], row[5], row[6])
      end
    elseif preview.manifest and (state.section == 'existing' or state.section == 'skipped') then
      for _, row in ipairs(Preview.rows(state.section, p, preview.manifest)) do
        add(row[1], row[2], row[3], row[4], row[5], row[6])
      end
    elseif state.section == 'details' and preview.manifest then
      if preview.id == 'bender' or preview.id == 'fluidShaper' then
        add('STOCKED IN MACHINE', 'blue')
        add('These reusable items stay in the machine and are omitted from patterns.')
        local stocked = {}
        local program = Programs.byId[preview.id]
        for _, recipe in ipairs(preview.manifest.recipes) do
          local key = Programs.switchKey(program, recipe.outputForm)
          stocked[key] = stocked[key]
            or {
              label = recipe.outputLabel,
              items = recipe.stock or {},
            }
        end
        for _, entry in ipairs(program.formChoices) do
          local group = stocked[entry[1]]
          if group and #group.items > 0 then
            local names = {}
            for _, item in ipairs(group.items) do
              names[#names + 1] = item.name == 'gregtech:gt.integrated_circuit'
                  and ('circuit ' .. item.damage)
                or tostring(item.label or item.name)
            end
            add(
              (program.switchByDestination and entry[2] or group.label or entry[2])
                .. ': '
                .. table.concat(names, ', ')
            )
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
        add(row[1], row[2], row[3], row[4], row[5], row[6])
      end
    elseif preview.id ~= 'assline' then
      for _, row in ipairs(Preview.planRows(p, preview.manifest)) do
        add(row[1], row[2], row[3], row[4], row[5], row[6])
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
      contentRows, destinations = {}, {}
      for _, r in ipairs(lines()) do
        for _, row in ipairs(U.wrapRow(r, width, unicode)) do
          contentRows[#contentRows + 1] = row
          if row[6] and row[6].destination then
            destinations[#destinations + 1] = { name = row[6].destination, row = #contentRows }
          end
        end
      end
    end
    local rows = contentRows
    local linked = #destinations > 1
    local linkTop, linkBottom = y, y + room - 1
    if linked then
      y, room = y + 1, room - 2
    end
    -- Let even a short final destination align with the first content row.
    -- Otherwise clamping at the document end can leave Next pointing at the
    -- same destination after a click because its heading never reaches the top.
    local maximum = math.max(0, #rows - room, linked and destinations[#destinations].row - 1 or 0)
    state.offset = math.max(0, math.min(state.offset, maximum))
    if linked then
      local current = 1
      for index, destination in ipairs(destinations) do
        if destination.row <= state.offset + 1 then
          current = index
        end
      end
      local function jumpLink(row, destination, direction)
        if destination then
          local label =
            U.wrapRow({ direction .. ': Jump to ' .. destination.name }, width - 4, unicode)[1][1]
          button(x, row, label, function()
            state.scrollDrag = nil
            state.offset = destination.row - 1
          end)
        else
          text(x, row, '', width)
        end
      end
      jumpLink(linkTop, destinations[current - 1], 'Previous')
      jumpLink(linkBottom, destinations[current + 1], 'Next')
    end
    for n = 1, room do
      local r = rows[state.offset + n]
      text(
        x,
        y + n - 1,
        r and r[1] or '',
        width,
        r and r[2] or 'text',
        nil,
        r and r[3],
        r and r[4],
        r and r[5]
      )
    end
    local thumb = maximum == 0 and room or math.max(1, math.floor(room * room / (maximum + room)))
    local top = y
      + (maximum == 0 and 0 or math.floor(state.offset / maximum * (room - thumb) + 0.5))
    scrollbar =
      { x = x + width + 1, y = y, room = room, maximum = maximum, thumb = thumb, top = top }
    for row = y, y + room - 1 do
      text(scrollbar.x, row, '', 2, 'text', row >= top and row < top + thumb and 'blue' or 'panel')
    end
    text(
      x,
      layout.scrollFooter,
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
    if
      not preview
      or state.busy
      or fs.exists(paths.pending)
      or (C.runner.requiresVerification(preview) and not state.verified)
    then
      return false
    end
    local p = preview.plan
    if #p.errors > 0 or (preview.manifest and #preview.manifest.unresolved > 0) then
      return false
    end
    return C.runner.hasChanges(preview)
  end
  draw = function()
    local key = state.page
      .. tostring(cfg)
      .. state.settings
      .. tostring(state.settingsPage)
      .. tostring(state.choice)
      .. tostring(state.selected)
      .. state.section
      .. tostring(state.preview)
      .. tostring(state.busy)
      .. tostring(state.paused)
      .. tostring(state.stopRequested)
      .. tostring(state.verified)
      -- Transactions create/clear these files for every pattern. While busy,
      -- they do not change the layout and must not invalidate the paint cache.
      .. tostring(not state.busy and fs.exists(paths.pending))
      .. tostring(not state.busy and fs.exists(paths.run))
    if key ~= paintKey then
      gpu.setBackground(colors.bg)
      gpu.fill(1, 1, w, h, ' ')
      paintCache = {}
      buttonWidths = {}
      paintKey = key
    end
    buttons = {}
    scrollbar = nil
    nav(layout.title, 'Programs', state.page == 'programs', function()
      navigate('programs')
    end, not state.busy)
    nav(layout.body - 2, 'Settings', state.page == 'settings', function()
      navigate('settings')
    end, not state.busy)
    nav(layout.body + 1, 'History', state.page == 'history', function()
      navigate('history')
    end)
    nav(layout.body + 4, 'Help', state.page == 'help', function()
      navigate('help')
    end)
    if state.preview then
      nav(
        state.page == 'settings' and layout.scrollFooter or layout.body + 7,
        'Current preview',
        state.page == 'preview',
        function()
          navigate('preview')
        end
      )
    end
    if state.page == 'settings' then
      text(3, layout.body + 7, 'SETTINGS SECTIONS', 26, 'muted')
      nav(layout.body + 9, 'Tier multipliers', state.settings == 'batch', function()
        navigate('settings', 'batch')
      end)
      nav(layout.body + 12, 'Shared interfaces', state.settings == 'shared', function()
        navigate('settings', 'shared')
      end)
      for n, p in ipairs(Programs.settings) do
        local id = p.id
        nav(layout.body + 12 + n * 3, p.name, state.settings == id, function()
          navigate('settings', id)
        end)
      end
      local section = Config.section(state.settings)
      local pageRow = layout.scrollFooter + (section.pageSize == 9 and 1 or 0)
      local pages = { {} }
      for _, f in ipairs(fields()) do
        local page = pages[#pages]
        if
          #page > 0
          and (#page >= (f.compact and 16 or section.pageSize or 8) or page[1].group ~= f.group)
        then
          page = {}
          pages[#pages + 1] = page
        end
        page[#page + 1] = f
      end
      state.settingsPage = math.min(state.settingsPage, #pages)
      local page = pages[state.settingsPage]
      text(
        34,
        layout.title,
        'SETTINGS / '
          .. section.name
          .. (page[1] and page[1].group and (' / ' .. page[1].group) or ''),
        124,
        'blue'
      )
      text(
        34,
        layout.subtitle,
        'Accept a field or navigate away to save. Numbers accept k / M shorthand.',
        124,
        'muted'
      )
      local y = layout.body - (section.pageSize == 9 and 2 or 1)
      local compact = page[1] and page[1].compact
      if compact then
        local overrides = page[1].group == 'Tier overrides'
        text(
          34,
          layout.body - 2,
          page[1].tableLabel or (overrides and 'MATERIAL TIER' or 'RELATIVE TIER'),
          42,
          'blue'
        )
        text(
          80,
          layout.body - 2,
          page[1].valueLabel or (overrides and 'OVERRIDE' or 'MULTIPLIER'),
          22,
          'blue'
        )
        if overrides then
          text(115, layout.body - 2, 'EFFECTIVE', 40, 'blue')
        end
        text(
          34,
          pageRow - 1,
          page[1].tableHelp
            or (
              overrides and 'Blank follows the curve. Later tiers remain skipped unless enabled.'
              or 'One multiplier per relative tier. Maximum and quantity limits still apply.'
            ),
          124,
          'muted'
        )
        y = layout.body
      end
      for _, f in ipairs(page) do
        if compact then
          text(34, y, f.label, 42, 'text')
          editorRow(80, y, 22, f)
          if page[1].group == 'Tier overrides' then
            local budget = Batch.budget(cfg.batch, f.label)
            text(115, y, budget == 0 and 'Skipped' or budget .. 'x', 40, 'muted')
          end
          y = y + 2
        else
          local helpY, height = y + 2, 4
          local isCheckbox = f.toggleValues or f.kind == 'toggle'
          if not isCheckbox then
            text(34, y, f.label, 124, 'blue')
          end
          if isCheckbox then
            local key = f.key
            local choices = f.toggleValues or { 'off', 'on' }
            checkbox(34, y, f.label, values()[key] == choices[2], function()
              chooseValue(key, values()[key] == choices[2] and choices[1] or choices[2])
            end)
            helpY, height = y + 1, f.help and f.help ~= '' and 3 or 2
          elseif f.kind == 'multiToggle' then
            local x, row = 34, y + 1
            local selected = Config.selected(values()[f.key], f.choices)
            for _, option in ipairs(f.choices) do
              local key, choice = f.key, option[1]
              if x + unicode.wlen('[ X ' .. option[2] .. ' ]') - 1 > 157 then
                x, row = 34, row + 1
              end
              x = toggleButton(x, row, selected[choice], function()
                toggleForm(key, f.choices, choice)
              end, true, option[2])
            end
            helpY, height = row + 1, row - y + 4
          elseif f.enableForm then
            local program = Programs.byId[state.settings]
            local choice = f.enableForm
            local selected = Config.selected(values()[program.formSwitch], program.formChoices)
            toggleButton(34, y + 1, selected[choice], function()
              toggleForm(program.formSwitch, program.formChoices, choice)
            end, true)
            editorRow(42, y + 1, 116, f)
          elseif f.kind == 'select' then
            local label, selected = values()[f.key], 1
            for n, option in ipairs(f.choices) do
              if option[1] == values()[f.key] then
                label, selected = option[2], n
              end
            end
            button(34, y + 1, label, function()
              commitEdit()
              state.choice =
                { key = f.key, label = f.label, choices = f.choices, selected = selected }
            end)
          elseif f.choices then
            local x = 34
            for _, option in ipairs(f.choices) do
              local key, value = f.key, option[1]
              x = button(x, y + 1, option[2], function()
                chooseValue(key, value)
              end, true, values()[key] == value)
            end
          else
            editorRow(34, y + 1, 124, f)
          end
          if f.help and f.help ~= '' then
            text(34, helpY, f.help, 124, 'muted')
          end
          y = y + height
        end
      end
      if #pages > 1 then
        text(34, pageRow, 'Settings page ' .. state.settingsPage .. '/' .. #pages, 30, 'muted')
        button(111, pageRow, 'Previous', function()
          commitEdit()
          state.settingsPage = state.settingsPage - 1
        end, state.settingsPage > 1)
        button(133, pageRow, 'Next', function()
          commitEdit()
          state.settingsPage = state.settingsPage + 1
        end, state.settingsPage < #pages)
      end
      button(34, layout.actions, 'Run program', function()
        navigate('programs')
      end)
      if state.settings == 'batch' and cfg.batch.mode == 'tiered' then
        button(54, layout.actions, 'Effective tiers', function()
          commitEdit()
          state.choice = { label = 'Material budgets at ' .. cfg.batch.currentTier, budgets = true }
        end)
      end
    elseif state.page == 'programs' then
      text(34, layout.title, 'RUN A PROGRAM', 124, 'blue')
      text(
        34,
        layout.subtitle,
        'Select what to do. Preview selected builds a plan without changing patterns.',
        124,
        'muted'
      )
      local y = layout.body - 1
      for _, p in ipairs(Programs.list) do
        local id = p.id
        button(34, y, (state.selected == id and '* ' or '') .. p.name, function()
          commitEdit()
          state.selected = id
        end)
        text(38, y + 1, p.description, 120, 'text')
        if p.unavailable then
          text(38, y + 2, p.unavailable, 120, 'muted')
          y = y + 1
        end
        y = y + 3
      end
      local selected = state.selected and Programs.byId[state.selected]
      local x = button(34, layout.actions, 'Preview selected', function()
        action('preview')
      end, selected ~= nil and not selected.unavailable)
      button(x, layout.actions, 'Program settings', function()
        navigate('settings', state.selected)
      end, selected ~= nil and #selected.fields > 0)
    elseif state.page == 'preview' then
      local preview = state.preview
      local p = preview and preview.plan
      local current = preview and preview.id or state.selected
      text(
        34,
        layout.title,
        'Preview - ' .. (current and Programs.byId[current].name or ''),
        124,
        'blue'
      )
      local x = 34
      local tabs = current and Programs.byId[current].previewTabs
        or preview and preview.id == 'assline' and {
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
        x = button(x, layout.tabs, (state.section == section and '* ' or '') .. tab[2], function()
          state.section = section
          state.offset = 0
        end)
      end
      scrollRows(34, layout.body, 74, layout.bodyBottom - layout.body + 1)
      text(113, layout.body, 'Summary', 45, 'blue')
      if p then
        if p.kind == 'donorCleanup' then
          text(113, layout.body + 2, p.banks .. ' donor interfaces', 45, 'muted')
          text(113, layout.body + 3, p.scanned .. ' encoded patterns scanned', 45)
          text(113, layout.body + 4, #p.cleanups .. ' recipes to park', 45, 'yellow')
          text(113, layout.body + 5, p.parked .. ' already parked', 45, 'green')
          text(113, layout.body + 6, p.skipped .. ' skipped; see Patterns', 45, 'muted')
        elseif preview.id == 'assline' then
          --todo remove and unify this
          text(113, layout.body + 2, p.scanned .. 'existing patterns scanned', 45)
          text(113, layout.body + 3, #p.changes .. 'existing patterns to update', 45, 'green')
          text(113, layout.body + 4, p.newRecipes .. ' donor patterns needed', 45, 'yellow')
          text(
            113,
            layout.body + 5,
            (#p.recipes - p.newRecipes) .. ' rename recipes reused',
            45,
            'green'
          )
          text(113, layout.body + 6, p.available .. ' processing donors available', 45, 'muted')
        else
          text(
            113,
            layout.body + 1,
            #(p.existing or {}) .. ' existing patterns scanned',
            45,
            'muted'
          )
          text(113, layout.body + 2, p.reused .. ' reused patterns recipes', 45, 'green')
          text(
            113,
            layout.body + 3,
            p.resizeCount .. ' reused patterns to resize',
            45,
            p.resizeCount > 0 and 'yellow_lighter1' or 'muted'
          )
          text(113, layout.body + 4, #p.preserved .. ' unrelated kept', 45, 'muted')
          text(
            113,
            layout.body + 6,
            p.required.processing
              .. '/'
              .. p.available.processing
              .. ' proc/ultimate pattern donors to be used',
            45,
            p.required.processing < p.available.processing and 'green' or 'red'
          )
          text(113, layout.body + 8, #p.moves .. ' sorting moves first', 45)
        end
        local y = layout.body + 10
        text(
          113,
          y,
          state.busy and (state.paused and 'Paused' or 'Executing preview')
            or fs.exists(paths.pending) and 'Saved transaction still open'
            or #p.errors == 0 and 'Ready to execute'
            or 'BLOCKED: ' .. #p.errors .. ' issue(s)',
          45,
          (state.busy or fs.exists(paths.pending)) and 'yellow'
            or #p.errors == 0 and 'green'
            or 'red'
        )
        local function summaryRow(message, tone)
          for _, row in ipairs(U.wrapRow({ message, tone }, 45, unicode)) do
            if y < layout.body + 20 then
              y = y + 1
              text(113, y, row[1], 45, tone)
            end
          end
        end
        if not state.busy and fs.exists(paths.pending) then
          summaryRow('Continue or stop the saved operation before Execute.', 'yellow')
        end
        for _, err in ipairs(p.errors) do
          summaryRow(err, 'red')
        end
        for _, warning in ipairs(p.warnings or {}) do
          summaryRow(warning, 'yellow')
        end
        if preview.manifest and #preview.manifest.unresolved > 0 then
          text(113, layout.body + 22, 'Registry names need verification.', 45, 'red')
        end
        if C.runner.requiresVerification(preview) then
          text(113, layout.body + 24, 'Destination assumption: 36 slots each.', 45, 'yellow')
          text(113, layout.body + 25, 'Verify expanded interfaces in the game.', 45, 'muted')
          button(
            113,
            layout.body + 27,
            state.verified and '36 slots verified' or 'Verify 36 slots',
            function()
              state.verified = not state.verified
            end,
            not state.busy
          )
        else
          text(113, layout.body + 24, 'Returns donors to their original slots.', 45, 'muted')
          text(113, layout.body + 25, 'Only the shared editor needs free space.', 45, 'muted')
        end
      end
      local x = button(34, layout.actions, 'Scan', function()
        action('preview')
      end, not state.busy)
      x = button(x, layout.actions, 'Execute preview', function()
        action('execute')
      end, executable())
      x = button(x, layout.actions, 'Program settings', function()
        navigate('settings', preview.id)
      end, not state.busy and preview ~= nil and #Programs.byId[preview.id].fields > 0)
      button(x, layout.actions, 'Run program', function()
        navigate('programs')
      end, not state.busy)
      if preview and preview.report and not state.busy then
        button(34, layout.scrollFooter + 1, 'Export report', function()
          local path = '/home/assline-preview.txt'
          local ok, why = pcall(function()
            local file, err = io.open(path, 'w')
            U.check(file, err or 'Cannot open report file')
            local written, writeError = file:write(preview.report)
            local closed, closeError = file:close()
            U.check(written and closed, writeError or closeError or 'Cannot save report')
          end)
          status(
            ok and 'Saved preview report to ' .. path or 'Report export failed: ' .. tostring(why),
            ok and 'green' or 'red'
          )
        end, not state.busy)
      end
    else
      text(34, layout.title, state.page == 'history' and 'HISTORY' or 'HELP', 124, 'blue')
      scrollRows(34, layout.body, 124, layout.bodyBottom - layout.body + 1)
      button(34, layout.actions, 'Run program', function()
        navigate('programs')
      end, not state.busy)
    end
    if state.busy then
      button(113, layout.actions, state.paused and 'Resume' or 'Pause', function()
        state.paused = not state.paused
        status(
          state.paused and 'Paused. Resume continues this run; Stop ends it.' or 'Resuming work.',
          'yellow'
        )
      end, not state.stopRequested)
      button(127, layout.actions, 'Stop', function()
        state.stopRequested, state.paused = true, false
        status('Stopping after the current pattern transaction / sorting cycle.', 'yellow')
      end)
    elseif C.runner.hasSaved() then
      if state.page ~= 'settings' then
        button(113, layout.scrollFooter + 1, 'Continue last operation', function()
          action('continue')
        end)
      end
      button(135, layout.actions, 'Stop saved', function()
        state.choice = { label = 'Stop saved operation', discard = true }
      end)
    end
    button(151, layout.actions, 'Quit', function()
      commitEdit()
      state.stopRequested, state.paused = true, false
      state.running = false
    end)
    text(3, layout.separator, string.rep('-', 155), 155, 'muted')
    text(3, layout.status, state.status, 155, state.tone)
    text(
      111,
      layout.metrics,
      string.format(
        '%.0f%% energy  |  %d KB free',
        energyFraction() * 100,
        math.floor(computer.freeMemory() / 1024)
      ),
      47,
      'muted'
    )
    if C.runner.hasSaved() and not state.busy then
      text(
        3,
        layout.notice,
        'Saved operation available. Continue it, or Stop saved to start fresh.',
        155,
        'muted'
      )
    end
    if state.choice then
      -- Modal controls replace the underlying hit areas, so clicks cannot leak
      -- through to settings or Execute. Closing it repaints the underlying page.
      buttons = {}
      scrollbar = nil
      if not state.choice.painted then
        gpu.setBackground(colors.panel)
        gpu.fill(48, 9, 104, 29, ' ')
        state.choice.painted = true
      end
      text(51, 10, state.choice.label, 98, 'blue', 'panel')
      text(
        51,
        12,
        state.choice.discard and 'Discard the saved run and unfinished transaction record.'
          or state.choice.budgets and 'Material budgets before recipe voltage and quantity limits.'
          or 'Choose a tier. Escape cancels.',
        98,
        'muted',
        'panel'
      )
      if state.choice.discard then
        text(
          51,
          15,
          'Completed edits and moves stay in place. Nothing is undone.',
          98,
          'yellow',
          'panel'
        )
        text(
          51,
          17,
          'Any pattern left in the editor stays there; occupied slots are kept.',
          98,
          'muted',
          'panel'
        )
        text(
          51,
          19,
          'The discarded record is saved in /home/assline.abandoned.',
          98,
          'muted',
          'panel'
        )
        button(51, 23, 'Discard saved operation', function()
          action('discard')
          state.choice = nil
        end)
      end
      local entries = state.choice.discard and {} or state.choice.choices or Batch.tiers
      for n, entry in ipairs(entries) do
        local x = n <= 9 and 51 or 101
        local y = 14 + ((n - 1) % 9) * 2
        if state.choice.budgets then
          local budget = Batch.budget(cfg.batch, entry)
          text(
            x,
            y,
            entry .. '  ' .. (budget == 0 and 'Skipped' or budget .. 'x'),
            45,
            'text',
            'panel',
            nil,
            nil,
            { from = 1, length = #entry, tier = entry }
          )
        else
          local value, label = entry[1], entry[2]
          button(x, y, label, function()
            chooseValue(state.choice.key, value)
          end, true, state.choice.selected == n)
        end
      end
      button(51, 35, 'Close', function()
        state.choice = nil
      end)
    end
  end
  local lastProgress, lastPoll = 0, -math.huge
  local function progress(message, immediate)
    if state.paused or state.stopRequested then
      return
    end
    if immediate or computer.uptime() - lastProgress >= 1 then
      status(message, 'yellow')
      text(3, layout.status, message, 155, 'yellow')
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
    return { paused = state.paused, stop = state.stopRequested }
  end
  action = function(name)
    commitEdit()
    local isWork = name == 'preview' or name == 'execute' or name == 'continue'
    U.check(not isWork or not state.busy, 'Work already running')
    if name == 'execute' then
      U.check(executable(), 'Review and verify the preview first')
    end
    if isWork then
      state.error = nil
      state.busy = true
      state.stopRequested, state.paused = false, false
      lastPoll = computer.uptime()
      status('Working: ' .. name .. ' (Pause / Resume / Stop; Esc stops)', 'yellow')
    end
    local ok, why = pcall(function()
      if name == 'history' then
        history()
      elseif name == 'preview' then
        local id = state.page == 'preview' and state.preview and state.preview.id or state.selected
        U.check(id, 'Choose a program first')
        invalidate()
        state.page = 'preview'
        state.section = 'changes'
        state.offset = 0
        state.preview = C.runner.preview(cfg, id, progress, control)
        status(
          C.runner.requiresVerification(state.preview)
              and 'Preview ready. Review the plan and verify destination capacity before Execute preview.'
            or 'Preview ready. Review which disposable donor recipes will be replaced before Execute preview.',
          'green'
        )
      elseif name == 'execute' then
        local preview = state.preview
        C.runner.execute(cfg, preview, progress, control)
        status('Program completed. Build a new preview to check the result.', 'green')
      elseif name == 'continue' then
        invalidate()
        state.preview = C.runner.continue(cfg, progress, control)
        if state.preview then
          state.page, state.section, state.offset = 'preview', 'changes', 0
          state.selected = state.preview.id
        end
        status(
          state.preview
              and not C.runner.hasChanges(state.preview)
              and #state.preview.plan.errors == 0
              and 'No remaining changes for the current settings.'
            or state.preview and state.preview.continuedWithChangedSettings and 'Settings changed since the saved run. Review the updated preview before executing.'
            or state.preview and 'Remaining work previewed with current settings. Review and Execute to continue.'
            or 'Saved transaction completed. Choose a program to preview the remaining work.',
          'green'
        )
      elseif name == 'discard' then
        C.runner.discard()
        invalidate()
        status(
          'Saved operation discarded. Existing patterns stay as they are. Build a new preview.',
          'muted'
        )
      end
    end)
    if name == 'execute' then
      invalidate()
    end
    if isWork then
      state.busy = false
    end
    if not ok and why == C.stopped then
      state.paused = false
      status(C.stopped, 'muted')
    else
      U.check(ok, why)
    end
    if isWork then
      perfReport(ok and (name .. ' complete') or 'stopped by user')
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
    if state.choice then
      if e[1] == 'key_down' then
        local key = e[4]
        if key == 1 then
          state.choice = nil
        elseif state.choice.choices then
          if key == 200 or key == 208 then
            state.choice.selected = math.max(
              1,
              math.min(#state.choice.choices, state.choice.selected + (key == 200 and -1 or 1))
            )
          elseif key == 28 or key == 0x9C then
            chooseValue(state.choice.key, state.choice.choices[state.choice.selected][1])
          end
        end
        return
      elseif e[1] ~= 'touch' and e[1] ~= 'interrupted' then
        return
      end
    end
    if e[1] == 'interrupted' then
      state.stopRequested, state.paused = true, false
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
        state.stopRequested, state.paused = true, false
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
        state.offset = state.offset
          - (scrollbar and scrollbar.room or layout.bodyBottom - layout.body + 1)
      elseif key == 209 then
        state.offset = state.offset
          + (scrollbar and scrollbar.room or layout.bodyBottom - layout.body + 1)
      elseif char == 113 then
        state.running = false
      elseif char == 115 and state.page == 'preview' then
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
