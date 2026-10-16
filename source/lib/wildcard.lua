-- One literal wildcard, shared between source matching and target substitution.
-- No Lua patterns or regular expressions are evaluated.
local U = require('assline_util')
local M = {}

local function split(value, label)
  U.check(type(value) == 'string' and value ~= '', label .. ' cannot be empty')
  local star = value:find('*', 1, true)
  if not star then
    return value, '', false
  end
  U.check(not value:find('*', star + 1, true), label .. ' supports only one * wildcard')
  return value:sub(1, star - 1), value:sub(star + 1), true
end

function M.compile(source, target)
  local prefix, suffix, capture = split(source, 'Source name')
  local before, after, replace = split(target, 'Target name')
  U.check(not replace or capture, 'A target * needs a source * wildcard')
  return function(name)
    if type(name) ~= 'string' then
      return nil
    end
    local middle = ''
    if capture then
      if #name < #prefix + #suffix or name:sub(1, #prefix) ~= prefix then
        return nil
      end
      if suffix ~= '' and name:sub(-#suffix) ~= suffix then
        return nil
      end
      middle = name:sub(#prefix + 1, #name - #suffix)
    elseif name ~= source then
      return nil
    end
    local destination = replace and (before .. middle .. after) or target
    U.check(destination ~= '' and #destination <= 512, 'Generated target name is empty or too long')
    return destination
  end
end

return M
