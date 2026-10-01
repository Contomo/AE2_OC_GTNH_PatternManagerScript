"""Find material forms that ultimately feed a non-recycling product.

This is a desktop build step. The full recipe export never runs on OC.
"""
import argparse
from collections import defaultdict, deque
import gzip
import hashlib
import json
import re
from pathlib import Path

from import_catalog import records
from material_forms import registry_forms


RECOVERY_FORMS = {
    'nugget', 'ingot', 'ingotHot', 'dust', 'dustSmall', 'dustTiny',
    'dustImpure', 'dustPure', 'cell', 'cellMolten',
}
RECOVERY_MACHINES = {
    'Macerator', 'Fluid Extractor', 'Thaumcraft Essentia Smelting', 'Recycler',
}
ARC_WASTE_MATERIALS = {'ash', 'ashdark'}


def is_recovered_output(output, material, reverse):
    normalized_material = re.sub(r'[^a-z0-9]', '', material.lower())
    if output.get('kind') == 'fluid':
        fluid = output.get('id', '').lower()
        if fluid.startswith(('molten.', 'plasma.')):
            return re.sub(r'[^a-z0-9]', '', fluid.split('.', 1)[1]) == normalized_material
        return False
    found = reverse.get(output.get('id'))
    return found is not None and found[0] == material and found[1] in RECOVERY_FORMS


def is_recycling(recipe, material, reverse):
    """Reject disposal and recovery, while keeping actual product recipes."""
    if recipe.get('machineType') in RECOVERY_MACHINES:
        return True
    outputs = recipe.get('outputs') or []
    if recipe.get('machineType') == 'Arc Furnace' and outputs and all(
            output.get('kind') == 'item'
            and (found := reverse.get(output.get('id'))) is not None
            and found[0].lower() in ARC_WASTE_MATERIALS for output in outputs):
        return True
    return bool(outputs) and all(is_recovered_output(output, material, reverse)
                                 for output in outputs)


def usage_index(recipes, reverse):
    counts = {}
    dependents = defaultdict(set)
    useful = set()
    for recipe in recipes:
        candidate_ids = set()
        for item in recipe.get('inputs', []):
            if item.get('id') in reverse:
                candidate_ids.add(item['id'])
            for alternative in item.get('alternatives', []):
                if alternative.get('id') in reverse:
                    candidate_ids.add(alternative['id'])
        for rid in candidate_ids:
            material = reverse[rid][0]
            result = counts.setdefault(rid, [0, 0])
            if is_recycling(recipe, material, reverse):
                result[1] += 1
                continue
            result[0] += 1
            for output in recipe.get('outputs', []):
                if is_recovered_output(output, material, reverse):
                    continue
                next_item = reverse.get(output.get('id')) if output.get('kind') == 'item' else None
                if next_item and next_item[0] == material:
                    dependents[output['id']].add(rid)
                else:
                    useful.add(rid)
    queue = deque(useful)
    while queue:
        for parent in dependents[queue.popleft()] - useful:
            useful.add(parent)
            queue.append(parent)
    return counts, useful


def build(recipe_export, registry, resource_index, ore_resources):
    source = {}
    for section, key, value in records(recipe_export):
        if section == 'meta':
            source[key] = value
        if section == 'resources':
            break
    resources = {row['id']: row for row in json.load(gzip.open(resource_index, 'rt'))['resources']}
    ores = json.load(gzip.open(ore_resources, 'rt'))['resources']
    for rid, row in ores.items():
        if rid in resources:
            resources[rid]['tags'] = row.get('tags', [])
    _, _, reverse = registry_forms(registry, resources)
    recipe_count = 0

    def recipes():
        nonlocal recipe_count
        for section, _, row in records(recipe_export):
            if section == 'recipes':
                recipe_count += 1
                yield row

    counts, useful = usage_index(recipes(), reverse)
    return {
        'policy': 'reachable-nonrecycling-v3',
        'datasetVersionId': source['datasetVersionId'],
        'recipeExportSha256': hashlib.sha256(Path(recipe_export).read_bytes()).hexdigest(),
        'recipeCount': recipe_count,
        'registeredItems': len(reverse),
        'counts': dict(sorted(counts.items())),
        'useful': sorted(useful),
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('recipes')
    parser.add_argument('registry')
    parser.add_argument('resources')
    parser.add_argument('ore_resources')
    parser.add_argument('output')
    args = parser.parse_args()
    registry = json.loads(Path(args.registry).read_text(encoding='utf-8-sig'))
    result = build(args.recipes, registry, args.resources, args.ore_resources)
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    Path(args.output).write_text(json.dumps(result, separators=(',', ':')) + '\n')
    print(result['recipeCount'], 'recipes;', len(result['useful']),
          'registered items with a path to a non-recycling product')
