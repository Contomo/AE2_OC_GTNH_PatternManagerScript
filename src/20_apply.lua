-- One durable intent per moved pattern. Recovery completes only that operation;
-- another scan is required before continuing the rest of a batch.
local function rawList(data,p,which)
  local root=nbt(data,p.tag).__value
  local t=root[which=='inputs' and 'in' or 'out']
  check(t and t.__nbt_type=='list','Unsupported encoded pattern layout')
  return t.__value
end
local function expected(op)
  local p=compact(op.original)
  if op.kind=='recipe' then
    p.inputs={[1]=op.input}; p.outputs={[1]=op.output}
  else for _,e in ipairs(op.edits) do p.inputs[e.index]=e.after end end
  return p
end
local function semantic(hw,p,q)
  if not exists(p) or not exists(q) or p.name~=q.name or p.damage~=q.damage then return false end
  if not eq(metadata(hw.data,p),metadata(hw.data,q)) then return false end
  for _,which in ipairs({'inputs','outputs'}) do
    local all={}; for k in pairs(p[which] or {}) do all[k]=true end; for k in pairs(q[which] or {}) do all[k]=true end
    for k in pairs(all) do if not stackEq(hw.data,p[which][k],q[which][k]) then return false end end
  end
  return true
end
local function allowedPartial(hw,p,op)
  check(exists(p) and p.name==op.original.name and p.damage==op.original.damage,'Unexpected pattern in buffer')
  check(eq(metadata(hw.data,p),metadata(hw.data,op.original)),'Pattern flags or other NBT changed; recovery stopped')
  local final=expected(op)
  for _,which in ipairs({'inputs','outputs'}) do
    local all={}; for k in pairs(p[which] or {}) do all[k]=true end
    for k in pairs(op.original[which]) do all[k]=true end
    for k in pairs(final[which]) do all[k]=true end
    for k in pairs(all) do
      local a=p[which][k]; local old=op.original[which][k]; local new=final[which][k]
      check(stackEq(hw.data,a,old) or stackEq(hw.data,a,new),'Unexpected '..which..' slot '..k..'; recovery stopped')
    end
  end
end
local function transfer(hw,from,to)
  local ok,slot=invoke(hw.terminal,'send',from,to)
  check(ok==true,'Pattern transfer failed: '..tostring(slot))
  check(slot==to.slot,'Pattern moved to unexpected slot '..tostring(slot))
end
local function setEntry(hw,slot,which,index,s)
  local method=which=='inputs' and 'setInterfacePatternInput' or 'setInterfacePatternOutput'
  if s then
    check(direct(hw,method,slot,index,{name=s.name,damage=s.damage,size=s.size,tag=s.tag},'item')==true,'Pattern setter returned failure')
  else check(direct(hw,method,slot,index)==true,'Pattern clear returned failure') end
end
local function finish(hw,op,progress)
  check(op.version==1 and op.direct==hw.direct.address and op.terminal==hw.terminal.address
    and op.data==hw.data.address and where(op.buffer)==where(hw.buffer),'Recovery hardware differs from saved operation')
  local goal=expected(op)
  local dest=current(hw,op.destination)
  local remote=current(hw,op.buffer)
  local p=remote.patterns[op.slot]
  check(patternEq(hw.data,p,direct(hw,'getInterfacePattern',op.slot)),'Direct/terminal buffer mismatch')
  local delivered=dest.patterns[op.destination.slot]
  if not exists(p) and exists(delivered) and semantic(hw,delivered,goal) then
    return -- A transfer succeeded immediately before the power loss.
  end
  if op.kind=='edit' and not exists(p) then
    check(patternEq(hw.data,delivered,op.original),'Original target pattern changed')
    transfer(hw,op.destination,endpoint(op.buffer,op.slot))
    p=direct(hw,'getInterfacePattern',op.slot)
    check(patternEq(hw.data,p,op.original),'Moved pattern failed read-back')
  else check(not exists(delivered),'Destination slot is occupied') end
  allowedPartial(hw,p,op)
  if op.kind=='recipe' then
    -- Clearing removes an NBT list element: ALWAYS clear from the end.
    for _,which in ipairs({'inputs','outputs'}) do
      local s=which=='inputs' and op.input or op.output
      local entries=rawList(hw.data,p,which)
      if not stackEq(hw.data,p[which][1],s) then setEntry(hw,op.slot,which,1,s) end
      for index=largest(entries),2,-1 do
        local entry=entries[index]
        check(entry and entry.__nbt_type=='compound' and type(entry.__value)=='table','Invalid pattern list entry')
        -- AE ignores empty compounds. Do not spend a server tick removing every
        -- unused cell in a padded processing donor. Clear nonempty cells only.
        if next(entry.__value)~=nil then setEntry(hw,op.slot,which,index) end
      end
    end
  else
    for _,e in ipairs(op.edits) do
      if not stackEq(hw.data,p.inputs[e.index],e.after) then setEntry(hw,op.slot,'inputs',e.index,e.after) end
    end
  end
  p=direct(hw,'getInterfacePattern',op.slot)
  check(semantic(hw,p,goal),'Edited pattern read-back failed; saved recovery record retained')
  check(patternEq(hw.data,current(hw,op.buffer).patterns[op.slot],p),'Edited direct buffer differs from named terminal buffer')
  local liveDest=current(hw,op.destination)
  check(not exists(liveDest.patterns[op.destination.slot]),'Destination filled during edit')
  transfer(hw,endpoint(op.buffer,op.slot),op.destination)
  local after=current(hw,op.destination).patterns[op.destination.slot]
  check(semantic(hw,after,goal),'Destination read-back failed')
  check(not exists(direct(hw,'getInterfacePattern',op.slot)),'Buffer slot did not empty')
  if progress then progress('Verified pattern in destination slot '..(op.destination.slot+1)) end
end
local function saveOp(hw,op)
  check(not fs.exists(paths.pending),'An unfinished operation needs Recover first')
  op.version=1; op.direct=hw.direct.address; op.terminal=hw.terminal.address; op.data=hw.data.address; op.buffer=clone(hw.buffer)
  writeFile(paths.pending,op)
end
local function clearOp() check(fs.remove(paths.pending),'Cannot clear completed recovery record') end
local function apply(c,plan,progress,control)
  check(not fs.exists(paths.pending),'Use Recover before applying another scan')
  check(#plan.errors==0,'Resolve scan blockers first')
  local fresh,hw=scan(c,progress,control)
  check(eq(fresh,plan),'Patterns or destinations changed since preview. Scan again.')
  fresh=nil
  writeFile(paths.backup,{config=clone(c),plan=plan})
  local workspace=plan.empty[1]
  for _,r in ipairs(plan.recipes) do
    if not r.existing then
      local op={kind='recipe',slot=r.donor.slot,original=r.donor.original,destination=r.destination,input=r.input,output=r.output}
      -- Recheck the exact disposable pattern before writing the intent.
      check(patternEq(hw.data,direct(hw,'getInterfacePattern',op.slot),op.original),'Buffer pattern changed')
      saveOp(hw,op); finish(hw,op,progress); clearOp(); workspace=workspace or op.slot
    end
  end
  for _,v in ipairs(plan.changes) do
    -- One fresh snapshot per interface, used only for this target operation.
    -- Check only the recipes used by this target, not the batch's full manifest.
    local required={}
    for _,e in ipairs(v.edits) do required[identity(hw.data,e.after)]=true end
    local snapshots={}
    for _,r in ipairs(plan.recipes) do
      if required[identity(hw.data,r.output)] then
        local e=r.existing or r.destination;local key=where(e)
        if not snapshots[key] then snapshots[key]=current(hw,e) end
        check(pureRecipe(hw.data,snapshots[key].patterns[e.slot],r),'Rename recipe removed or changed; scan again')
      end
    end
    check(workspace~=nil,'No free buffer slot')
    local op={kind='edit',slot=workspace,original=v.original,edits=v.edits,destination=endpoint(plan.target,v.slot)}
    check(not exists(direct(hw,'getInterfacePattern',workspace)),'Buffer workspace occupied')
    saveOp(hw,op); finish(hw,op,progress); clearOp()
  end
end
local function recover(c,progress,control)
  local op=check(readFile(paths.pending),'No pending operation')
  local hw=connect(c,progress,control); finish(hw,op,progress); clearOp()
end
C.apply=apply; C.recover=recover; C.paths=paths; C.finish=finish
