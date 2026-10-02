-- Compact runtime recipe compiler. This module has no component/UI calls.
-- Eligibility uses form capabilities, production flags and rare exceptions.
local U = require('assline_util')
local Planner = require('assline_planner')
local Batch = require('assline_batch')
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
local labels = {
  ingot = 'Ingot',
  nugget = 'Nugget',
  stick = 'Rod',
  ring = 'Ring',
  bolt = 'Bolt',
  screw = 'Screw',
  round = 'Round',
  gearGt = 'Gear',
  gearGtSmall = 'Small gear',
  rotor = 'Rotor',
  itemCasing = 'Item casing',
  toolHeadDrill = 'Drill head',
  dust = 'Dust',
  wireFine = 'Fine wire',
  plate = '1x Plate',
  plateDouble = '2x Plate',
  plateTriple = '3x Plate',
  plateQuadruple = '4x Plate',
  plateQuintuple = '5x Plate',
  plateDense = 'Dense Plate',
  foil = 'Foil',
  sheetmetal = 'Sheet metal',
  springSmall = 'Small spring',
  spring = 'Spring',
  stickLong = 'Long rod',
  wire1 = '1x wire',
  turbineBlade = 'Turbine blade',
}
local function formLabel(form)
  local pipeKind, pipeSize = form:match('^pipe(Fluid)(%a+)$')
  if not pipeKind then
    pipeKind, pipeSize = form:match('^pipe(Item)(%a+)$')
  end
  if pipeKind then
    return pipeSize .. ' ' .. pipeKind:lower() .. ' pipe'
  end
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
  if rule.mode == 'solidifier' then
    -- GT's matrix uses suffixes (IronMagnetic, TengamAttuned), while display
    -- names can put these modifiers first. Match either end, not Magnetite.
    local name = material.name:lower():gsub('[^a-z0-9]', '')
    for _, modifier in ipairs({ 'magnetic', 'attuned' }) do
      if name:sub(1, #modifier) == modifier or name:sub(-#modifier) == modifier then
        return false, 'Fluid Shaper excludes ' .. modifier .. ' material variants.'
      end
    end
  end
  if
    data.usage
    and data.source.usagePolicy
    and not (data.usage[material.u] or {})[rule.outputs[1].f]
  then
    return false, 'unused'
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
  U.check(
    mode == 'wiremill' or mode == 'coating' or mode == 'bender' or mode == 'solidifier',
    'Mode has no verified recipe rules yet'
  )
  local manifest = {
    version = 1,
    source = U.clone(data.source),
    policy = {
      mode = mode,
      polymer = polymer,
      pps = options.pps ~= false,
      sources = U.clone(options.sources),
      multiplier = multiplier,
      batch = U.clone(options.batch),
    },
    recipes = {},
    unusedExcluded = 0,
    unclassifiedRecipes = 0,
    tierExcluded = 0,
    skipped = {},
  }
  local seen, unresolved, skipped = {}, {}, {}
  manifest.unresolved = {}
  local function exclude(material, rule, reason)
    local out = rule.outputs[1]
    local item = M.resolve(data, material, out.f)
    local key = item.name .. ':' .. item.damage
    if not skipped[key] then
      skipped[key] = true
      manifest.skipped[#manifest.skipped + 1] = {
        material = material.name,
        form = out.f,
        label = material.name .. ' ' .. formLabel(out.f),
        name = item.name,
        damage = item.damage,
        reason = reason,
      }
    end
  end
  for _, material in ipairs(data.materials) do
    if checkpoint then
      checkpoint()
    end
    for ruleIndex, rule in ipairs(data.rules) do
      if
        rule.mode == mode
        and (not options.forms or options.forms[rule.outputs[1].f])
        and (not rule.polymer or rule.polymer == (polymer == 'none' and 'pvcSmall' or polymer))
        and (not options.sources or options.sources[rule.outputs[1].f] == rule.inputs[1].f)
      then
        local eligible, reason = M.eligible(data, material, rule)
        if reason == 'unused' then
          manifest.unusedExcluded = manifest.unusedExcluded + 1
          exclude(material, rule)
        elseif reason then
          exclude(material, rule, reason)
        end
        if eligible then
          if not material.tier then
            manifest.unclassifiedRecipes = manifest.unclassifiedRecipes + 1
          end
          local quantities = {}
          for _, side in ipairs({ 'inputs', 'outputs' }) do
            for _, e in ipairs(rule[side]) do
              local shared = e.i and data.items[e.i]
              if not shared or not shared.option or options[shared.option] ~= false then
                quantities[#quantities + 1] = { type = e.fluid and 'fluid' or 'item', size = e.n }
              end
            end
          end
          local voltage = data.voltages and data.voltages[material.v] or {}
          local eut = voltage[ruleIndex]
          if eut == nil then
            eut = rule.eut
          elseif eut == false then
            eut = nil
          end
          local recipeMultiplier, batch = Batch.resolve(
            options.batch,
            material.tier,
            eut,
            multiplier,
            quantities,
            material.tierSource
          )
          if recipeMultiplier == 0 then
            manifest.tierExcluded = manifest.tierExcluded + 1
            exclude(material, rule, batch.excluded)
          else
            local function resolve(e, stocked)
              if e.fluid == 'material' then
                local fluid =
                  U.check(material.molten, 'Missing verified molten fluid for ' .. material.name)
                local size = e.n * (stocked and 1 or recipeMultiplier)
                U.check(
                  U.integer(size) and size > 0,
                  'Pattern multiplier exceeds the supported fluid quantity'
                )
                return {
                  type = 'fluid',
                  name = fluid,
                  label = 'Molten ' .. material.name,
                  size = size,
                }
              end
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
              item.size = e.n * (stocked and 1 or recipeMultiplier)
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
            local route = (mode == 'wiremill' or mode == 'bender')
                and (' / from ' .. (labels[source] or source))
              or ''
            local recipe = {
              kind = 'processing',
              material = material.name,
              outputForm = out.f,
              outputLabel = label,
              inputs = {},
              outputs = {},
              label = material.name .. ' / ' .. label .. route,
              stock = {},
              batch = batch,
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
            U.check(#recipe.inputs > 0 and #recipe.outputs > 0, 'Rule contains no requested inputs')
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
    end
  end
  U.check(#manifest.recipes > 0 or #manifest.skipped > 0, 'No verified recipes for this mode')
  return manifest
end
return M
