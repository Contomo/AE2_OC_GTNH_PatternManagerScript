-- An AND/OR dependency graph: every input of a recipe is needed, while any
-- independent producer can supply an ingredient. Quantities do not affect cycles.
local U = require('assline_util')
local M = {}

function M.identity(stack)
  return U.canonical({ stack.type or 'item', stack.name, stack.damage or false, stack.tag or false })
end

function M.new(checkpoint)
  local graph = { ids = {}, nodes = {}, recipes = {} }

  function graph:node(stack)
    local key = M.identity(stack)
    local id = self.ids[key]
    if not id then
      id = #self.nodes + 1
      self.ids[key] = id
      self.nodes[id] = { label = stack.label or stack.name, producers = {} }
    end
    return id
  end

  function graph:add(recipe, origin, opaque)
    local row = { origin = origin, inputs = {}, outputs = {}, opaque = opaque == true }
    for _, which in ipairs({ 'inputs', 'outputs' }) do
      local seen = {}
      for _, stack in pairs(recipe[which]) do
        local id = self:node(stack)
        if not seen[id] then
          row[which][#row[which] + 1] = id
          seen[id] = true
        end
      end
    end
    local index = #self.recipes + 1
    self.recipes[index] = row
    for _, id in ipairs(row.outputs) do
      self.nodes[id].producers[#self.nodes[id].producers + 1] = index
    end
    return index
  end

  function graph:hasProducer(stack, excluded, activeOnly)
    local id = self.ids[M.identity(stack)]
    for _, index in ipairs(id and self.nodes[id].producers or {}) do
      if
        not (excluded or {})[self.recipes[index].origin]
        and not (activeOnly and self.recipes[index].opaque)
      then
        return true
      end
    end
    return false
  end

  function graph:restore(count)
    for index = #self.recipes, count + 1, -1 do
      for _, id in ipairs(self.recipes[index].outputs) do
        table.remove(self.nodes[id].producers)
      end
      self.recipes[index] = nil
    end
  end

  function graph:independent(inputs, forbidden, excluded)
    local blocked, pending, wanted, relevant, producers = {}, {}, {}, {}, {}
    excluded = excluded or {}
    for _, stack in pairs(forbidden or {}) do
      blocked[self:node(stack)] = true
    end
    local roots = {}
    for _, stack in pairs(inputs) do
      local id = self:node(stack)
      roots[#roots + 1] = id
      pending[#pending + 1] = id
    end
    while #pending > 0 do
      local id = table.remove(pending)
      if not wanted[id] then
        wanted[id], producers[id] = true, {}
        if not blocked[id] then
          for _, index in ipairs(self.nodes[id].producers) do
            local row = self.recipes[index]
            if not excluded[row.origin] then
              producers[id][#producers[id] + 1] = index
              if not relevant[index] then
                relevant[index] = row
                for _, input in ipairs(row.inputs) do
                  pending[#pending + 1] = input
                end
              end
            end
          end
        end
      end
    end
    -- Least fixed point, rather than recursive memoization: an alternative
    -- outside a strongly connected group must be able to ground the group.
    local ready, changed = {}, true
    for id in pairs(wanted) do
      ready[id] = not blocked[id] and #producers[id] == 0
    end
    while changed do
      changed = false
      for _, row in pairs(relevant) do
        if checkpoint then
          checkpoint()
        end
        local usable = #row.inputs > 0
        for _, id in ipairs(row.inputs) do
          usable = usable and ready[id]
        end
        if usable then
          for _, id in ipairs(row.outputs) do
            if wanted[id] and not blocked[id] and not ready[id] then
              ready[id], changed = true, true
            end
          end
        end
      end
    end
    local missing = {}
    for _, id in ipairs(roots) do
      if not ready[id] then
        missing[#missing + 1] = self.nodes[id].label
      end
    end
    return #missing == 0, missing
  end

  -- Validate all proposed recipes together, including future casts. Removing
  -- an unavailable producer must also invalidate any plan that depended on it.
  function graph:plan(entries, omitted)
    local excluded, original = U.clone(omitted or {}), #self.recipes
    for _, entry in ipairs(entries) do
      self:add(entry.recipe, entry.origin)
    end
    local changed = true
    while changed do
      changed = false
      local unsafe = {}
      for _, entry in ipairs(entries) do
        if
          not excluded[entry.origin]
          and entry.requireProducer
          and not self:hasProducer(entry.requireProducer, excluded)
        then
          unsafe[entry.origin] = true
        end
      end
      for origin in pairs(unsafe) do
        excluded[origin], changed = true, true
      end
      unsafe = {}
      for _, entry in ipairs(entries) do
        if not excluded[entry.origin] then
          local forbidden = U.clone(excluded)
          forbidden[entry.origin] = true
          if not self:independent(entry.recipe.inputs, entry.recipe.outputs, forbidden) then
            unsafe[entry.origin] = true
          end
        end
      end
      for origin in pairs(unsafe) do
        excluded[origin], changed = true, true
      end
    end
    self:restore(original)
    return excluded
  end

  return graph
end

return M
