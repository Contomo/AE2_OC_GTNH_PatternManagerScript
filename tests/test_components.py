import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'source/tools'))
from build_components import compile_routes, source_contract


class ComponentScrapeTests(unittest.TestCase):
    def setUp(self):
        self.data = json.loads((Path(__file__).resolve().parents[1] / 'source/data/components.json').read_text())

    def test_compact_catalog_retains_all_native_alternatives_and_shared_item_identities(self):
        data = self.data
        self.assertEqual(len(data['recipes']), 104)
        self.assertEqual(sum(1 + len(row['variants']) for row in data['recipes']), 142)
        self.assertEqual([sum(row['component'] == n for row in data['recipes']) for n in range(1, 9)], [13] * 8)
        identities = [(item['type'], data['names'][item['name'] - 1], item.get('damage')) for item in data['items']]
        self.assertEqual(len(identities), len(set(identities)))
        self.assertIn('GoodGenerator:circuitWrap', data['names'])
        self.assertIn('bartworks:gt.bwMetaGeneratedplateDense', data['names'])
        polymers = {item.get('polymer') for item in data['items']}
        self.assertTrue({'sbr', 'silicone', 'rubber'} <= polymers)
        self.assertEqual(len(data['evidence']['exports']['gt-5.09.54.133.zip']), 64)

    def test_native_casing_and_stock_assignments_are_separate_from_voltage(self):
        data = self.data
        for row in data['recipes']:
            self.assertEqual(row['yield'], 64)
            self.assertEqual(data['casings'][row['casing'] - 1], row['tier'])
            self.assertGreater(row['eut'], 0)
            if row['casing'] < 5:
                self.assertEqual(row['stock'], [])
            else:
                self.assertEqual(len(row['stock']), 1)
                index, count = row['stock'][0]
                circuit = data['items'][index - 1]
                self.assertEqual(circuit['damage'], data['components'][row['component'] - 1]['circuit'])
                self.assertEqual(data['names'][circuit['name'] - 1], 'gregtech:gt.integrated_circuit')
                self.assertEqual(count, 1)
            for index, amount in row['inputs']:
                self.assertGreater(amount, 0)
                self.assertNotEqual(data['names'][data['items'][index - 1]['name'] - 1], 'gregtech:gt.integrated_circuit')
            original = dict(row['inputs'])
            for variant in row['variants']:
                modified = original.copy()
                for index in variant['remove']:
                    self.assertIn(index, modified)
                    modified.pop(index)
                modified.update(variant['set'])
                self.assertNotEqual(modified, original)
                self.assertTrue(modified)
                self.assertTrue(all(amount > 0 for amount in modified.values()))

    def test_scraper_rejects_casing_and_circuit_disagreement_instead_of_guessing_from_labels(self):
        # A small source contract fixture exercises failure handling. The native
        # deployed catalog above is separately checked against scraped contracts.
        java = 'private int COAL_LV = 1, COAL_IV = 5;\n'
        for n, prefix in enumerate(('Electric_Motor', 'Electric_Piston', 'Electric_Pump', 'Robot_Arm',
                                    'Conveyor_Module', 'Emitter', 'Sensor', 'Field_Generator'), 1):
            key = ('MOTOR', 'PISTON', 'PUMP', 'ROBOT_ARM', 'CONVEYOR', 'EMITTER', 'SENSOR', 'FIELD_GENERATOR')[n - 1]
            java += f'int {key}_CIRCUIT = {n};\nGTValues.RA.stdBuilder().itemOutputs({prefix}_IV.get(64))'
            java += f'.circuit({key}_CIRCUIT).metadata(COAL_CASING_TIER, COAL_IV).addTo(componentAssemblyLineRecipes);\n'
        groups, outputs, casings = source_contract(java)
        self.assertEqual(len(groups), 8)
        self.assertEqual(outputs['Electric_Motor_IV']['casing'], 5)
        stack = {'kind': 'item', 'id': 'gregtech:gt.metaitem.01@32005', 'amount': 64,
                 'displayName': 'Electric Motor (IV)'}
        route = {'machineType': 'Component Assembly Line', 'id': 'test', 'specialValue': 4, 'eut': 1920,
                 'outputs': [stack], 'inputs': [{**stack, 'amount': 1}]}
        with self.assertRaisesRegex(ValueError, 'casing/output'):
            compile_routes([route], java, {})
        route['specialValue'] = 5
        with self.assertRaisesRegex(ValueError, 'stocked circuit'):
            compile_routes([route], java, {})


if __name__ == '__main__':
    unittest.main()
