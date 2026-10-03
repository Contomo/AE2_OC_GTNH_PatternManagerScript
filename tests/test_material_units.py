from pathlib import Path
import json
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'source' / 'tools'))
from import_material_units import amount, extract


class MaterialUnitTests(unittest.TestCase):
    def test_imports_arithmetic_and_maps_conductor_names(self):
        prefixes = '''
        public static final OrePrefixes ingot = new OrePrefixBuilder("ingot")
            .materialAmount(M * 1)
            .build();
        public static final OrePrefixes wireGt16 = new OrePrefixBuilder("wireGt16")
            .materialAmount(M * 8)
            .build();
        public static final OrePrefixes rotor = new OrePrefixBuilder("rotor")
            .materialAmount(M * 4 + M / 4)
            .build();
        public static final OrePrefixes unknown = new OrePrefixBuilder("unknown")
            .materialAmount(-1)
            .build();
        '''
        values = 'public static final long M = 3628800; public static final long L = 144;'
        data = extract(prefixes, values)
        self.assertEqual(data['fluidPerIngot'], 144)
        self.assertEqual(data['forms'], {'ingot': 1, 'rotor': 4.25, 'wire16': 8})
        self.assertEqual(amount('(M * 3) / 4', 3628800), 2721600)
        with self.assertRaises(ValueError):
            amount('__import__("os").system("echo bad")', 3628800)

    def test_pinned_amounts_cover_solids_and_both_conductor_types(self):
        path = Path(__file__).resolve().parents[1] / 'source' / 'data' / 'material_units.json'
        data = json.loads(path.read_text())
        forms = data['forms']
        self.assertEqual(forms['ingot'], 1)
        self.assertEqual(forms['plateDense'], 9)
        self.assertEqual(forms['gearGt'], 4)
        self.assertEqual(forms['stick'], 0.5)
        self.assertEqual(forms['wire16'], forms['cable16'])
        self.assertEqual(data['fluidPerIngot'], 144)
        self.assertEqual(len(data['source']['sha256']), 64)
