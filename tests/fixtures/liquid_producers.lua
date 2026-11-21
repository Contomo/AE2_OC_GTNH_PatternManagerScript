-- Actual exported ABS/DTPF/Exoticizer recipes, identified by their source IDs.
-- Stocked circuits are omitted from encoded inputs, as in the live setup.
return {
  {
    key = 'magmatter',
    machine = 'Heliofusion Exoticizer',
    sourceId = 'oracle:local-2.9.0-beta-2:gregtech:gt-recipe-fog-exotic:ab41b011ce68e35e',
    inputs = {
      { type = 'item', name = 'gregtech:gt.metaitem.01', size = 1, label = 'Iron Dust', damage = 2032 },
      { type = 'fluid', name = 'molten.iron', size = 1, label = 'Molten Iron' },
      { type = 'fluid', name = 'molten.bismuth', size = 1, label = 'Molten Bismuth' },
    },
    outputs = { { type = 'fluid', name = 'molten.magmatter', size = 576, label = 'Molten Magmatter' } },
  },
  {
    key = 'superconductorumvbase',
    machine = 'DTPF',
    sourceId = 'oracle:local-2.9.0-beta-2:gregtech:gt-recipe-plasmaforge:b7ed02c0c218ea4c',
    inputs = {
      { type = 'fluid', name = 'molten.spacetime', size = 7776, label = 'Molten SpaceTime' },
      { type = 'fluid', name = 'molten.orundum', size = 3888, label = 'Molten Orundum' },
      { type = 'fluid', name = 'molten.hypogen', size = 14256, label = 'Molten Hypogen' },
      { type = 'fluid', name = 'molten.titansteel', size = 6480, label = 'Molten Titansteel' },
      { type = 'fluid', name = 'molten.dragonblood', size = 2592, label = 'Molten Dragonblood' },
      { type = 'fluid', name = 'plasma.oxygen', size = 1296, label = 'Oxygen Plasma' },
      {
        type = 'fluid',
        name = 'exciteddtec',
        size = 78424,
        label = 'Excited Dimensionally Transcendent Exotic Catalyst',
      },
    },
    outputs = {
      {
        type = 'fluid',
        name = 'dimensionallytranscendentresidue',
        size = 78424,
        label = 'Dimensionally Transcendent Residue',
      },
      {
        type = 'fluid',
        name = 'molten.superconductorumvbase',
        size = 34992,
        label = 'Molten Superconductor Base UMV',
      },
    },
  },
  {
    key = 'shirabon',
    machine = 'DTPF',
    sourceId = 'oracle:local-2.9.0-beta-2:gregtech:gt-recipe-plasmaforge:e210decaaf6b8f96',
    inputs = {
      {
        type = 'fluid',
        name = 'molten.metastable oganesson',
        size = 1152,
        label = 'Molten Metastable Oganesson',
      },
      {
        type = 'fluid',
        name = 'molten.precious metals alloy',
        size = 2304,
        label = 'Molten Precious Metals Alloy',
      },
      { type = 'fluid', name = 'molten.spacetime', size = 288, label = 'Molten SpaceTime' },
      {
        type = 'fluid',
        name = 'dimensionallytranscendentresidue',
        size = 5000,
        label = 'Dimensionally Transcendent Residue',
      },
    },
    outputs = { { type = 'fluid', name = 'molten.shirabon', size = 144, label = 'Molten Shirabon' } },
  },
  {
    key = 'octiron',
    machine = 'Alloy Blast Smelter',
    sourceId = 'oracle:local-2.9.0-beta-2:gregtech:gtpp-recipe-alloyblastsmelter:f078e6481694d77b',
    inputs = { { type = 'item', name = 'miscutils:itemDustOctiron', size = 1, label = 'Octiron Dust', damage = 0 } },
    outputs = { { type = 'fluid', name = 'molten.octiron', size = 144, label = 'Molten Octiron' } },
  },
}
