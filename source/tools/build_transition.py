"""Derive compact implosion cleanup rules from the recipe export, not examples.

Electric recipes prove which extra inputs are explosives. Secondary tiny dusts
are optional AE outputs to omit, even when the electric machine produces them.
"""
import argparse
import gzip
import json
from collections import defaultdict
from pathlib import Path

from import_catalog import records


def identity(stack):
    return stack['kind'], stack['id'], stack.get('amount', 1)


def derive(recipes, resources):
    old = [r for r in recipes if r['machineType'] == 'Implosion Compressor']
    electric = defaultdict(list)
    for r in recipes:
        if r['machineType'] == 'Electric Implosion Compressor':
            electric[tuple(map(identity, r['inputs']))].append(r)
    explosives, secondary = {}, {}
    matched = 0
    for recipe in old:
        for index, stack in enumerate(recipe['inputs']):
            remaining = tuple(identity(s) for i, s in enumerate(recipe['inputs']) if i != index)
            if any(identity(r['outputs'][0]) == identity(recipe['outputs'][0])
                   for r in electric[remaining]):
                explosives[stack['id']] = stack['displayName']
                matched += 1
                break
        for stack in recipe['outputs'][1:]:
            tags = resources.get(stack['id'], {}).get('tags', [])
            if any(tag.startswith('dustTiny') for tag in tags):
                secondary[stack['id']] = stack['displayName']
    if not matched or not explosives or not secondary:
        raise ValueError('Missing implosion, electric counterpart or tiny-dust evidence')
    return {'explosives': dict(sorted(explosives.items())),
            'secondary': dict(sorted(secondary.items())),
            'evidence': {'implosionRecipes': len(old), 'matchedRecipes': matched}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('export', type=Path)
    parser.add_argument('ores', type=Path)
    parser.add_argument('--output', type=Path, default=Path('source/data/transition.json'))
    args = parser.parse_args()
    recipes, version = [], None
    for section, key, row in records(args.export):
        if section == 'meta' and key == 'gtnhVersion':
            version = row
        elif section == 'recipes' and 'Implosion Compressor' in row.get('machineType', ''):
            recipes.append(row)
    with gzip.open(args.ores, 'rt', encoding='utf-8') as stream:
        resources = json.load(stream)['resources']
    result = derive(recipes, resources)
    result['evidence']['sourceVersion'] = version
    args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
