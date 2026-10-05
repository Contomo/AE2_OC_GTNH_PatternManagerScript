"""Compile Component Assembly Line evidence into shared identities and route deltas.

Casing/circuit assignments are checked against the pinned GT source. Ingredient
identities and native amounts come from the machine export, never from examples.
"""
import argparse
from collections import defaultdict
import hashlib
import gzip
import json
from pathlib import Path
import re
import zipfile

from import_catalog import records
from material_forms import descriptor


def source_contract(java):
    casings = {tier: int(number) for tier, number in re.findall(r'COAL_(\w+)\s*=\s*(\d+)', java)}
    circuits = {key: int(number) for key, number in re.findall(r'(\w+)_CIRCUIT\s*=\s*(\d+)', java)}
    groups, outputs = {}, {}
    for call in re.findall(r'GTValues\.RA\.stdBuilder\(\)(.*?)\.addTo\(componentAssemblyLineRecipes\);', java, re.S):
        output = re.search(r'\.itemOutputs\((\w+)\.get\((\d+)\)\)', call)
        casing = re.search(r'\.metadata\(COAL_CASING_TIER, COAL_(\w+)\)', call)
        if not output or not casing:
            raise ValueError('Unknown Component Assembly Line builder layout')
        prefix, tier = output[1].rsplit('_', 1)
        circuit = re.search(r'\.circuit\((\w+)_CIRCUIT\)', call)
        if circuit:
            key = circuit[1]
            if key not in circuits or (prefix in groups and groups[prefix] != key):
                raise ValueError('Inconsistent component circuit assignment')
            groups[prefix] = key
        contract = {'tier': tier, 'casing': casings[casing[1]], 'yield': int(output[2]),
                    'circuit': circuits[circuit[1]] if circuit else None}
        if output[1] in outputs and outputs[output[1]] != contract:
            raise ValueError('Inconsistent alternate output contract')
        outputs[output[1]] = contract
    if len(groups) != 8 or sorted(circuits.values()) != list(range(1, 9)):
        raise ValueError('Expected eight verified component groups')
    components = []
    for prefix, key in sorted(groups.items(), key=lambda entry: circuits[entry[1]]):
        words = key.lower().split('_')
        components.append({'key': words[0] + ''.join(word.title() for word in words[1:]),
                           'label': key.replace('_', ' ').title(), 'circuit': circuits[key],
                           'prefix': prefix})
    return components, outputs, casings


def compile_routes(recipes, java, names, ores=None):
    components, contracts, casings = source_contract(java)
    groups = {component['prefix']: n for n, component in enumerate(components, 1)}
    items, identities, families, family_ids, candidates = [], {}, [], {}, defaultdict(list)

    def item(stack):
        rid = stack['id']
        if stack.get('tag') or stack.get('nbt') or stack['kind'] not in ('item', 'fluid'):
            raise ValueError('Unsupported component ingredient: ' + rid)
        key = stack['kind'], rid
        if key not in identities:
            name, damage = descriptor(rid) if stack['kind'] == 'item' else (rid, None)
            if stack['kind'] == 'item':
                name = names.get(name, name if name.startswith(('gregtech:', 'minecraft:')) else None)
                if not name:
                    raise ValueError('Unverified component registry name: ' + rid)
            if name not in family_ids:
                families.append(name)
                family_ids[name] = len(families)
            value = {'type': stack['kind'], 'name': family_ids[name], 'label': stack['displayName']}
            material = (ores or {}).get(rid, {}).get('material')
            polymer = {'Rubber': 'rubber', 'RubberSilicone': 'silicone',
                       'StyreneButadieneRubber': 'sbr'}.get(material)
            if stack['kind'] == 'fluid':
                polymer = {'molten.rubber': 'rubber', 'molten.silicone': 'silicone',
                           'molten.styrenebutadienerubber': 'sbr'}.get(rid)
            if polymer:
                value['polymer'] = polymer
            if damage is not None:
                value['damage'] = damage
            items.append(value)
            identities[key] = len(items)
        if not isinstance(stack['amount'], int) or stack['amount'] <= 0:
            raise ValueError('Invalid native component quantity')
        return identities[key]

    for recipe in recipes:
        if recipe['machineType'] != 'Component Assembly Line':
            continue
        if len(recipe['outputs']) != 1:
            raise ValueError('Component recipe must have one output')
        output = recipe['outputs'][0]
        label = re.fullmatch(r'(.+) \((\w+)\)', output['displayName'])
        enum = label[1].replace(' ', '_') + '_' + label[2] if label else ''
        contract = contracts.get(enum)
        if not contract or recipe['specialValue'] != contract['casing'] or output['amount'] != contract['yield']:
            raise ValueError('Scrape disagrees with source casing/output: ' + output['displayName'])
        prefix = enum.rsplit('_', 1)[0]
        inputs, stock = [], []
        for stack in recipe['inputs']:
            (inputs if stack.get('consumed', True) else stock).append([item(stack), stack['amount']])
        expected = contract['circuit']
        if expected is None and stock or expected is not None and (
                len(stock) != 1 or recipe.get('programmedCircuit') != str(expected)
                or recipe['inputs'][next(n for n, s in enumerate(recipe['inputs']) if not s.get('consumed', True))]['id']
                != 'gregtech:gt.integrated_circuit@' + str(expected)):
            raise ValueError('Scrape disagrees with stocked circuit: ' + output['displayName'])
        route = {'component': groups[prefix], 'tier': contract['tier'], 'casing': contract['casing'],
                 'output': item(output), 'yield': output['amount'], 'eut': recipe['eut'],
                 'inputs': inputs, 'stock': stock, 'sourceId': recipe['id']}
        candidates[route['output']].append(route)

    # Alternate recipes share their common ingredients. Only substitutions are
    # stored again; no duplicate full SBR/silicone recipe lists are deployed.
    rows = []
    for variants in candidates.values():
        variants.sort(key=lambda row: row['sourceId'])
        base = variants[0].copy()
        base.pop('sourceId')
        base['variants'] = []
        original = {i: count for i, count in base['inputs']}
        for variant in variants[1:]:
            if any(variant[key] != base[key] for key in ('component', 'tier', 'casing', 'yield', 'eut', 'stock')):
                raise ValueError('Alternates disagree on native component contract')
            changed = {i: count for i, count in variant['inputs']}
            delta = {'remove': sorted(set(original) - set(changed)),
                     'set': [[i, count] for i, count in changed.items() if original.get(i) != count]}
            if delta['remove'] or delta['set']:
                if delta not in base['variants']:
                    base['variants'].append(delta)
        rows.append(base)
    rows.sort(key=lambda row: (row['component'], row['casing']))
    return {'components': [{k: v for k, v in row.items() if k != 'prefix'} for row in components],
            'casings': sorted(casings, key=casings.get), 'names': families, 'items': items, 'recipes': rows}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('export', type=Path)
    parser.add_argument('gt', type=Path)
    parser.add_argument('names', type=Path)
    parser.add_argument('ores', type=Path)
    parser.add_argument('--output', type=Path, default=Path('source/data/components.json'))
    args = parser.parse_args()
    recipes, meta = [], {}
    for section, key, row in records(args.export):
        if section == 'meta' and key in ('datasetVersionId', 'gtnhVersion'):
            meta[key] = row
        elif section == 'recipes' and row.get('machineType') == 'Component Assembly Line':
            recipes.append(row)
    with zipfile.ZipFile(args.gt) as archive:
        def read(suffix):
            return archive.read(next(n for n in archive.namelist() if n.endswith(suffix))).decode('utf-8')
        java = read('/ComponentAssemblyLineLoader.java')
        machine = read('/MTEComponentAssemblyLine.java')
        registrations = read('/goodgenerator/loader/Loaders.java')
    if 'recipe.mSpecialValue > casingTier + 1' not in machine:
        raise ValueError('Unknown casing validation contract')
    names = json.loads(args.names.read_text())['names'].copy()
    # Recover the actual case from the registration call, not from the export's
    # lower-cased registry IDs. The domain is GoodGenerator's pinned mod ID.
    registered = re.search(r'GameRegistry.registerItem\(circuitWrap, "([^"]+)", Mods.ModIDs.GOOD_GENERATOR\)', registrations)
    if not registered:
        raise ValueError('Circuit wrap registration missing')
    with zipfile.ZipFile(args.gt) as archive:
        mods = archive.read(next(n for n in archive.namelist() if n.endswith('/gregtech/api/enums/Mods.java'))).decode('utf-8')
    domain = re.search(r'GOOD_GENERATOR\s*=\s*"([^"]+)"', mods)
    if not domain:
        raise ValueError('GoodGenerator mod ID missing')
    name = domain[1] + ':' + registered[1]
    names[name.lower()] = name
    with gzip.open(args.ores, 'rt') as stream:
        ores = json.load(stream)['resources']
    result = compile_routes(recipes, java, names, ores)
    if len(result['recipes']) != 104:
        raise ValueError('Expected eight groups across thirteen casing tiers')
    result['version'] = 1
    result['source'] = {'recipeVersion': meta['gtnhVersion'], 'targetVersion': '2.9.0-beta-3',
                        'datasetId': meta['datasetVersionId'], 'routes': len(recipes),
                        'recipeSource': 'https://github.com/GTNewHorizons/GT5-Unofficial/blob/5.09.54.133/src/main/java/goodgenerator/loader/ComponentAssemblyLineLoader.java',
                        'batchPolicy': 'Native batches of 64 components; shared tier gates and casing limit apply.'}
    result['evidence'] = {'loader': hashlib.sha256(java.encode()).hexdigest(),
                          'machine': hashlib.sha256(machine.encode()).hexdigest(), 'exports': {}}
    for path in (args.export, args.gt, args.names, args.ores):
        with path.open('rb') as stream:
            result['evidence']['exports'][path.name] = hashlib.file_digest(stream, 'sha256').hexdigest()
    args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(len(result['recipes']), 'component/tier outputs;', len(recipes), 'native routes;',
          len(result['items']), 'shared ingredients;', args.output.stat().st_size, 'bytes')


if __name__ == '__main__':
    main()
