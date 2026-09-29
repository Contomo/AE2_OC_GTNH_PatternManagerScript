local function runUI()
  local gpu=component.gpu; check(gpu,'GPU required')
  local term=require('term'); local keyboard=require('keyboard')
  local oldW,oldH=gpu.getResolution(); local oldFG=gpu.getForeground(); local oldBG=gpu.getBackground()
  local maxW,maxH=gpu.maxResolution(); check(maxW>=160 and maxH>=50,'Use a tier 3 GPU and screen with 160x50 resolution')
  local w,h=math.min(160,maxW),math.min(50,maxH)
  local colors={bg=0x101A26,panel=0x1A2A3C,text=0xDCE6EF,muted=0x8297AB,blue=0x5AC8FA,
    green=0x72D69A,yellow=0xFFD277,red=0xFF8585,button=0x27465E}
  local state={page='main',offset=0,section='changes',status='Enter a target, then Scan to preview changes.',tone='muted',running=true}
  local fields={
    {'buffer','Buffer interface name','Exact terminal display name of the directly connected interface.'},
    {'itemName','Item name template','{label} = original display name; {n} = duplicate number starting at 1.'},
    {'renameName','Rename interface template','Examples: Rename NAME_{n} or Rename {label}_{n}. Same names can span interfaces.'},
    {'bufferSlots','Usable buffer slots','Visible/unlocked pattern slots. Default 9; set 36 when all rows are available.'},
    {'renameSlots','Usable rename slots','Slots to use on each rename interface. Default 9; set 36 with capacity upgrades.'},
    {'terminalAddress','Terminal component address','Blank selects the only me_interface_terminal; otherwise paste an address/prefix.'},
    {'bufferAddress','Buffer component address','Blank selects the only me_interface; use an address/prefix if there are several.'},
    {'dataAddress','Data Card address','Blank selects the only data component. Tier 1 is sufficient.'},
    {'energyPause','Pause work below energy %','Default 25. Work waits for the resume level before continuing.'},
    {'energyResume','Resume work at energy % (default 75)','Must be at least 10 percentage points above the pause threshold.'}}
  local buttons={}; local edit
  local makerFields={
    {'makerDestination','Destination name','Exact name; all matching remote interfaces share the layout.'},
    {'makerDonors','Donor bank name','Exact name; all matching banks supply encoded donors.'},
    {'makerWorkspace','Editing/workspace name','Dedicated interface with an empty pattern slot.'},
    {'makerSlots','Destination slots per interface','Configured unlocked capacity, 1..512.'},
    {'makerDonorSlots','Donor slots per interface','Configured unlocked capacity, 1..512.'},
    {'makerWorkspaceSlots','Workspace slots per interface','Configured unlocked capacity, 1..512.'},
    {'makerPVC','Request PVC (on/off)','Consumed PVC only. Fluids and catalysts stay externally stocked.'},
    {'makerPPS','Request PPS (on/off)','Consumed PPS only; independent of PVC.'}}
  local paintKey,paintCache=nil,{}
  local contentKey,contentRows
  local function text(x,y,s,width,tone,bg)
    width=math.min(width or w-x+1,w-x+1); if width<1 then return end
    s=tostring(s or ''):gsub('\194\167.',''):gsub('[%c]',' ')
    s=unicode.sub(s,1,width)
    local key=x..':'..y..':'..width;local value=s..':'..tostring(tone)..':'..tostring(bg)
    if paintCache[key]==value then return end
    paintCache[key]=value
    gpu.setForeground(colors[tone or 'text']); gpu.setBackground(colors[bg or 'bg'])
    gpu.set(x,y,s..string.rep(' ',math.max(0,width-unicode.wlen(s))))
  end
  local function button(x,y,label,action,enabled)
    local length=unicode.len(label)+4
    text(x,y,'[ '..label..' ]',length,enabled==false and 'muted' or 'text','button')
    if enabled~=false then buttons[#buttons+1]={x=x,y=y,w=length,action=action} end
    return x+length+2
  end
  local location=U.locationText
  local function description(s) return tostring(s.size or '?')..' x '..tostring(s.label or s.name) end
  local function lines()
    local r={}; local p=state.plan
    local function add(s,tone) r[#r+1]={s,tone or 'text'} end
    if state.error then add('LAST ERROR','red');add(state.error,'red');add('') end
    if state.section=='maker' then
      if state.makerReport then for line in state.makerReport:gmatch('[^\n]+') do add(line) end
      else add('Open Maker setup, choose a mode and interface names, then Preview.','muted') end
    elseif state.section=='history' then
      add('RECENT OPERATIONS (newest first)','blue')
      add('/home/assline-perf.log; showing up to 16 KB.','muted');add('')
      for _,line in ipairs(state.history or {}) do add(line) end
      if not state.history or #state.history==0 then add('No operations recorded yet.','muted') end
    elseif state.section=='help' then
      add('SETUP','blue');add('Tier 3 screen/GPU, keyboard, 2 MB+ RAM, tier 1+ Data Card.')
      add('Connect the terminal and adapter-connected buffer to the same AE grid.')
      add('Use disposable encoded PROCESSING donors. Crafting donors are skipped.')
      add('Keep machines idle and buffer isolated from machinery. Enable allowItemStackNBTTags.')
      add('');add('WORKFLOW','blue');add('Set exact names and usable slot limits. Scan, review both tabs, then Apply.')
      add('Rename recipes install first. Edited targets return to their original slots.')
      add('');add('RECOVERY','yellow');add('After interruption, leave patterns in place and Recover; then Scan again.')
      add('Recovery stops on foreign edits. Pending: /home/assline.pending; backup: /home/assline.last.')
      add('History shows recent timing, charge and memory reports from /home/assline-perf.log.')
    elseif not p then
      add('Nothing scanned yet. Scan to see exactly what will change.','muted')
      add('Example: rod, 128 wire, 128 wire, 128 wire','muted')
      add('Result:  rod, 128 wire, 128 NAME_1, 128 NAME_2','green')
      add('The first occurrence stays unchanged. Numbering starts over in each pattern.','muted')
    elseif state.section=='recipes' then
      for _,v in ipairs(p.recipes) do
        add((v.existing and 'REUSE  ' or 'CREATE ')..v.name,v.existing and 'green' or 'yellow')
        add('  '..description(v.input)..' -> '..description(v.output))
        local e=v.existing or v.destination
        if e then add('  Slot '..(e.slot+1)..' at '..location(e),'muted') end
        if v.donor then add('  Consumes buffer pattern slot '..(v.donor.slot+1),'yellow') end
      end
      if #p.recipes==0 then add('No rename recipes required.','green') end
    else
      for _,v in ipairs(p.changes) do
        local out=v.original.outputs[1]
        add('PATTERN '..(v.slot+1)..'  '..(out and description(out) or '(no first output)'),'blue')
        for _,e in ipairs(v.edits) do
          add('  Input '..e.index..': '..description(e.before))
          add('        -> '..description(e.after),'green')
        end
      end
      if #p.changes==0 then add('No duplicate item inputs found.','green') end
    end
    return r
  end
  local draw,action,handle,commitEdit
  local function startEdit(key,draft,cursor)
    local values=draft and state.draft or cfg
    if not edit or edit.key~=key or edit.draft~=draft then
      edit={key=key,value=values[key],draft=draft}
    end
    edit.cursor=math.max(1,math.min(cursor,unicode.len(edit.value)+1));edit.selectAll=false
  end
  local function editorRow(x,y,width,key,draft)
    local values=draft and state.draft or cfg; local val=values[key]
    local first,cursor=1,nil
    if edit and edit.key==key then
      first=math.max(1,edit.cursor-width+3);cursor=edit.cursor
      val=unicode.sub(edit.value,first,edit.cursor-1)..'|'..unicode.sub(edit.value,edit.cursor)
      text(x,y,val,width,edit.selectAll and 'yellow' or 'blue','panel')
    else text(x,y,val=='' and (key:match('^maker') and '(required)' or '(automatic)') or val,width,'text','panel') end
    if state.busy then return end
    buttons[#buttons+1]={x=x,y=y,w=width,editKey=key,draft=draft,action=function(clickX)
      local at=first+clickX-x
      if cursor and at>cursor then at=at-1 end -- Account for the visible cursor glyph.
      startEdit(key,draft,at)
    end}
  end
  draw=function()
    local key=state.page..state.section..tostring(state.plan)..tostring(state.makerPlan)..tostring(state.busy)..tostring(state.error)..tostring(fs.exists(paths.pending))
    if key~=paintKey then
      gpu.setBackground(colors.bg);gpu.fill(1,1,w,h,' ');paintCache={};paintKey=key
    end
    buttons={}
    text(2,2,'ASSEMBLY LINE / PATTERN RENAMER',w-4,'blue')
    text(2,3,string.format('GTNH 2.9   |   %.0f%% energy   |   %d KB free',
      energyFraction()*100,math.floor(computer.freeMemory()/1024)),w-4,'muted')
    if state.page=='maker' then
      local x=button(2,5,'Preview',function() action('makerScan') end,not fs.exists(paths.pending))
      x=button(x,5,'Mode: '..state.draft.makerMode,function()
        commitEdit();state.draft.makerMode=state.draft.makerMode=='wiremill' and 'coating' or 'wiremill'
      end)
      button(x,5,'Back',function() state.page='main';edit=nil end)
      for i,f in ipairs(makerFields) do
        local y=7+(i-1)*4
        text(3,y,f[2],w-6,'blue');editorRow(3,y+1,w-6,f[1],true);text(3,y+2,f[3],w-6,'muted')
      end
      text(3,42,'Preview only. LATEX, combining and the new mode executor are the next stages.',w-6,'yellow')
    elseif state.page=='settings' then
      local x=button(2,5,'Save settings',function() action('save') end)
      button(x,5,'Cancel',function() state.page='main'; edit=nil end)
      for i,f in ipairs(fields) do
        local y=7+(i-1)*4
        text(3,y,f[2],w-6,'blue'); editorRow(3,y+1,w-6,f[1],true)
        if y+2<h-2 then text(3,y+2,f[3],w-6,'muted') end
      end
    else
      text(2,5,'Target interface',19,'blue'); editorRow(22,5,w-24,'target',false)
      local pending=fs.exists(paths.pending)
      local x=button(2,7,'Scan',function() action('scan') end,not pending and not state.busy)
      x=button(x,7,'Apply preview',function() action('apply') end,state.section~='maker' and state.plan and #state.plan.errors==0 and #state.plan.changes>0 and not pending and not state.busy)
      x=button(x,7,'Settings',function() action('settings') end,not state.busy)
      x=button(x,7,'Recover',function() action('recover') end,pending and not state.busy)
      x=button(x,7,'Quit',function() state.cancelled=true;state.running=false end)
      if state.busy then button(x,7,'Cancel work',function() state.cancelled=true end) end
      if not state.busy then button(x,7,'Maker setup',function() action('makerSettings') end) end
      x=2
      for _,tab in ipairs({{'changes','Input changes'},{'recipes','Rename recipes'},{'help','Setup / help'},{'history','History'},{'maker','Pattern maker'}}) do
        local section=tab[1]
        x=button(x,9,(state.section==section and '* ' or '')..tab[2],function() action(section) end)
      end
      local sideX=math.max(67,w-48); local contentW=sideX-4
      local rowsKey=state.section..tostring(state.plan)..tostring(state.makerPlan)..tostring(state.history)..tostring(state.error)
      if rowsKey~=contentKey then
        contentRows={};contentKey=rowsKey
        for _,r in ipairs(lines()) do
          for pos=1,math.max(1,unicode.len(r[1])),contentW do
            contentRows[#contentRows+1]={unicode.sub(r[1],pos,pos+contentW-1),r[2]}
          end
        end
      end
      local rows=contentRows
      local room=h-14
      state.offset=math.max(0,math.min(state.offset,math.max(0,#rows-room)))
      for n=1,room do local r=rows[state.offset+n];text(2,11+n,r and r[1] or '',contentW,r and r[2] or 'text') end
      text(2,h-2,'Rows '..math.min(#rows,state.offset+1)..'-'..math.min(#rows,state.offset+room)..' / '..#rows..'   (wheel / PgUp / PgDn)',contentW,'muted')
      text(sideX,12,'WHAT WILL HAPPEN',w-sideX-1,'blue')
      local p=state.plan
      if state.section=='maker' and state.makerPlan then
        local m=state.makerPlan
        text(sideX,14,m.reused..' existing patterns reused',w-sideX-1,'green')
        text(sideX,15,#m.layout..' ordered recipe positions',w-sideX-1)
        text(sideX,16,#m.moves..' sorting moves',w-sideX-1)
        text(sideX,17,(m.required.processing+m.required.crafting)..' donors needed',w-sideX-1,'yellow')
        text(sideX,19,#m.errors..' capacity/donor blockers',w-sideX-1,#m.errors==0 and 'green' or 'red')
        text(sideX,21,'Read-only preview; no patterns moved.',w-sideX-1,'yellow')
      elseif p then
        text(sideX,14,p.scanned..' patterns scanned',w-sideX-1)
        text(sideX,15,#p.changes..' patterns to update',w-sideX-1,'green')
        text(sideX,16,p.newRecipes..' buffer patterns to consume',w-sideX-1,'yellow')
        text(sideX,17,(#p.recipes-p.newRecipes)..' existing rename recipes reused',w-sideX-1,'green')
        text(sideX,18,p.skipped..' non-processing patterns skipped',w-sideX-1,'muted')
        local y=21
        if #p.errors==0 then text(sideX,y,'Ready to apply after review.',w-sideX-1,'green')
        else
          text(sideX,y,'BLOCKED: '..#p.errors..' issue(s)',w-sideX-1,'red'); y=y+2
          for _,err in ipairs(p.errors) do
            for pos=1,unicode.len(err),w-sideX-2 do
              if y<h-5 then text(sideX,y,unicode.sub(err,pos,pos+w-sideX-3),w-sideX-1,'red'); y=y+1 end
            end
            y=y+1
          end
        end
      end
      if pending then
        text(sideX,h-6,'UNFINISHED OPERATION',w-sideX-1,'red')
        text(sideX,h-5,'Select Recover before scanning.',w-sideX-1,'yellow')
      end
    end
    text(2,h-1,state.status,w-3,state.tone)
  end
  local lastProgress=0
  local function progress(message)
    if computer.uptime()-lastProgress>=1 then
      state.status=message; state.tone='yellow'; text(2,h-1,message,w-3,'yellow'); lastProgress=computer.uptime()
    end
    -- Recharge waits are handled before component calls by gate().
  end
  local function saveConfig() validate(cfg); writeFile(paths.config,cfg) end
  local function history()
    local f=io.open('/home/assline-perf.log','r');local groups={}
    if f then
      f:seek('set',math.max(0,fs.size('/home/assline-perf.log')-16384))
      local raw=f:read('*a') or '';f:close()
      for block in raw:gmatch('uptime=[^\n]*\n.-\n\n') do groups[#groups+1]=block end
      -- Include the last report, which has no following blank line.
      if #groups==0 or raw:sub(-2)~='\n\n' then
        local last=raw:match('.*\n(uptime=.*)') or (raw:match('^uptime=') and raw)
        if last then groups[#groups+1]=last end
      end
    end
    state.history={}
    for n=#groups,1,-1 do
      for line in groups[n]:gmatch('[^\n]+') do state.history[#state.history+1]=line end
      state.history[#state.history+1]=''
    end
  end
  commitEdit=function()
    if not edit then return end
    local value=trim(edit.value)
    if edit.draft then state.draft[edit.key]=value
    else
      check(value~='','Target name cannot be empty')
      cfg[edit.key]=value; state.plan=nil; saveConfig()
    end
    edit=nil
  end
  local lastPoll=-math.huge
  local function control(delay)
    local pulled
    if delay>0 or computer.uptime()-lastPoll>=0.1 then
      draw()
      local e={event.pull(delay)}
      handle(e);lastPoll=computer.uptime();pulled=e
    end
    check(not state.cancelled,'Work cancelled. Use Recover if an operation is pending; otherwise scan again.')
    return pulled
  end
  action=function(name)
    commitEdit()
    state.error=nil
    state.history=nil
    local isWork=name=='scan' or name=='apply' or name=='recover' or name=='makerScan'
    check(not isWork or not state.busy,'Work already running')
    if isWork then state.busy=true;state.cancelled=false;lastPoll=computer.uptime();state.status='Working: '..name..' (Esc cancels)';state.tone='yellow' end
    local success,why=pcall(function()
    if name=='history' then history();state.section=name;state.offset=0
    elseif name=='changes' or name=='recipes' or name=='help' or name=='maker' then state.section=name;state.offset=0
    elseif name=='makerSettings' then state.page='maker';state.draft=clone(cfg)
    elseif name=='makerScan' then
      validate(state.draft);writeFile(paths.config,state.draft);cfg=state.draft
      state.page='main';state.section='maker';state.offset=0;state.plan=nil;state.makerPlan=nil;state.makerReport=nil
      state.makerPlan,state.makerReport=C.maker.preview(cfg,progress,control)
      state.status='Maker preview complete. Review capacity, sorting and donor requirements.';state.tone='green'
    elseif name=='scan' then
      state.plan=nil; state.offset=0; state.plan=scan(cfg,progress,control)
      state.status='Scan complete. Review Input changes and Rename recipes, then Apply preview.'; state.tone='green'
    elseif name=='apply' then
      check(state.plan,'Scan first'); local p=state.plan; state.plan=nil
      apply(cfg,p,progress,control)
      state.status='Done. Updated '..#p.changes..' patterns and installed '..p.newRecipes..' rename recipes.'; state.tone='green'
    elseif name=='recover' then
      state.plan=nil; recover(cfg,progress,control)
      state.status='Saved operation completed. Scan again to continue the rest of the batch.';state.tone='green'
    elseif name=='settings' then state.page='settings';state.draft=clone(cfg)
    elseif name=='save' then
      validate(state.draft); writeFile(paths.config,state.draft); cfg=state.draft;state.plan=nil;state.page='main'
      state.status='Settings saved. Scan to build a new preview.';state.tone='green'
    end
    end)
    if isWork then state.busy=false end
    check(success,why)
    if isWork then
      local ok,why=pcall(perfReport,name..' complete');releaseWork();check(ok,why)
      if state.section=='history' then history() end
    end
  end
  local function insert(s)
    s=s:gsub('[\r\n]',' '):gsub('%z','')
    if edit.selectAll then edit.value='';edit.cursor=1;edit.selectAll=false end
    edit.value=unicode.sub(edit.value,1,edit.cursor-1)..s..unicode.sub(edit.value,edit.cursor)
    edit.cursor=edit.cursor+unicode.len(s)
  end
  handle=function(e)
    if e[1]=='interrupted' then state.cancelled=true;state.running=false
    elseif e[1]=='touch' then
      for _,b in ipairs(buttons) do
        if e[3]>=b.x and e[3]<b.x+b.w and e[4]==b.y then
          if edit and (b.editKey~=edit.key or b.draft~=edit.draft) then commitEdit() end
          b.action(e[3],e[4]); break
        end
      end
    elseif e[1]=='scroll' and not edit then state.offset=state.offset-e[5]*3
    elseif e[1]=='clipboard' and edit then insert(e[3])
    elseif e[1]=='key_down' then
      local char,key=e[3],e[4]
      if state.busy and (key==1 or char==113) then
        state.cancelled=true;if char==113 then state.running=false end
      elseif edit then
        if key==28 then commitEdit()
        elseif key==1 then edit=nil
        elseif key==30 and keyboard.isControlDown() then edit.selectAll=true
        elseif key==203 then edit.cursor=math.max(1,edit.cursor-1);edit.selectAll=false
        elseif key==205 then edit.cursor=math.min(unicode.len(edit.value)+1,edit.cursor+1);edit.selectAll=false
        elseif key==199 then edit.cursor=1;edit.selectAll=false
        elseif key==207 then edit.cursor=unicode.len(edit.value)+1;edit.selectAll=false
        elseif key==14 or key==211 then
          if edit.selectAll then edit.value='';edit.cursor=1;edit.selectAll=false
          else
            local at=key==14 and edit.cursor-1 or edit.cursor
            if at>=1 then edit.value=unicode.sub(edit.value,1,at-1)..unicode.sub(edit.value,at+1);edit.cursor=at end
          end
        elseif char and char>=32 and not keyboard.isControlDown() then insert(unicode.char(char)) end
      elseif key==201 then state.offset=state.offset-(h-14)
      elseif key==209 then state.offset=state.offset+(h-14)
      elseif state.page=='main' then
        if char==115 and not state.busy and not fs.exists(paths.pending) then action('scan')
        elseif char==97 and state.section~='maker' and not state.busy and state.plan and #state.plan.errors==0 and #state.plan.changes>0 then action('apply')
        elseif char==113 then state.running=false end
      end
    end
  end
  local ok,err=pcall(function()
    gpu.setResolution(w,h)
    local loaded=readFile(paths.config)
    if loaded then for k in pairs(defaults) do if loaded[k]~=nil then cfg[k]=loaded[k] end end;validate(cfg) end
    while state.running do
      draw()
      local e={event.pull(1)}
      local success,why=pcall(handle,e)
      if not success then
        state.status=tostring(why);state.error=state.status;state.offset=0;state.tone='red'
        pcall(perfReport,'stopped: '..state.status);releaseWork()
        if state.section=='history' then pcall(history) end
      end
    end
  end)
  releaseWork();state.plan=nil;state.history=nil;state.draft=nil;state.makerPlan=nil;state.makerReport=nil;buttons={};paintCache={};contentRows=nil;contentKey=nil;edit=nil
  gpu.setResolution(oldW,oldH);gpu.setForeground(oldFG);gpu.setBackground(oldBG);term.clear();term.setCursor(1,1)
  if not ok then error(err,0) end
end
C.runUI=runUI
