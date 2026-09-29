import gzip
import json
import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from import_catalog import import_catalog


class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'recipes.json.gz'
        self.resources = [
            {'id': 'ore:input', 'kind': 'item', 'alternatives': [{'id': 'test:input@7'}]},
            {'id': 'test:input@7', 'kind': 'item', 'nbt': {'exact': 'value'}, 'displayName': 'Input'},
            {'id': 'test:output@1', 'kind': 'item'}, {'id': 'test:unused', 'kind': 'item'},
        ]
        self.recipe = {
            'id': 'actual-1', 'machineType': 'Wiremill', 'source': {'recipeMap': 'Wiremill'},
            'inputs': [{'id': 'ore:input', 'kind': 'item', 'amount': 2, 'consumed': False,
                        'alternatives': [{'id': 'test:input@7'}], 'neiSlot': {'x': 25, 'y': 8}}],
            'outputs': [{'id': 'test:output@1', 'kind': 'item', 'amount': 4, 'chance': 0.5}],
            'runtimeCalculation': {'large': 'discarded'},
        }

    def write(self, recipes=None, version='2.9.0-beta-2'):
        with gzip.open(self.path, 'wt', encoding='utf-8') as f:
            f.write('{\n"datasetVersionId":"test-export",\n"gtnhVersion":' + json.dumps(version) + ',\n')
            for section, records in [('resources', self.resources), ('recipes', recipes or [self.recipe])]:
                f.write(json.dumps(section) + ': [\n')
                for row in records:
                    f.write(json.dumps(row) + ',\n')
                f.write('],\n')
            f.write('}\n')

    def test_preserves_actual_recipe_semantics_and_source_mismatch(self):
        self.write()
        data = import_catalog(self.path, ['Wiremill'], '2.9.0-beta-3')
        self.assertFalse(data['source']['versionMatchesTarget'])
        self.assertEqual(data['machineCounts'], {'Wiremill': 1})
        self.assertEqual(data['recipes'][0]['inputs'], self.recipe['inputs'])
        self.assertEqual(data['recipes'][0]['outputs'], self.recipe['outputs'])
        self.assertNotIn('runtimeCalculation', data['recipes'][0])
        self.assertEqual(data['resources']['test:input@7']['nbt'], {'exact': 'value'})
        self.assertNotIn('test:unused', data['resources'])
        self.assertEqual(len(data['source']['sha256']), 64)

    def test_absent_machine_does_not_manufacture_recipes(self):
        self.write()
        with self.assertRaisesRegex(ValueError, 'No actual recipes'):
            import_catalog(self.path, ['Cable Coating'], '2.9.0-beta-3')

    def test_duplicate_recipe_ids_and_missing_version_fail(self):
        self.write([self.recipe, self.recipe])
        with self.assertRaisesRegex(ValueError, 'Duplicate recipe'):
            import_catalog(self.path, ['Wiremill'], '2.9.0-beta-3')
        self.write(version='')
        with self.assertRaisesRegex(ValueError, 'version'):
            import_catalog(self.path, ['Wiremill'], '2.9.0-beta-3')


    def test_truncated_export_cannot_be_mistaken_for_complete_recipe_set(self):
        self.write()
        with gzip.open(self.path, 'rt', encoding='utf-8') as f:
            raw = f.read()
        with gzip.open(self.path, 'wt', encoding='utf-8') as f:
            f.write(raw.rsplit('}', 1)[0])
        with self.assertRaisesRegex(ValueError, 'Incomplete'):
            import_catalog(self.path, ['Wiremill'], '2.9.0-beta-3')


if __name__ == '__main__':
    unittest.main()
