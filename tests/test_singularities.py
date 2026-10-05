import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'source/tools'))
from build_singularities import crafting_chain, compile_routes


class SingularityScrapeTests(unittest.TestCase):
    def test_source_chain_ignores_support_items_and_rejects_duplicate_leaves(self):
        java = '''ExtremeCraftingManager.getInstance().addExtremeShapedOreRecipe(
          getModItem(EternalSingularity.ID, "combined_singularity", 1, 0),
          getModItem(Avaritia.ID, "Singularity", 1, 0),
          getModItem(ExtraUtilities.ID, "block_bedrockium", 1, 0));
        ExtremeCraftingManager.getInstance().addExtremeShapedOreRecipe(
          getModItem(EternalSingularity.ID, "eternal_singularity", 1, 0),
          getModItem(Avaritia.ID, "Resource_Block", 1, 0),
          getModItem(EternalSingularity.ID, "combined_singularity", 1, 0));'''
        resources = {'avaritia:singularity': {'displayName': 'Synthetic Singularity'}}
        groups = crafting_chain(java, resources, group_labels={0: 'Synthetic combined'})
        self.assertEqual(groups[0]['leaves'], ['avaritia:singularity'])
        java = java.replace('getModItem(ExtraUtilities.ID, "block_bedrockium", 1, 0)',
                            'getModItem(Avaritia.ID, "Singularity", 1, 0)')
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            crafting_chain(java, resources, group_labels={0: 'Synthetic combined'})

    def test_compiler_rejects_missing_native_routes_and_ignores_fluid_shortcuts_and_stocked_blackholes(self):
        def item(rid, amount=1):
            return {'id': rid, 'kind': 'item', 'amount': amount, 'displayName': rid}
        leaf, block, raw = 'minecraft:leaf', 'minecraft:block', 'minecraft:raw'
        groups = [{'label': 'Synthetic group', 'leaves': [leaf]}]
        native = {'machineType': 'Neutronium Compressor', 'inputs': [item(block, 7296)],
                  'outputs': [item(leaf)], 'eut': 480}
        compressor = {'machineType': 'Compressor', 'inputs': [item(raw, 9)],
                      'outputs': [item(block)], 'eut': 2}
        fluid = {**native, 'inputs': [{'id': 'molten.test', 'kind': 'fluid', 'amount': 9000}]}
        blackhole = {**compressor, 'inputs': [{**item('minecraft:blackhole'), 'consumed': False}]}
        registry = {'prefixes': {}, 'materials': {}, 'gtppMaterials': []}
        resources = {raw: {'kind': 'item', 'tags': ['ingotTest']}}
        result = compile_routes([native, compressor, fluid, blackhole], resources, groups, {}, registry, {})
        self.assertEqual(len(result['materials']), 1)
        self.assertEqual(result['materials'][0]['blocks'], 7296)
        self.assertEqual(result['rules'], [{'input': 9, 'output': 1, 'eut': 2}])
        with self.assertRaisesRegex(ValueError, 'ordinary'):
            compile_routes([native, blackhole], resources, groups, {}, registry, {})
        with self.assertRaisesRegex(ValueError, 'solid neutronium'):
            compile_routes([fluid, compressor], resources, groups, {}, registry, {})

    def test_deployed_chain_has_seven_groups_of_nine_and_two_shared_compressor_rules(self):
        data = json.loads((Path(__file__).resolve().parents[1] / 'source/data/singularities.json').read_text())
        self.assertEqual(len(data['materials']), 63)
        self.assertEqual(len(data['groups']), 7)
        self.assertEqual([sum(r['group'] == n for r in data['materials']) for n in range(1, 8)], [9] * 7)
        self.assertEqual({(r['input'], r['output'], r['eut']) for r in data['rules']}, {(9, 1, 2), (4, 1, 2)})
        self.assertEqual(max(r['blocks'] for r in data['materials']), 7296)
        self.assertTrue(all(r['eut'] == 480 for r in data['materials']))
        self.assertIn('Avaritia:Singularity', data['names'])
        self.assertIn('DraconicEvolution:draconicBlock', data['names'])
        self.assertIn('ProjRed|Exploration:projectred.exploration.stone', data['names'])


if __name__ == '__main__':
    unittest.main()
