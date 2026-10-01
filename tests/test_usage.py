import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from build_usage import is_recycling, usage_index


class UsageTests(unittest.TestCase):
    def test_exact_output_form_and_recycling_routes(self):
        reverse = {
            'mod:foil': ('Cerium', 'foil'),
            'mod:plate': ('Cerium', 'plate'),
            'mod:nugget': ('Cerium', 'nugget'),
            'mod:other': ('Copper', 'plate'),
        }
        ingredient = {'id': 'mod:foil', 'kind': 'item', 'amount': 1}
        def recipe(machine, outputs):
            return {'machineType': machine, 'inputs': [ingredient], 'outputs': outputs}
        counts, useful = usage_index([
            recipe('Furnace', [{'id': 'mod:nugget', 'kind': 'item'}]),
            recipe('Macerator', [{'id': 'mod:other', 'kind': 'item'}]),
            recipe('Fluid Extractor', [{'id': 'molten.cerium', 'kind': 'fluid'}]),
            recipe('Alloy Smelter', [{'id': 'molten.cerium', 'kind': 'fluid'}]),
            recipe('Assembler', [{'id': 'mod:other', 'kind': 'item'}]),
        ], reverse)
        self.assertEqual(counts['mod:foil'], [1, 4])
        self.assertIn('mod:foil', useful)
        self.assertFalse(is_recycling(recipe('Assembler', [{'id': 'mod:other', 'kind': 'item'}]),
                                      'Cerium', reverse))

    def test_listed_alternatives_are_counted_without_duplicate_primary(self):
        reverse = {'mod:a': ('Test', 'foil'), 'mod:b': ('Test', 'foil')}
        recipe = {'machineType': 'Assembler', 'inputs': [
            {'id': 'mod:a', 'alternatives': [{'id': 'mod:a'}, {'id': 'mod:b'}]}],
            'outputs': [{'id': 'mod:product', 'kind': 'item'}]}
        counts, useful = usage_index([recipe], reverse)
        self.assertEqual(counts, {'mod:a': [1, 0], 'mod:b': [1, 0]})
        self.assertEqual(useful, {'mod:a', 'mod:b'})

    def test_form_conversion_chains_need_a_real_product(self):
        reverse = {f'mod:{form}': ('Test', form) for form in
                   ('plate', 'foil', 'plateDouble', 'plateQuintuple', 'nugget')}
        def transform(source, target):
            return {'machineType': 'Bending Machine',
                    'inputs': [{'id': f'mod:{source}', 'kind': 'item'}],
                    'outputs': [{'id': f'mod:{target}', 'kind': 'item'}]}
        recipes = [transform('plate', 'foil'), transform('foil', 'nugget'),
                   transform('plateDouble', 'plateQuintuple'),
                   transform('plateQuintuple', 'plateDouble')]
        counts, useful = usage_index(recipes, reverse)
        self.assertEqual(counts['mod:plate'], [1, 0])
        self.assertFalse(useful)  # A larger-plate cycle is not a use.
        recipes.append({'machineType': 'Assembler',
                        'inputs': [{'id': 'mod:plateQuintuple', 'kind': 'item'}],
                        'outputs': [{'id': 'mod:machine', 'kind': 'item'}]})
        _, useful = usage_index(recipes, reverse)
        self.assertEqual(useful, {'mod:plateDouble', 'mod:plateQuintuple'})

    def test_arc_furnace_ash_is_disposal_not_a_product(self):
        reverse = {'mod:quad': ('Polybenzimidazole', 'plateQuadruple'),
                   'mod:ash': ('ash', 'dustSmall')}
        recipe = {'machineType': 'Arc Furnace',
                  'inputs': [{'id': 'mod:quad', 'kind': 'item'}],
                  'outputs': [{'id': 'mod:ash', 'kind': 'item'}]}
        counts, useful = usage_index([recipe], reverse)
        self.assertEqual(counts['mod:quad'], [0, 1])
        self.assertNotIn('mod:quad', useful)

    @unittest.skipUnless(Path('.research/usage.json').exists(), 'Local usage index not installed')
    def test_local_examples_have_no_product_path(self):
        index = json.loads(Path('.research/usage.json').read_text())
        useful = set(index['useful'])
        self.assertNotIn('gregtech:gt.metaitem.01@29065', useful)
        self.assertNotIn('bartworks:gt.bwmetageneratedfoil@10098', useful)
        self.assertNotIn('bartworks:gt.bwmetageneratedplate@10098', useful)
        self.assertNotIn('gregtech:gt.metaitem.01@20599', useful)


if __name__ == '__main__':
    unittest.main()
