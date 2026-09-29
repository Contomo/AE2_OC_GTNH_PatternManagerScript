local function item(s)
  return exists(s) and s.damage~=nil and s.amount==nil
    and not s.name:lower():find('fluiddrop',1,true) and not s.name:lower():find('fluid_drop',1,true)
    and not s.name:lower():find('fluidpacket',1,true) and not s.name:lower():find('fluid_packet',1,true)
end
local function metadata(data,p)
  local t=nbt(data,p.tag); t.__value['in']=nil; t.__value.out=nil; return t
end
local function safeDonor(data,p)
  if not processing(p) or not p.tag then return false end
  local t=encodedPattern(data,p);if not t then return false end
  for _,k in ipairs({'substitute','beSubstitute'}) do
    if t[k] and truth(t[k].__value) then return false end
  end
  return true
end
local function pureRecipe(data,p,r)
  if not safeDonor(data,p) then return false end
  for _,which in ipairs({'inputs','outputs'}) do
    for index,s in pairs(p[which]) do if exists(s) and index~=1 then return false end end
  end
  local a,b=p.inputs[1],p.outputs[1]
  return item(a) and item(b) and a.size>0 and a.size==b.size
    and identity(data,a)==identity(data,r.input) and identity(data,b)==identity(data,r.output)
end
local function scan(c,progress,control)
  Config.requireProgram(c,'assline')
  local settings=c.programs.assline
  local hw=connect(c,progress,control)
  local target=unique(hw,settings.target)
  check(where(target)~=where(hw.buffer),'Target is the pattern editor')
  local buffer=current(hw,hw.buffer)
  local p={target=endpoint(target),buffer=hw.buffer,changes={},recipes={},errors={},scanned=0,skipped=0,donors={},empty={}}
  local function problem(s) p.errors[#p.errors+1]=s end
  local wanted={}
  for _,slot in ipairs(keys(target.patterns)) do
    gate()
    local original=target.patterns[slot]
    if exists(original) then
      p.scanned=p.scanned+1
      if processing(original) then
        check(type(original.tag)=='string','Pattern NBT is hidden; enable allowItemStackNBTTags')
        local counts,occupied,changes={},{},{}
        for _,s in pairs(original.inputs) do if item(s) then occupied[identity(hw.data,s)]=true end end
        for _,index in ipairs(keys(original.inputs)) do
          local s=original.inputs[index]
          if item(s) then
            local id=identity(hw.data,s); local n=counts[id] or 0; counts[id]=n+1
            if n>0 then
              check(type(s.size)=='number' and s.size>0 and s.size<=2147483647,'Unsupported input amount')
              local output,label
              repeat
                label=token(settings.itemName,s.label or s.name,n)
                check(unicode.len(label)<=128,'Generated item name is longer than 128 characters')
                output=renamed(hw.data,s,label)
                if not occupied[identity(hw.data,output)] then break end
                n=n+1; check(n<=512,'Cannot allocate unique item names')
              until false
              counts[id]=n+1; occupied[identity(hw.data,output)]=true
              changes[#changes+1]={index=index,before=stack(s),after=output}
              local destName=token(settings.renameName,s.label or s.name,n)
              local recipeKey=canonical({destName,id,identity(hw.data,output)})
              if not wanted[recipeKey] then
                local r={input=stack(s),output=output,name=destName}
                wanted[recipeKey]=r; p.recipes[#p.recipes+1]=r
              end
            end
          end
        end
        if #changes>0 then p.changes[#p.changes+1]={slot=slot,original=compact(original),edits=changes} end
      else p.skipped=p.skipped+1 end
    end
    if progress then progress('Scanning pattern '..tostring(slot+1)) end
    check(computer.freeMemory()>160000,'Low memory; scan a smaller target interface')
  end
  -- Only requested names are fetched; no getAll(true) of a large ME network.
  local groups,used={},{ }
  for _,r in ipairs(p.recipes) do
    if not groups[r.name] then groups[r.name]=lookup(hw,r.name) end
    local group=groups[r.name]
    for _,i in ipairs(group) do
      check(where(i)~=where(target) and where(i)~=where(hw.buffer),'Rename interface overlaps target or buffer')
      for _,slot in ipairs(keys(i.patterns)) do
        if pureRecipe(hw.data,i.patterns[slot],r) then
          r.existing=endpoint(i,slot); break
        end
      end
      if r.existing then break end
    end
    if not r.existing then
      for _,i in ipairs(group) do
        local key=where(i); used[key]=used[key] or {}
        local slots=capacity(i)
        for slot=0,slots-1 do
          if not exists(i.patterns[slot]) and not used[key][slot] then
            used[key][slot]=true; r.destination=endpoint(i,slot); break
          end
        end
        if r.destination then break end
      end
      if not r.destination then problem('No verified free slot in "'..r.name..'" (missing, full, or capacity unavailable)') end
    end
    if progress then progress('Checking '..r.name) end
  end
  for slot=0,editorCapacity(hw)-1 do
    local remote=buffer.patterns[slot]
    local live=direct(hw,'getInterfacePattern',slot)
    check(patternEq(hw.data,remote,live),'Direct pattern editor does not match "'..c.shared.editor..'" at slot '..(slot+1))
    if not exists(remote) then p.empty[#p.empty+1]=slot
    end
  end
  local donors={}
  for _,bank in ipairs(lookup(hw,c.shared.donors)) do
    check(where(bank)~=where(target) and where(bank)~=where(hw.buffer),'New pattern buffer overlaps target or editor')
    for _,slot in ipairs(keys(bank.patterns)) do
      local pattern=bank.patterns[slot]
      if safeDonor(hw.data,pattern) then donors[#donors+1]={from=endpoint(bank,slot),slot=slot,original=compact(pattern)} end
    end
  end
  local n=0
  for _,r in ipairs(p.recipes) do
    if not r.existing then
      n=n+1
      if donors[n] then r.donor=donors[n] else problem('Need more disposable processing patterns in '..c.shared.donors) end
    end
  end
  p.newRecipes=n; p.available=#donors
  local requirements={}
  for name,group in pairs(groups) do
    local needed=0
    for _,i in ipairs(group) do for _,pattern in pairs(i.patterns) do if exists(pattern) then needed=needed+1 end end end
    for _,recipe in ipairs(p.recipes) do if recipe.name==name and not recipe.existing then needed=needed+1 end end
    requirements[name]=needed
  end
  p.capacities=Config.capacityReport(requirements)
  if (#p.changes>0 or n>0) and #p.empty==0 then problem('Leave one empty pattern slot in '..c.shared.editor..' for editing') end
  return p,hw
end
C.scan=scan
