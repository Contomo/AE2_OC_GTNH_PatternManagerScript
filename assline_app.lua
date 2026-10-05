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
-- Source: source/lib/util.lua
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

-- Encoded stacks have two layouts: older patterns store Count, while newer
-- patterns store Cnt and leave Count at zero. OC's converted size can thus be
-- zero even though the encoded amount is positive.
function M.patternEntry(root, which, index)
  local list = root and root[which == 'inputs' and 'in' or 'out']
  return list and list.__nbt_type == 'list' and list.__value[index]
end

function M.patternCount(stack, entry)
  local fields = entry and entry.__nbt_type == 'compound' and entry.__value
  local function positive(value)
    if type(value) == 'table' then
      value = value.__value
    end
    return M.integer(value) and value > 0 and value or nil
  end
  return positive(fields and fields.Cnt)
    or positive(fields and fields.Count)
    or positive(stack.size)
    or positive(stack.amount)
end

function M.ingredientSummary(list)
  local out = {}
  for _, index in ipairs(M.keys(list or {})) do
    local item = list[index]
    out[#out + 1] = tostring(item.size or item.amount or 1)
      .. (item.type == 'fluid' and ' mB ' or ' x ')
      .. tostring(item.label or item.name)
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
  local function add(text, tone, guideWidth, guideTone, accent, marker)
    result[#result + 1] = { text, tone or 'text', guideWidth, guideTone, accent, marker }
  end
  return result, add
end

-- One word wrapper for scrollable rows and narrow summary panels. Tree guides
-- repeat on continuation lines; accent positions follow the original text.
function M.wrapRow(row, width, unicode)
  local result = {}
  local prefixLength = math.min(row[3] or 0, width - 1)
  local prefix = unicode.sub(row[1], 1, prefixLength)
  local remaining = unicode.sub(row[1], prefixLength + 1)
  local consumed = prefixLength
  local available = width - unicode.wlen(prefix)
  repeat
    local count = unicode.len(remaining)
    if unicode.wlen(remaining) > available then
      local low, high = 1, count
      while low < high do
        local mid = math.ceil((low + high) / 2)
        if unicode.wlen(unicode.sub(remaining, 1, mid)) <= available then
          low = mid
        else
          high = mid - 1
        end
      end
      count = low
      local part = unicode.sub(remaining, 1, count)
      local boundary = part:match('^.*()%s')
      if boundary then
        local words = unicode.len(part:sub(1, boundary - 1))
        if words > 0 then
          count = words
        end
      end
    end
    local chunk = unicode.sub(remaining, 1, count)
    local accent
    if row[5] then
      local first = math.max(1, row[5].from - consumed)
      local last = math.min(count, row[5].from + row[5].length - 1 - consumed)
      if first <= last then
        accent = { from = prefixLength + first, length = last - first + 1, tier = row[5].tier }
      end
    end
    result[#result + 1] =
      { prefix .. chunk, row[2], prefixLength, row[4], accent, #result == 0 and row[6] or nil }
    local tail = unicode.sub(remaining, count + 1)
    remaining = tail:gsub('^%s+', '')
    consumed = consumed + count + unicode.len(tail) - unicode.len(remaining)
  until remaining == ''
  return result
end

return M

end)()
local TierDefinitions=(function()
-- Source: source/data/tiers.json
return {["source"]="https://github.com/GTNewHorizons/GT5-Unofficial/blob/5.09.54.133/src/main/java/gregtech/api/enums/GTValues.java",["names"]={"ULV","LV","MV","HV","EV","IV","LuV","ZPM","UV","UHV","UEV","UIV","UMV","UXV","OpV","MAX"},["voltages"]={8,32,128,512,2048,8192,32768,131072,524288,2097152,8388608,33554432,134217728,536870912,2147483640,8589934592},["colorSource"]="RGB colors of pinned GTValues.TIER_COLORS; Minecraft bold/underline formatting has no OC GPU equivalent",["colors"]={16733525,43520,16755200,16777045,5592405,5592575,16733695,5636095,43520,11141120,11141290,170,16733525,11141120,16777215,16777215}}
end)()
local MaterialUnits=(function()
-- Source: source/data/material_units.json
return {["policy"]="ore-prefix-material-units-v1",["source"]={["archive"]="gt-5.09.54.133.zip",["sha256"]="a5993a25fbf464348182baac16539bcf08bdfa18d22ef0217dc84fc4c14ca03e",["definitions"]={"gregtech/api/enums/OrePrefixes.java","gregtech/api/enums/GTValues.java"}},["fluidPerIngot"]=144,["forms"]={["armorBoots"]=4,["armorChestplate"]=8,["armorHelmet"]=5,["armorLeggings"]=7,["block"]=9,["blockCasing"]=9,["blockCasingAdvanced"]=9,["bolt"]=0.125,["bucket"]=1,["bucketClay"]=1,["bulletGtLarge"]=0.3333333333333333,["bulletGtMedium"]=0.16666666666666666,["bulletGtSmall"]=0.1111111111111111,["cable1"]=0.5,["cable12"]=6,["cable16"]=8,["cable2"]=1,["cable4"]=2,["cable8"]=4,["capsule"]=1,["capsuleMolten"]=1,["cell"]=1,["cellHydroCracked1"]=1,["cellHydroCracked2"]=1,["cellHydroCracked3"]=1,["cellMolten"]=1,["cellPlasma"]=1,["cellSteamCracked1"]=1,["cellSteamCracked2"]=1,["cellSteamCracked3"]=1,["comb"]=1,["compressed"]=3,["crystal"]=1,["dust"]=1,["dustImpure"]=1,["dustPure"]=1,["dustRefined"]=1,["dustSmall"]=0.25,["dustTiny"]=0.1111111111111111,["foil"]=0.25,["frameGt"]=2,["gearGt"]=4,["gearGtSmall"]=1,["gem"]=1,["gemChipped"]=0.25,["gemExquisite"]=4,["gemFlawed"]=0.5,["gemFlawless"]=2,["handleMallet"]=0.5,["ingot"]=1,["ingotHot"]=1,["itemCasing"]=0.5,["lens"]=0.75,["nugget"]=0.1111111111111111,["pipeHuge"]=12,["pipeLarge"]=6,["pipeMedium"]=3,["pipeNonuple"]=9,["pipeQuadruple"]=12,["pipeRestrictiveHuge"]=12,["pipeRestrictiveLarge"]=6,["pipeRestrictiveMedium"]=3,["pipeRestrictiveSmall"]=1,["pipeRestrictiveTiny"]=0.5,["pipeSmall"]=1,["pipeTiny"]=0.5,["plate"]=1,["plateDense"]=9,["plateDouble"]=2,["plateQuadruple"]=4,["plateQuintuple"]=5,["plateSuperdense"]=64,["plateTriple"]=3,["ring"]=0.25,["rotor"]=4.25,["round"]=0.1111111111111111,["screw"]=0.125,["sheetmetal"]=2,["spring"]=1,["springSmall"]=0.25,["stick"]=0.5,["stickLong"]=1,["toolAxe"]=3,["toolHeadBuzzSaw"]=4,["toolHeadChainsaw"]=2,["toolHeadDrill"]=4,["toolHeadFile"]=2,["toolHeadHammer"]=6,["toolHeadMallet"]=6,["toolHeadSaw"]=2,["toolHeadScrewdriver"]=1,["toolHeadWrench"]=4,["toolHoe"]=2,["toolPickaxe"]=3,["toolShears"]=2,["toolShovel"]=1,["toolSword"]=2,["turbineBlade"]=6,["wire1"]=0.5,["wire12"]=6,["wire16"]=8,["wire2"]=1,["wire4"]=2,["wire8"]=4,["wireFine"]=0.125}}
end)()
local TransitionRules=(function()
-- Source: source/data/transition.json
return {["explosives"]={["gregtech:gt.blockreinforced@5"]="Powderbarrel",["ic2:blockitnt"]="Industrial TNT",["ic2:itemdynamite"]="Dynamite",["minecraft:tnt"]="TNT"},["secondary"]={["bartworks:gt.bwmetagenerateddusttiny@90"]="Tiny Pile of Ruridit Dust",["gregtech:gt.metaitem.01@129"]="Tiny Pile of Neutronium Dust",["gregtech:gt.metaitem.01@306"]="Tiny Pile of Stainless Steel Dust",["gregtech:gt.metaitem.01@316"]="Tiny Pile of Tungstensteel Dust",["gregtech:gt.metaitem.01@329"]="Tiny Pile of Tritanium Dust",["gregtech:gt.metaitem.01@370"]="Tiny Pile of Tungstencarbide Dust",["gregtech:gt.metaitem.01@374"]="Tiny Pile of HSS-S Dust",["gregtech:gt.metaitem.01@388"]="Tiny Pile of Black Plutonium Dust",["gregtech:gt.metaitem.01@70"]="Tiny Pile of Europium Dust",["gregtech:gt.metaitem.01@815"]="Tiny Pile of Ashes",["gregtech:gt.metaitem.01@816"]="Tiny Pile of Dark Ashes",["gregtech:gt.metaitem.01@85"]="Tiny Pile of Platinum Dust"},["evidence"]={["implosionRecipes"]=1096,["matchedRecipes"]=1096,["sourceVersion"]="2.9.0-beta-2"}}
end)()
local SingularityData=(function()
-- Source: source/data/singularities.json
return {["names"]={"minecraft:dye","minecraft:lapis_block","Avaritia:Singularity","minecraft:gold_ingot","minecraft:gold_block","gregtech:gt.metaitem.01","gregtech:gt.blockmetal6","minecraft:iron_ingot","minecraft:iron_block","minecraft:redstone","minecraft:redstone_block","gregtech:gt.blockmetal7","gregtech:gt.blockmetal4","gregtech:gt.blockmetal2","minecraft:quartz","minecraft:quartz_block","gregtech:gt.blockmetal5","gregtech:gt.blockmetal3","minecraft:coal","minecraft:coal_block","universalsingularities:universal.vanilla.singularity","minecraft:diamond","minecraft:diamond_block","minecraft:emerald","minecraft:emerald_block","gregtech:gt.blockgem3","universalsingularities:universal.general.singularity","gregtech:gt.blockmetal1","gregtech:gt.blockgem2","gregtech:gt.blockmetal8","Thaumcraft:ItemResource","thaumicbases:quicksilverBlock","minecraft:nether_star","DraconicEvolution:draconium","universalsingularities:universal.draconicEvolution.singularity","DraconicEvolution:draconicBlock","EnderIO:blockIngotStorage","universalsingularities:universal.enderIO.singularity","EnderIO:itemAlloy","ExtraUtilities:unstableingot","ExtraUtilities:decorativeBlock1","universalsingularities:universal.extraUtilities.singularity","ProjRed|Core:projectred.core.part","ProjRed|Exploration:projectred.exploration.stone","universalsingularities:universal.projectRed.singularity","TConstruct:MetalBlock","universalsingularities:universal.tinkersConstruct.singularity","minecraft:ender_pearl","gregtech:gt.blockgem1"},["items"]={{["name"]=1,["damage"]=4,["label"]="Lapis Lazuli"},{["name"]=2,["damage"]=0,["label"]="Lapis Lazuli Block"},{["name"]=3,["damage"]=2,["label"]="Lapis Singularity"},{["name"]=4,["damage"]=0,["label"]="Gold Ingot"},{["name"]=5,["damage"]=0,["label"]="Block of Gold"},{["name"]=3,["damage"]=1,["label"]="Golden Singularity"},{["name"]=6,["damage"]=11054,["label"]="Silver Ingot"},{["name"]=7,["damage"]=10,["label"]="Block of Silver"},{["name"]=3,["damage"]=8,["label"]="Silver Singularity"},{["name"]=8,["damage"]=0,["label"]="Iron Ingot"},{["name"]=9,["damage"]=0,["label"]="Block of Iron"},{["name"]=3,["damage"]=0,["label"]="Iron Singularity"},{["name"]=10,["damage"]=0,["label"]="Redstone Dust"},{["name"]=11,["damage"]=0,["label"]="Block of Redstone"},{["name"]=3,["damage"]=3,["label"]="Redstone Singularity"},{["name"]=6,["damage"]=11057,["label"]="Tin Ingot"},{["name"]=12,["damage"]=7,["label"]="Block of Tin"},{["name"]=3,["damage"]=6,["label"]="Tin Singularity"},{["name"]=6,["damage"]=11089,["label"]="Lead Ingot"},{["name"]=13,["damage"]=2,["label"]="Block of Lead"},{["name"]=3,["damage"]=7,["label"]="Leaden Singularity"},{["name"]=6,["damage"]=11035,["label"]="Copper Ingot"},{["name"]=14,["damage"]=7,["label"]="Block of Copper"},{["name"]=3,["damage"]=5,["label"]="Copper Singularity"},{["name"]=15,["damage"]=0,["label"]="Nether Quartz"},{["name"]=16,["damage"]=0,["label"]="Block of Quartz"},{["name"]=3,["damage"]=4,["label"]="Nether Quartz Singularity"},{["name"]=6,["damage"]=11034,["label"]="Nickel Ingot"},{["name"]=17,["damage"]=4,["label"]="Block of Nickel"},{["name"]=3,["damage"]=9,["label"]="Nickel Singularity"},{["name"]=6,["damage"]=11321,["label"]="Enderium Ingot"},{["name"]=18,["damage"]=1,["label"]="Block of Enderium"},{["name"]=3,["damage"]=10,["label"]="Enderium Singularity"},{["name"]=19,["damage"]=0,["label"]="Coal"},{["name"]=20,["damage"]=0,["label"]="Block of Coal"},{["name"]=21,["damage"]=0,["label"]="Coal Singularity"},{["name"]=22,["damage"]=0,["label"]="Diamond"},{["name"]=23,["damage"]=0,["label"]="Block of Diamond"},{["name"]=21,["damage"]=2,["label"]="Diamond Singularity"},{["name"]=24,["damage"]=0,["label"]="Emerald"},{["name"]=25,["damage"]=0,["label"]="Block of Emerald"},{["name"]=21,["damage"]=1,["label"]="Emerald Singularity"},{["name"]=19,["damage"]=1,["label"]="Charcoal"},{["name"]=26,["damage"]=4,["label"]="Block of Charcoal"},{["name"]=27,["damage"]=3,["label"]="Charcoal Singularity"},{["name"]=6,["damage"]=11019,["label"]="Aluminium Ingot"},{["name"]=28,["damage"]=1,["label"]="Block of Aluminium"},{["name"]=27,["damage"]=0,["label"]="Aluminum Singularity"},{["name"]=6,["damage"]=11301,["label"]="Brass Ingot"},{["name"]=28,["damage"]=15,["label"]="Block of Brass"},{["name"]=27,["damage"]=1,["label"]="Brass Singularity"},{["name"]=6,["damage"]=11300,["label"]="Bronze Ingot"},{["name"]=14,["damage"]=0,["label"]="Block of Bronze"},{["name"]=27,["damage"]=2,["label"]="Bronze Singularity"},{["name"]=6,["damage"]=11303,["label"]="Electrum Ingot"},{["name"]=14,["damage"]=15,["label"]="Block of Electrum"},{["name"]=27,["damage"]=4,["label"]="Electrum Singularity"},{["name"]=6,["damage"]=11302,["label"]="Invar Ingot"},{["name"]=18,["damage"]=11,["label"]="Block of Invar"},{["name"]=27,["damage"]=5,["label"]="Invar Singularity"},{["name"]=6,["damage"]=11018,["label"]="Magnesium Ingot"},{["name"]=13,["damage"]=5,["label"]="Block of Magnesium"},{["name"]=27,["damage"]=6,["label"]="Magnesium Singularity"},{["name"]=6,["damage"]=11083,["label"]="Osmium Ingot"},{["name"]=17,["damage"]=9,["label"]="Block of Osmium"},{["name"]=27,["damage"]=7,["label"]="Osmium Singularity"},{["name"]=6,["damage"]=8505,["label"]="Olivine"},{["name"]=29,["damage"]=4,["label"]="Block of Olivine"},{["name"]=27,["damage"]=8,["label"]="Peridot Singularity"},{["name"]=6,["damage"]=8502,["label"]="Ruby"},{["name"]=29,["damage"]=11,["label"]="Block of Ruby"},{["name"]=27,["damage"]=9,["label"]="Ruby Singularity"},{["name"]=6,["damage"]=8503,["label"]="Sapphire"},{["name"]=29,["damage"]=12,["label"]="Block of Sapphire"},{["name"]=27,["damage"]=10,["label"]="Sapphire Singularity"},{["name"]=6,["damage"]=11305,["label"]="Steel Ingot"},{["name"]=7,["damage"]=13,["label"]="Block of Steel"},{["name"]=27,["damage"]=11,["label"]="Steel Singularity"},{["name"]=6,["damage"]=11028,["label"]="Titanium Ingot"},{["name"]=12,["damage"]=9,["label"]="Block of Titanium"},{["name"]=27,["damage"]=12,["label"]="Titanium Singularity"},{["name"]=6,["damage"]=11081,["label"]="Tungsten Ingot"},{["name"]=12,["damage"]=11,["label"]="Block of Tungsten"},{["name"]=27,["damage"]=13,["label"]="Tungsten Singularity"},{["name"]=6,["damage"]=11098,["label"]="Uranium 238 Ingot"},{["name"]=12,["damage"]=14,["label"]="Block of Uranium 238"},{["name"]=27,["damage"]=14,["label"]="Uranium Singularity"},{["name"]=6,["damage"]=11036,["label"]="Zinc Ingot"},{["name"]=30,["damage"]=6,["label"]="Block of Zinc"},{["name"]=27,["damage"]=15,["label"]="Zinc Singularity"},{["name"]=6,["damage"]=8534,["label"]="Tricalcium Phosphate"},{["name"]=29,["damage"]=8,["label"]="Block of Tricalcium Phosphate"},{["name"]=27,["damage"]=16,["label"]="Tricalcium Phosphate Singularity"},{["name"]=6,["damage"]=11052,["label"]="Palladium Ingot"},{["name"]=17,["damage"]=10,["label"]="Block of Palladium"},{["name"]=27,["damage"]=17,["label"]="Palladium Singularity"},{["name"]=6,["damage"]=11335,["label"]="Damascus Steel Ingot"},{["name"]=14,["damage"]=9,["label"]="Block of Damascus Steel"},{["name"]=27,["damage"]=18,["label"]="Damascus Steel Singularity"},{["name"]=6,["damage"]=11334,["label"]="Black Steel Ingot"},{["name"]=28,["damage"]=12,["label"]="Block of Black Steel"},{["name"]=27,["damage"]=19,["label"]="Black Steel Singularity"},{["name"]=6,["damage"]=11320,["label"]="Fluxed Electrum Ingot"},{["name"]=18,["damage"]=0,["label"]="Block of Fluxed Electrum"},{["name"]=27,["damage"]=20,["label"]="Fluxed Electrum Singularity"},{["name"]=31,["damage"]=3,["label"]="Quicksilver"},{["name"]=32,["damage"]=0,["label"]="Quicksilver Block"},{["name"]=27,["damage"]=21,["label"]="Quicksilver Singularity"},{["name"]=6,["damage"]=11337,["label"]="Shadow Steel Ingot"},{["name"]=7,["damage"]=8,["label"]="Block of Shadow Steel"},{["name"]=27,["damage"]=22,["label"]="Shadow Steel Singularity"},{["name"]=6,["damage"]=11084,["label"]="Iridium Ingot"},{["name"]=18,["damage"]=12,["label"]="Block of Iridium"},{["name"]=27,["damage"]=23,["label"]="Iridium Singularity"},{["name"]=33,["damage"]=0,["label"]="Nether Star"},{["name"]=26,["damage"]=3,["label"]="Block of Nether Star"},{["name"]=27,["damage"]=24,["label"]="Nether Star Singularity"},{["name"]=6,["damage"]=11085,["label"]="Platinum Ingot"},{["name"]=17,["damage"]=12,["label"]="Block of Platinum"},{["name"]=27,["damage"]=25,["label"]="Platinum Singularity"},{["name"]=6,["damage"]=11327,["label"]="Naquadria Ingot"},{["name"]=13,["damage"]=15,["label"]="Block of Naquadria"},{["name"]=27,["damage"]=26,["label"]="Naquadria Singularity"},{["name"]=6,["damage"]=11100,["label"]="Plutonium 239 Ingot"},{["name"]=17,["damage"]=13,["label"]="Block of Plutonium 239"},{["name"]=27,["damage"]=27,["label"]="Plutonium Singularity"},{["name"]=6,["damage"]=11340,["label"]="Meteoric Iron Ingot"},{["name"]=13,["damage"]=7,["label"]="Block of Meteoric Iron"},{["name"]=27,["damage"]=28,["label"]="Meteoric Iron Singularity"},{["name"]=6,["damage"]=11884,["label"]="Desh Ingot"},{["name"]=14,["damage"]=12,["label"]="Block of Desh"},{["name"]=27,["damage"]=29,["label"]="Desh Singularity"},{["name"]=6,["damage"]=11070,["label"]="Europium Ingot"},{["name"]=18,["damage"]=3,["label"]="Block of Europium"},{["name"]=27,["damage"]=30,["label"]="Europium Singularity"},{["name"]=6,["damage"]=11975,["label"]="Draconium Ingot"},{["name"]=34,["damage"]=0,["label"]="Draconium Block"},{["name"]=35,["damage"]=0,["label"]="Draconium Singularity"},{["name"]=6,["damage"]=11976,["label"]="Awakened Draconium Ingot"},{["name"]=36,["damage"]=0,["label"]="Awakened Draconium Block"},{["name"]=35,["damage"]=1,["label"]="Awakened Draconium Singularity"},{["name"]=6,["damage"]=11369,["label"]="Conductive Iron Ingot"},{["name"]=37,["damage"]=4,["label"]="Conductive Iron Block"},{["name"]=38,["damage"]=0,["label"]="Conductive Iron Singularity"},{["name"]=6,["damage"]=11365,["label"]="Electrical Steel Ingot"},{["name"]=37,["damage"]=0,["label"]="Electrical Steel Block"},{["name"]=38,["damage"]=1,["label"]="Electrical Steel Singularity"},{["name"]=6,["damage"]=11366,["label"]="Energetic Alloy Ingot"},{["name"]=37,["damage"]=1,["label"]="Energetic Alloy Block"},{["name"]=38,["damage"]=2,["label"]="Energetic Alloy Singularity"},{["name"]=39,["damage"]=6,["label"]="Dark Steel"},{["name"]=37,["damage"]=6,["label"]="Dark Steel Block"},{["name"]=38,["damage"]=3,["label"]="Dark Steel Singularity"},{["name"]=6,["damage"]=11378,["label"]="Pulsating Iron Ingot"},{["name"]=37,["damage"]=5,["label"]="Pulsating Iron Block"},{["name"]=38,["damage"]=4,["label"]="Pulsating Iron Singularity"},{["name"]=6,["damage"]=11381,["label"]="Redstone Alloy Ingot"},{["name"]=37,["damage"]=3,["label"]="Redstone Alloy Block"},{["name"]=38,["damage"]=5,["label"]="Redstone Alloy Singularity"},{["name"]=6,["damage"]=11379,["label"]="Soularium Ingot"},{["name"]=37,["damage"]=7,["label"]="Soularium Block"},{["name"]=38,["damage"]=6,["label"]="Soularium Singularity"},{["name"]=6,["damage"]=11367,["label"]="Vibrant Alloy Ingot"},{["name"]=37,["damage"]=2,["label"]="Vibrant Alloy Block"},{["name"]=38,["damage"]=7,["label"]="Vibrant Alloy Singularity"},{["name"]=40,["damage"]=0,["label"]="Unstable Ingot"},{["name"]=41,["damage"]=5,["label"]="Unstable Ingot Block"},{["name"]=42,["damage"]=0,["label"]="Unstable Ingot Singularity"},{["name"]=40,["damage"]=2,["label"]="Mobius \"Unstable/Stable\" Ingot"},{["name"]=43,["damage"]=56,["label"]="Electrotine"},{["name"]=44,["damage"]=11,["label"]="Block of Electrotine"},{["name"]=45,["damage"]=0,["label"]="Electrotine Singularity"},{["name"]=6,["damage"]=11351,["label"]="Rose Gold Ingot"},{["name"]=7,["damage"]=3,["label"]="Block of Rose Gold"},{["name"]=27,["damage"]=32,["label"]="Rose Gold Singularity"},{["name"]=6,["damage"]=11400,["label"]="Obzinite Ingot"},{["name"]=46,["damage"]=8,["label"]="Block of Obzinite"},{["name"]=47,["damage"]=1,["label"]="Obzinite Singularity"},{["name"]=6,["damage"]=11382,["label"]="Ardite Ingot"},{["name"]=46,["damage"]=1,["label"]="Block of Ardite"},{["name"]=47,["damage"]=2,["label"]="Ardite Singularity"},{["name"]=6,["damage"]=11033,["label"]="Cobalt Ingot"},{["name"]=14,["damage"]=5,["label"]="Block of Cobalt"},{["name"]=47,["damage"]=3,["label"]="Cobalt Singularity"},{["name"]=48,["damage"]=0,["label"]="Ender Pearl"},{["name"]=49,["damage"]=8,["label"]="Block of Enderpearl"},{["name"]=47,["damage"]=4,["label"]="Ender Singularity"},{["name"]=6,["damage"]=11386,["label"]="Manyullyn Ingot"},{["name"]=46,["damage"]=2,["label"]="Block of Manyullyn"},{["name"]=47,["damage"]=6,["label"]="Manyullyn Singularity"}},["rules"]={{["input"]=9,["output"]=1,["eut"]=2},{["input"]=4,["output"]=1,["eut"]=2}},["groups"]={"Nitronic Singularity","Psychotic Singularity","Spaghettic Singularity","Pneumatic Singularity","Cryptic Singularity","Historic Singularity","Meteoric Singularity"},["materials"]={{["label"]="Lapis",["group"]=1,["raw"]=1,["block"]=2,["singularity"]=3,["blocks"]=1215,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="ULV",["tierSource"]="quest item"},{["label"]="Golden",["group"]=1,["raw"]=4,["block"]=5,["singularity"]=6,["blocks"]=1215,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="ULV",["tierSource"]="quest item"},{["label"]="Silver",["group"]=1,["raw"]=7,["block"]=8,["singularity"]=9,["blocks"]=7296,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="ULV",["tierSource"]="quest recipe ingredient"},{["label"]="Iron",["group"]=1,["raw"]=10,["block"]=11,["singularity"]=12,["blocks"]=7296,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="ULV",["tierSource"]="quest item"},{["label"]="Redstone",["group"]=1,["raw"]=13,["block"]=14,["singularity"]=15,["blocks"]=7296,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="ULV",["tierSource"]="quest item"},{["label"]="Tin",["group"]=1,["raw"]=16,["block"]=17,["singularity"]=18,["blocks"]=3648,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="ULV",["tierSource"]="quest item"},{["label"]="Leaden",["group"]=1,["raw"]=19,["block"]=20,["singularity"]=21,["blocks"]=3648,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="ULV",["tierSource"]="production route estimate"},{["label"]="Copper",["group"]=1,["raw"]=22,["block"]=23,["singularity"]=24,["blocks"]=3648,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="ULV",["tierSource"]="quest item"},{["label"]="Nether Quartz",["group"]=1,["raw"]=25,["block"]=26,["singularity"]=27,["blocks"]=1215,["yield"]=1,["compressor"]=2,["eut"]=480,["tier"]="ULV",["tierSource"]="quest item"},{["label"]="Nickel",["group"]=2,["raw"]=28,["block"]=29,["singularity"]=30,["blocks"]=3648,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="ULV",["tierSource"]="ore access estimate"},{["label"]="Enderium",["group"]=2,["raw"]=31,["block"]=32,["singularity"]=33,["blocks"]=608,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="IV",["tierSource"]="quest recipe ingredient"},{["label"]="Coal",["group"]=2,["raw"]=34,["block"]=35,["singularity"]=36,["blocks"]=3648,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="ULV",["tierSource"]="quest item"},{["label"]="Diamond",["group"]=2,["raw"]=37,["block"]=38,["singularity"]=39,["blocks"]=729,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="ULV",["tierSource"]="quest item"},{["label"]="Emerald",["group"]=2,["raw"]=40,["block"]=41,["singularity"]=42,["blocks"]=729,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="ULV",["tierSource"]="quest item"},{["label"]="Charcoal",["group"]=2,["raw"]=43,["block"]=44,["singularity"]=45,["blocks"]=7296,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="ULV",["tierSource"]="quest item"},{["label"]="Aluminum",["group"]=2,["raw"]=46,["block"]=47,["singularity"]=48,["blocks"]=1824,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="LV",["tierSource"]="quest item"},{["label"]="Brass",["group"]=2,["raw"]=49,["block"]=50,["singularity"]=51,["blocks"]=1824,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="ULV",["tierSource"]="production route estimate"},{["label"]="Bronze",["group"]=2,["raw"]=52,["block"]=53,["singularity"]=54,["blocks"]=1824,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="ULV",["tierSource"]="quest item"},{["label"]="Electrum",["group"]=3,["raw"]=55,["block"]=56,["singularity"]=57,["blocks"]=912,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="ULV",["tierSource"]="production route estimate"},{["label"]="Invar",["group"]=3,["raw"]=58,["block"]=59,["singularity"]=60,["blocks"]=1824,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="ULV",["tierSource"]="quest item"},{["label"]="Magnesium",["group"]=3,["raw"]=61,["block"]=62,["singularity"]=63,["blocks"]=3648,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="LV",["tierSource"]="quest item"},{["label"]="Osmium",["group"]=3,["raw"]=64,["block"]=65,["singularity"]=66,["blocks"]=406,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="IV",["tierSource"]="quest item"},{["label"]="Peridot",["group"]=3,["raw"]=67,["block"]=68,["singularity"]=69,["blocks"]=608,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="UV",["tierSource"]="ore access estimate"},{["label"]="Ruby",["group"]=3,["raw"]=70,["block"]=71,["singularity"]=72,["blocks"]=608,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="ULV",["tierSource"]="quest item"},{["label"]="Sapphire",["group"]=3,["raw"]=73,["block"]=74,["singularity"]=75,["blocks"]=608,["yield"]=1,["compressor"]=1,["eut"]=480},{["label"]="Steel",["group"]=3,["raw"]=76,["block"]=77,["singularity"]=78,["blocks"]=912,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="ULV",["tierSource"]="quest item"},{["label"]="Titanium",["group"]=3,["raw"]=79,["block"]=80,["singularity"]=81,["blocks"]=2024,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="HV",["tierSource"]="quest item"},{["label"]="Tungsten",["group"]=4,["raw"]=82,["block"]=83,["singularity"]=84,["blocks"]=244,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="HV",["tierSource"]="quest item"},{["label"]="Uranium",["group"]=4,["raw"]=85,["block"]=86,["singularity"]=87,["blocks"]=507,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="ULV",["tierSource"]="production route estimate"},{["label"]="Zinc",["group"]=4,["raw"]=88,["block"]=89,["singularity"]=90,["blocks"]=3648,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="ULV",["tierSource"]="ore access estimate"},{["label"]="Tricalcium Phosphate",["group"]=4,["raw"]=91,["block"]=92,["singularity"]=93,["blocks"]=365,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="ULV",["tierSource"]="quest item"},{["label"]="Palladium",["group"]=4,["raw"]=94,["block"]=95,["singularity"]=96,["blocks"]=136,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="IV",["tierSource"]="quest item"},{["label"]="Damascus Steel",["group"]=4,["raw"]=97,["block"]=98,["singularity"]=99,["blocks"]=153,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="LV",["tierSource"]="quest item"},{["label"]="Black Steel",["group"]=4,["raw"]=100,["block"]=101,["singularity"]=102,["blocks"]=304,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="HV",["tierSource"]="production route estimate"},{["label"]="Fluxed Electrum",["group"]=4,["raw"]=103,["block"]=104,["singularity"]=105,["blocks"]=16,["yield"]=1,["compressor"]=1,["eut"]=480},{["label"]="Quicksilver",["group"]=4,["raw"]=106,["block"]=107,["singularity"]=108,["blocks"]=1824,["yield"]=1,["compressor"]=1,["eut"]=480},{["label"]="Shadow Steel",["group"]=5,["raw"]=109,["block"]=110,["singularity"]=111,["blocks"]=406,["yield"]=1,["compressor"]=1,["eut"]=480},{["label"]="Iridium",["group"]=5,["raw"]=112,["block"]=113,["singularity"]=114,["blocks"]=62,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="IV",["tierSource"]="quest item"},{["label"]="Nether Star",["group"]=5,["raw"]=115,["block"]=116,["singularity"]=117,["blocks"]=512,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="LV",["tierSource"]="quest item"},{["label"]="Platinum",["group"]=5,["raw"]=118,["block"]=119,["singularity"]=120,["blocks"]=406,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="HV",["tierSource"]="quest item"},{["label"]="Naquadria",["group"]=5,["raw"]=121,["block"]=122,["singularity"]=123,["blocks"]=66,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="ZPM",["tierSource"]="quest item"},{["label"]="Plutonium",["group"]=5,["raw"]=124,["block"]=125,["singularity"]=126,["blocks"]=244,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="HV",["tierSource"]="production route estimate"},{["label"]="Meteoric Iron",["group"]=5,["raw"]=127,["block"]=128,["singularity"]=129,["blocks"]=912,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="HV",["tierSource"]="quest item"},{["label"]="Desh",["group"]=5,["raw"]=130,["block"]=131,["singularity"]=132,["blocks"]=203,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="HV",["tierSource"]="quest item"},{["label"]="Europium",["group"]=5,["raw"]=133,["block"]=134,["singularity"]=135,["blocks"]=62,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="IV",["tierSource"]="quest item"},{["label"]="Draconium",["group"]=6,["raw"]=136,["block"]=137,["singularity"]=138,["blocks"]=1296,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="EV",["tierSource"]="quest item"},{["label"]="Awakened Draconium",["group"]=6,["raw"]=139,["block"]=140,["singularity"]=141,["blocks"]=760,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="UHV",["tierSource"]="ore access estimate"},{["label"]="Conductive Iron",["group"]=6,["raw"]=142,["block"]=143,["singularity"]=144,["blocks"]=912,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="MV",["tierSource"]="quest item"},{["label"]="Electrical Steel",["group"]=6,["raw"]=145,["block"]=146,["singularity"]=147,["blocks"]=912,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="MV",["tierSource"]="quest item"},{["label"]="Energetic Alloy",["group"]=6,["raw"]=148,["block"]=149,["singularity"]=150,["blocks"]=191,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="HV",["tierSource"]="quest item"},{["label"]="Dark Steel",["group"]=6,["raw"]=151,["block"]=152,["singularity"]=153,["blocks"]=912,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="MV",["tierSource"]="quest item"},{["label"]="Pulsating Iron",["group"]=6,["raw"]=154,["block"]=155,["singularity"]=156,["blocks"]=912,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="MV",["tierSource"]="quest item"},{["label"]="Redstone Alloy",["group"]=6,["raw"]=157,["block"]=158,["singularity"]=159,["blocks"]=912,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="LV",["tierSource"]="quest item"},{["label"]="Soularium",["group"]=6,["raw"]=160,["block"]=161,["singularity"]=162,["blocks"]=456,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="MV",["tierSource"]="quest item"},{["label"]="Vibrant Alloy",["group"]=7,["raw"]=163,["block"]=164,["singularity"]=165,["blocks"]=145,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="HV",["tierSource"]="quest item"},{["label"]="Unstable Ingot",["group"]=7,["raw"]=166,["block"]=167,["singularity"]=168,["blocks"]=66,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="HV",["tierSource"]="quest recipe ingredient",["alternatives"]={{["key"]="unstable",["raw"]=166,["compressor"]=1},{["key"]="mobius",["raw"]=169,["compressor"]=1}}},{["label"]="Electrotine",["group"]=7,["raw"]=170,["block"]=171,["singularity"]=172,["blocks"]=1215,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="LV",["tierSource"]="quest item"},{["label"]="Rose Gold",["group"]=7,["raw"]=173,["block"]=174,["singularity"]=175,["blocks"]=1824,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="MV",["tierSource"]="production route estimate"},{["label"]="Obzinite",["group"]=7,["raw"]=176,["block"]=177,["singularity"]=178,["blocks"]=229,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="ULV",["tierSource"]="quest item"},{["label"]="Ardite",["group"]=7,["raw"]=179,["block"]=180,["singularity"]=181,["blocks"]=304,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="LV",["tierSource"]="quest item"},{["label"]="Cobalt",["group"]=7,["raw"]=182,["block"]=183,["singularity"]=184,["blocks"]=1824,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="LV",["tierSource"]="quest item"},{["label"]="Ender",["group"]=7,["raw"]=185,["block"]=186,["singularity"]=187,["blocks"]=608,["yield"]=1,["compressor"]=1,["eut"]=480,["tier"]="ULV",["tierSource"]="quest item"},{["label"]="Manyullyn",["group"]=7,["raw"]=188,["block"]=189,["singularity"]=190,["blocks"]=308,["yield"]=1,["compressor"]=1,["eut"]=480}},["version"]=1,["source"]={["recipeVersion"]="2.9.0-beta-2",["targetVersion"]="2.9.0-beta-3",["datasetId"]="local-2.9.0-beta-2",["baseSingularities"]=63,["combinedSingularities"]=7,["root"]="Eternal Singularity",["chainSource"]="https://github.com/GTNewHorizons/NewHorizonsCoreMod/blob/2.9.61/src/main/java/com/dreammaster/scripts/ScriptAvaritia.java",["batchPolicy"]="One singularity per pattern; block recipes follow global batch settings."},["evidence"]={["exports"]={["recipes.json.gz"]="2c09a018091ea934c1cf8f612f447796f17e31e4f9d9cb3b01b894746abe0fed",["NewHorizonsCoreMod-2.9.61.zip"]="11688b8b3bf3adb688865becf7e3e21b8e854968baa5df125b97819998856c71",["ores.json.gz"]="07c9526c3e78b9e1a5104c76c89013997a3b7b687ecc2b356150a72441fc23c2",["singularity-registry-names.json"]="3fed6e35727aecd920cfc1fdc77adde8c5a0cf0159b37f5f574be820ab4bca62",["Eternal-Singularity-1.4.3.zip"]="861630d1ced5594baa1cbe1b68b676b1405826d75bc9f5643b6633f91f307b94",["Draconic-Evolution-1.5.33-GTNH.zip"]="a66d56bb4374c186c71535fb408b83365a620a159e8ad263b0f8b53d409294c3",["ProjectRed-4.12.43-GTNH.zip"]="9c32b1d0dc92f5d469f38231921e468cae8e29708474e4d342b441c4e1e0e5ca"},["chain"]="6045bf12e1ea66d751d2a1b15456462dd4396498a379e8d38df918ed749e2ad1"}}
end)()
local ComponentData=(function()
-- Source: source/data/components.json
return {["components"]={{["key"]="motor",["label"]="Motor",["circuit"]=1},{["key"]="piston",["label"]="Piston",["circuit"]=2},{["key"]="pump",["label"]="Pump",["circuit"]=3},{["key"]="robotArm",["label"]="Robot Arm",["circuit"]=4},{["key"]="conveyor",["label"]="Conveyor",["circuit"]=5},{["key"]="emitter",["label"]="Emitter",["circuit"]=6},{["key"]="sensor",["label"]="Sensor",["circuit"]=7},{["key"]="fieldGenerator",["label"]="Field Generator",["circuit"]=8}},["casings"]={"LV","MV","HV","EV","IV","LuV","ZPM","UV","UHV","UEV","UIV","UMV","UXV"},["names"]={"gregtech:gt.blockmachines","gregtech:gt.integrated_circuit","molten.mutatedlivingsolder","dimensionallyshiftedsuperfluid","protohalkonitebase","molten.infinity","molten.transcendentmetal","molten.tengampurified","molten.celestialtungsten","gregtech:gt.metaitem.01","molten.creon","molten.mellion","molten.hypogen","molten.spacetime","GoodGenerator:circuitWrap","gregtech:gt.metaitem.03","molten.magnetohydrodynamicallyconstrainedstarmatter","molten.eternity","molten.universium","molten.magmatter","molten.superconductorumvbase","molten.silicone","molten.draconiumawakened","molten.styrenebutadienerubber","molten.radoxpoly","molten.kevlar","molten.quantium","gregtech:gt.blockframes","molten.arceusalloy2b","molten.lafiumcompound","molten.cinobitea243","molten.pikyonium64b","molten.quantum","molten.astraltitanium","molten.titansteel","lubricant","molten.cosmicneutronium","molten.indalloy140","molten.neutronium","molten.naquadria","molten.samarium","gregtech:gt.metaitem.02","molten.ruridit","molten.hsss","molten.europium","molten.naquadahalloy","molten.americium","molten.rubber","molten.niobiumtitanium","molten.enderium","molten.naquadah","molten.vanadiumgallium","molten.bedrockium","molten.draconium","molten.redsteel","molten.titanium","minecraft:nether_star","molten.hssg","molten.tritanium","molten.brass","minecraft:ender_pearl","molten.electrum","minecraft:ender_eye","molten.chrome","molten.platinum","molten.iridium","molten.gallium","molten.trinium","molten.osmiridium","molten.electrumflux","molten.infinitycatalyst","bartworks:gt.bwMetaGeneratedplateDense"},["items"]={{["type"]="item",["name"]=1,["label"]="16x Nether Star Cable",["damage"]=11361},{["type"]="item",["name"]=2,["label"]="Programmed Circuit",["damage"]=1},{["type"]="fluid",["name"]=3,["label"]="Mutated Living Solder"},{["type"]="fluid",["name"]=4,["label"]="Dimensionally Shifted Superfluid"},{["type"]="fluid",["name"]=5,["label"]="Molten Proto-Halkonite Steel Base"},{["type"]="fluid",["name"]=6,["label"]="Molten Infinity"},{["type"]="fluid",["name"]=7,["label"]="Molten Transcendent Metal"},{["type"]="fluid",["name"]=8,["label"]="Molten Purified Tengam"},{["type"]="fluid",["name"]=9,["label"]="Molten Celestial Tungsten"},{["type"]="item",["name"]=10,["label"]="Electric Motor (UIV)",["damage"]=32017},{["type"]="fluid",["name"]=11,["label"]="Molten Creon"},{["type"]="fluid",["name"]=12,["label"]="Molten Mellion"},{["type"]="item",["name"]=1,["label"]="16x Quantium Cable",["damage"]=11381},{["type"]="fluid",["name"]=13,["label"]="Molten Hypogen"},{["type"]="fluid",["name"]=14,["label"]="Molten SpaceTime"},{["type"]="item",["name"]=10,["label"]="Electric Motor (UMV)",["damage"]=32018},{["type"]="item",["name"]=10,["label"]="Energised Tesseract",["damage"]=32417},{["type"]="item",["name"]=15,["label"]="Wrap of UHV Circuits",["damage"]=9},{["type"]="item",["name"]=1,["label"]="16x SpaceTime Wire",["damage"]=2611},{["type"]="item",["name"]=16,["label"]="Gold Nanites",["damage"]=4086},{["type"]="fluid",["name"]=17,["label"]="Molten Magnetohydrodynamically Constrained Star Matter"},{["type"]="fluid",["name"]=18,["label"]="Molten Eternity"},{["type"]="fluid",["name"]=19,["label"]="Molten Universium"},{["type"]="fluid",["name"]=20,["label"]="Molten Magmatter"},{["type"]="fluid",["name"]=21,["label"]="Molten Superconductor Base UMV"},{["type"]="item",["name"]=10,["label"]="Electric Motor (UXV)",["damage"]=32019},{["type"]="item",["name"]=10,["label"]="Dense Transcendent Metal Plate",["damage"]=22581},{["type"]="item",["name"]=2,["label"]="Programmed Circuit",["damage"]=2},{["type"]="item",["name"]=10,["label"]="Electric Piston (UIV)",["damage"]=32021},{["type"]="item",["name"]=10,["label"]="Dense SpaceTime Plate",["damage"]=22588},{["type"]="item",["name"]=10,["label"]="Electric Piston (UMV)",["damage"]=32022},{["type"]="item",["name"]=10,["label"]="Electric Piston (UXV)",["damage"]=32023},{["type"]="item",["name"]=2,["label"]="Programmed Circuit",["damage"]=3},{["type"]="fluid",["name"]=22,["label"]="Molten Silicone Rubber",["polymer"]="silicone"},{["type"]="fluid",["name"]=23,["label"]="Molten Awakened Draconium"},{["type"]="item",["name"]=10,["label"]="Electric Pump (UIV)",["damage"]=32025},{["type"]="fluid",["name"]=24,["label"]="Molten Styrene-Butadiene Rubber (SBR)",["polymer"]="sbr"},{["type"]="item",["name"]=10,["label"]="Electric Pump (UMV)",["damage"]=32026},{["type"]="fluid",["name"]=25,["label"]="Molten Radox Polymer"},{["type"]="fluid",["name"]=26,["label"]="Molten Kevlar"},{["type"]="item",["name"]=10,["label"]="Electric Pump (UXV)",["damage"]=32027},{["type"]="item",["name"]=2,["label"]="Programmed Circuit",["damage"]=5},{["type"]="item",["name"]=10,["label"]="Conveyor Module (UIV)",["damage"]=32029},{["type"]="item",["name"]=10,["label"]="Conveyor Module (UMV)",["damage"]=32030},{["type"]="item",["name"]=10,["label"]="Conveyor Module (UXV)",["damage"]=32031},{["type"]="item",["name"]=15,["label"]="Wrap of UIV Circuits",["damage"]=11},{["type"]="item",["name"]=15,["label"]="Wrap of UEV Circuits",["damage"]=10},{["type"]="item",["name"]=2,["label"]="Programmed Circuit",["damage"]=4},{["type"]="item",["name"]=10,["label"]="Robot Arm (UIV)",["damage"]=32033},{["type"]="item",["name"]=15,["label"]="Wrap of UMV Circuits",["damage"]=12},{["type"]="fluid",["name"]=27,["label"]="Molten Quantium"},{["type"]="item",["name"]=10,["label"]="Robot Arm (UMV)",["damage"]=32034},{["type"]="item",["name"]=15,["label"]="Wrap of UXV Circuits",["damage"]=13},{["type"]="item",["name"]=10,["label"]="Robot Arm (UXV)",["damage"]=32035},{["type"]="item",["name"]=28,["label"]="Transcendent Metal Frame Box",["damage"]=581},{["type"]="item",["name"]=16,["label"]="Nuclear Star",["damage"]=32230},{["type"]="item",["name"]=2,["label"]="Programmed Circuit",["damage"]=6},{["type"]="fluid",["name"]=29,["label"]="Molten Arceus Alloy 2B"},{["type"]="fluid",["name"]=30,["label"]="Molten Lafium Compound"},{["type"]="fluid",["name"]=31,["label"]="Molten Cinobite A243"},{["type"]="fluid",["name"]=32,["label"]="Molten Pikyonium 64B"},{["type"]="item",["name"]=10,["label"]="Emitter (UIV)",["damage"]=32037},{["type"]="item",["name"]=28,["label"]="SpaceTime Frame Box",["damage"]=588},{["type"]="fluid",["name"]=33,["label"]="Molten Quantum"},{["type"]="fluid",["name"]=34,["label"]="Molten Astral Titanium"},{["type"]="fluid",["name"]=35,["label"]="Molten Titansteel"},{["type"]="item",["name"]=10,["label"]="Emitter (UMV)",["damage"]=32038},{["type"]="item",["name"]=28,["label"]="Magnetohydrodynamically Constrained Star Matter Frame Box",["damage"]=583},{["type"]="item",["name"]=10,["label"]="Emitter (UXV)",["damage"]=32039},{["type"]="item",["name"]=2,["label"]="Programmed Circuit",["damage"]=7},{["type"]="item",["name"]=10,["label"]="Sensor (UIV)",["damage"]=32041},{["type"]="item",["name"]=10,["label"]="Sensor (UMV)",["damage"]=32042},{["type"]="item",["name"]=10,["label"]="Sensor (UXV)",["damage"]=32043},{["type"]="item",["name"]=2,["label"]="Programmed Circuit",["damage"]=8},{["type"]="item",["name"]=10,["label"]="Field Generator (UIV)",["damage"]=32045},{["type"]="item",["name"]=10,["label"]="Field Generator (UMV)",["damage"]=32046},{["type"]="item",["name"]=15,["label"]="Wrap of MAX Circuits",["damage"]=14},{["type"]="item",["name"]=10,["label"]="Field Generator (UXV)",["damage"]=32047},{["type"]="item",["name"]=1,["label"]="16x Draconium Cable",["damage"]=11341},{["type"]="fluid",["name"]=36,["label"]="Lubricant"},{["type"]="fluid",["name"]=37,["label"]="Molten Cosmic Neutronium"},{["type"]="item",["name"]=10,["label"]="Electric Motor (UEV)",["damage"]=32595},{["type"]="item",["name"]=1,["label"]="16x Bedrockium Cable",["damage"]=11321},{["type"]="fluid",["name"]=38,["label"]="Molten Indalloy 140"},{["type"]="fluid",["name"]=39,["label"]="Molten Neutronium"},{["type"]="fluid",["name"]=40,["label"]="Molten Naquadria"},{["type"]="fluid",["name"]=41,["label"]="Molten Samarium"},{["type"]="item",["name"]=10,["label"]="Electric Motor (UHV)",["damage"]=32596},{["type"]="item",["name"]=42,["label"]="Long Magnetic Iron Rod",["damage"]=22354},{["type"]="item",["name"]=42,["label"]="Long Iron Rod",["damage"]=22032},{["type"]="item",["name"]=1,["label"]="16x Copper Wire",["damage"]=1365},{["type"]="item",["name"]=1,["label"]="16x Tin Cable",["damage"]=1251},{["type"]="item",["name"]=10,["label"]="Electric Motor (LV)",["damage"]=32600},{["type"]="item",["name"]=42,["label"]="Long Magnetic Steel Rod",["damage"]=22355},{["type"]="item",["name"]=42,["label"]="Long Steel Rod",["damage"]=22305},{["type"]="item",["name"]=1,["label"]="16x Annealed Copper Wire",["damage"]=1385},{["type"]="item",["name"]=42,["label"]="Long Aluminium Rod",["damage"]=22019},{["type"]="item",["name"]=1,["label"]="16x Cupronickel Wire",["damage"]=1345},{["type"]="item",["name"]=1,["label"]="16x Copper Cable",["damage"]=1371},{["type"]="item",["name"]=10,["label"]="Electric Motor (MV)",["damage"]=32601},{["type"]="item",["name"]=1,["label"]="16x Annealed Copper Cable",["damage"]=1391},{["type"]="item",["name"]=42,["label"]="Long Stainless Steel Rod",["damage"]=22306},{["type"]="item",["name"]=1,["label"]="16x Electrum Wire",["damage"]=1445},{["type"]="item",["name"]=1,["label"]="16x Silver Cable",["damage"]=1471},{["type"]="item",["name"]=10,["label"]="Electric Motor (HV)",["damage"]=32602},{["type"]="item",["name"]=42,["label"]="Long Magnetic Neodymium Rod",["damage"]=22356},{["type"]="item",["name"]=42,["label"]="Long Titanium Rod",["damage"]=22028},{["type"]="item",["name"]=1,["label"]="16x Black Steel Wire",["damage"]=1545},{["type"]="item",["name"]=1,["label"]="16x Aluminium Cable",["damage"]=1591},{["type"]="item",["name"]=10,["label"]="Electric Motor (EV)",["damage"]=32603},{["type"]="item",["name"]=42,["label"]="Long Tungstensteel Rod",["damage"]=22316},{["type"]="item",["name"]=1,["label"]="16x Graphene Wire",["damage"]=1605},{["type"]="item",["name"]=1,["label"]="16x Tungsten Cable",["damage"]=1691},{["type"]="item",["name"]=10,["label"]="Electric Motor (IV)",["damage"]=32604},{["type"]="item",["name"]=42,["label"]="Long Magnetic Samarium Rod",["damage"]=22399},{["type"]="item",["name"]=1,["label"]="16x Yttrium Barium Cuprate Cable",["damage"]=1771},{["type"]="fluid",["name"]=43,["label"]="Molten Ruridit"},{["type"]="fluid",["name"]=44,["label"]="Molten HSS-S"},{["type"]="item",["name"]=10,["label"]="Electric Motor (LuV)",["damage"]=32606},{["type"]="item",["name"]=1,["label"]="16x Vanadium-Gallium Cable",["damage"]=1751},{["type"]="fluid",["name"]=45,["label"]="Molten Europium"},{["type"]="fluid",["name"]=46,["label"]="Molten Naquadah Alloy"},{["type"]="item",["name"]=10,["label"]="Electric Motor (ZPM)",["damage"]=32607},{["type"]="item",["name"]=1,["label"]="16x Naquadah Alloy Cable",["damage"]=1811},{["type"]="fluid",["name"]=47,["label"]="Molten Americium"},{["type"]="item",["name"]=10,["label"]="Electric Motor (UV)",["damage"]=32608},{["type"]="item",["name"]=42,["label"]="Tin Rotor",["damage"]=21057},{["type"]="item",["name"]=10,["label"]="Tin Screw",["damage"]=27057},{["type"]="item",["name"]=1,["label"]="Bronze Fluid Pipe",["damage"]=5122},{["type"]="fluid",["name"]=48,["label"]="Molten Rubber",["polymer"]="rubber"},{["type"]="item",["name"]=10,["label"]="Electric Pump (LV)",["damage"]=32610},{["type"]="item",["name"]=42,["label"]="Bronze Rotor",["damage"]=21300},{["type"]="item",["name"]=10,["label"]="Bronze Screw",["damage"]=27300},{["type"]="item",["name"]=1,["label"]="Steel Fluid Pipe",["damage"]=5132},{["type"]="item",["name"]=10,["label"]="Electric Pump (MV)",["damage"]=32611},{["type"]="item",["name"]=42,["label"]="Steel Rotor",["damage"]=21305},{["type"]="item",["name"]=10,["label"]="Steel Screw",["damage"]=27305},{["type"]="item",["name"]=1,["label"]="16x Gold Cable",["damage"]=1431},{["type"]="item",["name"]=1,["label"]="Stainless Steel Fluid Pipe",["damage"]=5142},{["type"]="item",["name"]=10,["label"]="Electric Pump (HV)",["damage"]=32612},{["type"]="item",["name"]=42,["label"]="Stainless Steel Rotor",["damage"]=21306},{["type"]="item",["name"]=10,["label"]="Stainless Steel Screw",["damage"]=27306},{["type"]="item",["name"]=1,["label"]="Titanium Fluid Pipe",["damage"]=5152},{["type"]="item",["name"]=10,["label"]="Electric Pump (EV)",["damage"]=32613},{["type"]="item",["name"]=42,["label"]="Tungstensteel Rotor",["damage"]=21316},{["type"]="item",["name"]=10,["label"]="Tungstensteel Screw",["damage"]=27316},{["type"]="item",["name"]=1,["label"]="Tungstensteel Fluid Pipe",["damage"]=5162},{["type"]="item",["name"]=10,["label"]="Electric Pump (IV)",["damage"]=32614},{["type"]="item",["name"]=10,["label"]="Dense HSS-S Plate",["damage"]=22374},{["type"]="fluid",["name"]=49,["label"]="Molten Niobium-Titanium"},{["type"]="item",["name"]=10,["label"]="Electric Pump (LuV)",["damage"]=32615},{["type"]="item",["name"]=10,["label"]="Dense Naquadah Alloy Plate",["damage"]=22325},{["type"]="fluid",["name"]=50,["label"]="Molten Enderium"},{["type"]="item",["name"]=10,["label"]="Electric Pump (ZPM)",["damage"]=32616},{["type"]="item",["name"]=10,["label"]="Dense Neutronium Plate",["damage"]=22129},{["type"]="fluid",["name"]=51,["label"]="Molten Naquadah"},{["type"]="item",["name"]=10,["label"]="Electric Pump (UV)",["damage"]=32617},{["type"]="item",["name"]=10,["label"]="Dense Cosmic Neutronium Plate",["damage"]=22982},{["type"]="item",["name"]=10,["label"]="Electric Pump (UHV)",["damage"]=32618},{["type"]="item",["name"]=1,["label"]="Large Nether Star Fluid Pipe",["damage"]=5223},{["type"]="item",["name"]=10,["label"]="Dense Infinity Plate",["damage"]=22397},{["type"]="item",["name"]=10,["label"]="Electric Pump (UEV)",["damage"]=32619},{["type"]="item",["name"]=10,["label"]="Dense Rubber Sheet",["polymer"]="rubber",["damage"]=22880},{["type"]="item",["name"]=10,["label"]="Conveyor Module (LV)",["damage"]=32630},{["type"]="item",["name"]=10,["label"]="Dense Silicone Rubber Sheet",["polymer"]="silicone",["damage"]=22471},{["type"]="item",["name"]=10,["label"]="Dense Styrene-Butadiene Rubber (SBR) Sheet",["polymer"]="sbr",["damage"]=22635},{["type"]="item",["name"]=10,["label"]="Conveyor Module (MV)",["damage"]=32631},{["type"]="item",["name"]=10,["label"]="Conveyor Module (HV)",["damage"]=32632},{["type"]="item",["name"]=10,["label"]="Conveyor Module (EV)",["damage"]=32633},{["type"]="item",["name"]=10,["label"]="Conveyor Module (IV)",["damage"]=32634},{["type"]="item",["name"]=10,["label"]="Conveyor Module (LuV)",["damage"]=32635},{["type"]="item",["name"]=10,["label"]="Conveyor Module (ZPM)",["damage"]=32636},{["type"]="item",["name"]=10,["label"]="Conveyor Module (UV)",["damage"]=32637},{["type"]="item",["name"]=10,["label"]="Conveyor Module (UHV)",["damage"]=32638},{["type"]="item",["name"]=10,["label"]="Conveyor Module (UEV)",["damage"]=32639},{["type"]="item",["name"]=10,["label"]="Dense Steel Plate",["damage"]=22305},{["type"]="item",["name"]=42,["label"]="Steel Gear",["damage"]=31305},{["type"]="item",["name"]=10,["label"]="Electric Piston (LV)",["damage"]=32640},{["type"]="item",["name"]=10,["label"]="Dense Aluminium Plate",["damage"]=22019},{["type"]="item",["name"]=42,["label"]="Aluminium Gear",["damage"]=31019},{["type"]="item",["name"]=10,["label"]="Electric Piston (MV)",["damage"]=32641},{["type"]="item",["name"]=10,["label"]="Dense Stainless Steel Plate",["damage"]=22306},{["type"]="item",["name"]=42,["label"]="Stainless Steel Gear",["damage"]=31306},{["type"]="item",["name"]=10,["label"]="Electric Piston (HV)",["damage"]=32642},{["type"]="item",["name"]=10,["label"]="Dense Titanium Plate",["damage"]=22028},{["type"]="item",["name"]=42,["label"]="Titanium Gear",["damage"]=31028},{["type"]="item",["name"]=10,["label"]="Electric Piston (EV)",["damage"]=32643},{["type"]="item",["name"]=10,["label"]="Dense Tungstensteel Plate",["damage"]=22316},{["type"]="item",["name"]=42,["label"]="Tungstensteel Gear",["damage"]=31316},{["type"]="item",["name"]=10,["label"]="Electric Piston (IV)",["damage"]=32644},{["type"]="item",["name"]=10,["label"]="Electric Piston (LuV)",["damage"]=32645},{["type"]="item",["name"]=10,["label"]="Electric Piston (ZPM)",["damage"]=32646},{["type"]="item",["name"]=10,["label"]="Electric Piston (UV)",["damage"]=32647},{["type"]="item",["name"]=10,["label"]="Electric Piston (UHV)",["damage"]=32648},{["type"]="item",["name"]=10,["label"]="Electric Piston (UEV)",["damage"]=32649},{["type"]="item",["name"]=15,["label"]="Wrap of LV Circuits",["damage"]=1},{["type"]="item",["name"]=10,["label"]="Robot Arm (LV)",["damage"]=32650},{["type"]="item",["name"]=15,["label"]="Wrap of MV Circuits",["damage"]=2},{["type"]="item",["name"]=10,["label"]="Robot Arm (MV)",["damage"]=32651},{["type"]="item",["name"]=15,["label"]="Wrap of HV Circuits",["damage"]=3},{["type"]="item",["name"]=10,["label"]="Robot Arm (HV)",["damage"]=32652},{["type"]="item",["name"]=15,["label"]="Wrap of EV Circuits",["damage"]=4},{["type"]="item",["name"]=10,["label"]="Robot Arm (EV)",["damage"]=32653},{["type"]="item",["name"]=15,["label"]="Wrap of IV Circuits",["damage"]=5},{["type"]="item",["name"]=10,["label"]="Robot Arm (IV)",["damage"]=32654},{["type"]="item",["name"]=15,["label"]="Wrap of LuV Circuits",["damage"]=6},{["type"]="item",["name"]=10,["label"]="Robot Arm (LuV)",["damage"]=32655},{["type"]="item",["name"]=15,["label"]="Wrap of ZPM Circuits",["damage"]=7},{["type"]="fluid",["name"]=52,["label"]="Molten Vanadium-Gallium"},{["type"]="item",["name"]=10,["label"]="Robot Arm (ZPM)",["damage"]=32656},{["type"]="item",["name"]=15,["label"]="Wrap of UV Circuits",["damage"]=8},{["type"]="item",["name"]=10,["label"]="Robot Arm (UV)",["damage"]=32657},{["type"]="fluid",["name"]=53,["label"]="Molten Bedrockium"},{["type"]="item",["name"]=10,["label"]="Robot Arm (UHV)",["damage"]=32658},{["type"]="fluid",["name"]=54,["label"]="Molten Draconium"},{["type"]="item",["name"]=10,["label"]="Robot Arm (UEV)",["damage"]=32659},{["type"]="item",["name"]=10,["label"]="Enderpearl Plate",["damage"]=17532},{["type"]="fluid",["name"]=55,["label"]="Molten Red Steel"},{["type"]="item",["name"]=10,["label"]="Field Generator (LV)",["damage"]=32670},{["type"]="item",["name"]=10,["label"]="Endereye Plate",["damage"]=17533},{["type"]="fluid",["name"]=56,["label"]="Molten Titanium"},{["type"]="item",["name"]=10,["label"]="Field Generator (MV)",["damage"]=32671},{["type"]="item",["name"]=10,["label"]="Quantum Eye",["damage"]=32724},{["type"]="item",["name"]=10,["label"]="Field Generator (HV)",["damage"]=32672},{["type"]="item",["name"]=57,["label"]="Nether Star",["damage"]=0},{["type"]="fluid",["name"]=58,["label"]="Molten HSS-G"},{["type"]="item",["name"]=10,["label"]="Field Generator (EV)",["damage"]=32673},{["type"]="item",["name"]=10,["label"]="Quantum Star",["damage"]=32725},{["type"]="item",["name"]=10,["label"]="Field Generator (IV)",["damage"]=32674},{["type"]="item",["name"]=28,["label"]="HSS-S Frame Box",["damage"]=374},{["type"]="item",["name"]=10,["label"]="Emitter (LuV)",["damage"]=32685},{["type"]="item",["name"]=10,["label"]="Field Generator (LuV)",["damage"]=32675},{["type"]="item",["name"]=28,["label"]="Naquadah Alloy Frame Box",["damage"]=325},{["type"]="item",["name"]=10,["label"]="Emitter (ZPM)",["damage"]=32686},{["type"]="item",["name"]=10,["label"]="Field Generator (ZPM)",["damage"]=32676},{["type"]="item",["name"]=28,["label"]="Neutronium Frame Box",["damage"]=129},{["type"]="item",["name"]=10,["label"]="Gravi Star",["damage"]=32726},{["type"]="item",["name"]=10,["label"]="Emitter (UV)",["damage"]=32687},{["type"]="item",["name"]=10,["label"]="Field Generator (UV)",["damage"]=32677},{["type"]="item",["name"]=28,["label"]="Cosmic Neutronium Frame Box",["damage"]=982},{["type"]="item",["name"]=10,["label"]="Emitter (UHV)",["damage"]=32688},{["type"]="item",["name"]=10,["label"]="Field Generator (UHV)",["damage"]=32678},{["type"]="item",["name"]=28,["label"]="Infinity Frame Box",["damage"]=397},{["type"]="item",["name"]=10,["label"]="Emitter (UEV)",["damage"]=32689},{["type"]="fluid",["name"]=59,["label"]="Molten Tritanium"},{["type"]="item",["name"]=10,["label"]="Field Generator (UEV)",["damage"]=32679},{["type"]="item",["name"]=10,["label"]="Certus Quartz",["damage"]=8516},{["type"]="fluid",["name"]=60,["label"]="Molten Brass"},{["type"]="item",["name"]=10,["label"]="Emitter (LV)",["damage"]=32680},{["type"]="item",["name"]=61,["label"]="Ender Pearl",["damage"]=0},{["type"]="fluid",["name"]=62,["label"]="Molten Electrum"},{["type"]="item",["name"]=10,["label"]="Emitter (MV)",["damage"]=32681},{["type"]="item",["name"]=63,["label"]="Eye of Ender",["damage"]=0},{["type"]="fluid",["name"]=64,["label"]="Molten Chrome"},{["type"]="item",["name"]=10,["label"]="Emitter (HV)",["damage"]=32682},{["type"]="fluid",["name"]=65,["label"]="Molten Platinum"},{["type"]="item",["name"]=10,["label"]="Emitter (EV)",["damage"]=32683},{["type"]="fluid",["name"]=66,["label"]="Molten Iridium"},{["type"]="item",["name"]=10,["label"]="Emitter (IV)",["damage"]=32684},{["type"]="fluid",["name"]=67,["label"]="Molten Gallium"},{["type"]="fluid",["name"]=68,["label"]="Molten Trinium"},{["type"]="fluid",["name"]=69,["label"]="Molten Osmiridium"},{["type"]="fluid",["name"]=70,["label"]="Molten Fluxed Electrum"},{["type"]="fluid",["name"]=71,["label"]="Molten Infinity Catalyst"},{["type"]="item",["name"]=42,["label"]="Long Brass Rod",["damage"]=22301},{["type"]="item",["name"]=10,["label"]="Sensor (LV)",["damage"]=32690},{["type"]="item",["name"]=42,["label"]="Flawless Emerald",["damage"]=29501},{["type"]="item",["name"]=42,["label"]="Long Electrum Rod",["damage"]=22303},{["type"]="item",["name"]=10,["label"]="Sensor (MV)",["damage"]=32691},{["type"]="item",["name"]=42,["label"]="Long Chrome Rod",["damage"]=22030},{["type"]="item",["name"]=10,["label"]="Sensor (HV)",["damage"]=32692},{["type"]="item",["name"]=42,["label"]="Long Platinum Rod",["damage"]=22085},{["type"]="item",["name"]=10,["label"]="Sensor (EV)",["damage"]=32693},{["type"]="item",["name"]=42,["label"]="Long Iridium Rod",["damage"]=22084},{["type"]="item",["name"]=10,["label"]="Sensor (IV)",["damage"]=32694},{["type"]="item",["name"]=72,["label"]="Dense Ruridit Plate",["damage"]=90},{["type"]="item",["name"]=10,["label"]="Sensor (LuV)",["damage"]=32695},{["type"]="item",["name"]=10,["label"]="Dense Osmiridium Plate",["damage"]=22317},{["type"]="item",["name"]=10,["label"]="Sensor (ZPM)",["damage"]=32696},{["type"]="item",["name"]=10,["label"]="Sensor (UV)",["damage"]=32697},{["type"]="item",["name"]=10,["label"]="Sensor (UHV)",["damage"]=32698},{["type"]="item",["name"]=10,["label"]="Sensor (UEV)",["damage"]=32699}},["recipes"]={{["component"]=1,["tier"]="LV",["casing"]=1,["output"]=93,["yield"]=64,["eut"]=7,["inputs"]={{94,24},{95,48},{96,12},{92,6}},["stock"]={},["variants"]={{["remove"]={96},["set"]={{91,12}}},{["remove"]={94,95},["set"]={{89,24},{90,48}}},{["remove"]={94,95,96},["set"]={{89,24},{90,48},{91,12}}}}},{["component"]=1,["tier"]="MV",["casing"]=2,["output"]=100,["yield"]=64,["eut"]=30,["inputs"]={{94,24},{97,48},{98,24},{101,6}},["stock"]={},["variants"]={{["remove"]={101},["set"]={{99,6}}}}},{["component"]=1,["tier"]="HV",["casing"]=3,["output"]=105,["yield"]=64,["eut"]=120,["inputs"]={{94,24},{102,48},{103,48},{104,12}},["stock"]={},["variants"]={}},{["component"]=1,["tier"]="EV",["casing"]=4,["output"]=110,["yield"]=64,["eut"]=480,["inputs"]={{106,24},{107,48},{108,48},{109,12}},["stock"]={},["variants"]={}},{["component"]=1,["tier"]="IV",["casing"]=5,["output"]=114,["yield"]=64,["eut"]=1920,["inputs"]={{106,24},{111,48},{112,48},{113,12}},["stock"]={{2,1}},["variants"]={}},{["component"]=1,["tier"]="LuV",["casing"]=6,["output"]=119,["yield"]=64,["eut"]=7680,["inputs"]={{115,24},{116,6},{84,6912},{80,12000},{117,110592},{118,13824}},["stock"]={{2,1}},["variants"]={}},{["component"]=1,["tier"]="ZPM",["casing"]=7,["output"]=123,["yield"]=64,["eut"]=30720,["inputs"]={{115,48},{120,24},{84,13824},{80,36000},{121,165888},{122,46848}},["stock"]={{2,1}},["variants"]={}},{["component"]=1,["tier"]="UV",["casing"]=8,["output"]=126,["yield"]=64,["eut"]=122880,["inputs"]={{124,24},{84,62208},{80,96000},{125,331776},{86,62208},{85,46848},{87,13824}},["stock"]={{2,1}},["variants"]={}},{["component"]=1,["tier"]="UHV",["casing"]=9,["output"]=88,["yield"]=64,["eut"]=491520,["inputs"]={{83,24},{84,124416},{80,192000},{85,442368},{86,124416},{81,93696},{87,27648}},["stock"]={{2,1}},["variants"]={}},{["component"]=1,["tier"]="UEV",["casing"]=10,["output"]=82,["yield"]=64,["eut"]=1966080,["inputs"]={{79,24},{3,124416},{80,192000},{81,442368},{6,148992},{51,124416},{8,55296}},["stock"]={{2,1}},["variants"]={}},{["component"]=1,["tier"]="UIV",["casing"]=11,["output"]=10,["yield"]=64,["eut"]=7864320,["inputs"]={{1,24},{3,124416},{4,302592},{5,442368},{6,442368},{7,148992},{8,110592},{9,27648}},["stock"]={{2,1}},["variants"]={{["remove"]={6},["set"]={{5,221184},{11,221184},{12,221184}}}}},{["component"]=1,["tier"]="UMV",["casing"]=12,["output"]=16,["yield"]=64,["eut"]=31457280,["inputs"]={{13,24},{3,124416},{4,192000},{14,470016},{8,221184},{15,148992},{9,27648}},["stock"]={{2,1}},["variants"]={}},{["component"]=1,["tier"]="UXV",["casing"]=13,["output"]=26,["yield"]=64,["eut"]=125829120,["inputs"]={{17,48},{18,114},{19,48},{20,12},{4,384000},{21,287232},{22,259584},{23,138240},{24,110592},{25,110592},{15,27648}},["stock"]={{2,1}},["variants"]={}},{["component"]=2,["tier"]="LV",["casing"]=1,["output"]=178,["yield"]=64,["eut"]=7,["inputs"]={{93,48},{176,16},{95,48},{92,6},{177,12}},["stock"]={},["variants"]={}},{["component"]=2,["tier"]="MV",["casing"]=2,["output"]=181,["yield"]=64,["eut"]=30,["inputs"]={{100,48},{179,16},{97,48},{99,6},{180,12}},["stock"]={},["variants"]={}},{["component"]=2,["tier"]="HV",["casing"]=3,["output"]=184,["yield"]=64,["eut"]=120,["inputs"]={{105,48},{182,16},{102,48},{138,6},{183,12}},["stock"]={},["variants"]={}},{["component"]=2,["tier"]="EV",["casing"]=4,["output"]=187,["yield"]=64,["eut"]=480,["inputs"]={{110,48},{185,16},{107,48},{109,6},{186,12}},["stock"]={},["variants"]={}},{["component"]=2,["tier"]="IV",["casing"]=5,["output"]=190,["yield"]=64,["eut"]=1920,["inputs"]={{114,48},{188,16},{111,48},{113,6},{189,12}},["stock"]={{28,1}},["variants"]={}},{["component"]=2,["tier"]="LuV",["casing"]=6,["output"]=191,["yield"]=64,["eut"]=7680,["inputs"]={{119,48},{149,32},{116,12},{84,6912},{80,12000},{118,86784}},["stock"]={{28,1}},["variants"]={}},{["component"]=2,["tier"]="ZPM",["casing"]=7,["output"]=192,["yield"]=64,["eut"]=30720,["inputs"]={{123,48},{152,32},{120,48},{84,13824},{80,36000},{122,86784}},["stock"]={{28,1}},["variants"]={}},{["component"]=2,["tier"]="UV",["casing"]=8,["output"]=193,["yield"]=64,["eut"]=122880,["inputs"]={{126,48},{155,32},{124,48},{84,62208},{80,96000},{85,86784},{86,62208}},["stock"]={{28,1}},["variants"]={}},{["component"]=2,["tier"]="UHV",["casing"]=9,["output"]=194,["yield"]=64,["eut"]=491520,["inputs"]={{88,48},{158,32},{83,48},{84,124416},{80,192000},{81,173568},{86,124416}},["stock"]={{28,1}},["variants"]={}},{["component"]=2,["tier"]="UEV",["casing"]=10,["output"]=195,["yield"]=64,["eut"]=1966080,["inputs"]={{82,48},{161,32},{79,48},{3,124416},{80,192000},{6,173568},{51,124416}},["stock"]={{28,1}},["variants"]={}},{["component"]=2,["tier"]="UIV",["casing"]=11,["output"]=29,["yield"]=64,["eut"]=7864320,["inputs"]={{10,48},{27,32},{1,48},{3,124416},{4,192000},{7,173568},{9,27648}},["stock"]={{28,1}},["variants"]={}},{["component"]=2,["tier"]="UMV",["casing"]=12,["output"]=31,["yield"]=64,["eut"]=31457280,["inputs"]={{16,48},{30,32},{13,48},{3,124416},{4,192000},{15,173568},{14,27648},{9,27648}},["stock"]={{28,1}},["variants"]={}},{["component"]=2,["tier"]="UXV",["casing"]=13,["output"]=32,["yield"]=64,["eut"]=125829120,["inputs"]={{26,48},{18,84},{20,12},{4,384000},{21,242688},{22,215040},{15,138240},{24,82944},{23,27648}},["stock"]={{28,1}},["variants"]={}},{["component"]=3,["tier"]="LV",["casing"]=1,["output"]=131,["yield"]=64,["eut"]=7,["inputs"]={{93,48},{127,48},{128,48},{92,3},{129,48},{37,3456}},["stock"]={},["variants"]={{["remove"]={37},["set"]={{130,3456}}},{["remove"]={37},["set"]={{34,3456}}}}},{["component"]=3,["tier"]="MV",["casing"]=2,["output"]=135,["yield"]=64,["eut"]=30,["inputs"]={{100,48},{132,48},{133,48},{99,3},{134,48},{130,3456}},["stock"]={},["variants"]={{["remove"]={130},["set"]={{37,3456}}},{["remove"]={130},["set"]={{34,3456}}}}},{["component"]=3,["tier"]="HV",["casing"]=3,["output"]=140,["yield"]=64,["eut"]=120,["inputs"]={{105,48},{136,48},{137,48},{138,3},{139,48},{130,3456}},["stock"]={},["variants"]={{["remove"]={130},["set"]={{37,3456}}},{["remove"]={130},["set"]={{34,3456}}}}},{["component"]=3,["tier"]="EV",["casing"]=4,["output"]=144,["yield"]=64,["eut"]=480,["inputs"]={{110,48},{141,48},{142,48},{109,3},{143,48},{37,3456}},["stock"]={},["variants"]={{["remove"]={37},["set"]={{34,3456}}},{["remove"]={37},["set"]={{130,3456}}}}},{["component"]=3,["tier"]="IV",["casing"]=5,["output"]=148,["yield"]=64,["eut"]=1920,["inputs"]={{114,48},{145,48},{146,48},{113,3},{147,48},{34,3456}},["stock"]={{33,1}},["variants"]={{["remove"]={34},["set"]={{37,3456}}}}},{["component"]=3,["tier"]="LuV",["casing"]=6,["output"]=151,["yield"]=64,["eut"]=7680,["inputs"]={{119,48},{149,10},{116,6},{84,6912},{80,12000},{118,64896},{150,13824},{34,6912}},["stock"]={{33,1}},["variants"]={{["remove"]={34},["set"]={{37,6912}}}}},{["component"]=3,["tier"]="ZPM",["casing"]=7,["output"]=154,["yield"]=64,["eut"]=30720,["inputs"]={{123,48},{152,10},{120,24},{84,13824},{80,36000},{122,64896},{153,41472},{37,13824}},["stock"]={{33,1}},["variants"]={{["remove"]={37},["set"]={{34,13824}}}}},{["component"]=3,["tier"]="UV",["casing"]=8,["output"]=157,["yield"]=64,["eut"]=122880,["inputs"]={{126,48},{155,10},{124,24},{84,62208},{80,96000},{156,82944},{85,64896},{86,62208},{34,27648}},["stock"]={{33,1}},["variants"]={{["remove"]={34},["set"]={{37,27648}}}}},{["component"]=3,["tier"]="UHV",["casing"]=9,["output"]=159,["yield"]=64,["eut"]=491520,["inputs"]={{88,48},{158,21},{83,24},{84,124416},{80,192000},{81,129792},{86,124416},{85,82944},{37,55296}},["stock"]={{33,1}},["variants"]={{["remove"]={37},["set"]={{34,55296}}}}},{["component"]=3,["tier"]="UEV",["casing"]=10,["output"]=162,["yield"]=64,["eut"]=1966080,["inputs"]={{82,48},{160,96},{161,21},{79,24},{3,124416},{80,192000},{6,129792},{51,124416},{37,110592}},["stock"]={{33,1}},["variants"]={{["remove"]={37},["set"]={{34,110592}}}}},{["component"]=3,["tier"]="UIV",["casing"]=11,["output"]=36,["yield"]=64,["eut"]=7864320,["inputs"]={{10,48},{27,21},{1,24},{3,124416},{4,192000},{7,129792},{34,110592},{35,82944},{9,27648}},["stock"]={{33,1}},["variants"]={{["remove"]={34},["set"]={{37,110592}}}}},{["component"]=3,["tier"]="UMV",["casing"]=12,["output"]=38,["yield"]=64,["eut"]=31457280,["inputs"]={{16,48},{30,21},{13,24},{3,124416},{4,192000},{15,129792},{34,110592},{6,82944},{14,27648},{9,27648}},["stock"]={{33,1}},["variants"]={{["remove"]={34},["set"]={{37,110592}}}}},{["component"]=3,["tier"]="UXV",["casing"]=13,["output"]=41,["yield"]=64,["eut"]=125829120,["inputs"]={{26,48},{18,42},{19,48},{20,12},{4,384000},{21,185088},{22,157440},{24,117504},{39,110592},{40,110592},{15,110592},{23,27648}},["stock"]={{33,1}},["variants"]={}},{["component"]=4,["tier"]="LV",["casing"]=1,["output"]=197,["yield"]=64,["eut"]=7,["inputs"]={{93,96},{178,48},{95,48},{196,3},{92,9}},["stock"]={},["variants"]={}},{["component"]=4,["tier"]="MV",["casing"]=2,["output"]=199,["yield"]=64,["eut"]=30,["inputs"]={{100,96},{181,48},{97,48},{198,3},{99,9}},["stock"]={},["variants"]={}},{["component"]=4,["tier"]="HV",["casing"]=3,["output"]=201,["yield"]=64,["eut"]=120,["inputs"]={{105,96},{184,48},{102,48},{200,3},{138,9}},["stock"]={},["variants"]={}},{["component"]=4,["tier"]="EV",["casing"]=4,["output"]=203,["yield"]=64,["eut"]=480,["inputs"]={{110,96},{187,48},{107,48},{202,3},{109,9}},["stock"]={},["variants"]={}},{["component"]=4,["tier"]="IV",["casing"]=5,["output"]=205,["yield"]=64,["eut"]=1920,["inputs"]={{114,96},{190,48},{111,48},{204,3},{113,9}},["stock"]={{48,1}},["variants"]={}},{["component"]=4,["tier"]="LuV",["casing"]=6,["output"]=207,["yield"]=64,["eut"]=7680,["inputs"]={{119,96},{191,48},{206,6},{204,12},{202,24},{116,18},{84,27648},{80,12000},{118,76032}},["stock"]={{48,1}},["variants"]={}},{["component"]=4,["tier"]="ZPM",["casing"]=7,["output"]=210,["yield"]=64,["eut"]=30720,["inputs"]={{123,96},{192,48},{208,6},{206,12},{204,24},{84,55296},{80,36000},{209,82944},{122,76032}},["stock"]={{48,1}},["variants"]={}},{["component"]=4,["tier"]="UV",["casing"]=8,["output"]=212,["yield"]=64,["eut"]=122880,["inputs"]={{126,96},{193,48},{211,6},{208,12},{206,24},{84,110592},{80,96000},{122,82944},{85,76032},{86,62208}},["stock"]={{48,1}},["variants"]={}},{["component"]=4,["tier"]="UHV",["casing"]=9,["output"]=214,["yield"]=64,["eut"]=491520,["inputs"]={{88,96},{194,48},{18,6},{211,12},{208,24},{84,124416},{80,192000},{81,152064},{86,124416},{213,82944}},["stock"]={{48,1}},["variants"]={}},{["component"]=4,["tier"]="UEV",["casing"]=10,["output"]=216,["yield"]=64,["eut"]=1966080,["inputs"]={{82,96},{195,48},{47,6},{18,12},{211,24},{3,124416},{80,192000},{6,152064},{51,124416},{215,82944}},["stock"]={{48,1}},["variants"]={}},{["component"]=4,["tier"]="UIV",["casing"]=11,["output"]=49,["yield"]=64,["eut"]=7864320,["inputs"]={{10,96},{29,48},{46,6},{47,12},{18,24},{1,72},{3,124416},{4,192000},{7,152064},{9,27648}},["stock"]={{48,1}},["variants"]={}},{["component"]=4,["tier"]="UMV",["casing"]=12,["output"]=52,["yield"]=64,["eut"]=31457280,["inputs"]={{16,96},{31,48},{50,6},{46,12},{47,24},{3,124416},{4,192000},{15,152064},{51,82944},{14,27648},{9,27648}},["stock"]={{48,1}},["variants"]={}},{["component"]=4,["tier"]="UXV",["casing"]=13,["output"]=54,["yield"]=64,["eut"]=125829120,["inputs"]={{26,96},{32,48},{53,6},{50,12},{46,24},{18,54},{20,24},{4,384000},{15,193536},{21,179712},{22,152064},{24,96768},{23,27648}},["stock"]={{48,1}},["variants"]={}},{["component"]=5,["tier"]="LV",["casing"]=1,["output"]=164,["yield"]=64,["eut"]=7,["inputs"]={{93,96},{166,32},{92,3}},["stock"]={},["variants"]={{["remove"]={166},["set"]={{163,32}}},{["remove"]={166},["set"]={{165,32}}}}},{["component"]=5,["tier"]="MV",["casing"]=2,["output"]=167,["yield"]=64,["eut"]=30,["inputs"]={{100,96},{163,32},{99,3}},["stock"]={},["variants"]={{["remove"]={163},["set"]={{165,32}}},{["remove"]={163},["set"]={{166,32}}}}},{["component"]=5,["tier"]="HV",["casing"]=3,["output"]=168,["yield"]=64,["eut"]=120,["inputs"]={{105,96},{163,32},{138,3}},["stock"]={},["variants"]={{["remove"]={163},["set"]={{165,32}}},{["remove"]={163},["set"]={{166,32}}}}},{["component"]=5,["tier"]="EV",["casing"]=4,["output"]=169,["yield"]=64,["eut"]=480,["inputs"]={{110,96},{165,32},{109,3}},["stock"]={},["variants"]={{["remove"]={165},["set"]={{163,32}}},{["remove"]={165},["set"]={{166,32}}}}},{["component"]=5,["tier"]="IV",["casing"]=5,["output"]=170,["yield"]=64,["eut"]=1920,["inputs"]={{114,96},{165,32},{113,3}},["stock"]={{42,1}},["variants"]={{["remove"]={165},["set"]={{166,32}}}}},{["component"]=5,["tier"]="LuV",["casing"]=6,["output"]=171,["yield"]=64,["eut"]=7680,["inputs"]={{119,96},{149,10},{116,6},{165,53},{84,6912},{80,12000},{118,31488}},["stock"]={{42,1}},["variants"]={{["remove"]={165},["set"]={{166,53}}}}},{["component"]=5,["tier"]="ZPM",["casing"]=7,["output"]=172,["yield"]=64,["eut"]=30720,["inputs"]={{123,96},{152,10},{120,24},{84,13824},{80,36000},{34,137376},{122,31488}},["stock"]={{42,1}},["variants"]={{["remove"]={34},["set"]={{37,137376}}}}},{["component"]=5,["tier"]="UV",["casing"]=8,["output"]=173,["yield"]=64,["eut"]=122880,["inputs"]={{126,96},{155,10},{124,24},{84,62208},{80,96000},{34,276048},{86,62208},{85,31488}},["stock"]={{42,1}},["variants"]={{["remove"]={34},["set"]={{37,276048}}}}},{["component"]=5,["tier"]="UHV",["casing"]=9,["output"]=174,["yield"]=64,["eut"]=491520,["inputs"]={{88,96},{158,10},{83,24},{84,124416},{80,192000},{37,276048},{86,124416},{81,62976}},["stock"]={{42,1}},["variants"]={{["remove"]={37},["set"]={{34,276048}}}}},{["component"]=5,["tier"]="UEV",["casing"]=10,["output"]=175,["yield"]=64,["eut"]=1966080,["inputs"]={{82,96},{161,10},{79,24},{3,124416},{80,192000},{34,552096},{51,124416},{6,62976}},["stock"]={{42,1}},["variants"]={{["remove"]={34},["set"]={{37,552096}}}}},{["component"]=5,["tier"]="UIV",["casing"]=11,["output"]=43,["yield"]=64,["eut"]=7864320,["inputs"]={{10,96},{27,10},{1,24},{3,124416},{4,192000},{34,552096},{7,62976},{9,27648}},["stock"]={{42,1}},["variants"]={{["remove"]={34},["set"]={{37,552096}}}}},{["component"]=5,["tier"]="UMV",["casing"]=12,["output"]=44,["yield"]=64,["eut"]=31457280,["inputs"]={{16,96},{30,10},{13,24},{3,124416},{4,192000},{37,552096},{15,62976},{14,27648},{9,27648}},["stock"]={{42,1}},["variants"]={{["remove"]={37},["set"]={{34,552096}}}}},{["component"]=5,["tier"]="UXV",["casing"]=13,["output"]=45,["yield"]=64,["eut"]=125829120,["inputs"]={{26,96},{18,36},{19,48},{20,12},{4,384000},{39,552096},{40,552096},{21,104448},{22,76800},{15,27648},{23,27648}},["stock"]={{42,1}},["variants"]={}},{["component"]=6,["tier"]="LV",["casing"]=1,["output"]=249,["yield"]=64,["eut"]=7,["inputs"]={{247,48},{196,6},{92,6},{248,13824}},["stock"]={},["variants"]={}},{["component"]=6,["tier"]="MV",["casing"]=2,["output"]=252,["yield"]=64,["eut"]=30,["inputs"]={{250,48},{198,6},{99,6},{251,13824}},["stock"]={},["variants"]={}},{["component"]=6,["tier"]="HV",["casing"]=3,["output"]=255,["yield"]=64,["eut"]=120,["inputs"]={{253,48},{200,6},{138,6},{254,13824}},["stock"]={},["variants"]={}},{["component"]=6,["tier"]="EV",["casing"]=4,["output"]=257,["yield"]=64,["eut"]=480,["inputs"]={{223,48},{202,6},{109,6},{256,13824}},["stock"]={},["variants"]={}},{["component"]=6,["tier"]="IV",["casing"]=5,["output"]=259,["yield"]=64,["eut"]=1920,["inputs"]={{228,48},{204,6},{113,6},{258,13824}},["stock"]={{57,1}},["variants"]={}},{["component"]=6,["tier"]="LuV",["casing"]=6,["output"]=231,["yield"]=64,["eut"]=7680,["inputs"]={{230,48},{119,48},{228,48},{206,12},{116,21},{84,27648},{260,331776},{117,27648}},["stock"]={{57,1}},["variants"]={}},{["component"]=6,["tier"]="ZPM",["casing"]=7,["output"]=234,["yield"]=64,["eut"]=30720,["inputs"]={{233,48},{123,48},{228,96},{208,12},{84,55296},{261,331776},{209,96768},{262,27648}},["stock"]={{57,1}},["variants"]={}},{["component"]=6,["tier"]="UV",["casing"]=8,["output"]=238,["yield"]=64,["eut"]=122880,["inputs"]={{236,48},{126,48},{237,192},{211,12},{84,110592},{86,393984},{122,96768},{85,27648}},["stock"]={{57,1}},["variants"]={}},{["component"]=6,["tier"]="UHV",["casing"]=9,["output"]=241,["yield"]=64,["eut"]=491520,["inputs"]={{240,48},{88,48},{237,384},{18,12},{84,124416},{263,442368},{86,124416},{213,96768},{81,27648}},["stock"]={{57,1}},["variants"]={}},{["component"]=6,["tier"]="UEV",["casing"]=10,["output"]=244,["yield"]=64,["eut"]=1966080,["inputs"]={{243,48},{82,48},{237,768},{47,12},{3,124416},{264,442368},{51,124416},{215,96768},{6,55296}},["stock"]={{57,1}},["variants"]={}},{["component"]=6,["tier"]="UIV",["casing"]=11,["output"]=62,["yield"]=64,["eut"]=7864320,["inputs"]={{55,48},{10,48},{56,96},{46,12},{1,84},{3,124416},{58,110592},{59,110592},{60,110592},{61,110592},{7,55296},{9,27648}},["stock"]={{57,1}},["variants"]={}},{["component"]=6,["tier"]="UMV",["casing"]=12,["output"]=67,["yield"]=64,["eut"]=31457280,["inputs"]={{63,48},{16,48},{56,192},{50,12},{3,124416},{9,138240},{64,110592},{65,110592},{66,110592},{51,96768},{15,55296},{14,27648}},["stock"]={{57,1}},["variants"]={}},{["component"]=6,["tier"]="UXV",["casing"]=13,["output"]=69,["yield"]=64,["eut"]=125829120,["inputs"]={{68,48},{26,48},{56,768},{53,12},{18,48},{20,24},{3,691200},{15,331776},{21,193536},{22,165888},{23,138240},{24,110592}},["stock"]={{57,1}},["variants"]={}},{["component"]=7,["tier"]="LV",["casing"]=1,["output"]=266,["yield"]=64,["eut"]=7,["inputs"]={{247,48},{176,21},{265,24},{196,3}},["stock"]={},["variants"]={}},{["component"]=7,["tier"]="MV",["casing"]=2,["output"]=269,["yield"]=64,["eut"]=30,["inputs"]={{267,48},{179,21},{268,24},{198,3}},["stock"]={},["variants"]={}},{["component"]=7,["tier"]="HV",["casing"]=3,["output"]=271,["yield"]=64,["eut"]=120,["inputs"]={{253,48},{182,21},{270,24},{200,3}},["stock"]={},["variants"]={}},{["component"]=7,["tier"]="EV",["casing"]=4,["output"]=273,["yield"]=64,["eut"]=480,["inputs"]={{223,48},{185,21},{272,24},{202,3}},["stock"]={},["variants"]={}},{["component"]=7,["tier"]="IV",["casing"]=5,["output"]=275,["yield"]=64,["eut"]=1920,["inputs"]={{228,48},{188,21},{274,24},{204,3}},["stock"]={{70,1}},["variants"]={}},{["component"]=7,["tier"]="LuV",["casing"]=6,["output"]=277,["yield"]=64,["eut"]=7680,["inputs"]={{230,48},{119,48},{276,42},{228,48},{206,12},{116,21},{84,27648},{260,331776}},["stock"]={{70,1}},["variants"]={}},{["component"]=7,["tier"]="ZPM",["casing"]=7,["output"]=279,["yield"]=64,["eut"]=30720,["inputs"]={{233,48},{123,48},{278,42},{228,96},{208,12},{84,55296},{261,331776},{209,96768}},["stock"]={{70,1}},["variants"]={}},{["component"]=7,["tier"]="UV",["casing"]=8,["output"]=280,["yield"]=64,["eut"]=122880,["inputs"]={{236,48},{126,48},{155,42},{237,192},{211,12},{84,110592},{86,393984},{122,96768}},["stock"]={{70,1}},["variants"]={}},{["component"]=7,["tier"]="UHV",["casing"]=9,["output"]=281,["yield"]=64,["eut"]=491520,["inputs"]={{240,48},{88,48},{158,42},{237,384},{18,12},{84,124416},{263,442368},{86,124416},{213,96768}},["stock"]={{70,1}},["variants"]={}},{["component"]=7,["tier"]="UEV",["casing"]=10,["output"]=282,["yield"]=64,["eut"]=1966080,["inputs"]={{243,48},{82,48},{161,42},{237,768},{47,12},{3,124416},{264,442368},{51,124416},{215,96768}},["stock"]={{70,1}},["variants"]={}},{["component"]=7,["tier"]="UIV",["casing"]=11,["output"]=71,["yield"]=64,["eut"]=7864320,["inputs"]={{55,48},{10,48},{27,42},{56,96},{46,12},{1,84},{3,124416},{58,110592},{59,110592},{60,110592},{61,110592},{9,27648}},["stock"]={{70,1}},["variants"]={}},{["component"]=7,["tier"]="UMV",["casing"]=12,["output"]=72,["yield"]=64,["eut"]=31457280,["inputs"]={{63,48},{16,48},{30,42},{56,192},{50,12},{3,124416},{9,138240},{64,110592},{65,110592},{66,110592},{51,96768},{14,27648}},["stock"]={{70,1}},["variants"]={}},{["component"]=7,["tier"]="UXV",["casing"]=13,["output"]=73,["yield"]=64,["eut"]=125829120,["inputs"]={{68,48},{26,48},{56,768},{53,12},{18,48},{20,24},{3,691200},{15,331776},{21,193536},{22,165888},{23,138240},{24,110592}},["stock"]={{70,1}},["variants"]={}},{["component"]=8,["tier"]="LV",["casing"]=1,["output"]=219,["yield"]=64,["eut"]=7,["inputs"]={{217,48},{200,12},{218,13824}},["stock"]={},["variants"]={}},{["component"]=8,["tier"]="MV",["casing"]=2,["output"]=222,["yield"]=64,["eut"]=30,["inputs"]={{220,48},{202,12},{221,13824}},["stock"]={},["variants"]={}},{["component"]=8,["tier"]="HV",["casing"]=3,["output"]=224,["yield"]=64,["eut"]=120,["inputs"]={{223,48},{204,12},{150,27648}},["stock"]={},["variants"]={}},{["component"]=8,["tier"]="EV",["casing"]=4,["output"]=227,["yield"]=64,["eut"]=480,["inputs"]={{225,48},{206,12},{226,27648}},["stock"]={},["variants"]={}},{["component"]=8,["tier"]="IV",["casing"]=5,["output"]=229,["yield"]=64,["eut"]=1920,["inputs"]={{228,48},{208,12},{118,27648}},["stock"]={{74,1}},["variants"]={}},{["component"]=8,["tier"]="LuV",["casing"]=6,["output"]=232,["yield"]=64,["eut"]=7680,["inputs"]={{230,48},{149,32},{228,96},{231,192},{208,12},{116,24},{84,27648},{117,221184}},["stock"]={{74,1}},["variants"]={}},{["component"]=8,["tier"]="ZPM",["casing"]=7,["output"]=235,["yield"]=64,["eut"]=30720,["inputs"]={{233,48},{152,32},{228,96},{234,192},{211,12},{84,55296},{121,221184},{209,110592}},["stock"]={{74,1}},["variants"]={}},{["component"]=8,["tier"]="UV",["casing"]=8,["output"]=239,["yield"]=64,["eut"]=122880,["inputs"]={{236,48},{155,32},{237,96},{238,192},{18,12},{84,110592},{125,331776},{122,110592},{86,62208}},["stock"]={{74,1}},["variants"]={}},{["component"]=8,["tier"]="UHV",["casing"]=9,["output"]=242,["yield"]=64,["eut"]=491520,["inputs"]={{240,48},{158,32},{237,192},{241,192},{47,12},{84,124416},{85,442368},{86,124416},{213,110592}},["stock"]={{74,1}},["variants"]={}},{["component"]=8,["tier"]="UEV",["casing"]=10,["output"]=246,["yield"]=64,["eut"]=1966080,["inputs"]={{243,48},{161,32},{237,384},{244,192},{46,12},{3,124416},{245,442368},{51,124416},{215,110592}},["stock"]={{74,1}},["variants"]={}},{["component"]=8,["tier"]="UIV",["casing"]=11,["output"]=75,["yield"]=64,["eut"]=7864320,["inputs"]={{55,48},{27,32},{56,48},{62,192},{50,12},{1,96},{3,124416},{4,110592},{5,221184},{11,221184},{12,221184},{9,27648}},["stock"]={{74,1}},["variants"]={{["remove"]={11,12},["set"]={{5,442368},{6,442368}}}}},{["component"]=8,["tier"]="UMV",["casing"]=12,["output"]=76,["yield"]=64,["eut"]=31457280,["inputs"]={{63,48},{30,32},{56,96},{67,192},{53,12},{3,124416},{14,470016},{51,110592},{9,27648}},["stock"]={{74,1}},["variants"]={}},{["component"]=8,["tier"]="UXV",["casing"]=13,["output"]=78,["yield"]=64,["eut"]=125829120,["inputs"]={{68,48},{56,3072},{69,192},{77,12},{18,66},{20,36},{3,691200},{15,248832},{21,179712},{22,152064},{23,138240},{24,110592},{25,110592}},["stock"]={{74,1}},["variants"]={}}},["version"]=1,["source"]={["recipeVersion"]="2.9.0-beta-2",["targetVersion"]="2.9.0-beta-3",["datasetId"]="local-2.9.0-beta-2",["routes"]=142,["recipeSource"]="https://github.com/GTNewHorizons/GT5-Unofficial/blob/5.09.54.133/src/main/java/goodgenerator/loader/ComponentAssemblyLineLoader.java",["batchPolicy"]="Native batches of 64 components; shared tier gates and casing limit apply."},["evidence"]={["loader"]="efb805c09383ded4f62bda937501337710df64667437737dd52ed4e5cfa5f26f",["machine"]="478c4355439be58254c7ffca9692aefefd96ec4b6cc0484c537337ccc997501c",["exports"]={["recipes.json.gz"]="2c09a018091ea934c1cf8f612f447796f17e31e4f9d9cb3b01b894746abe0fed",["gt-5.09.54.133.zip"]="a5993a25fbf464348182baac16539bcf08bdfa18d22ef0217dc84fc4c14ca03e",["registry-names.json"]="1ab9505d6e2e0c1c59300908801927e0da04edc506ba53b0e21f67e531657e9a",["ores.json.gz"]="07c9526c3e78b9e1a5104c76c89013997a3b7b687ecc2b356150a72441fc23c2"}}}
end)()
local Batch=(function()
-- Source: source/lib/batch.lua
-- Shared batch policy. Tier definitions are built from source/data/tiers.json.
local U = U
local Tiers = TierDefinitions
local MaterialUnits = MaterialUnits
local M = { tiers = Tiers.names, fields = {} }
local index = {}
for n, name in ipairs(M.tiers) do
  index[name] = n
end

function M.voltageTier(eut)
  if type(eut) ~= 'number' or eut < 0 then
    return nil
  end
  for n, voltage in ipairs(Tiers.voltages) do
    if eut <= voltage then
      return M.tiers[n]
    end
  end
  return 'MAX'
end

local group = 'Policy'
local function field(key, label, default, help, kind, choices)
  M.fields[#M.fields + 1] = {
    key = key,
    label = label,
    default = default,
    help = help,
    kind = kind or 'positiveInteger',
    choices = choices,
    group = group,
    placeholder = kind == 'optionalPositiveInteger' and 'Follow relative curve' or nil,
  }
end
local tierChoices = {}
for _, name in ipairs(M.tiers) do
  tierChoices[#tierChoices + 1] = { name, name }
end
local voltageChoices = { { 'current', 'Current progression tier' } }
for _, option in ipairs(tierChoices) do
  voltageChoices[#voltageChoices + 1] = option
end
field(
  'mode',
  'Batch policy',
  'tiered',
  'Fixed uses each program multiplier. Tiered applies the shared curve and quantity limits.',
  'choice',
  { { 'fixed', 'Fixed' }, { 'tiered', 'Tiered' } }
)
field(
  'currentTier',
  'Current progression tier',
  'LuV',
  'Select your current tier. Later materials are skipped unless enabled.',
  'select',
  tierChoices
)
field(
  'abovePolicy',
  'Include materials above your tier',
  'skip',
  '',
  'choice',
  { { 'skip', 'Skip' }, { 'fixed', 'Include' } }
)
field(
  'aboveMultiplier',
  'Later material multiplier',
  '1',
  'Used only when later materials are included.'
)
field(
  'unknownPolicy',
  'Unclassified materials',
  'voltage',
  'Recipe voltage is an estimate of material tier, not proof of accessibility.',
  'choice',
  { { 'voltage', 'Use recipe voltage' }, { 'fixed', 'Fixed fallback' }, { 'skip', 'Skip' } }
)
field(
  'unknownMultiplier',
  'Unclassified fallback multiplier',
  '1',
  'Also used when recipe voltage is missing.'
)
field(
  'voltagePolicy',
  'Recipe voltage constraint',
  'cap',
  'When enabled, cap batches by voltage and skip recipes above the reference tier.',
  'choice',
  { { 'off', 'Ignore voltage' }, { 'cap', 'Cap by voltage' } }
)
field(
  'voltageTier',
  'Voltage reference tier',
  'current',
  'Follow progression or select the voltage available to your machines.',
  'select',
  voltageChoices
)
field(
  'itemLimit',
  'Maximum items per pattern ingredient',
  '4096',
  'Shrink the whole batch together to preserve proportions.'
)
field(
  'fluidLimit',
  'Maximum fluid per pattern ingredient (mB)',
  '589824',
  'Fluid inputs and outputs share this per-ingredient limit.'
)
group = 'Batch sizing'
field(
  'costScaling',
  'Scale batches by material input',
  'on',
  'Divide fixed or tiered batches by consumed material in ingots; round down, minimum one batch.',
  'toggle'
)

field(
  'curveMode',
  'Multiplier curve',
  'generated',
  '',
  'choice',
  { { 'generated', 'Generated curve' }, { 'table', 'Custom table' } }
)
field(
  'curveShape',
  'Generated curve shape',
  'geometric',
  '',
  'choice',
  { { 'geometric', 'Geometric' }, { 'logarithmic', 'Logarithmic' } }
)
field('atTier', 'Current-tier multiplier', '4', 'Starting point of the generated curve.')
field(
  'maxMultiplier',
  'Maximum tiered multiplier',
  '512',
  'End of the generated curve and final ceiling, including tier overrides.'
)
field(
  'curveSpan',
  'Tiers below until maximum',
  '7',
  'Growth follows the selected shape; older tiers stay at maximum.'
)
-- Retain custom points and overrides in the same saved configuration. Their UI
-- is a compact editable table with shared headings, not repeated field help.
local preset = { 4, 8, 16, 32, 64, 128, 256, 512 }
group = 'Curve table'
for gap = 0, 7 do
  field(
    'below' .. gap,
    gap == 0 and 'Current tier' or gap == 7 and '7+ tiers below' or gap .. ' tiers below',
    tostring(preset[gap + 1]),
    ''
  )
end
group = 'Tier overrides'
for _, name in ipairs(M.tiers) do
  field('override' .. name, name, '', '', 'optionalPositiveInteger')
end
for _, f in ipairs(M.fields) do
  if f.key == 'voltagePolicy' or f.key == 'abovePolicy' then
    f.toggleValues = { f.choices[1][1], f.choices[2][1] }
  end
  if f.key ~= 'mode' and f.key ~= 'costScaling' then
    f.when = { mode = 'tiered' }
  end
  if f.key == 'aboveMultiplier' then
    f.when.abovePolicy = 'fixed'
  end
  if f.key == 'unknownMultiplier' then
    f.when.unknownPolicy = { 'fixed', 'voltage' }
  end
  if f.key == 'voltageTier' then
    f.when.voltagePolicy = 'cap'
  end
  if f.key == 'atTier' or f.key == 'curveSpan' or f.key == 'curveShape' then
    f.when.curveMode = 'generated'
  end
  if f.group == 'Curve table' then
    f.when.curveMode = 'table'
    f.compact = true
  end
  if f.group == 'Tier overrides' then
    f.compact = true
    f.placeholder = ''
  end
end

-- Recipe forms refer only to this recipe's main material. Shared ingredients
-- (polymers/PPS) and stocked molds/circuits are deliberately not counted.
function M.materialCost(rule)
  local total = 0
  for _, input in ipairs(rule.inputs or {}) do
    local units = input.fluid == 'material' and 1 / MaterialUnits.fluidPerIngot
      or MaterialUnits.forms[input.f]
    if input.f or input.fluid == 'material' then
      if not units then
        return nil
      end
      total = total + input.n * units
    end
  end
  return total > 0 and total or nil
end

function M.divisorForm(form)
  -- Fluid/item pipes use the same mold setting and the same form override.
  return (form:gsub('^pipeFluid', 'pipe'):gsub('^pipeItem', 'pipe'))
end
function M.divisorKey(form)
  return 'divisor' .. M.divisorForm(form)
end

function M.validate(values)
  U.check(index[values.currentTier], 'Unknown progression tier')
  U.check(
    values.voltageTier == 'current' or index[values.voltageTier],
    'Unknown voltage reference tier'
  )

  for _, f in ipairs(M.fields) do
    if
      f.kind == 'positiveInteger' or f.kind == 'optionalPositiveInteger' and values[f.key] ~= ''
    then
      local value = tonumber(values[f.key])
      U.check(U.integer(value) and value > 0, f.label .. ' must be a positive whole number')
    end
  end
  U.check(
    values.mode ~= 'tiered'
      or values.curveMode ~= 'generated'
      or tonumber(values.atTier) <= tonumber(values.maxMultiplier),
    'Current-tier multiplier must not exceed the maximum'
  )
end

local function relative(values, current, tier)
  local gap = index[current] - index[tier]
  if gap < 0 then
    return values.abovePolicy == 'skip' and 0 or tonumber(values.aboveMultiplier)
  end
  if values.curveMode == 'table' then
    return tonumber(values['below' .. math.min(gap, 7)])
  end
  local first, maximum = tonumber(values.atTier), tonumber(values.maxMultiplier)
  local span = tonumber(values.curveSpan)
  local fraction = math.min(1, gap / span)
  if values.curveShape == 'logarithmic' then
    return math.floor(
      first + (maximum - first) * math.log(1 + math.min(gap, span)) / math.log(1 + span) + 0.5
    )
  end
  return math.floor(first * (maximum / first) ^ fraction + 0.5)
end

function M.budget(values, tier)
  if not index[tier] then
    return tonumber(values.unknownMultiplier)
  end
  if index[tier] > index[values.currentTier] and values.abovePolicy == 'skip' then
    return 0
  end
  return tonumber(values['override' .. tier]) or relative(values, values.currentTier, tier)
end

-- Called once per requested recipe, before its items/fluids are resolved.
-- Stocked circuits, molds and omitted insulation solids do not constrain a batch.
function M.resolve(values, materialTier, eut, factor, quantities, materialSource, scaling)
  factor = factor or 1
  U.check(U.integer(factor) and factor > 0, 'Pattern multiplier must be a positive whole number')
  local recipeTier = M.voltageTier(eut)
  local detail = {
    materialTier = materialTier,
    recipeTier = recipeTier,
    eut = eut,
    materialSource = materialSource,
    native = scaling and scaling.native or nil,
  }
  local function scale(target)
    detail.unscaledMultiplier = target
    if values and values.costScaling == 'on' then
      local divisor = scaling and scaling.divisor
      detail.materialCost = scaling and scaling.cost
      detail.divisorSource = divisor and 'override' or 'material input'
      divisor = divisor or detail.materialCost or 1
      U.check(type(divisor) == 'number' and divisor > 0, 'Invalid material cost divisor')
      detail.divisor = math.max(1, divisor)
      target = math.max(1, math.floor(target / detail.divisor))
    end
    return target
  end
  if not values or values.mode == 'fixed' then
    detail.multiplier = detail.native and 1 or scale(factor)
    return detail.multiplier, detail
  end
  M.validate(values)
  -- Fixed program multipliers are intentionally irrelevant in tiered mode.
  local effectiveTier = materialTier
  if not index[effectiveTier] then
    if values.unknownPolicy == 'skip' then
      detail.excluded = 'Unclassified material: skipped by settings'
    elseif values.unknownPolicy == 'voltage' and recipeTier then
      effectiveTier = recipeTier
      detail.tierSource = 'recipe voltage estimate'
    end
  end
  detail.effectiveTier = effectiveTier
  detail.materialBudget = M.budget(values, effectiveTier)
  if detail.materialBudget == 0 then
    detail.excluded = 'Material tier above current progression'
  end
  local target = detail.materialBudget
  if values.voltagePolicy == 'cap' then
    local reference = values.voltageTier == 'current' and values.currentTier or values.voltageTier
    if recipeTier and index[recipeTier] > index[reference] then
      detail.excluded = 'Recipe voltage above ' .. reference
    end
    detail.voltageBudget = recipeTier and relative(values, reference, recipeTier)
      or tonumber(values.unknownMultiplier)
    target = math.min(target, detail.voltageBudget)
  end
  if detail.excluded then
    detail.multiplier = 0
    return 0, detail
  end
  -- Indivisible machine recipes retain one full native cycle. Tier/voltage
  -- eligibility still applies, but their ingredients cannot be clamped down.
  if detail.native then
    detail.multiplier = 1
    return 1, detail
  end
  target = math.min(target, tonumber(values.maxMultiplier))
  target = scale(target)
  for _, q in ipairs(quantities or {}) do
    local limit = tonumber(values[q.type == 'fluid' and 'fluidLimit' or 'itemLimit'])
    target = math.min(target, math.floor(limit / q.size))
  end
  U.check(target >= 1, 'One recipe batch exceeds the configured item/fluid limit')
  detail.multiplier = target
  return target, detail
end

function M.voltageText(detail)
  if not detail.recipeTier then
    return 'Unknown EU/t'
  end
  local digits = string.format('%.0f', detail.eut)
  local grouped = digits:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
  return grouped .. ' EU/t (' .. detail.recipeTier .. ')'
end

function M.describe(detail)
  if detail.native then
    return 'Native batch  |  Component ' .. detail.materialTier .. '  |  ' .. M.voltageText(detail)
  end
  local material = detail.materialTier
    or (detail.effectiveTier and (detail.effectiveTier .. ' estimated') or 'unclassified')
  if detail.materialTier and detail.materialSource and detail.materialSource ~= 'quest item' then
    material = material .. ' (estimated)'
  end
  return 'Batch '
    .. detail.multiplier
    .. 'x'
    .. (detail.divisor and detail.divisor > 1 and (' (' .. detail.unscaledMultiplier .. 'x / ' .. detail.divisor .. ')') or '')
    .. '  |  Material '
    .. material
    .. '  |  '
    .. M.voltageText(detail)
end

-- OC accepts RGB, without alpha. Blend tier colors locally when requested.
function M.color(tier, background, opacity)
  local rgb = Tiers.colors[index[tier]] or background
  if not opacity then
    return rgb
  end
  local value = 0
  for _, divisor in ipairs({ 65536, 256, 1 }) do
    local foreground = math.floor(rgb / divisor) % 256
    local back = math.floor(background / divisor) % 256
    value = value + math.floor(foreground * opacity + back * (1 - opacity) + 0.5) * divisor
  end
  return value
end
return M

end)()
local Programs=(function()
-- Source: source/lib/programs.lua
-- Program definitions shared by configuration, navigation and execution.
local Batch = Batch
local ComponentData = ComponentData
local M = {}
local function field(key, label, help, default, kind, optional)
  return {
    key = key,
    label = label,
    help = help,
    default = default or '',
    kind = kind or 'text',
    optional = optional,
  }
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
    'Fixed batch before material-cost scaling; all requested inputs and outputs scale together.',
    '1',
    'positiveInteger'
  )
end
local benderForms = {
  { 'plate', '1x' },
  { 'plateDouble', '2x' },
  { 'plateTriple', '3x' },
  { 'plateQuadruple', '4x' },
  { 'plateQuintuple', '5x' },
  { 'plateDense', 'Dense (9x)' },
  { 'foil', 'Foil' },
  { 'sheetmetal', 'Sheet metal' },
  { 'springSmall', 'Small spring' },
  { 'spring', 'Spring' },
}
local cableForms = {}
for _, size in ipairs({ 1, 2, 4, 8, 12, 16 }) do
  cableForms[#cableForms + 1] = { 'cable' .. size, size .. 'x Cable' }
end
local shaperForms = {
  { 'ingot', 'Ingot' },
  { 'nugget', 'Nugget' },
  { 'plate', '1x Plate' },
  { 'stick', 'Rod' },
  { 'stickLong', 'Long rod' },
  { 'ring', 'Ring' },
  { 'bolt', 'Bolt' },
  { 'screw', 'Screw' },
  { 'round', 'Round' },
  { 'gearGt', 'Gear' },
  { 'gearGtSmall', 'Small gear' },
  { 'rotor', 'Rotor' },
  { 'itemCasing', 'Item casing' },
  { 'toolHeadDrill', 'Drill head' },
  { 'turbineBlade', 'Turbine blade' },
  { 'pipeTiny', 'Tiny pipe' },
  { 'pipeSmall', 'Small pipe' },
  { 'pipeMedium', 'Medium pipe' },
  { 'pipeLarge', 'Large pipe' },
  { 'pipeHuge', 'Huge pipe' },
}
local function formSwitches(choices, label, help, hidden, default)
  local names = {}
  for _, option in ipairs(choices) do
    names[#names + 1] = option[1]
  end
  local f = field('forms', label, help, default or table.concat(names, ','), 'multiToggle')
  f.choices = choices
  f.hidden = hidden
  return f
end
local shaperOutputs = {}
local shaperFields = {}
for _, entry in ipairs(shaperForms) do
  local key = entry[1]
  if key:match('^pipe') then
    local size = key:sub(5)
    shaperOutputs['pipeFluid' .. size] = key
    shaperOutputs['pipeItem' .. size] = key
  else
    shaperOutputs[key] = key
  end
end
shaperFields[#shaperFields + 1] = formSwitches(
  shaperForms,
  'Enabled Fluid Shaper molds',
  'Only verified Fluid Solidifier routes are included. The reusable mold stays in the machine.',
  true,
  'plate,turbineBlade'
)
shaperFields[#shaperFields + 1] = multiplier()
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
    formChoices = cableForms,
    description = 'Plan insulation patterns in material and cable-size order.',
    fields = {
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
    formChoices = { { 'wire1', '1x wire' }, { 'wireFine', 'Fine wire' } },
    description = 'Create 1x wire and fine-wire patterns in separate destination banks.',
    outputs = { wire1 = 'wire1', wireFine = 'wireFine' },
    sources = { fields = { wire1 = 'wireSource', wireFine = 'fineSource' } },
    fields = {
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
    fields = {},
  },
  {
    id = 'bender',
    name = 'Bending machine',
    mode = 'bender',
    description = 'Scraped plate, foil, sheet-metal and spring routes with selectable inputs.',
    formChoices = benderForms,
    formSwitch = 'forms',
    sources = {
      fixed = { plate = 'ingot', sheetmetal = 'plate', spring = 'stickLong' },
      fields = {
        plateDouble = 'plateSource',
        plateTriple = 'plateSource',
        plateQuadruple = 'plateSource',
        plateQuintuple = 'plateSource',
        plateDense = 'plateSource',
        foil = 'plateSource',
        springSmall = 'springSmallSource',
      },
    },
    fields = {
      formSwitches(benderForms, '', '', true),
      choice(
        'plateSource',
        'Larger plate / foil input',
        { { 'ingot', 'Ingot' }, { 'plate', '1x plate' } },
        'ingot',
        'Applies to 2x, 3x, 4x, 5x and dense plates, plus foil. 1x plates always use ingots.'
      ),
      choice(
        'springSmallSource',
        'Small spring input',
        { { 'stick', 'Rod' }, { 'wire1', '1x wire' } },
        'stick',
        'Large springs always use long rods; sheet metal always uses 1x plates.'
      ),
      multiplier(),
    },
  },
  {
    id = 'fluidShaper',
    name = 'Fluid Shaper',
    mode = 'solidifier',
    description = 'Cast verified solid parts from molten fluid with stocked molds.',
    formChoices = shaperForms,
    formSwitch = 'forms',
    switchByDestination = true,
    outputs = shaperOutputs,
    fields = shaperFields,
  },
}
M.list[#M.list + 1] = {
  id = 'donorCleanup',
  name = 'Clean donor buffer',
  description = 'Replace disposable processing recipes with a tagged donor placeholder.',
  fields = {},
  requiresCapacityVerification = false,
  previewTabs = { { 'changes', 'Patterns' }, { 'details', 'Details' } },
}
M.list[#M.list + 1] = {
  id = 'implosionTransition',
  name = 'Implosion transition',
  description = 'Move existing patterns to electric implosion, removing explosives and tiny byproducts.',
  fields = {
    field(
      'source',
      'Old interface name',
      'All interfaces with this exact terminal name are included.',
      ''
    ),
    field(
      'destination',
      'New interface name',
      'Existing target patterns stay in place; migrated patterns use free slots.',
      ''
    ),
  },
  previewTabs = { { 'changes', 'Patterns' }, { 'capacity', 'Capacity' }, { 'details', 'Details' } },
}
local singularityForms = { { 'singularity', 'Singularities' }, { 'block', 'Blocks' } }
local singularityMultiplier = multiplier()
singularityMultiplier.label = 'Block pattern multiplier'
singularityMultiplier.help =
  'Block recipes only. Singularity patterns always request the exact amount for one output.'
M.list[#M.list + 1] = {
  id = 'singularities',
  name = 'Singularity line',
  mode = 'singularities',
  description = 'The 63 Eternal-chain singularities and their ordinary compressor block recipes.',
  formChoices = singularityForms,
  formSwitch = 'forms',
  switchByDestination = true,
  outputs = { singularity = 'singularity', block = 'block' },
  costForms = { block = true },
  fields = {
    formSwitches(singularityForms, '', '', true),
    choice(
      'unstable',
      'Unstable-block input',
      { { 'mobius', 'Mobius stable ingots' }, { 'unstable', 'Unstable ingots' } },
      'mobius',
      'Select one of the two scraped compressor routes; never installs both.'
    ),
    singularityMultiplier,
  },
}
local casingChoices = {}
for _, name in ipairs(ComponentData.casings) do
  casingChoices[#casingChoices + 1] = { name, name }
end
local casingField = choice(
  'casingTier',
  'Installed component casing tier',
  casingChoices,
  'LuV',
  'Upper limit by machine casing; shared progression and voltage constraints still apply.'
)
casingField.kind, casingField.group = 'select', 'Recipe selection'
local rubberField = choice(
  'rubber',
  'Component rubber',
  { { 'sbr', 'SBR' }, { 'silicone', 'Silicone' }, { 'rubber', 'Rubber (LV-EV only)' } },
  'sbr',
  'Choose one route. Rubber has no pump/conveyor route at IV through UMV.'
)
rubberField.kind, rubberField.group = 'select', 'Recipe selection'
local componentProgram = {
  id = 'componentAssembly',
  name = 'Component Assembly Line',
  mode = 'components',
  description = 'Eight component banks, filtered by installed casing tier.',
  distinctDestinations = true,
  costForms = {},
  outputs = {},
  fields = { casingField, rubberField },
  stockedForms = {},
}
for _, component in ipairs(ComponentData.components) do
  local key = component.key
  componentProgram.outputs[key] = key
  componentProgram.stockedForms[#componentProgram.stockedForms + 1] = { key, component.label }
end
M.list[#M.list + 1] = componentProgram
-- Each output has one editable destination and one switch. Configuration,
-- validation, routing and rendering all consume this same field schema.
local function destinationFields(program, definitions, help)
  local fields = {}
  program.destinationChoices = program.formChoices
  program.formSwitch, program.destinationSwitch, program.switchByDestination =
    'forms', 'forms', true
  for _, definition in ipairs(definitions) do
    local key, subtype, prefix, legacyKey =
      definition[1], definition[2], definition[3], definition[4]
    local f = field(
      key,
      subtype .. ' interface name',
      '',
      (prefix or program.name:gsub('%f[%a]%a', string.upper)) .. ' (' .. subtype .. ')',
      'destination',
      true
    )
    f.group, f.groupHelp, f.legacyKey = 'Interface Names', help, legacyKey
    if program.mode == 'components' then
      for _, component in ipairs(ComponentData.components) do
        if component.key == key then
          f.annotation = 'Circuit ' .. component.circuit
        end
      end
    end
    fields[#fields + 1] = f
  end
  local switch
  for _, f in ipairs(program.fields) do
    if f.key == 'forms' then
      f.hidden, switch = true, f
    end
    fields[#fields + 1] = f
  end
  if not switch then
    fields[#fields + 1] = formSwitches(program.formChoices, '', '', true)
  end
  program.fields = fields
end
local definitions = {
  insulator = {},
  wiremill = { { 'wire1', 'Wires' }, { 'wireFine', 'Fine Wires' } },
  combining = {
    { 'wire', 'Wires', 'Large Molecular Assembler' },
    { 'cable', 'Cables', 'Large Molecular Assembler' },
  },
  bender = {
    { 'plate', 'Plate' },
    { 'plateDouble', 'Double Plate', nil, 'plate' },
    { 'plateTriple', 'Triple Plate', nil, 'plate' },
    { 'plateQuadruple', 'Quadruple Plate', nil, 'plate' },
    { 'plateQuintuple', 'Quintuple Plate', nil, 'plate' },
    { 'plateDense', 'Dense Plate', nil, 'plate' },
    { 'foil', 'Foil' },
    { 'sheetmetal', 'Sheet Metal', nil, 'sheetMetal' },
    { 'springSmall', 'Small Spring', nil, 'spring' },
    { 'spring', 'Spring' },
  },
  fluidShaper = {},
  singularities = {
    { 'singularity', 'Singularities', 'Neutronium Compressor' },
    { 'block', 'Blocks', 'Compressor' },
  },
  componentAssembly = {},
}
for _, entry in ipairs(cableForms) do
  definitions.insulator[#definitions.insulator + 1] = { entry[1], entry[2], nil, 'destination' }
end
for _, entry in ipairs(shaperForms) do
  local subtype = entry[1] == 'plate' and 'Plate' or entry[2]:gsub('%f[%a]%a', string.upper)
  definitions.fluidShaper[#definitions.fluidShaper + 1] = { entry[1], subtype }
end
for _, component in ipairs(ComponentData.components) do
  definitions.componentAssembly[#definitions.componentAssembly + 1] =
    { component.key, component.label }
end
componentProgram.formChoices = componentProgram.stockedForms
for _, program in ipairs(M.list) do
  if program.id == 'insulator' or program.id == 'bender' then
    program.outputs = {}
    for _, entry in ipairs(program.formChoices) do
      program.outputs[entry[1]] = entry[1]
    end
  elseif program.id == 'combining' then
    program.formChoices = { { 'wire', 'Wires' }, { 'cable', 'Cables' } }
    program.outputs = { wire = 'wire', cable = 'cable' }
  end
  if definitions[program.id] then
    local help = program.id == 'fluidShaper'
        and 'Destinations for patterns; keep the matching mold stocked in each machine.'
      or program.id == 'componentAssembly' and 'Separate component banks; circuits stay stocked (IV+). LV-EV recipes need no circuit.'
      or 'Destinations for patterns. Every interface with the same exact name is included.'
    destinationFields(program, definitions[program.id], help)
  end
end
M.byId, M.settings = {}, {}
for _, program in ipairs(M.list) do
  if program.mode and program.formChoices then
    for _, entry in ipairs(program.formChoices) do
      if not program.costForms or program.costForms[entry[1]] then
        local f =
          field(Batch.divisorKey(entry[1]), entry[2], '', '', 'optionalPositiveInteger', true)
        f.costDivisor, f.group, f.compact, f.placeholder = entry[1], 'Batch divisors', true, 'Auto'
        f.tableLabel, f.valueLabel = 'OUTPUT FORM', 'BATCH DIVISOR'
        f.tableHelp =
          'Blank uses material input cost. A divisor of 1 keeps the full batch; 4 quarters it.'
        program.fields[#program.fields + 1] = f
      end
    end
  end
  if program.id == 'bender' or program.id == 'fluidShaper' then
    program.stockedForms = program.formChoices
  end
  M.byId[program.id] = program
  if #program.fields > 0 then
    M.settings[#M.settings + 1] = program
  end
end
function M.switchKey(program, form)
  return program.switchByDestination and program.outputs[form] or form
end
return M

end)()
local Config=(function()
-- Source: source/lib/config.lua
-- One configuration for the application: shared hardware and per-program fields.
local U = U
local Programs = Programs
local Batch = Batch
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
  batch = { name = 'Tier multipliers', fields = Batch.fields },
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
        local value = values and values[f.key]
        if value == nil and f.legacyKey then
          value = values and values[f.legacyKey]
        end
        if value ~= nil and not (f.kind == 'destination' and value == '') then
          c.programs[p.id][f.key] = value
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
        for _, entry in ipairs(Programs.byId.insulator.formChoices) do
          c.programs.insulator[entry[1]] = old.makerDestination
        end
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
function M.destinationEnabled(c, id, key)
  local program = Programs.byId[id]
  return M.selected(c.programs[id][program.destinationSwitch], program.destinationChoices)[key]
    == true
end
function M.enabledOutputs(c, id)
  local program, result = Programs.byId[id], {}
  if not program.outputs then
    return result
  end
  local selected = program.formSwitch
    and M.selected(c.programs[id][program.formSwitch], program.formChoices)
  for form in pairs(program.outputs) do
    result[form] = not selected or selected[Programs.switchKey(program, form)] == true
  end
  return result
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
  local needed, assigned = {}, {}
  for form, enabled in pairs(M.enabledOutputs(c, id)) do
    if enabled then
      needed[p.outputs[form]] = true
    end
  end
  for _, f in ipairs(p.fields) do
    if needed[f.key] then
      local name = c.programs[id][f.key]
      U.check(name ~= '', 'Set ' .. f.label .. ' in Settings > ' .. p.name)
      if p.distinctDestinations then
        U.check(not assigned[name], 'Each component needs a distinct destination name: ' .. name)
        assigned[name] = true
      end
    end
  end
  return p
end
return M

end)()
-- Source: source/app/00_core.lua
-- GTNH 2.9 / OpenOS. Terminal pattern slots are ZERO based; direct slots ONE based.
local component = require('component')
local event = require('event')
local computer = require('computer')
local fs = require('filesystem')
local serialization = require('serialization')
local unicode = require('unicode')
local C = {}
C.stopped = 'Work stopped. Continue last operation or start a new preview.'
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
  work.atomic = false
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
-- All component gates and waits share one cooperative control path. Stop is
-- deferred inside a journaled transaction; Pause can wait at any call boundary.
local function pollWork(delay)
  local e
  repeat
    local t = computer.uptime()
    e = work.control and (work.control(delay) or {}) or (delay > 0 and { event.pull(delay) } or {})
    if perf then
      if delay > 0 or work.control then
        perf.yields = perf.yields + 1
      end
      if delay > 0 then
        perf.wait = perf.wait + computer.uptime() - t
      end
    end
    if e.stop or e[1] == 'interrupted' or (e[1] == 'key_down' and e[4] == 1) then
      work.stopping = true
      work.stopReason = e.stop and C.stopped
        or 'Work cancelled. Continue last operation or scan again.'
    end
    delay = 0.25
  until not e.paused or work.stopping
  if work.stopping and not work.atomic then
    error(work.stopReason, 0)
  end
  return e
end
local function rest(seconds)
  local deadline = computer.uptime() + seconds
  repeat
    pollWork(math.max(0, math.min(0.25, deadline - computer.uptime())))
  until computer.uptime() >= deadline
end

local function gate()
  pollWork(0)
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
        'Energy keeps falling; work stopped. Recharge, then Continue last operation / Scan.'
      )
      U.check(
        now - lastGain < 30,
        'No recharge for 30 seconds; work stopped. Check power input, then Continue last operation / Scan.'
      )
      if work.progress and now - lastReport >= 2 then
        work.progress(
          string.format(
            'Waiting for energy: %.0f%% -> %.0f%%. Pause / Resume / Stop.',
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
  run = '/home/assline.run',
  abandoned = '/home/assline.abandoned',
  backup = '/home/assline.last',
}
local function readRaw(path, maximum)
  if not fs.exists(path) then
    return nil
  end
  U.check(fs.size(path) <= (maximum or 400000), 'File too large: ' .. path)
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
local function writeFile(path, t, maximum)
  local s = serialization.serialize(t)
  U.check(
    #s <= (maximum or 400000),
    'Recovery data exceeds disk/memory budget; use a smaller target interface'
  )
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
  U.check(readRaw(temp, maximum) == s, 'Saved file verification failed')
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
-- Canonical ingredient identity shared by planning and editor read-back.
-- AE2FC drops encode one mB per item; FluidTag is the fluid's own NBT.
local function patternIngredient(data, s, entry)
  U.check(not U.truth(s.hasTag) or type(s.tag) == 'string', 'Ingredient NBT hidden')
  local count = U.patternCount(s, entry)
  if not count then
    return nil
  end
  local normalized = stack(s)
  normalized.size, normalized.amount = count, nil
  normalized.type = s.damage == nil and 'fluid' or 'item'
  if s.name == 'ae2fc:fluid_drop' then
    local fields = entry and entry.__value
    local tag = fields and fields.tag
    if type(tag) ~= 'table' or tag.__nbt_type ~= 'compound' then
      tag = s.tag and nbt(data, s.tag)
    end
    local fluid = tag and tag.__value and tag.__value.Fluid
    U.check(
      fluid and fluid.__nbt_type == 'string' and fluid.__value ~= '',
      'Fluid drop has no readable Fluid name'
    )
    normalized.type, normalized.name, normalized.damage = 'fluid', fluid.__value:lower(), nil
    normalized.tag, normalized.hasTag = nil, false
    normalized.label = s.label and s.label:gsub('^[Dd]rop of ', '')
    local fluidTag = tag.__value.FluidTag
    if fluidTag and next(fluidTag.__value) then
      normalized.tag = invoke(data, 'encodeNBT', encodableNBT(fluidTag))
      U.check(U.eq(nbt(data, normalized.tag), fluidTag), 'Fluid NBT round trip failed')
      normalized.hasTag = true
    end
  end
  return normalized
end
local function fluidDrop(data, s)
  local root = {
    __nbt_type = 'compound',
    __value = {
      Fluid = { __nbt_type = 'string', __value = s.name },
    },
  }
  if s.tag then
    root.__value.FluidTag = nbt(data, s.tag)
  end
  local tag = invoke(data, 'encodeNBT', encodableNBT(root))
  U.check(U.eq(nbt(data, tag), root), 'Fluid drop NBT round trip failed')
  return { type = 'item', name = 'ae2fc:fluid_drop', damage = 0, size = s.size, tag = tag }
end
local function effectivePattern(data, p)
  if not U.exists(p) then
    return p
  end
  local needsNormalization = p.name == 'ae2fc:encodedPattern'
  for _, which in ipairs({ 'inputs', 'outputs' }) do
    for _, s in pairs(p[which] or {}) do
      if
        U.exists(s)
        and (
          not U.integer(s.size)
          or s.size <= 0
          or s.amount ~= nil
          or s.name == 'ae2fc:fluid_drop'
        )
      then
        needsNormalization = true
        break
      end
    end
  end
  if not needsNormalization then
    return p
  end
  local root = encodedPattern(data, p)
  if not root then
    return p
  end
  local normalized = compact(p)
  for _, which in ipairs({ 'inputs', 'outputs' }) do
    for index, s in pairs(normalized[which]) do
      normalized[which][index] = patternIngredient(data, s, U.patternEntry(root, which, index)) or s
    end
  end
  return normalized
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

-- Source: source/app/10_plan.lua
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
  -- AE2FC reads in/out. Its old duplicated Inputs/Outputs lists are preserved
  -- verbatim as metadata; the interface setters do not rewrite those copies.
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

-- Source: source/app/20_apply.lua
-- One durable intent per moved pattern. Recovery completes only that operation;
-- another scan is required before continuing the rest of a batch.
local function rawList(data, p, which)
  local root = nbt(data, p.tag).__value
  local t = root[which == 'inputs' and 'in' or 'out']
  U.check(t and t.__nbt_type == 'list', 'Unsupported encoded pattern layout')
  return t.__value
end
local recipeOperations =
  { recipe = true, imprint = true, resize = true, park = true, transition = true }
local function expected(data, op)
  local p = compact(effectivePattern(data, op.original))
  if recipeOperations[op.kind] then
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
  p = effectivePattern(hw.data, p)
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
  local final = expected(hw.data, op)
  p = effectivePattern(hw.data, p)
  local original = effectivePattern(hw.data, op.original)
  for _, which in ipairs({ 'inputs', 'outputs' }) do
    local all = {}
    for k in pairs(p[which] or {}) do
      all[k] = true
    end
    for k in pairs(original[which]) do
      all[k] = true
    end
    for k in pairs(final[which]) do
      all[k] = true
    end
    for k in pairs(all) do
      local a = p[which][k]
      local old = original[which][k]
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
  local destination = U.locationText(to) .. ' slot ' .. to.slot .. ' (zero based)'
  U.check(ok == true, 'Pattern transfer failed to ' .. destination .. ': ' .. tostring(slot))
  U.check(
    slot == to.slot,
    'Pattern moved to unexpected slot ' .. tostring(slot) .. '; requested ' .. destination
  )
end
local function verifyDelivery(hw, from, to, matches, failure)
  local after = current(hw, to).patterns[to.slot]
  if matches(after) then
    return
  end
  local message = failure
    .. ' at '
    .. U.locationText(to)
    .. ' slot '
    .. to.slot
    .. ' (zero based). '
  if not U.exists(after) then
    message = message
      .. 'Terminal send reported success, but the destination pattern is absent. '
      .. 'Check capacity cards: hidden slots can accept a transfer and then eject the pattern. '
    local source = current(hw, from).patterns[from.slot]
    message = message
      .. (
        U.exists(source) and 'Source still contains a pattern.'
        or 'Source is empty; check the interface and dropped items.'
      )
  else
    message = message .. 'Destination contains a different pattern.'
  end
  error(message .. ' Saved operation retained.', 0)
end
local function setEntry(hw, slot, which, index, s, previous, normalizedPrevious, patternName)
  local method = which == 'inputs' and 'setInterfacePatternInput' or 'setInterfacePatternOutput'
  if s then
    -- Resize old fluid drops without changing their representation or item NBT.
    -- Imprinting a different ingredient still uses the normal typed setter.
    if s.type == 'fluid' and previous and previous.name == 'ae2fc:fluid_drop' then
      local old = normalizedPrevious
      if old and old.name == s.name and tagKey(hw.data, old) == tagKey(hw.data, s) then
        local amount = s.size
        s = U.clone(previous)
        s.type, s.size, s.amount = 'item', amount, nil
      end
    end
    -- Ordinary AE2 patterns use PatternHelper's item-only parser. Their fluid
    -- ingredients must be drops; ultimate and fluid patterns accept native fluids.
    if s.type == 'fluid' and patternName == 'appliedenergistics2:item.ItemEncodedPattern' then
      s = fluidDrop(hw.data, s)
    end
    local detail = s.type == 'fluid'
        and { name = s.name, amount = s.size, size = s.size, tag = s.tag }
      or { name = s.name, damage = s.damage, size = s.size, tag = s.tag }
    U.check(
      direct(hw, method, slot, index, detail, s.type or 'item') == true,
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
  local goal = expected(hw.data, op)
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
  if (op.kind == 'edit' or op.kind == 'resize' or op.kind == 'park') and not U.exists(p) then
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
  local observed = effectivePattern(hw.data, p)
  if recipeOperations[op.kind] then
    -- Clearing removes an NBT list element: ALWAYS clear from the end.
    for _, which in ipairs({ 'inputs', 'outputs' }) do
      local desired = goal[which]
      local entries = rawList(hw.data, p, which)
      for index, s in ipairs(desired) do
        if not stackEq(hw.data, observed[which][index], s) then
          setEntry(hw, op.slot, which, index, s, p[which][index], observed[which][index], p.name)
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
      if not stackEq(hw.data, observed.inputs[e.index], e.after) then
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
  verifyDelivery(hw, endpoint(op.buffer, op.slot), op.destination, function(after)
    return semantic(hw, after, goal)
  end, 'Destination read-back failed')
  U.check(not U.exists(direct(hw, 'getInterfacePattern', op.slot)), 'Buffer slot did not empty')
  if progress then
    progress('Verified pattern in destination slot ' .. (op.destination.slot + 1))
  end
end
local function saveOp(hw, op)
  U.check(not fs.exists(paths.pending), 'Continue or stop the saved operation first')
  op.version = 1
  op.direct = hw.direct.address
  op.terminal = hw.terminal.address
  op.data = hw.data.address
  op.buffer = U.clone(hw.buffer)
  writeFile(paths.pending, op)
  work.atomic = true
end
local function clearOp()
  U.check(fs.remove(paths.pending), 'Cannot clear completed recovery record')
  if fs.exists(paths.cursor) then
    U.check(fs.remove(paths.cursor), 'Cannot clear completed recovery progress')
  end
  work.atomic = false
  gate()
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
                .. '". Refill buffers to continue; Stop / Esc to stop.',
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
  U.check(
    not fs.exists(paths.pending),
    'Continue or stop the saved operation before applying another scan'
  )
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
  work.atomic = true
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
-- Source: source/lib/planner.lua
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
        source = match and copy(match.current) or nil,
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
  -- Destinations containing only excluded outputs stay in place, but still
  -- contribute to existing-pattern counts and capacity reports.
  for _, g in pairs(groups) do
    if #g.wanted == 0 then
      for _, t in ipairs(g.tokens) do
        p.preserved[#p.preserved + 1] =
          { from = t.current, to = t.current, fingerprint = t.pattern.fingerprint }
      end
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
local Singularities=(function()
-- Source: source/lib/singularities.lua
-- Solid machine routes traced from Eternal's extreme-crafting dependency chain.
-- Shared item identities and compressor rules are resolved here; placement,
-- deduplication, resizing and execution remain the normal maker's responsibility.
local U = U
local Batch = Batch
local M = {}

function M.compile(data, options, checkpoint)
  U.check(data.version == 1 and data.source and data.materials, 'Unsupported singularity catalog')
  options = options or {}
  local manifest = {
    version = 1,
    source = U.clone(data.source),
    policy = {
      mode = 'singularities',
      multiplier = options.multiplier or 1,
      batch = U.clone(options.batch),
      unstable = options.unstable or 'mobius',
    },
    recipes = {},
    skipped = {},
    unresolved = {},
    unusedExcluded = 0,
    unclassifiedRecipes = 0,
    tierExcluded = 0,
  }
  local function ingredient(index, amount)
    local item = U.clone(U.check(data.items[index], 'Unknown singularity item'))
    item.name = U.check(data.names[item.name], 'Unknown singularity registry name')
    item.type, item.size = 'item', amount
    U.check(U.integer(amount) and amount > 0, 'Invalid singularity ingredient quantity')
    return item
  end
  for _, row in ipairs(data.materials) do
    if checkpoint then
      checkpoint()
    end
    local raw, compressor = row.raw, row.compressor
    if row.alternatives then
      local selected
      for _, alternative in ipairs(row.alternatives) do
        if alternative.key == manifest.policy.unstable then
          selected = alternative
        end
      end
      U.check(selected, 'Unknown unstable ingot route')
      raw, compressor = selected.raw, selected.compressor
    end
    local function add(form, input, inputCount, output, outputCount, eut, batchValues, cost)
      if options.forms and not options.forms[form] then
        return
      end
      local multiplier, batch = Batch.resolve(
        batchValues,
        row.tier,
        eut,
        form == 'singularity' and 1 or options.multiplier,
        { { type = 'item', size = inputCount }, { type = 'item', size = outputCount } },
        row.tierSource,
        { cost = cost, divisor = tonumber((options.formDivisors or {})[form]) }
      )
      if multiplier == 0 then
        local item = ingredient(output, outputCount)
        manifest.tierExcluded = manifest.tierExcluded + 1
        manifest.skipped[#manifest.skipped + 1] = {
          material = row.label,
          form = form,
          label = item.label,
          name = item.name,
          damage = item.damage,
          reason = batch.excluded,
        }
        return
      end
      local label = form == 'singularity' and 'Singularity' or 'Block'
      manifest.recipes[#manifest.recipes + 1] = {
        kind = 'processing',
        material = row.label,
        outputForm = form,
        outputLabel = label,
        label = row.label .. ' / ' .. label,
        inputs = { ingredient(input, inputCount * multiplier) },
        outputs = { ingredient(output, outputCount * multiplier) },
        stock = {},
        batch = batch,
        chainGroup = data.groups[row.group],
      }
      if form == 'block' and not row.tier then
        manifest.unclassifiedRecipes = manifest.unclassifiedRecipes + 1
      end
    end
    -- A single singularity can require more than the global per-item limit.
    -- Its recipe is indivisible: never clamp or scale down those requirements.
    add('singularity', row.block, row.blocks, row.singularity, row.yield, row.eut)
    local rule = U.check(data.rules[compressor], 'Missing compressor rule')
    add('block', raw, rule.input, row.block, rule.output, rule.eut, options.batch, rule.input)
  end
  return manifest
end

return M

end)()
local Components=(function()
-- Source: source/lib/components.lua
-- Component recipes have genuinely different ingredients at each tier. Shared
-- identities and alternate-route deltas are scraped; placement is handled by
-- the normal maker. A machine cycle always produces its native stack of 64.
local U = U
local Batch = Batch
local M = {}

function M.compile(data, options, checkpoint)
  U.check(data.version == 1 and data.components and data.recipes, 'Unsupported component catalog')
  options = options or {}
  local casingIndex
  for index, name in ipairs(data.casings) do
    if name == options.casingTier then
      casingIndex = index
    end
  end
  U.check(casingIndex, 'Select the installed Component Assembly Line casing tier')
  local polymer = options.rubber or 'sbr'
  U.check(
    polymer == 'sbr' or polymer == 'silicone' or polymer == 'rubber',
    'Unknown component rubber'
  )
  local manifest = {
    version = 1,
    source = U.clone(data.source),
    policy = {
      mode = 'components',
      casingTier = options.casingTier,
      rubber = polymer,
      batch = U.clone(options.batch),
    },
    recipes = {},
    choices = {},
    skipped = {},
    unresolved = {},
    tierExcluded = 0,
    unusedExcluded = 0,
    unclassifiedRecipes = 0,
  }
  local function ingredient(index, amount)
    local item = U.check(data.items[index], 'Unknown component ingredient')
    return {
      type = item.type,
      name = U.check(data.names[item.name], 'Missing component registry'),
      damage = item.damage,
      label = item.label,
      size = amount,
    }
  end
  for _, row in ipairs(data.recipes) do
    if checkpoint then
      checkpoint()
    end
    local component = U.check(data.components[row.component], 'Unknown component group')
    if not options.forms or options.forms[component.key] then
      local output = ingredient(row.output, row.yield)
      local _, batch = Batch.resolve(
        options.batch,
        row.tier,
        row.eut,
        1,
        nil,
        'component casing',
        { native = true }
      )
      local reason = row.casing > casingIndex and ('Requires ' .. row.tier .. ' component casings')
        or batch.excluded
      local choices = {}
      if not reason then
        for variantIndex = 0, #row.variants do
          local amounts = {}
          for _, pair in ipairs(row.inputs) do
            amounts[pair[1]] = pair[2]
          end
          if variantIndex > 0 then
            local delta = row.variants[variantIndex]
            for _, index in ipairs(delta.remove) do
              amounts[index] = nil
            end
            for _, pair in ipairs(delta.set) do
              amounts[pair[1]] = pair[2]
            end
          end
          local compatible, inputs = true, {}
          for _, index in ipairs(U.keys(amounts)) do
            local material = data.items[index].polymer
            if material and material ~= polymer then
              compatible = false
            end
            inputs[#inputs + 1] = ingredient(index, amounts[index])
          end
          if compatible then
            local stock = {}
            for _, pair in ipairs(row.stock) do
              stock[#stock + 1] = ingredient(pair[1], pair[2])
            end
            choices[#choices + 1] = {
              kind = 'processing',
              material = component.label,
              outputForm = component.key,
              outputLabel = row.tier,
              label = component.label .. ' / ' .. row.tier,
              inputs = inputs,
              outputs = { U.clone(output) },
              stock = stock,
              casingTier = row.tier,
              componentCircuit = component.circuit,
              batch = U.clone(batch),
            }
          end
        end
        if #choices == 0 then
          reason = 'No native route using the selected rubber'
        end
      end
      if reason then
        manifest.tierExcluded = manifest.tierExcluded + 1
        manifest.skipped[#manifest.skipped + 1] = {
          material = component.label,
          form = component.key,
          label = output.label,
          name = output.name,
          damage = output.damage,
          reason = reason,
        }
      else
        manifest.recipes[#manifest.recipes + 1] = choices[1]
        manifest.choices[#manifest.recipes] = choices
      end
    end
  end
  return manifest
end

return M

end)()
local Modes=(function()
-- Source: source/lib/modes.lua
-- Compact runtime recipe compiler. This module has no component/UI calls.
-- Eligibility uses form capabilities, production flags and rare exceptions.
local U = U
local Components = Components
local Planner = Planner
local Batch = Batch
local Singularities = Singularities
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
    if data.source.materialSourcePolicy and rule.outputs[1].f == 'ingot' then
      local sources = (data.origins or {})[material.o] or {}
      if not sources.native_molten then
        return false, 'No verified native liquid source for ingots.'
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
local function ruleRecipe(
  data,
  material,
  rule,
  options,
  recipeMultiplier,
  batch,
  unresolved,
  unresolvedNames
)
  local function resolve(e, stocked)
    if e.fluid == 'material' then
      local fluid = U.check(material.molten, 'Missing verified molten fluid for ' .. material.name)
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
      if unresolvedNames then
        unresolvedNames[#unresolvedNames + 1] = item.name
      end
    end
    return item
  end
  local out = rule.outputs[1]
  local label = formLabel(out.f)
  local mode = rule.mode
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
  return recipe
end
function M.compile(data, mode, options, checkpoint)
  if mode == 'components' then
    return Components.compile(data, options, checkpoint)
  end
  if mode == 'singularities' then
    return Singularities.compile(data, options, checkpoint)
  end
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
      formDivisors = U.clone(options.formDivisors),
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
            material.tierSource,
            {
              cost = Batch.materialCost(rule),
              divisor = tonumber(
                (options.formDivisors or {})[Batch.divisorForm(rule.outputs[1].f)]
              ),
            }
          )
          if recipeMultiplier == 0 then
            manifest.tierExcluded = manifest.tierExcluded + 1
            exclude(material, rule, batch.excluded)
          else
            local recipe = ruleRecipe(
              data,
              material,
              rule,
              options,
              recipeMultiplier,
              batch,
              unresolved,
              manifest.unresolved
            )
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

end)()
local Preview=(function()
-- Source: source/lib/preview.lua
-- One renderer for maker previews, on screen and in exported reports.
local U = U
local Planner = Planner
local Batch = Batch
local M = {}
local interfaceTone = 'muted'
local function destinationRow(add, name)
  add('DESTINATION: ' .. tostring(name), 'blue', nil, nil, nil, { destination = name })
end

local function spacer(rows, add)
  if #rows > 0 and rows[#rows][1] ~= '' then
    add('')
  end
end

local function treeRow(rows, add, prefix, content, tone)
  add(prefix .. content, tone)
  local row = rows[#rows]
  row[3], row[4] = #prefix, interfaceTone
end

function M.planRows(plan, manifest)
  local rows, add = U.rows()
  local details = {}
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
  if manifest.source.batchPolicy then
    add(manifest.source.batchPolicy, 'muted')
    if (manifest.tierExcluded or 0) > 0 then
      add(manifest.tierExcluded .. ' routes excluded by settings; see Excluded.', 'yellow')
    end
  elseif manifest.policy and manifest.policy.batch and manifest.policy.batch.mode == 'tiered' then
    add(
      'Tiered batches at '
        .. manifest.policy.batch.currentTier
        .. '; fixed program multipliers do not apply.',
      'muted'
    )
    add(
      (manifest.unclassifiedRecipes or 0)
        .. ' unclassified recipes; policy: '
        .. manifest.policy.batch.unknownPolicy
        .. '.  '
        .. (manifest.tierExcluded or 0)
        .. ' routes excluded by tier settings.',
      'muted'
    )
  elseif manifest.policy then
    add(
      'Batch policy: Fixed  |  Program multiplier ' .. (manifest.policy.multiplier or 1) .. 'x',
      'muted'
    )
  end
  if manifest.source.usagePolicy then
    add(
      manifest.unusedExcluded .. ' recipe routes skipped: output has no non-recycling use.',
      'muted'
    )
  end
  if plan.resizeCount > 0 then
    add(
      plan.resizeCount .. ' reused patterns will be resized to the configured batch.',
      'yellow_lighter1'
    )
  end
  local group, bank, material
  for _, entry in ipairs(plan.layout) do
    local recipe = details[entry.key]
    if group ~= entry.group then
      spacer(rows, add)
      group, bank, material = entry.group, nil, nil
      destinationRow(add, group)
    end
    local location = entry.destination and U.where(entry.destination) or 'needs space'
    if bank ~= location then
      if bank then
        spacer(rows, add)
      end
      bank, material = location, nil
      add(
        '  +-- Interface '
          .. (entry.destination and U.locationText(entry.destination) or '(needs space)'),
        interfaceTone
      )
    else
      add('  |', interfaceTone)
    end
    local currentMaterial = recipe.material or recipe.label
    if material ~= currentMaterial then
      material = currentMaterial
      treeRow(rows, add, '  |  ', material, 'blue')
    end
    treeRow(
      rows,
      add,
      '  |    ',
      (entry.resize and 'RESIZE  ' or entry.existing and 'REUSE   ' or 'CREATE  ')
        .. (recipe.outputLabel or recipe.outputForm or '')
        .. (entry.destination and ('   slot ' .. entry.destination.slot) or '   needs space'),
      entry.resize and 'yellow_lighter1' or entry.existing and 'green' or 'yellow'
    )
    if entry.resize then
      treeRow(
        rows,
        add,
        '  |      ',
        'Multiply current quantities by ' .. entry.newScale .. ' / ' .. entry.oldScale,
        'yellow_lighter1'
      )
    end
    treeRow(rows, add, '  |      ', U.ingredientSummary(recipe.inputs))
    treeRow(rows, add, '  |      ', '-> ' .. U.ingredientSummary(recipe.outputs), 'green')
    if recipe.batch then
      local description, voltage = Batch.describe(recipe.batch), Batch.voltageText(recipe.batch)
      treeRow(rows, add, '  |      ', description, 'muted')
      if recipe.batch.recipeTier then
        rows[#rows][5] = {
          from = 10 + #description - #voltage,
          length = #voltage,
          tier = recipe.batch.recipeTier,
        }
      end
    end
  end
  return rows
end

function M.capacityRows(plan)
  local rows, add = U.rows()
  add('DESTINATION SPACE', 'blue')
  add('Assuming 3 capacity cards per interface (36 slots).', 'muted')
  spacer(rows, add)
  for _, group in ipairs(plan.capacities or {}) do
    add(group.name, 'blue')
    add(group.interfaces .. ' interfaces (' .. group.patterns .. ' patterns)')
  end
  spacer(rows, add)
  add('Every matching interface is included, ordered by location.', 'muted')
  add('Existing unrelated patterns count toward required space.', 'muted')
  for _, err in ipairs(plan.errors or {}) do
    add('BLOCKED: ' .. err, 'red')
  end
  return rows
end

function M.existingRows(plan)
  local rows, add = U.rows()
  add('EXISTING DESTINATION PATTERNS', 'blue')
  add(
    #(plan.existing or {})
      .. ' occupied; '
      .. plan.reused
      .. ' reused; '
      .. #plan.preserved
      .. ' kept.',
    'muted'
  )
  local group, bank
  for _, entry in ipairs(plan.existing or {}) do
    local location = U.where(entry.from)
    if group ~= entry.interface then
      spacer(rows, add)
      group, bank = entry.interface, nil
      destinationRow(add, group)
    end
    if bank ~= location then
      if bank then
        spacer(rows, add)
      end
      bank = location
      add('  +-- Interface ' .. U.locationText(entry.from), interfaceTone)
    else
      add('  |', interfaceTone)
    end
    treeRow(
      rows,
      add,
      '  |  ',
      entry.status .. '  slot ' .. entry.from.slot .. '  ' .. entry.label,
      entry.status == 'RESIZE' and 'yellow_lighter1'
        or entry.status == 'KEEP' and 'yellow'
        or 'green'
    )
    treeRow(rows, add, '  |    ', entry.reason, 'muted')
    if entry.inputs and entry.inputs ~= '' and entry.status == 'KEEP' then
      treeRow(rows, add, '  |    ', 'Encoded inputs: ' .. entry.inputs, 'muted')
    end
    if entry.requestedInputs and entry.status == 'KEEP' then
      treeRow(rows, add, '  |    ', 'Requested inputs: ' .. entry.requestedInputs, 'muted')
    end
    if U.where(entry.from) ~= U.where(entry.to) or entry.from.slot ~= entry.to.slot then
      treeRow(
        rows,
        add,
        '  |    ',
        'Final: ' .. U.locationText(entry.to) .. ' slot ' .. entry.to.slot,
        'muted'
      )
    end
  end
  if #(plan.existing or {}) == 0 then
    add('No patterns in the selected destination interfaces.', 'muted')
  end
  spacer(rows, add)
  add('SORTING MOVES', 'blue')
  for n, move in ipairs(plan.moves) do
    add(
      n .. '/' .. #plan.moves .. '  ' .. ((plan.moveLabels or {})[move.fingerprint] or 'Pattern'),
      'yellow'
    )
    add(
      '  '
        .. U.locationText(move.from)
        .. ' slot '
        .. move.from.slot
        .. ' -> '
        .. U.locationText(move.to)
        .. ' slot '
        .. move.to.slot,
      'muted'
    )
  end
  if #plan.moves == 0 then
    add('No sorting moves needed.', 'muted')
  end
  return rows
end

function M.excludedRows(manifest)
  local rows, add = U.rows()
  add('EXCLUDED OUTPUTS', 'blue')
  add(
    #(manifest.skipped or {}) .. ' output forms excluded by material, use or tier policy.',
    'muted'
  )
  add('Existing patterns for these outputs are kept; see Existing.', 'muted')
  local material
  for _, item in ipairs(manifest.skipped or {}) do
    if material ~= item.material then
      spacer(rows, add)
      material = item.material
      add(material, 'blue')
    end
    add('  ' .. item.label, 'yellow')
    add('    ' .. (item.reason or 'No path to a non-recycling product.'), 'muted')
  end
  if #(manifest.skipped or {}) == 0 then
    add('No selected output forms excluded.', 'green')
  end
  return rows
end

function M.donorRows(plan, section)
  local rows, add = U.rows()
  add('DONOR BUFFER CLEANUP', 'blue')
  add('Terminal name: "' .. plan.name .. '"', 'muted')
  add(
    #plan.cleanups
      .. ' to park; '
      .. plan.parked
      .. ' already parked; '
      .. plan.skipped
      .. ' skipped.'
  )
  add('Replaces the old recipes. Patterns return to their original slots.', 'yellow')
  if section == 'details' then
    spacer(rows, add)
    add('PARKING RECIPE', 'blue')
    add('1 tagged paper -> 1 identical tagged paper')
    add('Tag: ae2ocDonor = parked-v1; name: OC donor placeholder', 'muted')
    add('The tag distinguishes it from ordinary paper; real recipes are removed.')
    add('No paper or other item needs to be supplied. This edits the encoded recipe only.')
    spacer(rows, add)
    add('REUSABILITY', 'blue')
    add('Processing, ultimate and supported fluid patterns retain their item type and metadata.')
    add('The normal donor pool can imprint them again. Already parked patterns are left alone.')
    add('Crafting, substitution, tunnel and invalid patterns are skipped with a reason.')
    add('Empty recipes can acquire a persistent InvalidPattern flag, which this API cannot clear.')
    add('Uses one empty editor slot, shared Pause / Resume / Stop and transaction recovery.')
  else
    local bank
    for _, entry in ipairs(plan.entries) do
      if bank ~= U.where(entry.from) then
        spacer(rows, add)
        bank = U.where(entry.from)
        add('  +-- Interface ' .. U.locationText(entry.from), interfaceTone)
      else
        add('  |', interfaceTone)
      end
      local status = entry.status == 'park' and 'PARK'
        or entry.status == 'parked' and 'ALREADY PARKED'
        or 'SKIP'
      treeRow(
        rows,
        add,
        '  |  ',
        status .. ' slot ' .. entry.from.slot .. '  ' .. entry.label,
        entry.status == 'park' and 'yellow' or entry.status == 'parked' and 'green' or 'muted'
      )
      if entry.reason then
        treeRow(rows, add, '  |    ', entry.reason, 'muted')
      end
    end
  end
  for _, err in ipairs(plan.errors) do
    add('BLOCKED: ' .. err, 'red')
  end
  return rows
end

function M.transitionRows(plan, section)
  if section == 'capacity' then
    return M.capacityRows(plan)
  end
  local rows, add = U.rows()
  add('IMPLOSION TRANSITION', 'blue')
  add('FROM: ' .. plan.source, 'muted')
  destinationRow(add, plan.destination)
  if section == 'details' then
    add('Moves the same encoded patterns; no disposable donors are needed.')
    add('Preserves quantities, item type and supported pattern metadata.')
    add('Removes TNT, industrial TNT, dynamite and powderbarrels.', 'yellow')
    add('Omits known secondary tiny dust / ash outputs. The primary output stays.')
    add('The machine may still produce these byproducts; AE will not request them.', 'muted')
    add('Existing target patterns stay in place. Free slots fill in interface / slot order.')
    add('Skipped patterns remain in the old interfaces; their reasons appear under Patterns.')
    add('Pause / Resume / Stop and Continue use the shared operation journal.', 'muted')
  else
    local bank
    for _, entry in ipairs(plan.entries) do
      if bank ~= U.where(entry.from) then
        spacer(rows, add)
        bank = U.where(entry.from)
        add('  +-- Old interface ' .. U.locationText(entry.from), interfaceTone)
      else
        add('  |', interfaceTone)
      end
      treeRow(
        rows,
        add,
        '  |  ',
        (entry.reason and 'SKIP' or 'MOVE') .. ' slot ' .. entry.from.slot .. '  ' .. entry.label,
        entry.reason and 'muted' or 'green'
      )
      if entry.reason then
        treeRow(rows, add, '  |    ', entry.reason, 'muted')
      else
        treeRow(
          rows,
          add,
          '  |    ',
          'Inputs: ' .. U.ingredientSummary(entry.recipe.inputs),
          'text'
        )
        treeRow(
          rows,
          add,
          '  |    ',
          'Outputs: ' .. U.ingredientSummary(entry.recipe.outputs),
          'text'
        )
        for _, which in ipairs({ 'inputs', 'outputs' }) do
          if #entry.removed[which] > 0 then
            treeRow(
              rows,
              add,
              '  |    ',
              'Remove ' .. which .. ': ' .. U.ingredientSummary(entry.removed[which]),
              'yellow'
            )
          end
        end
        treeRow(
          rows,
          add,
          '  |    ',
          entry.to and ('To ' .. U.locationText(entry.to) .. ' slot ' .. entry.to.slot)
            or 'Needs a free target slot',
          'muted'
        )
      end
    end
  end
  for _, err in ipairs(plan.errors) do
    add('BLOCKED: ' .. err, 'red')
  end
  return rows
end

function M.rows(section, plan, manifest)
  if plan.kind == 'transition' then
    return M.transitionRows(plan, section)
  end
  if plan.kind == 'donorCleanup' then
    return M.donorRows(plan, section)
  end
  if section == 'existing' then
    return M.existingRows(plan)
  end
  if section == 'skipped' then
    return M.excludedRows(manifest)
  end
  if section == 'capacity' then
    return M.capacityRows(plan)
  end
  return M.planRows(plan, manifest)
end

function M.report(plan, manifest)
  local lines = {}
  local function append(rows)
    for _, row in ipairs(rows) do
      lines[#lines + 1] = row[1]
    end
    lines[#lines + 1] = ''
  end
  if plan.kind == 'transition' then
    for _, section in ipairs({ 'changes', 'capacity', 'details' }) do
      append(M.rows(section, plan))
    end
    return table.concat(lines, '\n') .. '\n'
  end
  if plan.kind == 'donorCleanup' then
    append(M.donorRows(plan))
    append(M.donorRows(plan, 'details'))
    return table.concat(lines, '\n') .. '\n'
  end
  append(M.capacityRows(plan))
  append(M.planRows(plan, manifest))
  for _, warning in ipairs(plan.warnings) do
    lines[#lines + 1] = 'NOTE: ' .. warning
  end
  lines[#lines + 1] = ''
  append(M.existingRows(plan))
  append(M.excludedRows(manifest))
  return table.concat(lines, '\n') .. '\n'
end

return M

end)()
local Settings=(function()
-- Source: source/lib/settings.lua
-- Measure settings once, then use those exact rows for pagination and drawing.
-- Destination lists, tables and ordinary controls all share the same page area.
local U = U
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

end)()
-- Source: source/app/25_maker.lua
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
local function patternRecipe(data, p, root)
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
        local ingredient = patternIngredient(data, s, U.patternEntry(root, which, index))
        if not ingredient then
          return nil, 'Encoded ' .. which .. ' slot ' .. index .. ' has no readable count'
        end
        r[which][index] = ingredient
      end
    end
  end
  return r
end
-- NetworkControl is exposed by a block ME interface or an ME controller,
-- not by multipart interfaces. These queries are read-only; never submit a
-- crafting job just to inspect whether an output already has a recipe.
local function ingotNetwork(c)
  local prefix = c.shared.networkAddress
  if prefix == '' then
    local editor = selectDevice('me_interface', c.shared.editorAddress)
    if editor.getCraftable or editor.getCraftables then
      return editor
    end
  end
  local matches = {}
  for _, kind in ipairs(prefix == '' and { 'me_controller' } or { 'me_controller', 'me_interface' }) do
    for address, tp in component.list(kind, true) do
      if tp == kind and address:sub(1, #prefix) == prefix then
        local proxy = component.proxy(address)
        if proxy.getCraftable or proxy.getCraftables then
          matches[#matches + 1] = proxy
        end
      end
    end
  end
  U.check(
    #matches == 1,
    'Ingot checks need one ME network component; set its address in Shared interfaces'
  )
  return matches[1]
end
local function filterCraftableIngots(c, hw, snapshot, manifest, destination)
  if not manifest.policy or manifest.policy.mode ~= 'solidifier' then
    return
  end
  manifest.requestedRecipes = manifest.requestedRecipes or manifest.recipes
  local owned = {}
  for _, bank in ipairs(snapshot.interfaces) do
    if bank.role == 'destination' then
      for _, p in pairs(bank.patterns) do
        owned[bank.name .. ':' .. tostring(p.recipeKey)] = true
      end
    end
  end
  local skipped, recipes, checks, network = {}, {}, {}, nil
  for _, entry in ipairs(manifest.skipped) do
    if not entry.network then
      skipped[#skipped + 1] = entry
    end
  end
  for _, recipe in ipairs(manifest.requestedRecipes) do
    local omit = false
    if recipe.outputForm == 'ingot' then
      network = network or ingotNetwork(c)
      local output = recipe.outputs[1]
      local filter = { name = output.name, damage = output.damage }
      local craftable
      if network.getCraftable then
        craftable = invoke(network, 'getCraftable', filter, 'item') ~= nil
      else
        local found = invoke(network, 'getCraftables', filter)
        U.check(type(found) == 'table', 'ME crafting query failed')
        craftable = next(found) ~= nil
      end
      local key = recipeKey(hw.data, recipe)
      -- ME advertises outputs, not competing recipe inputs. An installed,
      -- matching cast must not make itself disappear on the next scan.
      omit = craftable and not owned[destination(recipe) .. ':' .. key]
      checks[output.name .. ':' .. output.damage] = craftable
      if omit then
        skipped[#skipped + 1] = {
          material = recipe.material,
          form = recipe.outputForm,
          label = recipe.label,
          name = output.name,
          damage = output.damage,
          network = true,
          reason = 'Ingot already craftable in the ME network; no new cast added.',
        }
      end
    end
    if not omit then
      recipes[#recipes + 1] = recipe
    end
  end
  manifest.recipes, manifest.skipped = recipes, skipped
  manifest.policy.ingotNetwork = network and network.address or nil
  manifest.policy.ingotCraftables = checks
end
local function explainExisting(plan, snapshot, request, manifest)
  local function itemKey(item)
    return item and item.name and (item.name .. ':' .. tostring(item.damage or 0))
  end
  local function slotKey(entry)
    return where(entry) .. ':' .. entry.slot
  end
  local skipped, wantedOutputs, wantedKeys = {}, {}, {}
  for _, item in ipairs(manifest.skipped or {}) do
    skipped[itemKey(item)] = item
  end
  for index, recipe in ipairs(manifest.recipes) do
    local desired = request.recipes[index]
    wantedKeys[desired.destination .. ':' .. desired.key] = true
    for _, output in pairs(recipe.outputs) do
      wantedOutputs[itemKey(output)] = {
        label = recipe.label,
        destination = desired.destination,
        inputs = U.ingredientSummary(recipe.inputs),
      }
    end
  end
  local reused, kept = {}, {}
  for _, entry in ipairs(plan.layout) do
    if entry.source then
      reused[slotKey(entry.source)] = entry
    end
  end
  for _, entry in ipairs(plan.preserved) do
    kept[slotKey(entry.from)] = entry
  end
  local destinations = {}
  for _, interface in ipairs(snapshot.interfaces) do
    if interface.role == 'destination' then
      destinations[#destinations + 1] = interface
    end
  end
  table.sort(destinations, U.ordered)
  plan.existing, plan.moveLabels = {}, {}
  for _, interface in ipairs(destinations) do
    for _, slot in ipairs(U.keys(interface.patterns)) do
      local pattern = interface.patterns[slot]
      local from = U.endpoint(interface, slot)
      local key = slotKey(from)
      local reusedEntry, keptEntry = reused[key], kept[key]
      local outputKey = itemKey(pattern.output)
      local skippedItem = skipped[outputKey]
      local wantedOutput = wantedOutputs[outputKey]
      local label = skippedItem and skippedItem.label
        or wantedOutput and wantedOutput.label
        or pattern.output and pattern.output.label
        or outputKey
        or 'Unknown output'
      local reason
      if reusedEntry then
        reason = reusedEntry.resize and 'Recipe matches; batch will be resized.'
          or 'Recipe matches the selected route.'
      elseif skippedItem then
        reason = 'Skipped: '
          .. (skippedItem.reason or 'no path to a non-recycling product in the recipe export.')
      elseif wantedKeys[interface.name .. ':' .. tostring(pattern.recipeKey)] then
        reason = 'Duplicate of a selected recipe; kept after the planned patterns.'
      elseif wantedOutput and wantedOutput.destination ~= interface.name then
        reason = 'Selected output belongs in interface ' .. wantedOutput.destination .. '.'
      elseif wantedOutput then
        reason = pattern.reason and ('Output selected; ' .. pattern.reason .. '.')
          or 'Recipe differs: inputs, ratio, NBT or flags.'
      elseif pattern.matchIssue then
        reason = pattern.matchIssue
      else
        reason = 'Output not requested by this program or its current settings.'
      end
      local entry = {
        interface = interface.name,
        from = from,
        to = reusedEntry and reusedEntry.destination or keptEntry and keptEntry.to or from,
        status = reusedEntry and (reusedEntry.resize and 'RESIZE' or 'REUSE') or 'KEEP',
        label = label,
        output = pattern.output,
        inputs = pattern.inputSummary,
        requestedInputs = wantedOutput and wantedOutput.inputs or nil,
        reason = reason,
      }
      plan.existing[#plan.existing + 1] = entry
      plan.moveLabels[pattern.fingerprint] = label
    end
  end
end
-- Resolve alternate native routes against the same snapshot used for planning.
-- This reuses installed alternatives without creating competing output recipes.
local function selectRecipeChoices(hw, manifest, snapshot, destination)
  if not manifest.choices then
    return
  end
  for index, choices in ipairs(manifest.choices) do
    gate()
    local candidateKeys, selected = {}, choices[1]
    for _, recipe in ipairs(choices) do
      candidateKeys[recipeKey(hw.data, recipe)] = recipe
    end
    local found = false
    for _, bank in ipairs(snapshot.interfaces) do
      if bank.role == 'destination' and bank.name == destination(selected) then
        for _, slot in ipairs(U.keys(bank.patterns)) do
          local pattern = bank.patterns[slot]
          local candidate = pattern.kind == 'processing' and candidateKeys[pattern.recipeKey]
          if candidate then
            selected, found = candidate, true
            break
          end
        end
      end
      if found then
        break
      end
    end
    manifest.recipes[index] = U.clone(selected)
  end
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
    return routing.destinations and routing.destinations[recipe.outputForm or recipe.form]
      or routing.destination
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
  for _, recipe in ipairs(manifest.requestedRecipes or manifest.recipes) do
    group(destination(recipe), 'destination')
  end
  for _, item in ipairs(manifest.skipped or {}) do
    group(destination(item), 'destination')
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
          local output = p.outputs and p.outputs[1]
          if U.exists(output) then
            value.output = {
              name = output.name,
              damage = output.damage,
              size = U.patternCount(output, U.patternEntry(root, 'outputs', 1)),
              label = output.label,
            }
          end
          local inputLabels = {}
          for _, index in ipairs(U.keys(p.inputs)) do
            local input = p.inputs[index]
            if U.exists(input) then
              inputLabels[#inputLabels + 1] = tostring(
                U.patternCount(input, U.patternEntry(root, 'inputs', index)) or '?'
              ) .. ' x ' .. tostring(input.label or input.name)
            end
          end
          value.inputSummary = table.concat(inputLabels, ', ')
          if root then
            local r, issue = patternRecipe(hw.data, p, root)
            if r then
              value.kind = r.kind
              value.inputSummary = U.ingredientSummary(r.inputs)
              if r.outputs[1] then
                value.output = U.clone(r.outputs[1])
              end
              local valid, key, scale = pcall(recipeKey, hw.data, r)
              if valid then
                value.recipeKey = key
                value.scale = scale
              else
                value.matchIssue = 'Encoded ingredients could not be compared'
              end
              value.donor = value.reason == nil
            else
              value.matchIssue = issue
              value.reason = value.reason or issue
            end
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
  selectRecipeChoices(hw, manifest, snapshot, destination)
  filterCraftableIngots(c, hw, snapshot, manifest, destination)
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
  explainExisting(plan, snapshot, request, manifest)
  return plan, snapshot, request, labels
end
C.maker = {
  planner = Planner,
  scan = scanManifest,
  report = Preview.report,
  rows = Preview.planRows,
  discover = discover,
}
local function programRouting(c, id)
  local program = Config.requireProgram(c, id)
  local values = c.programs[id]
  local routing = { donors = c.shared.donors, workspace = c.shared.editor }
  local forms
  if program.outputs then
    forms = Config.enabledOutputs(c, id)
    routing.destinations = {}
    for form, key in pairs(program.outputs) do
      routing.destinations[form] = values[key]
    end
  end
  local sources
  if program.sources then
    sources = {}
    for form, source in pairs(program.sources.fixed or {}) do
      sources[form] = source
    end
    for form, key in pairs(program.sources.fields or {}) do
      sources[form] = values[key]
    end
  end
  local formDivisors = {}
  for _, field in ipairs(program.fields) do
    if field.costDivisor then
      formDivisors[field.costDivisor] = tonumber(values[field.key])
    end
  end
  return routing,
    {
      polymer = values.polymer,
      multiplier = tonumber(values.multiplier),
      batch = c.batch,
      pps = values.pps ~= 'off',
      forms = forms,
      sources = sources,
      formDivisors = formDivisors,
      unstable = values.unstable,
      casingTier = values.casingTier,
      rubber = values.rubber,
    },
    program
end
function C.maker.preview(c, id, progress, control)
  validate(c)
  startWork(c, progress, control)
  local routing, options, program = programRouting(c, id)
  local catalogs = { singularities = SingularityData, components = ComponentData }
  local data = catalogs[program.mode] or require('assline_data')
  local manifest = Modes.compile(data, program.mode, options, gate)
  local plan, snapshot, _, labels = scanManifest(c, manifest, routing, progress, control, true)
  local groups = {}
  for _, recipe in ipairs(manifest.recipes) do
    local name = routing.destinations and routing.destinations[recipe.outputForm or recipe.form]
      or routing.destination
    groups[name] = (groups[name] or 0) + 1
  end
  local banks = {}
  for _, i in ipairs(snapshot.interfaces) do
    banks[where(i)] = i.name
  end
  for _, entry in ipairs(plan.preserved) do
    local name = banks[where(entry.from)]
    groups[name] = (groups[name] or 0) + 1
  end
  plan.capacities = Config.capacityReport(groups)
  local report = Preview.report(plan, manifest)
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
  verifyDelivery(hw, op.source, op.destination, matches, 'Sorted pattern read-back failed')
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
  local parked = false
  local function track(move)
    if where(move.to) == where(hw.buffer) then
      parked = true
    end
    if where(move.from) == where(hw.buffer) then
      parked = false
    end
  end
  -- An interrupted cycle may already have a pattern in its workspace.
  for n = 1, cursor.index - 1 do
    track(op.moves[n])
  end
  for n = cursor.index, #op.moves do
    local move = op.moves[n]
    C.maker.finishMove(
      hw,
      { source = move.from, destination = move.to, fingerprint = move.fingerprint }
    )
    writeFile(paths.cursor, { id = op.id, index = n + 1 })
    track(move)
    -- Stop only when the cycle has returned its parked pattern. The cursor
    -- retains the remaining moves without holding an editor slot hostage.
    if not parked then
      work.atomic = false
      gate()
      work.atomic = true
    end
    if progress then
      progress('Sorted pattern ' .. n .. ' / ' .. #op.moves)
    end
  end
end

function C.maker.apply(c, id, plan, manifest, progress, control)
  U.check(
    not fs.exists(paths.pending),
    'Continue or stop the saved operation before executing another preview'
  )
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
    -- pattern in the editor; continuation finishes that cycle before replanning.
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
        U.check(s.type == 'item' or s.type == 'fluid', 'Unsupported ingredient type')
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
function C.runner.hasChanges(preview)
  local plan = preview.plan
  if plan.kind == 'donorCleanup' then
    return #plan.cleanups > 0
  end
  if plan.kind == 'transition' then
    return #plan.transfers > 0
  end
  return preview.id == 'assline' and #plan.changes > 0
    or preview.id ~= 'assline' and (#plan.moves + #plan.creates + #plan.resizes) > 0
end
function C.runner.requiresVerification(preview)
  return Programs.byId[preview.id].requiresCapacityVerification ~= false
end
function C.runner.preview(c, id, progress, control)
  Config.requireProgram(c, id)
  local preview = { id = id, configKey = U.canonical(c) }
  if id == 'assline' then
    preview.plan = scan(c, progress, control)
  elseif id == 'donorCleanup' then
    preview.plan, preview.report = C.donors.preview(c, progress, control)
  elseif id == 'implosionTransition' then
    preview.plan, preview.report = C.transition.preview(c, progress, control)
  else
    preview.plan, preview.report, preview.manifest = C.maker.preview(c, id, progress, control)
  end
  return preview
end
function C.runner.execute(c, preview, progress, control)
  U.check(preview and preview.configKey == U.canonical(c), 'Settings changed; build a new preview')
  Config.requireProgram(c, preview.id)
  U.check(not fs.exists(paths.pending), 'Continue or stop the saved operation before executing')
  writeFile(paths.run, { version = 1, program = preview.id, configKey = U.canonical(c) })
  if preview.id == 'assline' then
    apply(c, preview.plan, progress, control)
  elseif preview.id == 'donorCleanup' then
    C.donors.apply(c, preview.plan, progress, control)
  elseif preview.id == 'implosionTransition' then
    C.transition.apply(c, preview.plan, progress, control)
  else
    C.maker.apply(c, preview.id, preview.plan, preview.manifest, progress, control)
  end
  U.check(fs.remove(paths.run), 'Cannot clear completed program run')
end

function C.runner.hasSaved()
  return fs.exists(paths.run) or fs.exists(paths.pending)
end

function C.runner.continue(c, progress, control)
  local saved, op = readFile(paths.run), readFile(paths.pending)
  U.check(saved or op, 'No saved operation')
  local backup = readFile(paths.backup)
  local id = saved and saved.program
    or op and (op.kind == 'edit' or op.kind == 'recipe') and 'assline'
    or backup and backup.program
  if id and not saved then
    writeFile(paths.run, { version = 1, program = id, configKey = U.canonical(c) })
  end
  if op then
    recover(c, progress, control)
  end
  -- A fresh plan recognizes the finished patterns and checks today's interface
  -- contents/settings. Never replay an old full plan after a stop or restart.
  if id then
    local preview = C.runner.preview(c, id, progress, control)
    preview.continuedWithChangedSettings = saved and saved.configKey ~= U.canonical(c) or false
    if
      not C.runner.hasChanges(preview)
      and #preview.plan.errors == 0
      and (not preview.manifest or #preview.manifest.unresolved == 0)
    then
      U.check(fs.remove(paths.run), 'Cannot clear completed program run')
    end
    return preview
  end
end

function C.runner.discard()
  U.check(C.runner.hasSaved(), 'No saved operation')
  -- One bounded archive may contain both 400 KB records plus the small cursor.
  writeFile(paths.abandoned, {
    operation = readFile(paths.pending),
    step = readFile(paths.cursor),
    run = readFile(paths.run),
  }, 900000)
  for _, path in ipairs({ paths.pending, paths.cursor, paths.run }) do
    if fs.exists(path) then
      U.check(fs.remove(path), 'Cannot discard ' .. path)
    end
  end
end

-- Source: source/app/26_donors.lua
-- Park disposable processing recipes in their original donor slots. Discovery,
-- ingredient writes, journaling and recovery are the application's shared ones.
C.donors = {}
local function donorMarker(hw)
  local root = {
    __nbt_type = 'compound',
    __value = {
      ae2ocDonor = { __nbt_type = 'string', __value = 'parked-v1' },
      display = {
        __nbt_type = 'compound',
        __value = { Name = { __nbt_type = 'string', __value = 'OC donor placeholder' } },
      },
    },
  }
  local tag = invoke(hw.data, 'encodeNBT', encodableNBT(root))
  U.check(U.eq(nbt(hw.data, tag), root), 'Donor marker NBT round trip failed')
  local marker = { type = 'item', name = 'minecraft:paper', damage = 0, size = 1, tag = tag }
  return { kind = 'processing', inputs = { marker }, outputs = { U.clone(marker) } }
end

function C.donors.scan(c, progress, control)
  local hw = connect(c, progress, control)
  local recipe = donorMarker(hw)
  local plan = {
    kind = 'donorCleanup',
    name = c.shared.donors,
    banks = 0,
    scanned = 0,
    parked = 0,
    skipped = 0,
    cleanups = {},
    entries = {},
    errors = {},
    warnings = {},
    bindings = {
      terminal = hw.terminal.address,
      direct = hw.direct.address,
      data = hw.data.address,
    },
  }
  for _, ref in ipairs(discover(hw, c.shared.donors)) do
    local bank = current(hw, ref)
    U.check(bank.name == c.shared.donors, 'Donor interface renamed during scan')
    U.check(where(bank) ~= where(hw.buffer), 'Donor interface overlaps the pattern editor')
    plan.banks = plan.banks + 1
    for _, slot in ipairs(U.keys(bank.patterns)) do
      gate()
      local p = bank.patterns[slot]
      if U.exists(p) then
        plan.scanned = plan.scanned + 1
        local reason = donorIssue(hw.data, p)
        if not reason and not processing(p) then
          reason = 'Crafting pattern: the editor cannot change its crafting flag.'
        end
        local entry = {
          from = endpoint(bank, slot),
          fingerprint = p.tag and patternFingerprint(hw, p) or U.canonical(compact(p)),
          label = p.label or p.name,
          status = 'skip',
          reason = reason,
        }
        if not reason then
          local observed = effectivePattern(hw.data, p)
          entry.label = U.ingredientSummary(observed.outputs)
          if not next(observed.inputs) or not next(observed.outputs) then
            entry.reason = 'Empty recipe: re-encode it manually before using it as a donor.'
          else
            local goal = compact(observed)
            goal.inputs, goal.outputs = recipe.inputs, recipe.outputs
            if semantic(hw, p, goal) then
              entry.status = 'parked'
              plan.parked = plan.parked + 1
            else
              entry.status = 'park'
              plan.cleanups[#plan.cleanups + 1] = entry
            end
          end
        end
        if entry.status == 'skip' then
          plan.skipped = plan.skipped + 1
        end
        plan.entries[#plan.entries + 1] = entry
      end
    end
    if progress then
      progress('Read donor bank at ' .. U.locationText(bank))
    end
  end
  if plan.banks == 0 then
    plan.errors[#plan.errors + 1] = 'No donor interfaces named "' .. c.shared.donors .. '".'
  end
  if #plan.cleanups > 0 then
    for slot = 0, editorCapacity(hw) - 1 do
      if not U.exists(direct(hw, 'getInterfacePattern', slot)) then
        plan.workspace = endpoint(hw.buffer, slot)
        break
      end
    end
    if not plan.workspace then
      plan.errors[#plan.errors + 1] = 'The pattern editor needs one empty slot.'
    end
  end
  return plan, hw, recipe
end

function C.donors.preview(c, progress, control)
  local plan = C.donors.scan(c, progress, control)
  return plan, Preview.report(plan)
end

function C.donors.apply(c, plan, progress, control)
  U.check(#plan.errors == 0, 'Resolve cleanup blockers first')
  local fresh, hw, recipe = C.donors.scan(c, progress, control)
  U.check(U.eq(fresh, plan), 'Donor banks or editor changed since preview. Scan again.')
  writeFile(
    paths.backup,
    { config = U.clone(c), program = 'donorCleanup', cleaned = #plan.cleanups }
  )
  for n, entry in ipairs(plan.cleanups) do
    gate()
    local bank = current(hw, entry.from)
    U.check(bank.name == plan.name, 'Donor interface renamed before cleanup')
    local original = bank.patterns[entry.from.slot]
    U.check(patternFingerprint(hw, original) == entry.fingerprint, 'Donor changed before cleanup')
    U.check(safeDonor(hw.data, original), 'Donor is no longer editable')
    U.check(
      not U.exists(direct(hw, 'getInterfacePattern', plan.workspace.slot)),
      'Pattern editor workspace occupied'
    )
    local op = {
      kind = 'park',
      slot = plan.workspace.slot,
      destination = entry.from,
      original = compact(original),
      recipe = recipe,
    }
    saveOp(hw, op)
    finish(hw, op, progress)
    clearOp()
    if progress then
      progress('Parked donor ' .. n .. ' / ' .. #plan.cleanups)
    end
  end
end

-- Source: source/app/27_transition.lua
-- Existing patterns supply both the recipe and the physical pattern. Only the
-- scraped cleanup identities change; all editing uses the shared transaction.
C.transition = {}

local function transitionId(stack)
  return stack.name:lower() .. ((stack.damage or 0) ~= 0 and '@' .. stack.damage or '')
end

local function transitionRecipe(hw, pattern)
  local observed = effectivePattern(hw.data, pattern)
  local recipe = { kind = 'processing', inputs = {}, outputs = {} }
  local removed = { inputs = {}, outputs = {} }
  for _, which in ipairs({ 'inputs', 'outputs' }) do
    for _, index in ipairs(U.keys(observed[which])) do
      local stack = observed[which][index]
      if U.exists(stack) then
        local rules = which == 'inputs' and TransitionRules.explosives or TransitionRules.secondary
        local label = stack.type ~= 'fluid' and rules[transitionId(stack)]
        if label and (which == 'inputs' or #recipe.outputs > 0) then
          local discarded = U.clone(stack)
          discarded.label = label
          removed[which][#removed[which] + 1] = discarded
        else
          recipe[which][#recipe[which] + 1] = U.clone(stack)
        end
      end
    end
  end
  return recipe, removed
end

function C.transition.scan(c, progress, control)
  local settings = c.programs.implosionTransition
  U.check(settings.source ~= settings.destination, 'Old and new interface names must differ')
  for _, name in ipairs({ settings.source, settings.destination }) do
    U.check(
      name ~= c.shared.editor and name ~= c.shared.donors,
      'Transition interfaces must differ from the editor and donor buffer'
    )
  end
  local hw = connect(c, progress, control)
  local plan = {
    kind = 'transition',
    source = settings.source,
    destination = settings.destination,
    sourceBanks = 0,
    targetBanks = 0,
    occupied = 0,
    free = 0,
    scanned = 0,
    skipped = 0,
    entries = {},
    transfers = {},
    targets = {},
    errors = {},
    warnings = {},
    bindings = {
      terminal = hw.terminal.address,
      direct = hw.direct.address,
      data = hw.data.address,
    },
  }
  local free = {}
  for _, ref in ipairs(discover(hw, settings.destination)) do
    local bank = current(hw, ref)
    U.check(bank.name == settings.destination, 'Target interface renamed during scan')
    plan.targetBanks = plan.targetBanks + 1
    local target = { ref = endpoint(bank), patterns = {} }
    for _, slot in ipairs(U.keys(bank.patterns)) do
      local p = bank.patterns[slot]
      if U.exists(p) then
        target.patterns[slot] = U.canonical(compact(p))
        plan.occupied = plan.occupied + 1
      end
    end
    plan.targets[#plan.targets + 1] = target
    for slot = 0, capacity(bank) - 1 do
      if not U.exists(bank.patterns[slot]) then
        free[#free + 1] = endpoint(bank, slot)
      end
    end
  end
  plan.free = #free
  for _, ref in ipairs(discover(hw, settings.source)) do
    local bank = current(hw, ref)
    U.check(bank.name == settings.source, 'Source interface renamed during scan')
    plan.sourceBanks = plan.sourceBanks + 1
    for _, slot in ipairs(U.keys(bank.patterns)) do
      gate()
      local p = bank.patterns[slot]
      if U.exists(p) then
        plan.scanned = plan.scanned + 1
        local reason = donorIssue(hw.data, p)
        if not reason and not processing(p) then
          reason = 'Crafting pattern: cannot change its crafting flag.'
        end
        local entry = {
          from = endpoint(bank, slot),
          fingerprint = U.canonical(compact(p)),
          label = p.label or p.name,
          reason = reason,
        }
        if not reason then
          entry.recipe, entry.removed = transitionRecipe(hw, p)
          entry.label = U.ingredientSummary(entry.recipe.outputs)
          if #entry.recipe.inputs == 0 or #entry.recipe.outputs == 0 then
            entry.reason = 'Cleanup would leave an empty recipe; left in the old interface.'
          else
            entry.to = free[#plan.transfers + 1]
            plan.transfers[#plan.transfers + 1] = entry
          end
        end
        if entry.reason then
          plan.skipped = plan.skipped + 1
        end
        plan.entries[#plan.entries + 1] = entry
      end
    end
    if progress then
      progress('Read old interface at ' .. U.locationText(bank))
    end
  end
  if plan.sourceBanks == 0 then
    plan.errors[#plan.errors + 1] = 'No old interfaces named "' .. settings.source .. '".'
  end
  if plan.targetBanks == 0 then
    plan.errors[#plan.errors + 1] = 'No new interfaces named "' .. settings.destination .. '".'
  end
  if #plan.transfers > #free then
    plan.errors[#plan.errors + 1] = 'Insufficient free target slots: need '
      .. #plan.transfers
      .. ', have '
      .. #free
  end
  plan.capacities =
    Config.capacityReport({ [settings.destination] = plan.occupied + #plan.transfers })
  if #plan.transfers > 0 then
    for slot = 0, editorCapacity(hw) - 1 do
      if not U.exists(direct(hw, 'getInterfacePattern', slot)) then
        plan.workspace = endpoint(hw.buffer, slot)
        break
      end
    end
    if not plan.workspace then
      plan.errors[#plan.errors + 1] = 'The pattern editor needs one empty slot.'
    end
  end
  return plan, hw
end

function C.transition.preview(c, progress, control)
  local plan = C.transition.scan(c, progress, control)
  return plan, Preview.report(plan)
end

function C.transition.apply(c, plan, progress, control)
  U.check(#plan.errors == 0, 'Resolve transition blockers first')
  local fresh, hw = C.transition.scan(c, progress, control)
  U.check(U.eq(fresh, plan), 'Interfaces or editor changed since preview. Scan again.')
  writeFile(
    paths.backup,
    { config = U.clone(c), program = 'implosionTransition', moved = #plan.transfers }
  )
  for n, entry in ipairs(plan.transfers) do
    gate()
    local bank = current(hw, entry.from)
    U.check(bank.name == plan.source, 'Source interface renamed before transfer')
    U.check(
      current(hw, entry.to).name == plan.destination,
      'Target interface renamed before transfer'
    )
    local original = bank.patterns[entry.from.slot]
    U.check(
      U.canonical(compact(original)) == entry.fingerprint,
      'Source pattern changed before transfer'
    )
    U.check(safeDonor(hw.data, original), 'Source pattern is no longer editable')
    U.check(
      not U.exists(direct(hw, 'getInterfacePattern', plan.workspace.slot)),
      'Pattern editor workspace occupied'
    )
    local op = {
      kind = 'transition',
      slot = plan.workspace.slot,
      source = entry.from,
      destination = entry.to,
      original = compact(original),
      recipe = entry.recipe,
    }
    saveOp(hw, op)
    finish(hw, op, progress)
    clearOp()
    if progress then
      progress('Transitioned pattern ' .. n .. ' / ' .. #plan.transfers)
    end
  end
end

-- Source: source/app/30_ui.lua
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
  local function editorRow(x, y, width, f, active)
    local value = values()[f.key]
    local first, cursor = 1, nil
    if edit and edit.key == f.key and edit.section == state.settings then
      first = math.max(1, edit.cursor - width + 3)
      cursor = edit.cursor
      value = unicode.sub(edit.value, first, edit.cursor - 1)
        .. '|'
        .. unicode.sub(edit.value, edit.cursor)
      text(
        x,
        y,
        value,
        width,
        active == false and 'muted' or edit.selectAll and 'yellow' or 'blue',
        'panel'
      )
    else
      text(
        x,
        y,
        value == '' and (f.placeholder or '(not configured)') or value,
        width,
        (value == '' or active == false) and 'muted' or 'text',
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
    elseif p.kind == 'donorCleanup' or p.kind == 'transition' then
      for _, row in ipairs(Preview.rows(state.section, p)) do
        add(row[1], row[2], row[3], row[4], row[5], row[6])
      end
    elseif preview.manifest and (state.section == 'existing' or state.section == 'skipped') then
      for _, row in ipairs(Preview.rows(state.section, p, preview.manifest)) do
        add(row[1], row[2], row[3], row[4], row[5], row[6])
      end
    elseif state.section == 'details' and preview.manifest then
      if preview.id == 'singularities' then
        add('ETERNAL SINGULARITY CHAIN', 'blue')
        add(
          preview.manifest.source.combinedSingularities
            .. ' combined singularities / '
            .. preview.manifest.source.baseSingularities
            .. ' base singularities.'
        )
        add('Extreme crafting is used to trace dependencies; its recipes are not patterned.')
        add(preview.manifest.source.batchPolicy, 'muted')
        add(
          'Native singularity counts can exceed the global per-item limit; they stay exact.',
          'muted'
        )
        add('Molten shortcuts and stabilized-black-hole block recipes are excluded.', 'muted')
        add('')
      end
      if preview.id == 'componentAssembly' then
        add('COMPONENT ASSEMBLY LINE', 'blue')
        add('Installed casings: ' .. preview.manifest.policy.casingTier)
        add(preview.manifest.source.batchPolicy, 'muted')
        add('One recipe per component/tier. Compatible installed alternatives are reused.', 'muted')
        add('')
      end
      if Programs.byId[preview.id].stockedForms then
        add('STOCKED IN MACHINE', 'blue')
        add('These reusable items stay in the machine and are omitted from patterns.')
        local stocked = {}
        local program = Programs.byId[preview.id]
        for _, recipe in ipairs(preview.manifest.recipes) do
          local key = Programs.switchKey(program, recipe.outputForm)
          if not stocked[key] or #stocked[key].items == 0 then
            stocked[key] = { label = recipe.outputLabel, items = recipe.stock or {} }
          end
        end
        for _, entry in ipairs(program.stockedForms) do
          local group = stocked[entry[1]]
          if group and #group.items > 0 then
            local names = {}
            for _, item in ipairs(group.items) do
              names[#names + 1] = item.name == 'gregtech:gt.integrated_circuit'
                  and ('circuit ' .. item.damage)
                or tostring(item.label or item.name)
            end
            add(
              (
                (program.switchByDestination or program.mode == 'components') and entry[2]
                or group.label
                or entry[2]
              )
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
      -- Sidebar sections have their own bounds; derive spacing so adding a
      -- program cannot cover Current preview or bottom actions.
      local sectionTop = layout.body + 15
      local sectionStep = math.min(
        3,
        math.floor((layout.scrollFooter - 2 - sectionTop) / math.max(1, #Programs.settings - 1))
      )
      for n, p in ipairs(Programs.settings) do
        local id = p.id
        nav(sectionTop + (n - 1) * sectionStep, p.name, state.settings == id, function()
          navigate('settings', id)
        end)
      end
      local section = Config.section(state.settings)
      local pageRow, top = layout.scrollFooter, layout.body - 1
      local pages = Settings.pages(fields(), 124, layout.bodyBottom - top + 1, unicode)
      state.settingsPage = math.min(state.settingsPage, #pages)
      local page = pages[state.settingsPage]
      text(34, layout.title, 'SETTINGS / ' .. section.name, 124, 'blue')
      text(
        34,
        layout.subtitle,
        'Accept a field or navigate away to save. Numbers accept k / M shorthand.',
        124,
        'muted'
      )
      local function helpLines(y, content)
        for index, line in ipairs(content) do
          text(34, y + index - 1, line, 124, 'muted')
        end
      end
      local function optionButtons(block, x, y, key, choices, active)
        local selected = choices and Config.selected(values()[key], choices)
        for _, option in ipairs(block.options or {}) do
          local value = option.choice[1]
          local callback = function()
            if choices then
              toggleForm(key, choices, value)
            else
              chooseValue(key, value)
            end
          end
          if choices then
            toggleButton(
              x + option.x,
              y + option.row,
              selected[value],
              callback,
              active,
              option.choice[2]
            )
          else
            button(
              x + option.x,
              y + option.row,
              option.choice[2],
              callback,
              active,
              values()[key] == value
            )
          end
        end
      end
      local function destinationRow(block, y)
        local f, program = block.field, Programs.byId[state.settings]
        local active = Config.destinationEnabled(cfg, state.settings, f.key)
        toggleButton(34, y, active, function()
          toggleForm(program.destinationSwitch, program.destinationChoices, f.key)
        end, true)
        local annotation = f.annotation or ''
        local width = 116 - (annotation ~= '' and unicode.wlen(annotation) + 2 or 0)
        editorRow(42, y, width, f, active)
        if annotation ~= '' then
          text(44 + width, y, annotation, unicode.wlen(annotation), 'muted')
        end
      end
      for _, block in ipairs(page.blocks) do
        local y, f = top + block.row, block.field
        if block.kind == 'heading' then
          text(34, y, block.label, 124, 'blue')
          helpLines(y + 1, block.help)
        elseif block.kind == 'tableHeading' then
          local overrides = f.group == 'Tier overrides'
          text(
            34,
            y,
            f.tableLabel or (overrides and 'MATERIAL TIER' or 'RELATIVE TIER'),
            42,
            'blue'
          )
          text(80, y, f.valueLabel or (overrides and 'OVERRIDE' or 'MULTIPLIER'), 22, 'blue')
          if overrides then
            text(115, y, 'EFFECTIVE', 40, 'blue')
          end
          helpLines(y + 1, block.help)
        elseif block.kind == 'destination' then
          destinationRow(block, y)
        elseif block.kind == 'table' then
          text(34, y, f.label, 42, 'text')
          editorRow(80, y, f.valueWidth or 22, f)
          if f.group == 'Tier overrides' then
            local budget = Batch.budget(cfg.batch, f.label)
            text(115, y, budget == 0 and 'Skipped' or budget .. 'x', 40, 'muted')
          end
        elseif block.kind == 'checkbox' then
          local key, choices = f.key, f.toggleValues or { 'off', 'on' }
          checkbox(34, y, f.label, values()[key] == choices[2], function()
            chooseValue(key, values()[key] == choices[2] and choices[1] or choices[2])
          end)
          helpLines(y + 1, block.help)
        else
          for index, label in ipairs(block.labels) do
            text(34, y + index - 1, label, 124, 'blue')
          end
          local controlY = y + block.control
          if f.kind == 'select' then
            local label, selected = values()[f.key], 1
            for n, option in ipairs(f.choices) do
              if option[1] == values()[f.key] then
                label, selected = option[2], n
              end
            end
            button(34, controlY, label, function()
              commitEdit()
              state.choice =
                { key = f.key, label = f.label, choices = f.choices, selected = selected }
            end)
          elseif f.choices then
            optionButtons(
              block,
              34,
              controlY,
              f.key,
              f.kind == 'multiToggle' and f.choices or nil,
              true
            )
          else
            editorRow(34, controlY, 124, f)
          end
          helpLines(y + block.helpRow, block.help)
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
        if p.kind == 'transition' then
          text(
            113,
            layout.body + 2,
            p.sourceBanks .. ' old / ' .. p.targetBanks .. ' new interfaces',
            45,
            'muted'
          )
          text(113, layout.body + 3, p.scanned .. ' encoded patterns scanned', 45)
          text(113, layout.body + 4, #p.transfers .. ' patterns to move and clean', 45, 'green')
          text(113, layout.body + 5, p.skipped .. ' skipped; see Patterns', 45, 'muted')
          text(113, layout.body + 6, p.free .. ' free target slots', 45)
          text(113, layout.body + 8, 'No disposable donors needed', 45, 'muted')
        elseif p.kind == 'donorCleanup' then
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

-- Source: source/app/90_main.lua
if ... == '--test' then
  return C
end
runUI()

end,table.unpack(args,1,args.n))
package.path=savedPath
if args[1]~='--test' then unload() end
if not ok then error(result,0) end
return result
