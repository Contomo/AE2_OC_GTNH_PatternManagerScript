-- Program definitions shared by configuration, navigation and execution.
local M={}
local function field(key,label,help,default,kind)
  return {key=key,label=label,help=help,default=default or '',kind=kind or 'text'}
end
local function choice(key,label,choices)
  local f=field(key,label,'Choose the input used for these patterns.','ingot','choice');f.choices=choices;return f
end
M.list={
  {id='assline',name='Assembly line renamer',description='Review duplicate inputs and create their rename patterns.',
    fields={field('target','Assembly line interface','Exact name of the interface containing the patterns to manage.','Advanced Assline (1)'),
      field('itemName','Renamed item template','{label} is the original item name; {n} is the duplicate number.','NAME_{n}'),
      field('renameName','Rename destination template','All interfaces matching the resulting name participate.','Rename NAME_{n}')}},
  {id='insulator',name='Wire insulator',mode='coating',description='Plan insulation patterns in material and cable-size order.',
    fields={field('destination','Insulator interface name','All interfaces with this exact name receive insulation patterns.'),
      field('pvc','Request PVC','Off means PVC must already be stocked in the machine.','on','toggle'),
      field('pps','Request PPS','Off means PPS must already be stocked in the machine.','on','toggle')}},
  {id='wiremill',name='Wiremill',mode='wiremill',description='Create 1x wire and fine-wire patterns in separate destination banks.',
    outputs={wire1='wire1',wireFine='wireFine'},
    fields={field('wire1','1x wire interface name','All matching interfaces receive recipes producing 1x wire.'),
      field('wireFine','Fine wire interface name','All matching interfaces receive recipes producing fine wire.'),
      choice('wireSource','1x wire input',{{'ingot','Ingot'},{'stick','Rod'}}),
      choice('fineSource','Fine wire input',{{'ingot','Ingot'},{'stick','Rod'},{'wire1','1x wire'}})}},
  {id='combining',name='Wire combining',unavailable='Combining recipe rules are not implemented yet.',
    description='Combine wire and cable sizes in a molecular assembler.',
    fields={field('wire','Bare wire interface name','Destination bank for combined bare-wire sizes.'),
      field('cable','Insulated cable interface name','Destination bank for combined insulated-cable sizes.')}},
  {id='bender',name='Bending machine',unavailable='Bending recipe rules are not implemented yet.',
    description='Separate destinations for plates, foil and sheet metal.',
    fields={field('plate','Plate interface name','Destination bank for plate recipes.'),
      field('foil','Foil interface name','Destination bank for foil recipes.'),
      field('sheetMetal','Sheet metal interface name','Destination bank for sheet-metal recipes.')}}
}
M.byId={}
for _,program in ipairs(M.list) do M.byId[program.id]=program end
return M
