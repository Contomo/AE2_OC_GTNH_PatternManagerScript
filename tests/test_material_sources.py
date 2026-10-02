import gzip
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'source' / 'tools'))
from build_material_sources import build, source_index
from compile_matrix import compile_matrix


def item(rid, **extra):
    return {'kind': 'item', 'id': rid, 'amount': 1, **extra}


def fluid(rid):
    return {'kind': 'fluid', 'id': rid, 'amount': 144}


def recipe(name, machine, inputs, outputs):
    return {'id': name, 'machineType': machine, 'inputs': inputs, 'outputs': outputs}


class MaterialSourceTests(unittest.TestCase):
    def setUp(self):
        # Invented identifiers test contracts; real scrape cases are below.
        self.reverse = {'test:dust': ('sample', 'dust'), 'test:ingot': ('sample', 'ingot'),
                        'test:hot': ('sample', 'ingotHot'), 'test:plate': ('sample', 'plate'),
                        'test:cell': ('sample', 'cellMolten')}
        self.fluids = {'molten.sample': {'sample'}, 'plasma.sample': {'sample'}}

    def index(self, recipes):
        return source_index(iter(recipes), self.reverse, self.fluids)['sample']

    def test_ebf_ingots_and_extraction_do_not_establish_native_molten(self):
        row = self.index([
            recipe('ebf', 'Blast Furnace', [item('test:dust')], [item('test:hot')]),
            recipe('cool', 'Vacuum Freezer', [item('test:hot')], [item('test:ingot')]),
            recipe('melt', 'Fluid Extractor', [item('test:ingot')], [fluid('molten.sample')]),
        ])
        self.assertEqual(row['solid']['count'], 1)
        self.assertEqual(row['solid']['example']['recipe'], 'ebf')
        self.assertFalse(row['fluids']['molten.sample']['native'])

    def test_alloy_dust_in_abs_is_creation_even_when_material_identity_is_unchanged(self):
        row = self.index([recipe('abs', 'Alloy Blast Smelter',
                                 [item('test:dust')], [fluid('molten.sample')])])
        self.assertTrue(row['fluids']['molten.sample']['native'])
        self.assertEqual(row['fluids']['molten.sample']['example']['recipe'], 'abs')
        self.assertEqual(row['solid']['count'], 0)

    def test_remelting_parts_and_uncanning_never_count_as_native_fluid(self):
        row = self.index([
            recipe('extract-scrap', 'Fluid Extractor', [item('test:machine')], [fluid('molten.sample')]),
            recipe('remelt', 'Alloy Blast Smelter', [item('test:plate')], [fluid('molten.sample')]),
            recipe('uncan', 'Canner', [item('test:cell')], [fluid('molten.sample')]),
            recipe('tank', 'Tank', [item('test:cell')], [fluid('molten.sample')]),
            recipe('other-container', 'Other', [item('test:cell')], [fluid('molten.sample')]),
            recipe('upgrade-display', 'Godforge Upgrades', [], [fluid('molten.sample')]),
        ])
        found = row['fluids']['molten.sample']
        self.assertFalse(found['native'])
        self.assertEqual(sum(found['rejected'].values()), 6)

    def test_recycling_solids_and_casting_do_not_establish_direct_ingot_production(self):
        row = self.index([
            recipe('cast', 'Fluid Solidifier', [fluid('molten.sample')], [item('test:ingot')]),
            recipe('smelt-plate', 'Furnace', [item('test:plate')], [item('test:ingot')]),
            recipe('salvage', 'Arc Furnace', [item('test:machine')], [item('test:ingot')]),
        ])
        self.assertEqual(row['solid']['count'], 0)

    def test_plasma_cooling_needs_an_independent_source_and_closed_cycles_cannot_seed_it(self):
        cycle = [
            recipe('heat', 'Heater', [fluid('molten.sample')], [fluid('plasma.sample')]),
            recipe('cool', 'Vacuum Freezer', [fluid('plasma.sample')], [fluid('molten.sample')]),
        ]
        row = self.index(cycle)
        self.assertFalse(any(f['native'] for f in row['fluids'].values()))
        row = self.index(cycle + [recipe('fusion', 'Fusion Reactor',
                                        [fluid('other-a'), fluid('other-b')], [fluid('plasma.sample')])])
        self.assertTrue(all(f['native'] for f in row['fluids'].values()))
        self.assertEqual(row['fluids']['molten.sample']['example']['requiresNativeFluids'], ['plasma.sample'])
        self.assertEqual(row['fluids']['plasma.sample']['example']['recipe'], 'fusion')

    def test_stocked_parts_do_not_block_creation_but_consumed_alternatives_are_checked(self):
        row = self.index([recipe('abs', 'Alloy Blast Smelter',
                                 [item('test:dust'), item('test:ingot', consumed=False)],
                                 [fluid('molten.sample')])])
        self.assertTrue(row['fluids']['molten.sample']['native'])
        row = self.index([recipe('ambiguous', 'Other',
                                 [item('test:unknown', alternatives=[item('test:ingot')])],
                                 [fluid('molten.sample')])])
        self.assertFalse(row['fluids']['molten.sample']['native'])

    def test_unobserved_fluid_is_unknown_not_a_native_source(self):
        row = self.index([])
        self.assertFalse(row['fluids']['molten.sample']['native'])
        self.assertEqual(row['fluids']['molten.sample']['count'], 0)

    def test_streamed_export_and_compiler_share_verified_source_flags(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            prefixes = ['null'] * 18
            prefixes[2], prefixes[11], prefixes[17] = 'dust', 'ingot', 'plate'
            registry = {'materials': {'30': 'Sample'}, 'prefixes': {'gregtech:gt.metaitem.01': prefixes}}
            resources = [item(f'gregtech:gt.metaitem.01@{prefix+30}') for prefix in (2000, 11000, 17000)]
            resources += [fluid('different-fluid-id')]
            cast = recipe('cast', 'Fluid Solidifier', [fluid('different-fluid-id'),
                           item('gregtech:gt.metaitem.01@32306', consumed=False)], [resources[1]])
            catalog = {'source': {'datasetId': 'fixture'}, 'recipes': [cast], 'resources': {}}
            recipes = [cast, recipe('abs', 'Alloy Blast Smelter', [resources[0]], [fluid('different-fluid-id')])]
            export = root / 'recipes.json.gz'
            with gzip.open(export, 'wt') as stream:
                stream.write('{\n"datasetVersionId":"fixture",\n"resources":[\n')
                stream.write(',\n'.join(json.dumps(r) for r in resources))
                stream.write('\n],\n"recipes":[\n')
                stream.write(',\n'.join(json.dumps(r) for r in recipes))
                stream.write('\n]\n}\n')
            for name, content in [('resources.json.gz', {'resources': resources}),
                                  ('ores.json.gz', {'resources': {}})]:
                with gzip.open(root / name, 'wt') as stream:
                    json.dump(content, stream)
            catalog['source']['sha256'] = hashlib.sha256(export.read_bytes()).hexdigest()
            evidence = build(export, catalog, registry, root / 'resources.json.gz', root / 'ores.json.gz')
            self.assertEqual(evidence['recipeCount'], 2)
            self.assertTrue(evidence['materials']['sample']['fluids']['different-fluid-id']['native'])
            matrix = compile_matrix(catalog, registry, resources={r['id']: r for r in resources},
                                    material_sources=evidence)
            flags = matrix['origins'][matrix['materials'][0]['o'] - 1]
            self.assertTrue(flags['native_molten'])
            self.assertNotIn('native_ingot', flags)
            evidence['materials']['sample']['solid']['count'] = 1
            both = compile_matrix(catalog, registry, resources={r['id']: r for r in resources},
                                  material_sources=evidence)
            both_flags = both['origins'][both['materials'][0]['o'] - 1]
            self.assertTrue(both_flags['native_ingot'] and both_flags['native_molten'])
            self.assertEqual(matrix['rules'], both['rules'])
            self.assertEqual(matrix['capabilities'], both['capabilities'])
            self.assertEqual(matrix['production'], both['production'])
            self.assertNotIn('example', both['materials'][0])
            for field, message in [('policy', 'Unsupported'), ('datasetVersionId', 'different datasets'),
                                   ('recipeExportSha256', 'different exports')]:
                with self.assertRaisesRegex(ValueError, message):
                    compile_matrix(catalog, registry, material_sources={**evidence, field: 'wrong'})
            with self.assertRaisesRegex(ValueError, 'different recipe exports'):
                build(export, {**catalog, 'source': {**catalog['source'], 'sha256': 'wrong'}}, registry,
                      root / 'resources.json.gz', root / 'ores.json.gz')

    def test_tracked_scrape_confirms_vanadium_gallium_vs_abs_alloys(self):
        evidence = json.loads(Path('data/material-sources.json').read_text())
        self.assertEqual(evidence['recipeCount'], 276677)
        vg = evidence['materials']['vanadiumgallium']
        self.assertGreater(vg['solid']['count'], 0)
        self.assertFalse(vg['fluids']['molten.vanadiumgallium']['native'])
        self.assertEqual(vg['fluids']['molten.vanadiumgallium']['count'],
                         vg['fluids']['molten.vanadiumgallium']['rejected']['recovery or container transport'])
        for name in ('abyssalalloy', 'stainlesssteel'):
            native = evidence['materials'][name]['fluids']['molten.' + name]
            self.assertTrue(native['native'])
            self.assertEqual(native['example']['machine'], 'Alloy Blast Smelter')


if __name__ == '__main__':
    unittest.main()
