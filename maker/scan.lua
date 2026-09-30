-- Shared named-interface adapter. Planning is read-only; execution uses the
-- same editor, durable operations and recovery as the assembly-line program.
-- Pattern reads are performed one interface at a time; metadata discovery never
-- converts an entire network's pattern inventories into Lua tables.
local function discover(hw,name) return lookup(hw,name,true) end
local function recipeKey(data,recipe)
  local normalized=clone(recipe)
  for _,which in ipairs({'inputs','outputs'}) do
    for _,s in pairs(normalized[which]) do
      local key=tagKey(data,s);s.tag=key~='{}' and key or nil
    end
  end
  return Planner.recipeKey(normalized)
end
local function patternRecipe(p,root)
  check(type(p.tag)=='string','Pattern NBT hidden; enable allowItemStackNBTTags')
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
  local groups,names={},{}
  local function group(name,role)
    check(type(name)=='string' and name~='','Set the '..role..' interface name in Settings')
    check(not names[name] or names[name]==role,'Interface roles overlap: '..name)
    if not names[name] then groups[#groups+1]={name=name,role=role};names[name]=role end
  end
  local function destination(recipe)
    return routing.destinations and routing.destinations[recipe.outputForm] or routing.destination
  end
  check(manifest.version==1 and type(manifest.recipes)=='table','Unsupported manifest schema')
  Planner.sequence(manifest.recipes,'Recipes')
  check(type(manifest.source)=='table' and type(manifest.source.recipeVersion)=='string'
    and type(manifest.source.targetVersion)=='string','Manifest must identify recipe and target versions')
  for _,recipe in ipairs(manifest.recipes) do group(destination(recipe),'destination') end
  group(routing.donors,'donor');group(routing.workspace,'workspace')
  local hw={terminal=selectDevice('me_interface_terminal',c.shared.terminalAddress),data=selectDevice('data',c.shared.dataAddress)}
  local snapshot={terminal=hw.terminal.address,interfaces={}}
  for _,g in ipairs(groups) do
    local found=discover(hw,g.name)
    for _,entry in ipairs(found) do
      local i=current(hw,endpoint(entry))
      check(i.name==g.name,'Interface renamed while scanning; scan again')
      local slots=capacity(i)
      -- Donor capacity is irrelevant: include every occupied pattern, even when
      -- the buffer is a larger inventory than a standard destination interface.
      if g.role=='donor' then slots=math.max(1,largest(i.patterns)+1) end
      local compacted={name=i.name,location=clone(i.location),side=side(i.side),role=g.role,capacity=slots,patterns={}}
      for slot,p in pairs(i.patterns or {}) do
        if exists(p) then
          check(type(p.tag)=='string','Pattern NBT hidden in '..g.name)
          local reason,root=donorIssue(hw.data,p)
          local value={kind='unknown',fingerprint=patternFingerprint(hw,p),reason=reason}
          if root then
            local r=patternRecipe(p,root)
            value.kind=r.kind
            local valid,key=pcall(recipeKey,hw.data,r)
            if valid then value.recipeKey=key end
            value.donor=value.reason==nil
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
    local key=recipeKey(hw.data,r);r.key=key
    request.recipes[#request.recipes+1]={key=key,kind=r.kind,destination=destination(r),
      stock=clone(r.stock),stockAlternatives=clone(r.stockAlternatives)}
    labels[key]=r.label or r.id or r.outputs[1].name
  end
  local plan=Planner.plan(request,snapshot,function()
    gate();check(computer.freeMemory()>160000,'Low memory while planning')
  end)
  return plan,snapshot,request,labels
end
local function previewRows(plan,manifest,labels)
  local rows,details={},{}
  local function add(s,tone) rows[#rows+1]={s,tone or 'text'} end
  local function ingredients(list)
    local out={}
    for _,s in ipairs(list) do out[#out+1]=s.size..' x '..(s.label or s.name) end
    return table.concat(out,', ')
  end
  for _,recipe in ipairs(manifest.recipes) do details[recipe.key or Planner.recipeKey(recipe)]=recipe end
  add('PATTERN PLAN','blue')
  add(string.format('%d reuse   |   %d new   |   %d other patterns kept',plan.reused,
    plan.required.processing+plan.required.crafting,#plan.preserved),'green')
  add('')
  local group,bank,material
  for _,r in ipairs(plan.layout) do
    local recipe=details[r.key]
    if group~=r.group then
      group=r.group;bank=nil;material=nil;add('');add('DESTINATION: '..tostring(group),'blue')
    end
    local location=r.destination and where(r.destination)
    if location and bank~=location then
      bank=location;add('Interface: '..U.locationText(r.destination),'muted')
    end
    if material~=(recipe.material or recipe.label) then
      material=recipe.material or recipe.label;add('');add(material,'blue')
    end
    add((r.existing and 'REUSE   ' or 'CREATE  ')..(recipe.outputLabel or recipe.outputForm or '')..
      (r.destination and ('   slot '..r.destination.slot) or '   needs space'),r.existing and 'green' or 'yellow')
    add('  '..ingredients(recipe.inputs))
    add('  -> '..ingredients(recipe.outputs),'green')
    add('')
  end
  return rows
end
local function previewReport(plan,manifest,labels)
  local lines={}
  for _,r in ipairs(previewRows(plan,manifest,labels)) do lines[#lines+1]=r[1] end
  for _,err in ipairs(plan.errors) do lines[#lines+1]='BLOCKED: '..err end
  return table.concat(lines,'\n')..'\n'
end

C.maker={planner=Planner,scan=scanManifest,report=previewReport,rows=previewRows,discover=discover}
local function programRouting(c,id)
  local program=Config.requireProgram(c,id)
  local values=c.programs[id]
  local routing={donors=c.shared.donors,workspace=c.shared.editor,destination=values.destination}
  local forms
  if program.outputs then
    forms={};routing.destinations={}
    for form,key in pairs(program.outputs) do forms[form]=true;routing.destinations[form]=values[key] end
  end
  return routing,{polymer=values.polymer,pps=values.pps~='off',forms=forms,
    sources=id=='wiremill' and {wire1=values.wireSource,wireFine=values.fineSource} or nil},program
end
function C.maker.preview(c,id,progress,control)
  validate(c);startWork(c,progress,control)
  local routing,options,program=programRouting(c,id)
  local manifest=Modes.compile(require('assline_data'),program.mode,options,gate)
  local plan,snapshot,_,labels=scanManifest(c,manifest,routing,progress,control,true)
  local groups={}
  for _,recipe in ipairs(manifest.recipes) do
    local name=routing.destinations and routing.destinations[recipe.outputForm] or routing.destination
    groups[name]=(groups[name] or 0)+1
  end
  local banks={}
  for _,i in ipairs(snapshot.interfaces) do banks[where(i)]=i.name end
  for _,entry in ipairs(plan.preserved) do
    local name=banks[where(entry.from)];groups[name]=groups[name]+1
  end
  plan.capacities=Config.capacityReport(groups)
  local report=previewReport(plan,manifest,labels)
  for _,g in ipairs(plan.capacities) do
    report=string.format('%s: %d total slots needed; at least %d fully expanded interface(s).\n',g.name,g.patterns,g.interfaces)..report
  end
  return plan,report,manifest
end

function C.maker.finishMove(hw,op)
  local source=current(hw,op.source).patterns[op.source.slot]
  local destination=current(hw,op.destination).patterns[op.destination.slot]
  local function matches(p)
    return op.fingerprint and patternFingerprint(hw,p)==op.fingerprint or op.original and patternEq(hw.data,p,op.original)
  end
  if not exists(source) and matches(destination) then return end
  check(matches(source),'Sorting source changed; recovery stopped')
  check(not exists(destination),'Sorting destination is occupied')
  transfer(hw,op.source,op.destination)
  check(matches(current(hw,op.destination).patterns[op.destination.slot]),'Sorted pattern read-back failed')
end

function C.maker.finishSort(hw,op,progress)
  local cursor=check(readFile(paths.cursor),'Missing sorting recovery progress')
  check(cursor.id==op.id and U.integer(cursor.index) and cursor.index>=1 and cursor.index<=#op.moves+1,'Invalid sorting recovery progress')
  for n=cursor.index,#op.moves do
    local move=op.moves[n]
    C.maker.finishMove(hw,{source=move.from,destination=move.to,fingerprint=move.fingerprint})
    writeFile(paths.cursor,{id=op.id,index=n+1})
    if progress then progress('Sorted pattern '..n..' / '..#op.moves) end
  end
end

function C.maker.apply(c,id,plan,manifest,progress,control)
  check(not fs.exists(paths.pending),'Use Recover before executing another preview')
  check(#plan.errors==0,'Resolve preview blockers first')
  check(not manifest.unresolved or #manifest.unresolved==0,'Resolve unverified registry spellings before execution')
  local routing=programRouting(c,id)
  local baseline=clone(plan);baseline.capacities=nil
  local _,snapshot,request=scanManifest(c,manifest,routing,progress,control)
  Planner.revalidate(request,snapshot,baseline,gate)
  local hw=connect(c,progress,control)
  local editor=current(hw,hw.buffer)
  local slot=plan.creates[1] and plan.creates[1].workspace.slot
  if slot then
    check(where(plan.creates[1].workspace)==where(hw.buffer),'Planned workspace is not the shared pattern editor')
    check(slot<editorCapacity(hw),'Editor workspace slot is unavailable')
    check(patternEq(hw.data,editor.patterns[slot],direct(hw,'getInterfacePattern',slot)),'Direct pattern editor does not match the terminal')
    check(not exists(editor.patterns[slot]),'Pattern editor workspace occupied')
  end
  writeFile(paths.backup,{config=clone(c),program=id,created=#plan.creates,sorted=#plan.moves})
  if #plan.moves>0 then
    -- Keep the whole sorting stage durable. A cycle can temporarily park a
    -- pattern in the editor; Recover must finish the cycle before a new scan.
    local op={kind='sort',moves=plan.moves,id=invoke(hw.data,'sha256',canonical(plan.moves))}
    writeFile(paths.cursor,{id=op.id,index=1})
    saveOp(hw,op);C.maker.finishSort(hw,op,progress);clearOp()
  end
  local recipes={}
  for _,recipe in ipairs(manifest.recipes) do recipes[recipe.key or Planner.recipeKey(recipe)]=recipe end
  for _,create in ipairs(plan.creates) do
    local original=check(current(hw,create.from).patterns[create.from.slot],'Donor disappeared')
    check(patternFingerprint(hw,original)==create.fingerprint,'Donor pattern changed')
    check(safeDonor(hw.data,original),'Only disposable processing donors can be imprinted by this executor')
    local recipe=recipes[create.key]
    check(recipe and recipe.kind=='processing','Unsupported pattern kind')
    for _,which in ipairs({'inputs','outputs'}) do for _,s in ipairs(recipe[which]) do check(s.type=='item','Only solid ingredients are supported') end end
    local op={kind='imprint',source=create.from,slot=create.workspace.slot,destination=create.to,original=compact(original),recipe=recipe}
    saveOp(hw,op);finish(hw,op,progress);clearOp()
    if progress then progress('Installed '..recipe.label) end
  end
end

C.runner={}
function C.runner.preview(c,id,progress,control)
  Config.requireProgram(c,id)
  local preview={id=id,configKey=canonical(c)}
  if id=='assline' then preview.plan=scan(c,progress,control)
  else preview.plan,preview.report,preview.manifest=C.maker.preview(c,id,progress,control) end
  return preview
end
function C.runner.execute(c,preview,progress,control)
  check(preview and preview.configKey==canonical(c),'Settings changed; build a new preview')
  Config.requireProgram(c,preview.id)
  if preview.id=='assline' then apply(c,preview.plan,progress,control)
  else C.maker.apply(c,preview.id,preview.plan,preview.manifest,progress,control) end
end
