-- Read-only OC adapter. Donor banks are discovered by exact terminal name.
-- Pattern reads are performed one interface at a time; metadata discovery never
-- converts an entire network's pattern inventories into Lua tables.
local function discover(hw,name) return lookup(hw,name,true) end
local function patternRecipe(data,p)
  check(type(p.tag)=='string','Pattern NBT hidden; enable allowItemStackNBTTags')
  local root=nbt(data,p.tag).__value
  local crafting=truth(p.isCraftable)
  check(p.isCraftable~=nil and p.inputs and p.outputs,'Unsupported encoded pattern')
  local r={kind=crafting and 'crafting' or 'processing',inputs={},outputs={},
    substitute=root.substitute and truth(root.substitute.__value) or false,
    beSubstitute=root.beSubstitute and truth(root.beSubstitute.__value) or false}
  for _,which in ipairs({'inputs','outputs'}) do
    for index,s in pairs(p[which]) do
      if exists(s) then
        check(not truth(s.hasTag) or type(s.tag)=='string','Ingredient NBT hidden')
        r[which][index]={type=s.damage~=nil and s.amount==nil and 'item' or 'fluid',
          name=s.name,damage=s.damage,size=s.amount or s.size,tag=s.tag}
      end
    end
  end
  return r
end
local function scanManifest(c,manifest,routing,progress,control,started)
  validate(c);if not started then startWork(c,progress,control) end
  local groups={{name=routing.destination,role='destination',slots=routing.slots},
    {name=routing.donors,role='donor',slots=routing.donorSlots},
    {name=routing.workspace,role='workspace',slots=routing.workspaceSlots}}
  check(manifest.version==1 and type(manifest.recipes)=='table','Unsupported manifest schema')
  Planner.sequence(manifest.recipes,'Recipes')
  check(type(manifest.source)=='table' and type(manifest.source.recipeVersion)=='string'
    and type(manifest.source.targetVersion)=='string','Manifest must identify recipe and target versions')
  local hw={terminal=selectDevice('me_interface_terminal',c.terminalAddress),data=selectDevice('data',c.dataAddress)}
  local snapshot={terminal=hw.terminal.address,interfaces={}}
  local names={}
  for _,g in ipairs(groups) do
    check(type(g.name)=='string' and g.name~='' and not names[g.name],'Configured interface names must be unique')
    check(g.role=='destination' or g.role=='donor' or g.role=='workspace','Invalid group role')
    check(type(g.slots)=='number' and g.slots>=1 and g.slots<=512 and g.slots==math.floor(g.slots),'Set usable group slots to 1..512')
    names[g.name]=true
    local found=discover(hw,g.name)
    for _,entry in ipairs(found) do
      local i=current(hw,endpoint(entry))
      check(i.name==g.name,'Interface renamed while scanning; scan again')
      local compacted={name=i.name,location=clone(i.location),side=side(i.side),role=g.role,capacity=g.slots,patterns={}}
      for slot,p in pairs(i.patterns or {}) do
        if exists(p) then
          check(type(p.tag)=='string','Pattern NBT hidden in '..g.name)
          local value={kind='unknown',fingerprint=canonical({p.name,p.damage,p.size,invoke(hw.data,'sha256',p.tag)})}
          if p.name=='appliedenergistics2:item.ItemEncodedPattern' and p.isCraftable~=nil and p.inputs and p.outputs then
            local r=patternRecipe(hw.data,p)
            value.kind=r.kind
            local valid,key=pcall(Planner.recipeKey,r)
            if valid then value.recipeKey=key end
            value.donor=valid and not r.substitute and not r.beSubstitute
          end
          compacted.patterns[slot]=value
        end
      end
      snapshot.interfaces[#snapshot.interfaces+1]=compacted
      if progress then progress('Read '..i.name..' at '..U.locationText(i)) end
      check(computer.freeMemory()>160000,'Low memory while collecting compact interface snapshot')
    end
  end
  local request={recipes={},source=clone(manifest.source),policy=clone(manifest.policy or {}),unresolved=clone(manifest.unresolved)}
  local labels={}
  for _,r in ipairs(manifest.recipes) do
    local key=Planner.recipeKey(r)
    request.recipes[#request.recipes+1]={key=key,kind=r.kind,destination=routing.destination,
      stock=clone(r.stock),stockAlternatives=clone(r.stockAlternatives)}
    labels[key]=r.label or r.id or r.outputs[1].name
  end
  local plan=Planner.plan(request,snapshot,function()
    gate();check(computer.freeMemory()>160000,'Low memory while planning')
  end)
  return plan,snapshot,request,labels
end
local function describe(e)
  if not e then return '(no available slot)' end
  return U.locationText(e)..' slot '..e.slot
end
local function previewReport(plan,manifest,labels)
  local details={}
  local function ingredients(list)
    local out={}
    for _,s in ipairs(list or {}) do
      out[#out+1]=tostring(s.size or s.n)..'x '..(s.fluid or (s.name..':'..s.damage))
    end
    return table.concat(out,', ')
  end
  for _,recipe in ipairs(manifest.recipes) do details[Planner.recipeKey(recipe)]=recipe end
  local lines={'PATTERN MAKER / PREVIEW','Recipe source: '..manifest.source.recipeVersion..
    ' | target: '..manifest.source.targetVersion,'Slots below are ZERO based; configured capacities must match unlocked rows.',
    'Workspace connectivity is not verified by this read-only tool.'}
  if manifest.source.excludedRecipes then lines[#lines+1]='Unsupported source recipes excluded: '..manifest.source.excludedRecipes end
  for _,name in ipairs(manifest.unresolved or {}) do lines[#lines+1]='UNVERIFIED registry spelling: '..name end
  lines[#lines+1]='Fluids, circuits and omitted PVC/PPS require external stocking; alternatives use the listed primary item.'
  lines[#lines+1]=string.format('Reuse %d | Create %d processing + %d crafting | Preserve %d unrelated/duplicate patterns',
    plan.reused,plan.required.processing,plan.required.crafting,#plan.preserved)
  for _,err in ipairs(plan.errors) do lines[#lines+1]='BLOCKED: '..err end
  lines[#lines+1]='FINAL LAYOUT (material and rule order)'
  for _,r in ipairs(plan.layout) do
    lines[#lines+1]=(r.existing and 'REUSE ' or 'CREATE ')..labels[r.key]..' -> '..describe(r.destination)
    local recipe=details[r.key]
    lines[#lines+1]='  '..ingredients(recipe.inputs)..' -> '..ingredients(recipe.outputs)
    if recipe.stock and #recipe.stock>0 then lines[#lines+1]='  External: '..ingredients(recipe.stock) end
    if recipe.stockAlternatives then lines[#lines+1]='  Other external-stock alternatives: '..#recipe.stockAlternatives end
  end
  lines[#lines+1]='SORT EXISTING PATTERNS FIRST'
  for _,m in ipairs(plan.moves) do lines[#lines+1]=describe(m.from)..' -> '..describe(m.to) end
  for _,m in ipairs(plan.preserved) do lines[#lines+1]='PRESERVE '..describe(m.from)..' -> '..describe(m.to) end
  lines[#lines+1]='THEN IMPRINT AND INSTALL (not executed in this release)'
  for _,m in ipairs(plan.creates) do
    lines[#lines+1]=labels[m.key]..': donor '..describe(m.from)..' via '..describe(m.workspace)..' -> '..describe(m.to)
  end
  return table.concat(lines,'\n')..'\n'
end

C.maker={planner=Planner,scan=scanManifest,report=previewReport,discover=discover}
function C.maker.preview(c,progress,control)
  validate(c);startWork(c,progress,control)
  check(c.makerDestination~='' and c.makerDonors~='' and c.makerWorkspace~='',
    'Set destination, donor bank and workspace names in Maker setup')
  local manifest=require('assline_modes').compile(require('assline_data'),c.makerMode,
    {pvc=c.makerPVC=='on',pps=c.makerPPS=='on'},gate)
  local plan,_,_,labels=scanManifest(c,manifest,{destination=c.makerDestination,donors=c.makerDonors,
    workspace=c.makerWorkspace,slots=tonumber(c.makerSlots),donorSlots=tonumber(c.makerDonorSlots),
    workspaceSlots=tonumber(c.makerWorkspaceSlots)},progress,control,true)
  return plan,previewReport(plan,manifest,labels)
end
