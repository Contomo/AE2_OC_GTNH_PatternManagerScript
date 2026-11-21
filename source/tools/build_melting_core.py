"""Derive Helioflux recipes from the pinned Godforge conversion and live EBF export.

Desktop evidence stays outside the OC catalog. Item identities, feeds and output
sets are interned once; optional gas variants share their common dust feed.
"""
import argparse
from collections import defaultdict
import gzip
import hashlib
import json
import math
from pathlib import Path
import re
import zipfile

from import_catalog import records
from import_registry_names import recover
from material_forms import descriptor, registry_forms, solidifier_route, primary_solidifier_fluids
from build_material_sources import raw_material_sources


def source_contract(archive):
    with zipfile.ZipFile(archive) as z:
        def read(suffix):
            return z.read(next(p for p in z.namelist() if p.endswith(suffix))).decode()
        java = read('/tectech/loader/recipe/Godforge.java')
        bridge = read('/BridgeMaterialsLoader.java')
    for expected in ('RecipeMaps.blastFurnaceRecipes.getAllRecipes()',
                     'potentialFluid.amount *= stack.stackSize',
                     'fluidOutputs.addAll(Arrays.asList(recipe.mFluidOutputs))',
                     'mat.getMolten(INGOTS * data.mMaterial.mAmount / GTValues.M)',
                     'mat.getFluid(1_000)', 'dict.startsWith("ingotHot")',
                     'dict.startsWith("dustRoasted") && !dict.contains("Cobalt")'):
        if expected not in java:
            raise ValueError('Unknown Godforge conversion: ' + expected)
    if 'werkstoffBridgeMaterial.mStandardMoltenFluid = werkstoff.getMolten(1)' not in bridge:
        raise ValueError('Unknown BartWorks molten bridge')
    return hashlib.sha256(java.encode()).hexdigest()


def process_gases(archive):
    with zipfile.ZipFile(archive) as z:
        java = z.read(next(p for p in z.namelist() if p.endswith('/BlastFurnaceGasStat.java'))).decode()
    gases = re.findall(r'^\s*(\w+)\((?:Materials|WerkstoffLoader)\.\w+\.get(?:Gas|FluidOrGas)\(', java, re.M)
    if not gases:
        raise ValueError('Unknown BlastFurnaceGasStat declarations')
    return {name.lower() for name in gases}


def compile_catalog(recipes, resources, registry, names, units, tiers, origins,
                    optional_gases, raw_sources=None):
    families, materials, reverse = registry_forms(registry, resources)
    primary = primary_solidifier_fluids(recipes, reverse, materials)
    casts, ingot_molds = {}, set()
    for recipe in recipes:
        route = solidifier_route(recipe, reverse)
        if route and route[1] == 'ingot' and route[2] == primary[route[0]]:
            ingot_molds.add(next(e['id'] for e in recipe['inputs'] if not e.get('consumed', True)))
            feed = next(e for e in recipe['inputs'] if e.get('consumed', True))
            out = recipe['outputs'][0]
            if feed['amount'] != units['fluidPerIngot'] * out['amount']:
                raise ValueError('Unexpected ingot casting unit: ' + recipe['id'])
            old = casts.get(route[0])
            candidate = (feed['id'], out['id'], recipe['eut'])
            if old and old[:2] != candidate[:2]:
                raise ValueError('Conflicting ingot cast: ' + route[0])
            casts[route[0]] = candidate

    conversions = {}
    for rid, (material, form) in reverse.items():
        if material not in casts or form not in units['forms']:
            continue
        family = materials[material]['family']
        if family in ('gt', 'bw'):
            conversions[rid] = (casts[material][0], int(units['fluidPerIngot'] * units['forms'][form]), material)
        else:
            tags = resources.get(rid, {}).get('tags', [])
            first = tags[0] if tags else ''
            token = first[8:] if first.startswith('ingotHot') else (
                first[11:] if first.startswith('dustRoasted') and 'Cobalt' not in first else '')
            if token and 'molten.' + token.lower() == casts[material][0]:
                conversions[rid] = (casts[material][0], units['fluidPerIngot'], material)

    items, item_ids, namespaces, namespace_ids = [], {}, [], {}
    feeds, feed_ids, products, product_ids = [], {}, [], {}
    rejected, witnesses = [], []

    def item(rid, kind='item'):
        key = kind, rid
        if key not in item_ids:
            raw, damage = descriptor(rid) if kind == 'item' else (rid, None)
            name = raw if kind == 'fluid' else names.get(raw)
            if name is None and raw.startswith(('gregtech:', 'minecraft:')):
                name = raw
            if name is None:
                raise ValueError('Unverified registry name: ' + raw)
            if name not in namespace_ids:
                namespace_ids[name] = len(namespaces) + 1
                namespaces.append(name)
            row = {'name': namespace_ids[name], 'type': kind,
                   'label': resources.get(rid, {}).get('displayName', rid)}
            if damage is not None:
                row['damage'] = damage
            item_ids[key] = len(items) + 1
            items.append(row)
        return item_ids[key]

    def intern(values, rows, index):
        key = tuple(tuple(pair) for pair in values)
        if key not in index:
            index[key] = len(rows) + 1
            rows.append(values)
        return index[key]

    def pairs(stacks):
        values = defaultdict(int)
        for s in stacks:
            if s.get('tag') or s.get('nbt') or s.get('amount', 0) <= 0:
                raise ValueError('Unsupported tagged/empty ingredient')
            values[item(s['id'], s['kind'])] += s['amount']
        return [[i, n] for i, n in sorted(values.items())]

    candidates = []
    for recipe in recipes:
        if recipe['machineType'] != 'Blast Furnace':
            continue
        converted, outputs, primary = [], [], None
        for out in recipe['outputs']:
            mapping = conversions.get(out['id']) if out['kind'] == 'item' else None
            if mapping:
                fluid, amount, material = mapping
                converted.append(out['id'])
                outputs.append({'kind': 'fluid', 'id': fluid, 'amount': amount * out['amount']})
                primary = primary or material
            else:
                outputs.append(out)
        if not primary:
            rejected.append({'recipe': recipe['id'], 'reason': 'No verified convertible molten ingot output'})
            continue
        try:
            consumed = [e for e in recipe['inputs'] if e.get('consumed', True)]
            stock = [e for e in recipe['inputs'] if not e.get('consumed', True)]
            circuit = 0
            for s in stock:
                raw, damage = descriptor(s['id'])
                if raw != 'gregtech:gt.integrated_circuit' or s['amount'] != 1:
                    raise ValueError('Unsupported stocked catalyst')
                circuit = damage
            if any(o.get('chance', 1) not in (1, 100, 10000) for o in outputs if o['kind'] == 'item'):
                raise ValueError('Probabilistic solid coproduct')
            output = intern(pairs(outputs), products, product_ids)
            feed = pairs(consumed)
            same_dust = any(reverse.get(e['id']) == (primary, 'dust') for e in consumed)
            raw_feed = all(e['kind'] == 'fluid' or reverse.get(e['id'], ('', ''))[1].startswith(
                ('dust', 'crushed', 'rawOre')) for e in consumed)
            cost = sum(units['forms'].get(reverse.get(e['id'], ('', ''))[1], 0) * e['amount']
                       for e in consumed if e['kind'] == 'item')
            candidates.append({'material': primary, 'feed': feed, 'output': output,
                               'circuit': circuit, 'eut': recipe['eut'], 'heat': recipe.get('specialValue', 0),
                               'ticks': recipe.get('durationTicks', 0), 'rank': 0 if same_dust else 1 if raw_feed else 2,
                               'cost': max(1, cost), 'sourceId': recipe['id']})
        except ValueError as error:
            rejected.append({'recipe': recipe['id'], 'reason': str(error)})

    # Optional gas is established by an otherwise identical no-fluid recipe.
    # Required reaction fluids have no such counterpart and stay in the feed.
    dry = set()
    for row in candidates:
        if all(items[i - 1]['type'] == 'item' for i, _ in row['feed']):
            dry.add((row['output'], tuple(map(tuple, row['feed']))))
    groups = defaultdict(list)
    gases = set()
    for row in candidates:
        fluids = [[i, n] for i, n in row['feed'] if items[i - 1]['type'] == 'fluid']
        solids = [[i, n] for i, n in row['feed'] if items[i - 1]['type'] == 'item']
        row['gas'] = 0
        if len(fluids) == 1 and (row['output'], tuple(map(tuple, solids))) in dry:
            if namespaces[items[fluids[0][0] - 1]['name'] - 1] in optional_gases:
                row['gas'], row['gasAmount'] = fluids[0]
                row['feed'] = solids
                gases.add(row['gas'])
            else:
                # Earlier releases incorrectly treated reaction fluids as
                # optional. Recognize that old pattern for migration only.
                row['legacyGas'] = fluids[0][0]
        row['feed'] = intern(row['feed'], feeds, feed_ids)
        witnesses.append({'recipe': row.pop('sourceId'), 'material': row['material']})
        groups[row['material']].append(row)

    material_rows = []
    for key, (fluid, ingot, eut) in sorted(casts.items()):
        origin = origins.get(key, {}).get('fluids', {}).get(fluid, {})
        tier = tiers.get(key, {})
        routes = groups.get(key, [])
        seen, unique = set(), []
        for route in sorted(routes, key=lambda r: (r['rank'], r['gas'], r['ticks'], r['feed'])):
            route.pop('material')
            signature = json.dumps(route, sort_keys=True)
            if signature not in seen:
                unique.append(route)
                seen.add(signature)
        material_rows.append({'name': materials[key]['name'], 'key': key,
                              'tier': tier.get('tier'), 'tierSource': tier.get('kind'),
                              'fluid': item(fluid, 'fluid'), 'ingot': item(ingot), 'castEUt': eut,
                              'native': origin.get('native', False),
                              'nativeMachine': origin.get('example', {}).get('machine'), 'routes': unique})
        dust = materials[key]['_forms'].get('dust')
        if raw_sources is not None and dust in raw_sources:
            material_rows[-1]['rawSource'] = raw_sources[dust]['independent']

    # Only exact, deterministic extractor routes are eligible for automatic
    # retirement. Coproduct or unrecognized patterns remain visible to proof.
    extraction_rules, extraction_ids, extraction_sets = [], {}, defaultdict(set)
    extraction_extra = defaultdict(list)
    known_fluids = {f for f, _, _ in casts.values()}
    for recipe in recipes:
        if recipe['machineType'] != 'Fluid Extractor' or len(recipe['outputs']) != 1:
            continue
        consumed = [e for e in recipe['inputs'] if e.get('consumed', True)]
        out = recipe['outputs'][0]
        if (len(consumed) == 1 and consumed[0]['kind'] == 'item' and out['kind'] == 'fluid'
                and out['id'] in known_fluids):
            found = reverse.get(consumed[0]['id'])
            if found and casts.get(found[0], (None,))[0] == out['id']:
                key, form = found
                raw, damage = descriptor(consumed[0]['id'])
                name = names.get(raw, raw if raw.startswith(('gregtech:', 'minecraft:')) else None)
                if name is None:
                    rejected.append({'recipe': recipe['id'], 'reason': 'Unverified extractor registry name: ' + raw})
                    continue
                common = math.gcd(consumed[0]['amount'], out['amount'])
                rule = {'n': consumed[0]['amount'] // common, 'amount': out['amount'] // common}
                material = materials[key]
                family = families.get(material['family'], {})
                resolver = family.get(form, {})
                if resolver.get('name') == raw and damage == resolver['prefix'] + material['dsf']:
                    rule.update(kind='meta', name=name, prefix=resolver['prefix'])
                elif resolver.get('template') and resolver['template'] % material['dsf'] == raw:
                    suffix = len(str(material['dsf']))
                    rule.update(kind='suffix', name=name[:-suffix])
                    material['exSuffix'] = name[-suffix:]
                else:
                    rule.update(kind='literal', name=name, damage=damage)
                if rule['kind'] == 'literal':
                    if rule not in extraction_extra[key]: extraction_extra[key].append(rule)
                else:
                    signature = json.dumps(rule, sort_keys=True)
                    if signature not in extraction_ids:
                        extraction_ids[signature] = len(extraction_rules) + 1
                        extraction_rules.append(rule)
                    extraction_sets[key].add(extraction_ids[signature])
    sets, set_ids = [], {}
    for row in material_rows:
        key = row['key']
        row['dsf'] = materials[key]['dsf']
        if materials[key].get('exSuffix'): row['exSuffix'] = materials[key]['exSuffix']
        signature = tuple(sorted(extraction_sets[key]))
        if signature not in set_ids:
            set_ids[signature] = len(sets) + 1
            sets.append(list(signature))
        row['ex'] = set_ids[signature]
        if extraction_extra[key]: row['exExtra'] = extraction_extra[key]
    if len(ingot_molds) != 1:
        raise ValueError('Ambiguous ingot mold')
    result = {'version': 1, 'names': namespaces, 'items': items, 'feeds': feeds, 'products': products,
              'materials': material_rows, 'gases': sorted(gases),
              'ingotMold': item(next(iter(ingot_molds))),
              'circuits': sorted({r['circuit'] for m in material_rows for r in m['routes']}),
              'extraction': {'rules': extraction_rules, 'sets': sets}}
    return result, {'rejected': rejected, 'derivedRecipes': witnesses}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--export', type=Path, default=Path('../OreDictScript/research/recipes.json.gz'))
    parser.add_argument('--gt', type=Path, default=Path('.research/gt-5.09.54.133.zip'))
    parser.add_argument('--output', type=Path, default=Path('source/data/melting_core.json'))
    args = parser.parse_args()
    java_hash = source_contract(args.gt)
    resources, recipes, meta = {}, [], {}
    for section, key, row in records(args.export):
        if section == 'meta':
            meta[key] = row
        elif section == 'resources':
            resources[key] = {k: v for k, v in row.items() if k in ('id', 'kind', 'displayName', 'tags')}
        elif row['machineType'] in ('Blast Furnace', 'Fluid Extractor', 'Fluid Solidifier'):
            recipes.append(row)
    with gzip.open('../OreDictScript/data/ores.json.gz', 'rt') as stream:
        for rid, row in json.load(stream)['resources'].items():
            if rid in resources:
                resources[rid]['tags'] = row.get('tags', [])
    registry = json.loads(Path('../OreDictScript/data/registry-rules.json').read_text())
    names = json.loads(Path('data/registry-names.json').read_text())['names']
    names.update(recover(args.gt, registry, {'recipes': recipes}, '.research/EnderIO-ItemAlloy.java',
                         '.research/EnderIO-ModObject.java', '.research/hiddenitems-pinned.cfg')['names'])
    units = json.loads(Path('source/data/material_units.json').read_text())
    tiers = json.loads(Path('data/material-tiers.json').read_text())['materials']
    origins = json.loads(Path('data/material-sources.json').read_text())['materials']
    _, _, reverse = registry_forms(registry, resources)
    raw_sources = raw_material_sources(
        (row for section, _, row in records(args.export) if section == 'recipes'), resources, reverse)
    result, evidence = compile_catalog(recipes, resources, registry, names, units, tiers, origins,
                                       process_gases(args.gt), raw_sources)
    evidence['rawSources'] = raw_sources
    result['source'] = {'recipeVersion': meta['gtnhVersion'], 'targetVersion': '2.9.0-beta-3',
                        'datasetId': meta['datasetVersionId'],
                        'recipeSource': 'https://github.com/GTNewHorizons/GT5-Unofficial/blob/5.09.54.133/src/main/java/tectech/loader/recipe/Godforge.java',
                        'godforgeSha256': java_hash,
                        'conversionPolicy': 'Pinned EBF-to-molten conversion; registered ingot casts; native liquids preserved.'}
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    settings = {'circuits': result['circuits'], 'gases': [
        {'name': result['names'][result['items'][i - 1]['name'] - 1], 'label': result['items'][i - 1]['label']}
        for i in result['gases']], 'legacyGases': sorted({
            result['names'][result['items'][r['legacyGas'] - 1]['name'] - 1]
            for m in result['materials'] for r in m['routes'] if r.get('legacyGas')})}
    Path('source/data/melting_settings.json').write_text(json.dumps(settings, indent=2) + '\n')
    Path('.research/melting-core-evidence.json').write_text(json.dumps(evidence, indent=2))
    print(len(result['materials']), 'ingot casts;', sum(len(m['routes']) for m in result['materials']),
          'derived routes;', len(result['extraction']['rules']), 'shared extraction rules;', args.output.stat().st_size, 'bytes')


if __name__ == '__main__':
    main()
