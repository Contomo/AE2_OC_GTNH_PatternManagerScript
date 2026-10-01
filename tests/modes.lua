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
      chrome=true
    end
  end
  assert(nbti and not chrome) -- Chrome wiremill outputs have no non-recycling consumers.
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
    assert(#result.recipes==183 and #result.unresolved==0)
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
      assert(r.label:find('from '..(r.outputForm=='wire1' and 'Ingot' or ({ingot='Ingot',stick='Rod',wire1='1x wire'})[source]),1,true))
    end
    if source=='ingot' then assert(#result.recipes>0 and #result.recipes<294) end
  end
end)

test('all five polymer choices use scraped batch sizes and retain one pattern per cable size',function()
  local ids={pvc=2649,pvcSmall=1649,pdms=2633,pdmsSmall=1633}
  for _,polymer in ipairs({'pvc','pvcSmall','pdms','pdmsSmall','none'}) do for _,pps in ipairs({true,false}) do
    local manifest=M.compile(data,'coating',{polymer=polymer,pps=pps});local seen={}
    assert(#manifest.recipes==183 and #manifest.unresolved==0)
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
test('Mu-metal plate is selected from scraped bender and use evidence',function()
  local manifest=M.compile(data,'bender',{
    forms={plate=true,foil=true},sources={plate='ingot',foil='plate'}})
  local found=false
  for _,r in ipairs(manifest.recipes) do
    if r.material=='Mu-metal' and r.outputForm=='plate' then
      assert(r.outputs[1].name==data.registryNames['bartworks:gt.bwmetageneratedplate'])
      assert(r.outputs[1].damage==11351)
      found=true
    end
  end
  assert(found)
  for _,r in ipairs(manifest.skipped) do
    assert(not (r.material=='Mu-metal' and r.form=='plate'))
  end
end)

test('bender compiles only scraped ingot routes, with source circuit selectors stocked',function()
  local forms={'plate','plateDouble','plateTriple','plateQuadruple','plateQuintuple','plateDense','foil'}
  local expected={plate={1,1,1},plateDouble={2,1,2},plateTriple={3,1,3},
    plateQuadruple={4,1,4},plateQuintuple={5,1,5},plateDense={9,1,9},foil={1,4,10}}
  local enabled={};for _,form in ipairs(forms) do enabled[form]=true end
  local sources={plate='ingot',plateDouble='ingot',plateTriple='ingot',
    plateQuadruple='ingot',plateQuintuple='ingot',plateDense='ingot',foil='ingot'}
  local manifest=M.compile(data,'bender',{forms=enabled,sources=sources,multiplier=1})
  local counts={};local seen={}
  for _,r in ipairs(manifest.recipes) do
    local form=r.outputForm;local tuple=assert(expected[form]);counts[form]=(counts[form] or 0)+1
    assert(not (r.material=='Polybenzimidazole' and form=='plateQuadruple'))
    assert(#r.inputs==1 and r.inputs[1].size==tuple[1] and r.outputs[1].size==tuple[2])
    assert(#r.stock==1 and r.stock[1].name=='gregtech:gt.integrated_circuit')
    assert(r.stock[1].damage==tuple[3] and r.stock[1].size==1)
    assert(r.inputs[1].name~='gregtech:gt.integrated_circuit')
    local identity=r.material..':'..form;assert(not seen[identity]);seen[identity]=true
  end
  assert(#manifest.unresolved==0 and #manifest.recipes>500,'unresolved='..#manifest.unresolved..' recipes='..#manifest.recipes..' first='..tostring(manifest.unresolved[1] and manifest.unresolved[1].reason or manifest.unresolved[1]))
  for _,form in ipairs(forms) do assert(counts[form]>0) end
  local onlyFoil=M.compile(data,'bender',{forms={foil=true},sources={foil='ingot'}})
  assert(#onlyFoil.recipes==counts.foil)
  assert(onlyFoil.unusedExcluded>0)
  for _,r in ipairs(onlyFoil.recipes) do
    assert(r.outputForm=='foil' and r.material~='Cerium' and r.material~='LithiumChloride')
  end
  local noSingles=M.compile(data,'bender',{forms={plateDouble=true},sources={plateDouble='ingot'}})
  assert(#noSingles.recipes==counts.plateDouble)
  local singles=M.compile(data,'bender',{forms={plate=true},sources={plate='ingot'}})
  for _,r in ipairs(singles.recipes) do assert(r.material~='LithiumChloride') end
end)

test('plate-fed bender routes, sheet metal and both spring inputs use source circuits',function()
  local forms={plateDouble=true,plateDense=true,foil=true,sheetmetal=true,springSmall=true,spring=true}
  local sources={plateDouble='plate',plateDense='plate',foil='plate',sheetmetal='plate',
    springSmall='stick',spring='stickLong'}
  local manifest=M.compile(data,'bender',{forms=forms,sources=sources})
  local counts={}
  local circuits={plateDouble=2,plateDense=9,foil=1,sheetmetal=11,springSmall=1,spring=1}
  local copperDense=false
  for _,r in ipairs(manifest.recipes) do
    counts[r.outputForm]=(counts[r.outputForm] or 0)+1
    assert(#r.inputs==1 and r.stock[1].name=='gregtech:gt.integrated_circuit')
    assert(r.stock[1].damage==circuits[r.outputForm])
    if r.material=='Copper' and r.outputForm=='plateDense' then
      assert(r.outputs[1].name=='gregtech:gt.metaitem.01' and r.outputs[1].damage==22035)
      copperDense=true
    end
    assert(r.inputs[1].label:lower():find(sources[r.outputForm]:lower(),1,true)
      or r.outputForm=='springSmall' and r.inputs[1].label:find('Rod',1,true)
      or r.outputForm=='spring' and r.inputs[1].label:find('Long rod',1,true))
  end
  assert(#manifest.unresolved==0 and copperDense,table.concat(manifest.unresolved,','))
  for form in pairs(forms) do assert(counts[form]>0,form..' missing') end
  local wire=M.compile(data,'bender',{forms={springSmall=true},sources={springSmall='wire1'}})
  assert(#wire.recipes>0 and #wire.unresolved==0)
  for _,r in ipairs(wire.recipes) do
    assert(r.outputForm=='springSmall' and r.inputs[1].label:find('Wire',1,true))
  end
end)

print('SUCCESS: '..tests..' tests (material/rule compiler)')
