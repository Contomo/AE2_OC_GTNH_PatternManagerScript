package.path='tests/lib/?.lua;'..package.path
local M=require('assline_modes')
local P=require('assline_planner')
local U=require('assline_util')
local data=require('assline_data')
local tests=0
local function test(name,f) f();tests=tests+1;print('PASS '..name) end
local function has(list,name,damage)
  for _,s in ipairs(list) do if s.name==name and s.damage==damage then return true end end
end
test('real matrix resolves suffixes, wire bases and independent eligibility',function()
  local wires=M.compile(data,'wiremill')
  local nbti,chrome=false,false
  for _,r in ipairs(wires.recipes) do
    if has(r.outputs,'gregtech:gt.blockmachines',1725) then nbti=true end
    if r.label:match('^Chrome /') then
      assert(has(r.outputs,'gregtech:gt.metaitem.02',19030))
      for _,s in ipairs(r.outputs) do assert(s.name~='gregtech:gt.blockmachines') end
      chrome=true
    end
  end
  assert(nbti and chrome)
  assert(wires.source.recipeVersion=='2.9.0-beta-2' and wires.source.targetVersion=='2.9.0-beta-3')
end)
test('PVC and PPS switches omit only their consumed solids and retain external requirements',function()
  local fixture={version=2,source=data.source,families={},production={},capabilities={{wire1=true,cable1=true}},items={
    {name='gregtech:pvc',damage=1,option='pvc'},{name='gregtech:pps',damage=2,option='pps'}},
    materials={{name='Test',a=1,conductor={name='gregtech:gt.blockmachines',base=1720},coating='pps'}},
    rules={{id='coat',mode='coating',coating='pps',requires={'wire1','cable1'},
      inputs={{f='wire1',n=1},{i=1,n=2},{i=2,n=3}},outputs={{f='cable1',n=1}},stock={{fluid='rubber',n=144}}}}}
  for _,pvc in ipairs({true,false}) do for _,pps in ipairs({true,false}) do
    local r=M.compile(fixture,'coating',{pvc=pvc,pps=pps}).recipes[1]
    assert(#r.inputs==1+(pvc and 1 or 0)+(pps and 1 or 0))
    assert(#r.stock==1+(pvc and 0 or 1)+(pps and 0 or 1))
    assert(r.inputs[1].damage==1720 and r.outputs[1].damage==1726)
  end end
end)

test('registration alone does not grant a production route',function()
  local fixture={version=2,source=data.source,families={gt={ingot={name='gregtech:gt.metaitem.01',prefix=11000}}},items={},
    capabilities={{ingot=true,wire1=true}},production={{ingot_wire=true}},
    materials={{name='Allowed',family='gt',a=1,p=1,dsf=30,conductor={name='gregtech:gt.blockmachines',base=1300}},
      {name='Unavailable',family='gt',a=1,dsf=360,conductor={name='gregtech:gt.blockmachines',base=1720}}},
    rules={{id='ingot.wire1',mode='wiremill',process='ingot_wire',requires={'ingot','wire1'},inputs={{f='ingot',n=1}},outputs={{f='wire1',n=2}},stock={}}}}
  local r=M.compile(fixture,'wiremill').recipes
  assert(#r==1 and r[1].inputs[1].damage==11030)
  assert(not pcall(M.compile,fixture,'coating'))
  fixture.materials[1].deny={['ingot.wire1']=true}
  assert(not pcall(M.compile,fixture,'wiremill'))
end)

test('shared form resolver handles scraped external IDs and BW without duplicating recipes',function()
  local rows={};for _,m in ipairs(data.materials) do rows[m.name]=m end
  local fixture={capabilities={{ingot=true}},families={gt={ingot={name='gregtech:gt.metaitem.01',prefix=11000}}}}
  local arbitrary={name='Quorlium',family='gt',dsf=30,a=1,
    overrides={ingot={name='unseenpack:component',damage=71}}}
  assert(M.resolve(fixture,arbitrary,'ingot').name=='unseenpack:component')
  assert(M.resolve(fixture,arbitrary,'ingot').damage==71)
  local chrome=M.resolve(data,rows.Chrome,'rotor')
  assert(chrome.name=='gregtech:gt.metaitem.02' and chrome.damage==21030)
  assert(M.resolve(data,rows.Chrome,'gear').damage==31030)
  local found=false
  for _,m in ipairs(data.materials) do
    if M.supports(data,m,'boltedCasing') then
      assert(M.resolve(data,m,'boltedCasing').name=='bartworks:bw.werkstoffblockscasing.01');found=true
    end
  end
  assert(found)
end)

test('equivalent externally stocked variants produce one processing pattern',function()
  local wires=M.compile(data,'coating',{pvc=false,pps=false})
  local seen={}
  for _,r in ipairs(wires.recipes) do
    local key=P.recipeKey(r);assert(not seen[key]);seen[key]=true
    assert(r.destination==nil and r.kind=='processing')
    for _,s in ipairs(r.inputs) do
      assert(s.type=='item' and s.name~='gregtech:gt.integrated_circuit')
      assert(not (s.name=='gregtech:gt.metaitem.01' and (s.damage==1649 or s.damage==2649 or s.damage==29631)))
    end
  end
end)
test('wire recipes remain in numeric size order within each material',function()
  for _,mode in ipairs({'wiremill','coating'}) do
    local manifest=M.compile(data,mode)
    local last={}
    for _,r in ipairs(manifest.recipes) do
      local material,size=r.label:match('^(.-) / (%d+)x ')
      if size then size=tonumber(size);assert(not last[material] or size>=last[material]);last[material]=size end
    end
  end
end)
test('unavailable forms fail visibly before resolving metadata',function()
  local d=U.clone(data)
  d.capabilities={{ingot=true}}
  local m={a=1,family='gt',dsf=30}
  assert(not pcall(M.resolve,d,m,'wire16'))
end)
test('insulation has exactly one pattern per material and size for every PVC/PPS setting',function()
  for _,pvc in ipairs({true,false}) do for _,pps in ipairs({true,false}) do
    local result=M.compile(data,'coating',{pvc=pvc,pps=pps});local outputs={}
    assert(#result.recipes==306 and #result.unresolved==0)
    for _,r in ipairs(result.recipes) do
      assert(r.outputs[1].size==1 and r.inputs[1].size==1)
      local key=r.outputs[1].name..':'..r.outputs[1].damage
      assert(not outputs[key]);outputs[key]=true
      for _,s in ipairs(r.inputs) do
        assert(s.label and s.damage~=1633 and s.damage~=2633)
        if not pvc then assert(s.damage~=1649 and s.damage~=2649) end
        if not pps then assert(s.damage~=29631) end
      end
    end
  end end
end)

test('wiremill input selection excludes alternative routes and uses recovered registry case',function()
  for _,source in ipairs({'ingot','stick','wire1'}) do
    local result=M.compile(data,'wiremill',{forms={wire1=true,wireFine=true},sources={wire1='ingot',wireFine=source}})
    assert(#result.unresolved==0)
    local outputs={}
    for _,r in ipairs(result.recipes) do
      local key=r.outputs[1].name..':'..r.outputs[1].damage
      assert(not outputs[key]);outputs[key]=true
      assert(r.label:find('from '..(r.outputForm=='wire1' and 'Ingot' or ({ingot='Ingot',stick='Rod',wire1='wire1'})[source]),1,true))
    end
    if source=='ingot' then assert(#result.recipes==294) end
  end
end)

test('all five polymer choices use scraped batch sizes and retain one pattern per cable size',function()
  local ids={pvc=2649,pvcSmall=1649,pdms=2633,pdmsSmall=1633}
  for _,polymer in ipairs({'pvc','pvcSmall','pdms','pdmsSmall','none'}) do for _,pps in ipairs({true,false}) do
    local manifest=M.compile(data,'coating',{polymer=polymer,pps=pps});local seen={}
    assert(#manifest.recipes==306 and #manifest.unresolved==0)
    local batch=(polymer=='pvc' or polymer=='pdms') and 4 or 1
    local annealed=false
    for _,r in ipairs(manifest.recipes) do
      assert(r.inputs[1].size==batch and r.outputs[1].size==batch)
      local id=r.outputs[1].name..':'..r.outputs[1].damage;assert(not seen[id]);seen[id]=true
      local polymerCount=0
      for _,item in ipairs(r.inputs) do
        if item.name=='gregtech:gt.metaitem.01' then
          if item.damage==29631 then assert(pps)
          else assert(item.damage==ids[polymer]);polymerCount=polymerCount+1 end
        end
      end
      assert(polymerCount==(polymer=='none' and 0 or 1))
      if r.material=='AnnealedCopper' and r.outputForm=='cable1' then
        annealed=true
        if polymer=='pvc' then assert(r.inputs[2].damage==2649 and r.inputs[2].size==1 and r.outputs[1].size==4) end
      end
    end
    assert(annealed)
  end end
end)

test('multipliers scale every encoded ingredient without changing recipe eligibility or proportions',function()
  for _,mode in ipairs({'wiremill','coating'}) do
    local options={polymer='pvc',multiplier=1,sources=mode=='wiremill' and {wire1='ingot',wireFine='ingot'} or nil}
    local base=M.compile(data,mode,options);options.multiplier=256
    local scaled=M.compile(data,mode,options)
    assert(#base.recipes==#scaled.recipes and scaled.policy.multiplier==256)
    for n,r in ipairs(base.recipes) do
      assert(P.recipeKey(r)==P.recipeKey(scaled.recipes[n]))
      for _,which in ipairs({'inputs','outputs'}) do
        for index,s in ipairs(r[which]) do assert(scaled.recipes[n][which][index].size==s.size*256) end
      end
    end
  end
  for _,value in ipairs({0,-1,1.5,2147483647}) do
    local ok=pcall(M.compile,data,'coating',{polymer='pvc',multiplier=value})
    assert(not ok,'invalid/overflowing multiplier accepted')
  end
end)

print('SUCCESS: '..tests..' tests (material/rule compiler)')
