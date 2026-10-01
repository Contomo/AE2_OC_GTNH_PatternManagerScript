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

-- OC's pattern converter returns ItemStacks. Their count is `size`; an
-- unrelated `amount` field can be zero on ordinary encoded patterns.
function M.patternCount(stack)
  return M.check(M.integer(stack.size) and stack.size > 0 and stack.size,
    'Encoded pattern ingredient has no positive item stack size')
end

function M.ingredientSummary(list)
  local out = {}
  for _, item in ipairs(list or {}) do
    out[#out + 1] = tostring(item.size or item.amount or 1)
      .. ' x ' .. tostring(item.label or item.name)
  end
  return table.concat(out, ', ')
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
