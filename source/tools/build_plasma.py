"""Import plasma fabrication paths; recover upgrade metadata from pinned GT source.

The export omits FOG_PLASMA_MULTISTEP. Never infer it from duration or the
presence of a regular fusion recipe. All runtime identities/amounts come from
the export; source arrays supply only the missing upgrade classification.
"""
import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import re
import zipfile

from import_catalog import records
from import_registry_names import recover
from material_forms import descriptor, normal

MACHINE = 'Heliothermal Plasma Fabricator'
SOURCE = 'https://github.com/GTNewHorizons/GT5-Unofficial/blob/5.09.54.133/src/main/java/'
PLASMA_REF = r'(MaterialsElements\.(?:getInstance\(\)|STANDALONE)|Materials)\.(\w+)\.getPlasma\('


def source_groups(java, elements, machine):
    if ('getMetadataOrDefault(FOG_PLASMA_TIER, 0) > getPlasmaTier()' not in machine
            or 'getMetadataOrDefault(FOG_PLASMA_MULTISTEP, false) && !isMultiStepPlasmaCapable' not in machine):
        raise ValueError('Unknown plasma module upgrade contract')
    labels = dict(re.findall(r'(\w+)\s*=\s*new Material\(\s*"([^"]+)"', elements))
    arrays = dict(re.findall(r'FluidStack\[\]\s+(\w+)\s*=\s*\{(.*?)\};', java, re.S))
    groups = {}
    for block in re.findall(r'GTValues\.RA\.stdBuilder\(\)(.*?)\.addTo\(godforgePlasmaRecipes\);', java, re.S):
        tier = re.search(r'\.metadata\(FOG_PLASMA_TIER, ([0-2])\)', block)
        step = re.search(r'\.metadata\(FOG_PLASMA_MULTISTEP, (true|false)\)', block)
        output = re.search(r'\.fluidOutputs\((.*?)\)\s*\.duration', block, re.S)
        if not tier or not step or not output:
            raise ValueError('Unsupported plasma recipe declaration')
        array = re.fullmatch(r'(\w+)\[i\]', output[1])
        refs = re.findall(PLASMA_REF, arrays[array[1]] if array else output[1])
        if not refs:
            raise ValueError('No source plasma reference')
        for family, symbol in refs:
            token = normal(symbol if family == 'Materials' else labels[symbol])
            value = int(tier[1]), step[1] == 'true'
            if token in groups and groups[token] != value:
                raise ValueError('Conflicting plasma upgrade metadata: ' + token)
            groups[token] = value
    return groups


def compile_catalog(recipes, groups, names):
    fusion = {s['id'] for r in recipes if r['machineType'] == 'Fusion Reactor'
              for s in r['outputs'] if s['kind'] == 'fluid' and s.get('chance', 1) in (1, 100, 10000)}
    items, item_ids, rows, witnesses = [], {}, {}, defaultdict(list)
    namespaces, namespace_ids = [], {}
    voltages = set()

    def item(stack):
        key = stack['kind'], stack['id']
        if key not in item_ids:
            name, damage = descriptor(stack['id']) if key[0] == 'item' else (stack['id'], None)
            registered = name if key[0] == 'fluid' else names.get(name, name if name.startswith(('gregtech:', 'minecraft:')) else None)
            if not registered:
                raise ValueError('Unverified registry spelling: ' + name)
            if registered not in namespace_ids:
                namespace_ids[registered] = len(namespaces) + 1
                namespaces.append(registered)
            value = {'type': key[0], 'name': namespace_ids[registered], 'label': stack['displayName']}
            if damage is not None:
                value['damage'] = damage
            item_ids[key] = len(items) + 1
            items.append(value)
        return item_ids[key]

    for recipe in sorted(recipes, key=lambda r: r['id']):
        if recipe['machineType'] != MACHINE:
            continue
        if len(recipe['inputs']) != 1 or len(recipe['outputs']) != 1:
            raise ValueError('Unsupported plasma recipe shape')
        feed, output = recipe['inputs'][0], recipe['outputs'][0]
        if feed['kind'] == 'item' and not feed['displayName'].endswith(' Dust'):
            raise ValueError('Unsupported non-dust solid plasma feed')
        if output['kind'] != 'fluid' or not output['id'].startswith('plasma.'):
            raise ValueError('Unsupported plasma output')
        for stack in (feed, output):
            if (stack['kind'] not in ('item', 'fluid') or not stack.get('consumed', True)
                    or stack.get('tag') or stack.get('nbt') or stack['amount'] <= 0
                    or stack.get('chance', 1) not in (1, 100, 10000)):
                raise ValueError('Unsupported plasma ingredient')
        # The declared material symbol or the registered display name must join
        # unambiguously. This also handles GTpp's source-named material objects.
        tokens = {normal(output['id'][7:]), normal(output['displayName'].removesuffix(' Plasma'))}
        matches = {groups[token] for token in tokens if token in groups}
        if len(matches) != 1:
            raise ValueError('Missing/ambiguous plasma upgrade metadata: ' + output['id'])
        tier, multistep = matches.pop()
        if recipe['specialValue'] != tier:
            raise ValueError('Export and source disagree on plasma tier')
        row = {'label': output['displayName'].removesuffix(' Plasma'), 'tier': tier,
               'multistep': multistep, 'fusion': output['id'] in fusion,
               'output': [item(output), output['amount']], 'paths': {}}
        previous = rows.setdefault(output['id'], row)
        if any(previous[k] != row[k] for k in ('tier', 'multistep', 'fusion', 'output')):
            raise ValueError('Alternate paths disagree on plasma product')
        path = 'dust' if feed['kind'] == 'item' else 'fluid'
        candidate = [item(feed), feed['amount']]
        if path in previous['paths'] and previous['paths'][path] != candidate:
            raise ValueError('Multiple feeds for the same plasma path')
        previous['paths'][path] = candidate
        voltages.add(recipe['eut'])
        witnesses[output['id']].append(recipe['id'])
    if len(voltages) != 1:
        raise ValueError('Expected one Forge-controlled recipe voltage')
    return {'version': 1, 'eut': voltages.pop(), 'names': namespaces, 'items': items,
            'materials': sorted(rows.values(), key=lambda row: row['label'].lower())}, dict(witnesses)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--export', type=Path, default=Path('../OreDictScript/research/recipes.json.gz'))
    parser.add_argument('--gt', type=Path, default=Path('.research/gt-5.09.54.133.zip'))
    parser.add_argument('--output', type=Path, default=Path('source/data/plasma.json'))
    args = parser.parse_args()
    recipes, meta = [], {}
    for section, key, row in records(args.export):
        if section == 'meta' and key in ('gtnhVersion', 'datasetVersionId'):
            meta[key] = row
        elif section == 'recipes' and row.get('machineType') in (MACHINE, 'Fusion Reactor'):
            recipes.append(row)
    with zipfile.ZipFile(args.gt) as archive:
        def read(suffix):
            return archive.read(next(p for p in archive.namelist() if p.endswith(suffix))).decode()
        java = read('/tectech/loader/recipe/Godforge.java')
        elements = read('/MaterialsElements.java')
        machine = read('/MTEPlasmaModule.java')
    groups = source_groups(java, elements, machine)
    names = json.loads(Path('data/registry-names.json').read_text())['names']
    registry = json.loads(Path('../OreDictScript/data/registry-rules.json').read_text())
    recovered = recover(args.gt, registry, {'recipes': recipes}, '.research/EnderIO-ItemAlloy.java',
                        '.research/EnderIO-ModObject.java', '.research/hiddenitems-pinned.cfg',
                        reference_archives=('.research/Draconic-Evolution-1.5.33-GTNH.zip',))
    names.update(recovered['names'])
    result, witnesses = compile_catalog(recipes, groups, names)
    result['source'] = {'recipeVersion': meta['gtnhVersion'], 'targetVersion': '2.9.0-beta-3',
                        'datasetId': meta['datasetVersionId'], 'recipeSource': SOURCE+'tectech/loader/recipe/Godforge.java',
                        'godforgeSha256': hashlib.sha256(java.encode()).hexdigest(),
                        'machineSha256': hashlib.sha256(machine.encode()).hexdigest(),
                        'fusionComparison': 'Exact fluid outputs in the exported Fusion Reactor recipe map.'}
    args.output.write_text(json.dumps(result, indent=2)+'\n')
    Path('.research/plasma-evidence.json').write_text(json.dumps(witnesses, indent=2)+'\n')
    print(len(result['materials']), 'plasma products;', sum(m['fusion'] for m in result['materials']),
          'also produced by regular fusion;', args.output.stat().st_size, 'bytes')


if __name__ == '__main__':
    main()
