import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'source' / 'tools'))
from build_transition import derive


class TransitionEvidenceTests(unittest.TestCase):
    def test_derives_extra_inputs_and_only_secondary_tiny_outputs(self):
        def item(name, amount=1):
            return {'kind': 'item', 'id': name, 'amount': amount, 'displayName': name}
        source = {'machineType': 'Implosion Compressor',
                  'inputs': [item('material', 4), item('explosive', 8)],
                  'outputs': [item('primaryTiny'), item('secondaryTiny'), item('other')]}
        electric = {'machineType': 'Electric Implosion Compressor',
                    'inputs': [item('material', 4)], 'outputs': source['outputs']}
        result = derive([source, electric], {
            'primaryTiny': {'tags': ['dustTinyTest']},
            'secondaryTiny': {'tags': ['dustTinyTest']},
            'other': {'tags': ['dustTest']},
        })
        self.assertEqual(result['explosives'], {'explosive': 'explosive'})
        self.assertEqual(result['secondary'], {'secondaryTiny': 'secondaryTiny'})
        electric['inputs'][0]['amount'] = 5
        with self.assertRaises(ValueError):
            derive([source, electric], {'secondaryTiny': {'tags': ['dustTinyTest']}})

    def test_deployed_evidence_covers_every_exported_implosion_recipe(self):
        rules = json.loads((Path(__file__).resolve().parents[1] /
                            'source/data/transition.json').read_text())
        self.assertEqual(rules['evidence']['matchedRecipes'], 1096)
        self.assertEqual(rules['evidence']['implosionRecipes'], 1096)
        self.assertEqual(len(rules['explosives']), 4)
        self.assertEqual(len(rules['secondary']), 12)
        self.assertIn('minecraft:tnt', rules['explosives'])
        self.assertIn('gregtech:gt.metaitem.01@816', rules['secondary'])


if __name__ == '__main__':
    unittest.main()
