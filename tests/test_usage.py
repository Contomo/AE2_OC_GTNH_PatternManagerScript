import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from build_usage import is_recycling, usage_counts


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
        counts = usage_counts([
            recipe('Furnace', [{'id': 'mod:nugget', 'kind': 'item'}]),
            recipe('Macerator', [{'id': 'mod:other', 'kind': 'item'}]),
            recipe('Fluid Extractor', [{'id': 'molten.cerium', 'kind': 'fluid'}]),
            recipe('Alloy Smelter', [{'id': 'molten.cerium', 'kind': 'fluid'}]),
            recipe('Assembler', [{'id': 'mod:other', 'kind': 'item'}]),
        ], reverse)
        self.assertEqual(counts['mod:foil'], [1, 4])
        self.assertFalse(is_recycling(recipe('Assembler', [{'id': 'mod:other', 'kind': 'item'}]),
                                      'Cerium', reverse))

    def test_listed_alternatives_are_counted_without_duplicate_primary(self):
        reverse = {'mod:a': ('Test', 'foil'), 'mod:b': ('Test', 'foil')}
        recipe = {'machineType': 'Assembler', 'inputs': [
            {'id': 'mod:a', 'alternatives': [{'id': 'mod:a'}, {'id': 'mod:b'}]}],
            'outputs': [{'id': 'mod:product', 'kind': 'item'}]}
        self.assertEqual(usage_counts([recipe], reverse), {'mod:a': [1, 0], 'mod:b': [1, 0]})

    @unittest.skipUnless(Path('.research/usage.json').exists(), 'Local usage index not installed')
    def test_local_examples_have_no_direct_nonrecycling_consumers(self):
        counts = json.loads(Path('.research/usage.json').read_text())['counts']
        self.assertEqual(counts['gregtech:gt.metaitem.01@29065'][0], 0)
        self.assertEqual(counts['bartworks:gt.bwmetageneratedfoil@10098'][0], 0)


if __name__ == '__main__':
    unittest.main()
