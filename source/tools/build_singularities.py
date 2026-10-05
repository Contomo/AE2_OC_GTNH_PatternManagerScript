"""Trace the pinned Eternal crafting chain and compile its solid machine routes.

Only identities, counts and shared rule indices are deployed. Extreme recipes
are dependency evidence; their grids are never emitted as patterns.
"""
import argparse
from collections import defaultdict
import gzip
import hashlib
import json
from pathlib import Path
import re
import zipfile

from import_catalog import records
from material_forms import descriptor, normal, registry_forms


def read_source(archive, suffix):
    with zipfile.ZipFile(archive) as z:
        return z.read(next(n for n in z.namelist() if n.endswith(suffix))).decode('utf-8')


def crafting_chain(java, resources, root='eternalsingularity:eternal_singularity', group_labels=None):
    graph = {}
    calls = re.findall(r'ExtremeCraftingManager\.getInstance\(\)\.addExtremeShapedOreRecipe\((.*?)\);', java, re.S)
    for call in calls:
        refs = []
        for mod, name, amount, damage in re.findall(
                r'getModItem\((\w+)\.ID, "([^"]+)", (\d+), (\d+)\)', call):
            rid = (mod + ':' + name).lower() + ('@' + damage if int(damage) else '')
            refs.append(rid)
        if refs:
            if refs[0] in graph:
                raise ValueError('Multiple extreme routes for ' + refs[0])
            graph[refs[0]] = refs[1:]
    if root not in graph:
        raise ValueError('Eternal crafting root missing from source')
    groups = []
    for combined in graph[root]:
        if combined not in graph or 'singularity' not in combined:
            continue
        leaves = [rid for rid in graph[combined]
                  if resources.get(rid, {}).get('displayName', '').endswith('Singularity')]
        if not leaves or any(rid in graph for rid in leaves):
            raise ValueError('Unexpected nested or empty singularity group: ' + combined)
        label = resources.get(combined, {}).get('displayName')
        if not label and group_labels:
            label = group_labels.get(descriptor(combined)[1])
        if not label:
            raise ValueError('Missing combined singularity display name: ' + combined)
        groups.append({'id': combined, 'label': label, 'leaves': leaves})
    leaves = [rid for group in groups for rid in group['leaves']]
    if not groups or len(leaves) != len(set(leaves)):
        raise ValueError('Missing groups or duplicate base singularities')
    return groups


def block_registrations(draconic, projectred):
    """Recover names from the two registration styles absent in getModItem refs."""
    names = {}
    constants = read_source(draconic, '/common/lib/Strings.java')
    strings = dict(re.findall(r'String\s+(\w+)\s*=\s*"([^"]+)"', constants))
    refs = read_source(draconic, '/common/lib/References.java')
    domain = re.search(r'String MODID = "([^"]+)"', refs)[1]
    registration = read_source(draconic, '/common/ModBlocks.java')
    if 'GameRegistry.registerBlock(block, name.substring(name.indexOf(":") + 1))' not in registration:
        raise ValueError('Unknown Draconic block registration layout')
    with zipfile.ZipFile(draconic) as z:
        for path in z.namelist():
            if path.endswith('.java'):
                text = z.read(path).decode('utf-8')
                if 'ModBlocks.register(this)' in text:
                    for constant in re.findall(r'setBlockName\(Strings\.(\w+)\)', text):
                        name = domain + ':' + strings[constant]
                        names[name.lower()] = name
    module = read_source(projectred, '/ProjectRedExploration.scala')
    domain = re.search(r'modid = "([^"]+)"', module)[1]
    blocks = read_source(projectred, '/exploration/blocks.scala')
    for name in re.findall(r'extends BlockCore\("([^"]+)"', blocks):
        name = domain + ':' + name
        names[name.lower()] = name
    return names


def compile_routes(recipes, resources, groups, names, registry, tiers):
    by_output = defaultdict(list)
    for recipe in recipes:
        if recipe['machineType'] in ('Neutronium Compressor', 'Compressor') and len(recipe['outputs']) == 1:
            by_output[recipe['outputs'][0]['id']].append(recipe)
    _, materials, reverse = registry_forms(registry, resources)
    items, item_index, family_names, rules, rule_index, rows = [], {}, [], [], {}, []
    name_index = {}

    def item(stack):
        rid = stack['id']
        if stack['kind'] != 'item' or stack.get('tag') or stack.get('nbt'):
            raise ValueError('Unsupported tagged or non-item singularity ingredient: ' + rid)
        if rid not in item_index:
            raw_name, damage = descriptor(rid)
            name = names.get(raw_name)
            if name is None:
                if not raw_name.startswith(('minecraft:', 'gregtech:')):
                    raise ValueError('Unverified registry spelling: ' + raw_name)
                name = raw_name
            if name not in name_index:
                name_index[name] = len(family_names) + 1
                family_names.append(name)
            item_index[rid] = len(items) + 1
            items.append({'name': name_index[name], 'damage': damage, 'label': stack['displayName']})
        return item_index[rid]

    def rule(route):
        count = route['inputs'][0]['amount']
        output = route['outputs'][0]['amount']
        key = count, output, route['eut']
        if key not in rule_index:
            rule_index[key] = len(rules) + 1
            rules.append({'input': count, 'output': output, 'eut': route['eut']})
        return rule_index[key]

    for group_index, group in enumerate(groups, 1):
        for rid in group['leaves']:
            native = [r for r in by_output[rid] if r['machineType'] == 'Neutronium Compressor'
                      and len(r['inputs']) == 1 and r['inputs'][0]['kind'] == 'item']
            if len(native) != 1:
                raise ValueError('Expected one solid neutronium route: ' + rid)
            route = native[0]
            block = route['inputs'][0]
            candidates = []
            for recipe in by_output[block['id']]:
                if recipe['machineType'] != 'Compressor' or len(recipe['inputs']) != 1:
                    continue
                ingredient = recipe['inputs'][0]
                tags = resources.get(ingredient['id'], {}).get('tags', [])
                ordinary = any(tag.startswith(('ingot', 'gem', 'dust')) for tag in tags)
                # Quicksilver has no ore tags. Its explicit many-raw-items to
                # one-block route is still evidence; do not invent a tag for it.
                ordinary = ordinary or (ingredient['amount'] > 1 and recipe['outputs'][0]['amount'] == 1)
                if ingredient['kind'] == 'item' and ingredient.get('consumed', True) and ordinary:
                    candidates.append(recipe)
            if not candidates:
                raise ValueError('No ordinary ingot/gem/dust compressor route: ' + block['id'])
            # Vanilla gem routes beat purified/industrial alternatives. Equal
            # alternatives remain available as a selectable input, not extra patterns.
            candidates.sort(key=lambda r: (not r['inputs'][0]['id'].startswith('minecraft:'),
                                           r['inputs'][0]['amount'], r['inputs'][0]['id']))
            primary = candidates[0]
            raw = primary['inputs'][0]
            key = reverse.get(raw['id'], (normal(resources.get(raw['id'], {}).get('material', '')), None))[0]
            tier = tiers.get(key, {})
            row = {'label': route['outputs'][0]['displayName'].removesuffix(' Singularity'),
                   'group': group_index, 'raw': item(raw), 'block': item(block),
                   'singularity': item(route['outputs'][0]), 'blocks': block['amount'],
                   'yield': route['outputs'][0]['amount'], 'compressor': rule(primary), 'eut': route['eut']}
            if tier:
                row['tier'], row['tierSource'] = tier['tier'], tier.get('kind')
            if len(candidates) > 1 and all('ingotUnstable' in resources.get(
                    r['inputs'][0]['id'], {}).get('tags', []) for r in candidates):
                row['alternatives'] = [{'key': 'mobius' if r['inputs'][0]['displayName'].startswith('Mobius') else 'unstable',
                                        'raw': item(r['inputs'][0]), 'compressor': rule(r)} for r in candidates]
            rows.append(row)
    return {'names': family_names, 'items': items, 'rules': rules,
            'groups': [g['label'] for g in groups], 'materials': rows}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('export', 'core', 'registry', 'ores', 'names', 'tiers', 'eternal', 'draconic', 'projectred'):
        parser.add_argument(name, type=Path)
    parser.add_argument('--output', type=Path, default=Path('source/data/singularities.json'))
    args = parser.parse_args()
    recipes, resources, meta = [], {}, {}
    for section, key, row in records(args.export):
        if section == 'meta' and key in ('datasetVersionId', 'gtnhVersion'):
            meta[key] = row
        elif section == 'resources':
            resources[key] = {k: row[k] for k in ('id', 'kind', 'displayName') if k in row}
        elif section == 'recipes' and row.get('machineType') in ('Compressor', 'Neutronium Compressor'):
            recipes.append(row)
    with gzip.open(args.ores, 'rt') as stream:
        for rid, resource in json.load(stream)['resources'].items():
            if rid in resources:
                resources[rid].update(tags=resource.get('tags', []), material=resource.get('material', ''))
    java = read_source(args.core, '/scripts/ScriptAvaritia.java')
    lang = read_source(args.eternal, '/en_US.lang')
    group_labels = {int(number): label for number, label in re.findall(
        r'^item\.combined\.singularity\.(\d+)\.name=(.+)$', lang, re.M)}
    groups = crafting_chain(java, resources, group_labels=group_labels)
    names = json.loads(args.names.read_text())['names']
    names.update(block_registrations(args.draconic, args.projectred))
    result = compile_routes(recipes, resources, groups, names, json.loads(args.registry.read_text()),
                            json.loads(args.tiers.read_text())['materials'])
    result['version'] = 1
    result['source'] = {'recipeVersion': meta['gtnhVersion'], 'targetVersion': '2.9.0-beta-3',
                        'datasetId': meta['datasetVersionId'], 'baseSingularities': len(result['materials']),
                        'combinedSingularities': len(groups), 'root': 'Eternal Singularity',
                        'chainSource': 'https://github.com/GTNewHorizons/NewHorizonsCoreMod/blob/2.9.61/src/main/java/com/dreammaster/scripts/ScriptAvaritia.java',
                        'batchPolicy': 'One singularity per pattern; block recipes follow global batch settings.'}
    result['evidence'] = {'exports': {}, 'chain': hashlib.sha256(java.encode()).hexdigest()}
    for path in (args.export, args.core, args.ores, args.names, args.eternal, args.draconic, args.projectred):
        with path.open('rb') as stream:
            result['evidence']['exports'][path.name] = hashlib.file_digest(stream, 'sha256').hexdigest()
    args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(len(result['materials']), 'base singularities;', len(result['rules']), 'shared compressor rules;',
          len(result['items']), 'shared items;', args.output.stat().st_size, 'bytes')


if __name__ == '__main__':
    main()
