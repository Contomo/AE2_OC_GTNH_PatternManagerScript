"""Index direct, non-recycling consumers of registered material items.

This is a desktop build step. The full recipe export never runs on OC.
"""
import argparse
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


def is_recycling(recipe, material, reverse):
    """Reject disposal and recovery, while keeping actual product recipes."""
    if recipe.get('machineType') in RECOVERY_MACHINES:
        return True
    outputs = recipe.get('outputs') or []
    normalized_material = re.sub(r'[^a-z0-9]', '', material.lower())
    def recovered(output):
        if output.get('kind') == 'fluid':
            fluid = output.get('id', '').lower()
            if fluid.startswith(('molten.', 'plasma.')):
                return re.sub(r'[^a-z0-9]', '', fluid.split('.', 1)[1]) == normalized_material
            return False
        found = reverse.get(output.get('id'))
        return found is not None and found[0] == material and found[1] in RECOVERY_FORMS
    return bool(outputs) and all(
        recovered(output) for output in outputs
    )


def usage_counts(recipes, reverse):
    counts = {}
    for recipe in recipes:
        candidate_ids = set()
        for item in recipe.get('inputs', []):
            if item.get('id') in reverse:
                candidate_ids.add(item['id'])
            for alternative in item.get('alternatives', []):
                if alternative.get('id') in reverse:
                    candidate_ids.add(alternative['id'])
        for rid in candidate_ids:
            result = counts.setdefault(rid, [0, 0])
            result[1 if is_recycling(recipe, reverse[rid][0], reverse) else 0] += 1
    return counts


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

    counts = usage_counts(recipes(), reverse)
    return {
        'policy': 'direct-nonrecycling-v1',
        'datasetVersionId': source['datasetVersionId'],
        'recipeExportSha256': hashlib.sha256(Path(recipe_export).read_bytes()).hexdigest(),
        'recipeCount': recipe_count,
        'registeredItems': len(reverse),
        'counts': dict(sorted(counts.items())),
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
    useful = sum(counts[0] > 0 for counts in result['counts'].values())
    print(result['recipeCount'], 'recipes;', useful, 'registered items with direct non-recycling uses')
