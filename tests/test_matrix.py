import gzip
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'source' / 'tools'))
from compile_matrix import compile_matrix, descriptor
from material_forms import resolve, registry_forms


class MatrixTests(unittest.TestCase):
    def fixture(self):
        def ingredient(rid, amount=1, **extra):
            return dict(kind='item', id=rid, amount=amount, **extra)
        registry = {'materials': {'30': 'Chrome', '360': 'NiobiumTitanium'},
                    'prefixes': {'gregtech:gt.metaitem.01': ['null'] * 11 + ['ingot'],
                                 'gregtech:gt.metaitem.02': ['null'] * 19 + ['wireFine']}}
        catalog = {'source': {'recipeVersion': 'beta2', 'targetVersion': 'beta3'}, 'resources': {}, 'recipes': []}
        for suffix in (30, 360):
            catalog['recipes'].append({'id': str(suffix), 'machineType': 'Wiremill',
                                      'inputs': [ingredient(f'gregtech:gt.metaitem.01@{11000+suffix}')],
                                      'outputs': [ingredient(f'gregtech:gt.metaitem.02@{19000+suffix}', 8)]})
        return catalog, registry

    def test_shared_rule_and_prefix_tables_replace_repeated_descriptors(self):
        catalog, registry = self.fixture()
        data = compile_matrix(catalog, registry)
        self.assertEqual(len(data['materials']), 2)
        self.assertEqual(len(data['rules']), 1)
        self.assertEqual(len(data['items']), 0)
        self.assertEqual(data['families']['gt']['wireFine']['prefix'], 19000)
        self.assertTrue(all(data['production'][row['p']-1]['ingot_wireFine'] for row in data['materials']))
        self.assertTrue(all('m' not in row for row in data['materials']))

    def test_registration_does_not_create_recipe_eligibility(self):
        catalog, registry = self.fixture()
        catalog['recipes'].pop()
        data = compile_matrix(catalog, registry)
        self.assertEqual([row['dsf'] for row in data['materials']], [30])

    def test_direct_use_profiles_follow_actual_output_ids(self):
        catalog, registry = self.fixture()
        catalog['source']['datasetId'] = 'fixture'
        outputs = [recipe['outputs'][0]['id'] for recipe in catalog['recipes']]
        usage = {'policy': 'reachable-nonrecycling-v3', 'datasetVersionId': 'fixture',
                 'recipeCount': 9, 'recipeExportSha256': 'fixture-sha',
                 'useful': [outputs[1]],
                 'counts': {outputs[0]: [1, 3], outputs[1]: [1, 0]}}
        data = compile_matrix(catalog, registry, usage=usage)
        rows = {row['name']: row for row in data['materials']}
        self.assertNotIn('wireFine', data['usage'][rows['Chrome']['u'] - 1])
        self.assertIn('wireFine', data['usage'][rows['NiobiumTitanium']['u'] - 1])
        self.assertEqual(data['source']['usagePolicy'], usage['policy'])
        with self.assertRaisesRegex(ValueError, 'different datasets'):
            compile_matrix(catalog, registry, usage={**usage, 'datasetVersionId': 'other'})
        catalog['source']['sha256'] = 'export-sha'
        with self.assertRaisesRegex(ValueError, 'different exports'):
            compile_matrix(catalog, registry, usage=usage)

    def test_bender_imports_scraped_ingot_and_plate_routes_with_stocked_circuits(self):
        catalog, registry = self.fixture()
        catalog['recipes'] = []
        prefixes = ['null'] * 30
        for index, form in [(11, 'ingot'), (17, 'plate'), (18, 'plateDouble')]:
            prefixes[index] = form
        registry['prefixes']['gregtech:gt.metaitem.01'] = prefixes
        def item(rid, amount=1, consumed=True):
            return {'kind':'item','id':rid,'amount':amount,'consumed':consumed}
        def recipe(name, suffix, input_form, input_amount, output_form, circuit):
            indexes={'ingot':11000,'plate':17000,'plateDouble':18000}
            return {'id':name,'machineType':'Bending Machine','inputs':[
                item(f'gregtech:gt.metaitem.01@{indexes[input_form]+suffix}',input_amount),
                item(f'gregtech:gt.integrated_circuit@{circuit}',consumed=False)],
                'outputs':[item(f'gregtech:gt.metaitem.01@{indexes[output_form]+suffix}')]}
        catalog['recipes'] = [
            recipe('chrome-plate',30,'ingot',1,'plate',1),
            recipe('chrome-double',30,'ingot',2,'plateDouble',2),
            recipe('chrome-plate-derived',30,'plate',2,'plateDouble',2),
            recipe('niobium-plate',360,'ingot',1,'plate',1)]
        data=compile_matrix(catalog,registry)
        rules=[r for r in data['rules'] if r['mode']=='bender']
        self.assertEqual(len(rules),3)
        self.assertEqual({r['process'] for r in rules},
                         {'ingot_plate','ingot_plateDouble','plate_plateDouble'})
        self.assertTrue(all(len(r['inputs'])==1 for r in rules))
        self.assertEqual({r['inputs'][0]['f'] for r in rules},{'ingot','plate'})
        circuits={r['outputs'][0]['f']:data['items'][r['stock'][0]['i']-1]['damage'] for r in rules}
        self.assertEqual(circuits,{'plate':1,'plateDouble':2})
        niobium=next(m for m in data['materials'] if m['name']=='NiobiumTitanium')
        self.assertNotIn('ingot_plateDouble',data['production'][niobium['p']-1])

    def test_external_form_ids_are_scraped_for_arbitrary_materials(self):
        catalog, registry = self.fixture()
        registry['materials'] = {'30': 'Quorlium', '360': 'Vexium'}
        # Names/IDs deliberately have no relation to the material or form. Only
        # scraped tags establish identity, and the actual recipe selects an item
        # when both an ordinary metadata item and external alternatives exist.
        resources = {}
        for recipe, (suffix, material, rid, decoy) in zip(catalog['recipes'], [
                (30, 'Quorlium', 'unseenpack:component@71', 'unseenpack:alternative@72'),
                (360, 'Vexium', 'anotherpack:object_17', 'anotherpack:alternative_18')]):
            resources[rid] = {'kind': 'item', 'displayName': 'Unrelated label',
                              'tags': ['ingot' + material]}
            resources[f'gregtech:gt.metaitem.01@{11000+suffix}'] = {'kind': 'item'}
            resources[decoy] = {'kind': 'item', 'tags': ['ingot' + material]}
            recipe['inputs'][0]['id'] = rid
        for order in (resources, dict(reversed(list(resources.items())))):
            data = compile_matrix(catalog, registry, resources=order)
            self.assertEqual(len(data['rules']), 1)
            self.assertEqual(len(data['items']), 0)
            for row in data['materials']:
                recipe = next(r for r in catalog['recipes'] if r['id'] == str(row['dsf']))
                self.assertEqual(resolve(data['families'], row, 'ingot'),
                                 descriptor(recipe['inputs'][0]['id']))
        # Changing evidence changes the resolver without editing compiler code.
        catalog['recipes'][0]['inputs'][0]['id'] = 'unseenpack:alternative@72'
        changed = compile_matrix(catalog, registry, resources=resources)
        row = next(m for m in changed['materials'] if m['dsf'] == 30)
        self.assertEqual(resolve(changed['families'], row, 'ingot'),
                         ('unseenpack:alternative', 72))

    def test_untagged_display_names_do_not_create_material_mappings(self):
        _, registry = self.fixture()
        families, rows, reverse = registry_forms(registry, {
            'unseenpack:component@71': {'kind': 'item', 'displayName': 'Chrome Ingot'},
            'unseenpack:component@72': {'kind': 'item', 'tags': ['ingotUnregisteredMaterial']}})
        self.assertFalse(rows)
        self.assertFalse(reverse)

    def test_exact_nbt_and_chance_require_an_explicit_resolver(self):
        catalog, registry = self.fixture()
        catalog['recipes'][0]['inputs'][0]['nbt'] = {'display': 'custom'}
        with self.assertRaisesRegex(ValueError, 'NBT'):
            compile_matrix(catalog, registry)
        del catalog['recipes'][0]['inputs'][0]['nbt']
        rid = catalog['recipes'][0]['inputs'][0]['id']
        catalog['resources'][rid] = {'nbt': {'display': 'custom'}}
        with self.assertRaisesRegex(ValueError, 'NBT'):
            compile_matrix(catalog, registry)
        catalog['resources'].clear()
        catalog['recipes'][0]['outputs'][0]['chance'] = .5
        with self.assertRaisesRegex(ValueError, 'Chance'):
            compile_matrix(catalog, registry)

    def test_alternatives_require_the_exact_primary_item(self):
        catalog, registry = self.fixture()
        catalog['recipes'][0]['inputs'][0]['alternatives'] = [{'id': 'other:item@0', 'amount': 1}]
        with self.assertRaisesRegex(ValueError, 'Primary item'):
            compile_matrix(catalog, registry)

    @unittest.skipUnless(Path('.research/pattern-catalog.json.gz').exists(), 'Local recipe evidence not installed')
    def test_local_evidence_round_trip(self):
        catalog = json.load(gzip.open('.research/pattern-catalog.json.gz', 'rt', encoding='utf-8'))
        registry = json.loads(Path('../OreDictScript/data/registry-rules.json').read_text(encoding='utf-8-sig'))
        resources = {r['id']: r for r in json.load(gzip.open('../OreDictScript/research/resource-index.json.gz', 'rt'))['resources']}
        ores = json.load(gzip.open('../OreDictScript/data/ores.json.gz', 'rt'))['resources']
        for rid, resource in resources.items():
            resource['tags'] = ores.get(rid, {}).get('tags', [])
        data = compile_matrix(catalog, registry, resources=resources)
        actual = set()

        def key(mode, inputs, outputs, stock):
            return json.dumps([mode, sorted(inputs), sorted(outputs), sorted(stock)], separators=(',', ':'))

        for material in data['materials']:
            available = data['capabilities'][material['a']-1]
            # Every claimed form must resolve to a concrete registered item.
            for form in available:
                name, damage = resolve(data['families'], material, form)
                self.assertTrue(name + '@' + str(damage) in resources or
                                damage == 0 and name in resources, (material['name'], form, name, damage))
            for rule in data['rules']:
                eligible = (material.get('coating') == rule.get('coating') if rule['mode'] == 'coating'
                            else material.get('p') and data['production'][material['p']-1].get(rule['process']))
                if not eligible or any(f not in available for f in rule['requires']) or rule['id'] in material.get('deny', {}):
                    continue

                def entry(e):
                    if 'fluid' in e:
                        return ('fluid', e['fluid'], 0, e['n'])
                    if 'f' in e:
                        name, damage = resolve(data['families'], material, e['f'])
                    else:
                        item = data['items'][e['i']-1]
                        name, damage = item['name'], item['damage']
                    return ('item', name, damage, e['n'])
                actual.add(key(rule['mode'], list(map(entry, rule['inputs'])), list(map(entry, rule['outputs'])), list(map(entry, rule['stock']))))
        expected = set()
        missing = 0
        for recipe in catalog['recipes']:
            mode = {'Wiremill': 'wiremill', 'Cable Coating': 'coating'}[recipe['machineType']]
            inputs, outputs, stock = [], [], []
            for side, target in [('inputs', inputs), ('outputs', outputs)]:
                for e in recipe[side]:
                    name, damage = descriptor(e['id']) if e['kind'] == 'item' else (e['id'], 0)
                    value = (e['kind'], name, damage, e['amount'])
                    (stock if e['kind'] == 'fluid' or e.get('consumed') is False else target).append(value)
            value = key(mode, inputs, outputs, stock)
            expected.add(value)
            if value not in actual:
                # Recipes without either selectable polymer are alternatives,
                # not a fifth consumed-solid route.
                polymer_ids = {'gregtech:gt.metaitem.01@1649', 'gregtech:gt.metaitem.01@2649',
                               'gregtech:gt.metaitem.01@1633', 'gregtech:gt.metaitem.01@2633'}
                alternative = mode == 'coating' and not any(e['id'] in polymer_ids for e in recipe['inputs'])
                if not alternative:
                    missing += 1
        excluded_nonselected = sum(1 for recipe in catalog['recipes'] if
            recipe['outputs'][0].get('displayName') in data['source']['excludedOutputs'] and
            recipe['machineType'] == 'Cable Coating' and not any(
                e['id'] in polymer_ids for e in recipe['inputs']))
        self.assertEqual(missing, data['source']['excludedRecipes'] - excluded_nonselected)
        self.assertFalse(actual - expected, 'Rules generated recipes absent from the evidence')
        self.assertEqual(sum(r['mode']=='wiremill' for r in data['rules']), 21)
        self.assertEqual(sum(len(m.get('deny', {})) for m in data['materials']), 2)
        forms = set().union(*data['capabilities'])
        self.assertTrue({'gearGt','gearGtSmall','stickLong','ring','screw','bolt','rotor','springSmall','spring',
                         'itemCasing','plateDouble','plateTriple','plateQuadruple','plateQuintuple','plateDense',
                         'plateSuperdense','frameGt','pipeFluidTiny','pipeItemSmall','casingBolted','casingRebolted',
                         'sheetmetal','round','foil'} <= forms)

    @unittest.skipUnless(Path('.research/pattern-catalog-with-bender.json.gz').exists(),
                         'Local bending evidence not installed')
    def test_bender_expansion_contains_no_recipe_absent_from_scrape(self):
        catalog = json.load(gzip.open('.research/pattern-catalog-with-bender.json.gz', 'rt'))
        registry = json.loads(Path('../OreDictScript/data/registry-rules.json').read_text(encoding='utf-8-sig'))
        resources = {r['id']: r for r in json.load(gzip.open('../OreDictScript/research/resource-index.json.gz', 'rt'))['resources']}
        resources.update(json.load(gzip.open('../OreDictScript/data/ores.json.gz', 'rt'))['resources'])
        resources.update(catalog['resources'])
        for recipe in catalog['recipes']:
            for entry in recipe['inputs'] + recipe['outputs']:
                if entry['kind'] == 'item':
                    resources.setdefault(entry['id'], {'kind': 'item'})
        data = compile_matrix(catalog, registry, resources=resources)
        mu = next(m for m in data['materials'] if m['name'] == 'Mu-metal')
        self.assertEqual(mu['dsf'], 11351)
        self.assertIn('plate', data['capabilities'][mu['a'] - 1])
        self.assertIn('ingot_plate', data['production'][mu['p'] - 1])

        def ingredient(rid, amount):
            name, damage = descriptor(rid)
            return name, damage, amount

        def identity(inputs, outputs, stock):
            return tuple(sorted(inputs)), tuple(sorted(outputs)), tuple(sorted(stock))

        source = set()
        for recipe in catalog['recipes']:
            if recipe['machineType'] != 'Bending Machine':
                continue
            inputs, stock = [], []
            for item in recipe['inputs']:
                (inputs if item.get('consumed', True) else stock).append(ingredient(item['id'], item['amount']))
            outputs = [ingredient(item['id'], item['amount']) for item in recipe['outputs']]
            source.add(identity(inputs, outputs, stock))

        expanded = set()
        for material in data['materials']:
            available = data['capabilities'][material['a']-1]
            production = data['production'][material['p']-1] if material.get('p') else {}
            for rule in data['rules']:
                if rule['mode'] != 'bender' or not production.get(rule['process']):
                    continue
                if any(form not in available for form in rule['requires']) or rule['id'] in material.get('deny', {}):
                    continue
                def expand(entries):
                    result = []
                    for entry in entries:
                        if 'f' in entry:
                            name, damage = resolve(data['families'], material, entry['f'])
                        else:
                            item = data['items'][entry['i']-1]
                            name, damage = item['name'], item['damage']
                        result.append((name, damage, entry['n']))
                    return result
                expanded.add(identity(expand(rule['inputs']), expand(rule['outputs']), expand(rule['stock'])))
        self.assertGreater(len(expanded), 2500)
        self.assertFalse(expanded - source, 'Bender matrix generated a recipe absent from the scrape')

    @unittest.skipUnless(Path('.research/pattern-catalog-with-shaper.json.gz').exists(),
                         'Local Fluid Shaper evidence not installed')
    def test_fluid_shaper_expansion_contains_no_recipe_absent_from_scrape(self):
        catalog = json.load(gzip.open('.research/pattern-catalog-with-shaper.json.gz', 'rt'))
        registry = json.loads(Path('../OreDictScript/data/registry-rules.json').read_text(encoding='utf-8-sig'))
        resources = {r['id']: r for r in json.load(gzip.open('../OreDictScript/research/resource-index.json.gz', 'rt'))['resources']}
        resources.update(json.load(gzip.open('../OreDictScript/data/ores.json.gz', 'rt'))['resources'])
        resources.update(catalog['resources'])
        for recipe in catalog['recipes']:
            for entry in recipe['inputs'] + recipe['outputs']:
                if entry['kind'] == 'item':
                    resources.setdefault(entry['id'], {'kind': 'item'})
        data = compile_matrix(catalog, registry, resources=resources)
        _, _, reverse = registry_forms(registry, resources)
        source = set()
        for recipe in catalog['recipes']:
            if recipe['machineType'] != 'Fluid Solidifier' or len(recipe['outputs']) != 1:
                continue
            output = reverse.get(recipe['outputs'][0]['id'])
            consumed = [e for e in recipe['inputs'] if e.get('consumed', True)]
            stocked = [e for e in recipe['inputs'] if e.get('consumed') is False]
            if (not output or output[1] in ('dust', 'gem') or
                    len(consumed) != 1 or consumed[0]['kind'] != 'fluid' or
                    len(stocked) != 1 or stocked[0]['kind'] != 'item' or
                    not stocked[0]['id'].startswith('gregtech:gt.metaitem.01@323')):
                continue
            source.add((consumed[0]['id'], consumed[0]['amount'],
                        descriptor(recipe['outputs'][0]['id']), recipe['outputs'][0]['amount'],
                        descriptor(stocked[0]['id'])))
        expanded = set()
        for material in data['materials']:
            available = data['capabilities'][material['a'] - 1]
            production = data['production'][material['p'] - 1] if material.get('p') else {}
            for rule in data['rules']:
                if (rule['mode'] != 'solidifier' or not production.get(rule['process']) or
                        rule['id'] in material.get('deny', {}) or
                        any(form not in available for form in rule['requires'])):
                    continue
                self.assertEqual(rule['inputs'][0]['fluid'], 'material')
                output_name, output_damage = resolve(data['families'], material,
                                                     rule['outputs'][0]['f'])
                mold = data['items'][rule['stock'][0]['i'] - 1]
                expanded.add((material['molten'], rule['inputs'][0]['n'],
                              (output_name, output_damage), rule['outputs'][0]['n'],
                              (mold['name'], mold['damage'])))
        self.assertGreater(len(expanded), 3000)
        self.assertFalse(expanded - source, 'Fluid Shaper matrix generated a recipe absent from the scrape')
        materials = {row['name']: row for row in data['materials']}
        self.assertEqual(materials['Copper']['molten'], 'molten.copper')
        self.assertEqual(materials['Iron']['molten'], 'molten.iron')


if __name__ == '__main__':
    unittest.main()
