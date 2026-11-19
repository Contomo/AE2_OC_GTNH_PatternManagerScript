"""Conversion contracts plus assertions against the checked-in real scrape.

The small Sample fixtures are deliberately invented; real GTNH evidence is
checked separately, including the pinned Java conversion contract.
"""
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'source' / 'tools'))
from build_melting_core import compile_catalog, source_contract


def item(rid, n=1, **extra):
    return {'id': rid, 'kind': 'item', 'amount': n, 'displayName': rid, **extra}


def fluid(rid, n=144):
    return {'id': rid, 'kind': 'fluid', 'amount': n, 'displayName': rid}


def recipe(rid, machine, inputs, outputs, **extra):
    return {'id': rid, 'machineType': machine, 'inputs': inputs, 'outputs': outputs,
            'eut': 120, 'specialValue': 3600, 'durationTicks': 200, **extra}


class MeltingCoreTests(unittest.TestCase):
    def setUp(self):
        prefixes = ['null'] * 18
        prefixes[2], prefixes[11], prefixes[12], prefixes[17] = 'dust', 'ingot', 'ingotHot', 'plate'
        self.registry = {'materials': {'30': 'Sample'}, 'prefixes': {'gregtech:gt.metaitem.01': prefixes}}
        self.dust = item('gregtech:gt.metaitem.01@2030')
        self.ingot = item('gregtech:gt.metaitem.01@11030')
        self.hot = item('gregtech:gt.metaitem.01@12030')
        self.mold = item('gregtech:gt.metaitem.01@32306', consumed=False)
        self.circuit = item('gregtech:gt.integrated_circuit@1', consumed=False)
        self.cast = recipe('cast', 'Fluid Solidifier', [fluid('molten.sample'), self.mold], [self.ingot])
        self.dry = recipe('dry', 'Blast Furnace', [self.dust, self.circuit], [self.hot])
        self.resources = {s['id']: s for s in (self.dust, self.ingot, self.hot, self.mold,
                                             self.circuit, fluid('molten.sample'), fluid('nitrogen', 100))}
        self.units = {'fluidPerIngot': 144, 'forms': {'dust': 1, 'ingot': 1, 'ingotHot': 1, 'plate': 1}}

    def compile(self, recipes):
        return compile_catalog(recipes, self.resources, self.registry, {}, self.units,
                               {'sample': {'tier': 'EV'}}, {})

    def test_hot_ingot_conversion_copies_amount_heat_voltage_and_stocked_circuit(self):
        hot = {**self.hot, 'amount': 3}
        result, evidence = self.compile([self.cast, {**self.dry, 'outputs': [hot]}])
        row = result['materials'][0]
        route = row['routes'][0]
        self.assertEqual((row['tier'], route['circuit'], route['heat'], route['eut']), ('EV', 1, 3600, 120))
        self.assertEqual(result['products'][route['output'] - 1][0][1], 432)
        self.assertEqual(len(result['feeds'][route['feed'] - 1]), 1)
        self.assertEqual(len(evidence['derivedRecipes']), 1)
        self.assertEqual(result['items'][result['ingotMold'] - 1]['damage'], 32306)

    def test_optional_gas_variants_share_the_dust_feed_but_required_fluids_remain(self):
        gas = recipe('gas', 'Blast Furnace', [self.dust, item('gregtech:gt.integrated_circuit@11', consumed=False),
                                             fluid('nitrogen', 100)], [self.hot], durationTicks=100)
        mandatory = recipe('reaction', 'Blast Furnace', [dict(self.dust, amount=2), fluid('nitrogen', 600)],
                           [dict(self.hot, amount=2)])
        result, _ = self.compile([self.cast, self.dry, gas, mandatory])
        routes = result['materials'][0]['routes']
        assisted = next(r for r in routes if r['gas'])
        dry = next(r for r in routes if r['circuit'] == 1)
        required = next(r for r in routes if r['circuit'] == 0)
        self.assertEqual(assisted['feed'], dry['feed'])
        self.assertEqual(assisted['gasAmount'], 100)
        self.assertEqual(required['gas'], 0)
        self.assertEqual(len(result['feeds'][required['feed'] - 1]), 2)

    def test_repeated_extraction_amounts_become_one_semantic_rule(self):
        extract = recipe('extract', 'Fluid Extractor', [self.ingot], [fluid('molten.sample')])
        scaled = recipe('scaled', 'Fluid Extractor', [dict(self.ingot, amount=32)], [fluid('molten.sample', 4608)])
        result, _ = self.compile([self.cast, self.dry, extract, scaled])
        self.assertEqual(len(result['extraction']['rules']), 1)
        self.assertEqual(result['extraction']['rules'][0], {
            'kind': 'meta', 'name': 'gregtech:gt.metaitem.01', 'prefix': 11000, 'n': 1, 'amount': 144})
        self.assertEqual(result['extraction']['sets'], [[1]])

    def test_godforge_converts_chance_molten_outputs_but_does_not_promise_chance_solid_outputs(self):
        converted = {**self.dry, 'outputs': [dict(self.hot, chance=0.5)]}
        result, _ = self.compile([self.cast, converted])
        self.assertEqual(len(result['materials'][0]['routes']), 1)
        solid = item('test:unmeltable', chance=0.5)
        result, evidence = self.compile([self.cast, {**self.dry, 'outputs': [self.hot, solid]}])
        self.assertFalse(result['materials'][0]['routes'])
        self.assertEqual(evidence['rejected'][0]['reason'], 'Probabilistic solid coproduct')

    def test_checked_in_catalog_retains_real_quantum_hypogen_and_tungsten_evidence(self):
        result = json.loads(Path('source/data/melting_core.json').read_text())
        materials = {m['key']: m for m in result['materials']}
        self.assertEqual(materials['quantum']['nativeMachine'], 'DTPF')
        self.assertEqual(materials['hypogen']['nativeMachine'], 'Fusion Reactor')
        self.assertTrue(materials['tungsten']['routes'])
        self.assertEqual(len(result['materials']), 342)
        self.assertEqual(sum(len(m['routes']) for m in result['materials']), 937)
        self.assertLess(len(result['extraction']['rules']), 100)
        self.assertLess(Path('source/data/melting_core.json').stat().st_size, 800000)
        self.assertNotIn('extractors', result)
        if Path('.research/gt-5.09.54.133.zip').exists():
            self.assertEqual(source_contract('.research/gt-5.09.54.133.zip'), result['source']['godforgeSha256'])


if __name__ == '__main__':
    unittest.main()
