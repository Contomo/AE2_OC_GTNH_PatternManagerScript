-- Measure settings once, then use those exact rows for pagination and drawing.
-- Destination lists, tables and ordinary controls all share the same page area.
local U = require('assline_util')
local M = {}

local function lines(value, width, unicode)
  local result = {}
  if value and value ~= '' then
    for _, row in ipairs(U.wrapRow({ value }, width, unicode)) do
      result[#result + 1] = row[1]
    end
  end
  return result
end

function M.buttons(choices, width, unicode, toggles)
  local result, x, y = {}, 0, 0
  for _, choice in ipairs(choices or {}) do
    local length = unicode.wlen('[ ' .. (toggles and 'X ' or '') .. choice[2] .. ' ]')
    U.check(length <= width, 'Setting option is wider than its control area')
    if x > 0 and x + length > width then
      x, y = 0, y + 1
    end
    result[#result + 1] = { choice = choice, x = x, row = y }
    x = x + length + 2
  end
  return result, #result > 0 and y + 1 or 0
end

function M.measure(field, width, unicode)
  local kind = field.kind
  local block = { field = field, kind = kind, help = lines(field.help, width, unicode) }
  if kind == 'destination' then
    block.height = 1
  elseif field.compact then
    block.kind, block.height = 'table', 2
  elseif field.toggleValues or kind == 'toggle' then
    block.kind, block.control, block.height = 'checkbox', 0, #block.help + 2
  else
    block.labels = lines(field.label, width, unicode)
    block.control = #block.labels
    local rows = 1
    if field.choices and kind ~= 'select' then
      block.options, rows = M.buttons(field.choices, width, unicode, kind == 'multiToggle')
    end
    block.helpRow = block.control + rows
    block.height = block.helpRow + #block.help + 1
  end
  return block
end

local function heading(field, width, unicode)
  if field.kind == 'destination' then
    local help = lines(field.groupHelp, width, unicode)
    return { kind = 'heading', label = 'Interface Names', help = help, height = #help + 2 }
  elseif field.compact then
    local help = lines(field.tableHelp, width, unicode)
    return { kind = 'tableHeading', field = field, help = help, height = #help + 2 }
  elseif field.group then
    return { kind = 'heading', label = field.group, help = {}, height = 2 }
  end
end

function M.pages(fields, width, height, unicode)
  local pages = { { blocks = {}, height = 0 } }
  local group
  for _, field in ipairs(fields) do
    local page, block = pages[#pages], M.measure(field, width, unicode)
    local changed = field.group ~= group
    local header = (changed or #page.blocks == 0) and heading(field, width, unicode) or nil
    -- Ordinary first-page group names already appear in the settings title.
    if #pages == 1 and #page.blocks == 0 and not field.compact and field.kind ~= 'destination' then
      header = nil
    end
    local gap = changed and #page.blocks > 0 and 1 or 0
    if page.height + gap + (header and header.height or 0) + block.height > height then
      U.check(#page.blocks > 0, 'Setting control exceeds available page height')
      page = { blocks = {}, height = 0 }
      pages[#pages + 1] = page
      header, gap = heading(field, width, unicode), 0
    end
    U.check(
      (header and header.height or 0) + block.height <= height,
      'Setting control exceeds available page height'
    )
    page.height = page.height + gap
    if header then
      header.row = page.height
      page.blocks[#page.blocks + 1] = header
      page.height = page.height + header.height
    end
    block.row = page.height
    page.blocks[#page.blocks + 1] = block
    page.height, group = page.height + block.height, field.group
  end
  return pages
end

return M
