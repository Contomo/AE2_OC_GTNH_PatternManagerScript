"""Synthetic import contracts plus checks against the real checked-in catalog."""
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'source' / 'tools'))
from build_plasma import compile_catalog, source_groups, MACHINE


def stack(rid, kind='fluid', label='Sample Plasma', amount=144):
    return {'id': rid, 'kind': kind, 'displayName': label, 'amount': amount}


def recipe(rid, feed, machine=MACHINE):
    return {'id': rid, 'machineType': machine, 'inputs': [feed],
            'outputs': [stack('plasma.sample')], 'eut': 100, 'specialValue': 1}


class PlasmaTests(unittest.TestCase):
    def test_paths_share_one_product_and_fusion_overlap_uses_output_identity(self):
        recipes = [recipe('dust', stack('test:dust', 'item', 'Sample Dust', 1)),
                   recipe('fluid', stack('molten.sample')), recipe('fusion', stack('other'), 'Fusion Reactor')]
        result, evidence = compile_catalog(recipes, {'sample': (1, True)}, {'test:dust': 'Test:dust'})
        self.assertEqual(len(result['materials']), 1)
        row = result['materials'][0]
        self.assertEqual((row['tier'], row['multistep'], row['fusion']), (1, True, True))
        self.assertEqual(set(row['paths']), {'dust', 'fluid'})
        self.assertEqual(len(evidence['plasma.sample']), 2)

    def test_source_metadata_is_required_and_must_agree_with_export(self):
        records = [recipe('fluid', stack('molten.sample'))]
        with self.assertRaisesRegex(ValueError, 'metadata'):
            compile_catalog(records, {}, {})
        with self.assertRaisesRegex(ValueError, 'disagree'):
            compile_catalog(records, {'sample': (2, False)}, {})

    def test_unknown_item_case_and_multiple_feeds_for_one_path_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'registry spelling'):
            compile_catalog([recipe('dust', stack('test:dust', 'item', 'Sample Dust', 1))], {'sample': (1, False)}, {})
        with self.assertRaisesRegex(ValueError, 'Multiple feeds'):
            compile_catalog([recipe('a', stack('molten.a')), recipe('b', stack('molten.b'))], {'sample': (1, False)}, {})

    def test_multistep_is_read_from_source_declarations_not_duration(self):
        java = '''FluidStack[] products = { Materials.Sample.getPlasma(144) };
        GTValues.RA.stdBuilder().fluidOutputs(products[i]).duration(7)
        .metadata(FOG_PLASMA_MULTISTEP, true).metadata(FOG_PLASMA_TIER, 1).addTo(godforgePlasmaRecipes);'''
        machine = '''getMetadataOrDefault(FOG_PLASMA_TIER, 0) > getPlasmaTier()
        getMetadataOrDefault(FOG_PLASMA_MULTISTEP, false) && !isMultiStepPlasmaCapable'''
        self.assertEqual(source_groups(java, '', machine), {'sample': (1, True)})

    def test_real_catalog_has_complete_upgrade_metadata_and_preserves_registered_case(self):
        data = json.loads(Path('source/data/plasma.json').read_text())
        self.assertEqual(len(data['materials']), 120)
        self.assertEqual(sum(m['fusion'] for m in data['materials']), 30)
        self.assertEqual(sum(len(m['paths']) for m in data['materials']), 220)
        self.assertEqual(len({tuple(m['output']) for m in data['materials']}), 120)
        self.assertIn('DraconicEvolution:draconiumDust', data['names'])
        self.assertIn('miscutils:itemDustNeptunium', data['names'])
        for row in data['materials']:
            self.assertIn(row['tier'], (0, 1, 2))
            self.assertIsInstance(row['multistep'], bool)


if __name__ == '__main__':
    unittest.main()
