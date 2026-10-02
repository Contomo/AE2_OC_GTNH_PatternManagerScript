"""Find native ingot and liquid producers in the full desktop recipe export.

Extraction, finished-part remelting and container transport are not creation.
Same-material plasma cooling must trace to an independent liquid producer; a
closed heat/cool cycle cannot establish a source. Raw alloy dust is permitted.
Only deduplicated source flags are deployed to OC, not the evidence below.
"""
import argparse
from collections import defaultdict
import gzip
import hashlib
import json
from pathlib import Path

from build_usage import RECOVERY_MACHINES
from import_catalog import records
from material_forms import normal, registry_forms, solidifier_route


NON_PRODUCTION = RECOVERY_MACHINES | {
    'Canner', 'Fluid Canner', 'Tank', 'Packager', 'Unpackager', 'Godforge Upgrades',
}
RAW_FORMS = {
    'dust', 'dustSmall', 'dustTiny', 'dustImpure', 'dustPure', 'rawOre',
    'crushed', 'crushedPurified', 'crushedCentrifuged',
}


def consumed(recipe):
    for entry in recipe['inputs']:
        if entry.get('consumed', True):
            yield entry
            yield from entry.get('alternatives', [])


def rejection(recipe, material, reverse):
    if recipe['machineType'] in NON_PRODUCTION:
        return 'recovery or container transport'
    for entry in consumed(recipe):
        found = reverse.get(entry['id']) if entry.get('kind', 'item') == 'item' else None
        if found and found[0] == material and found[1] not in RAW_FORMS:
            return 'consumes an existing solid or container of this material'
    return None


def example(recipe, dependencies=()):
    result = {'recipe': recipe['id'], 'machine': recipe['machineType']}
    if dependencies:
        result['requiresNativeFluids'] = sorted(dependencies)
    return result


def source_index(recipes, reverse, fluid_materials):
    """One streaming pass, then resolve only same-material liquid dependencies."""
    materials = {}
    candidates = defaultdict(list)

    def material_row(key):
        return materials.setdefault(key, {'solid': {'count': 0}, 'fluids': {}})

    for fluid, keys in fluid_materials.items():
        for key in keys:
            material_row(key)['fluids'][fluid] = {'native': False, 'count': 0, 'rejected': {}}
    for recipe in recipes:
        inputs = list(consumed(recipe))
        for output in recipe['outputs']:
            if output.get('kind') == 'fluid':
                fluid = output['id']
                for key in fluid_materials.get(fluid, ()):
                    row = material_row(key)['fluids'][fluid]
                    row['count'] += 1
                    reason = rejection(recipe, key, reverse)
                    if reason:
                        row['rejected'][reason] = row['rejected'].get(reason, 0) + 1
                        continue
                    dependencies = {e['id'] for e in inputs if e.get('kind') == 'fluid'
                                    and key in fluid_materials.get(e['id'], ())}
                    candidates[key, fluid].append((dependencies, example(recipe, dependencies)))
            elif output.get('kind') == 'item':
                found = reverse.get(output['id'])
                if not found or found[1] not in ('ingot', 'ingotHot'):
                    continue
                key = found[0]
                if (recipe['machineType'] == 'Fluid Solidifier' or rejection(recipe, key, reverse)
                        or any(e.get('kind') == 'fluid' and key in fluid_materials.get(e['id'], ())
                               for e in inputs)):
                    continue
                known_inputs = [reverse[e['id']] for e in inputs
                                if e.get('kind', 'item') == 'item' and e['id'] in reverse]
                # Salvaging an unmapped machine/tool into metal does not prove
                # direct ingot manufacture. Require a raw material or alloy feed.
                if not any(form in RAW_FORMS or (material != key and form in ('ingot', 'ingotHot', 'nugget'))
                           for material, form in known_inputs):
                    continue
                row = material_row(key)['solid']
                row['count'] += 1
                witness = example(recipe)
                if any(material == key and form in RAW_FORMS for material, form in known_inputs):
                    # Prefer direct raw-material evidence over alloy routes.
                    witness['usesMaterialRawForm'] = True
                if 'example' not in row or (witness.get('usesMaterialRawForm')
                                           and not row['example'].get('usesMaterialRawForm')):
                    row['example'] = witness

    native = set()
    pending = dict(candidates)
    while pending:
        ready = {}
        for (key, fluid), routes in pending.items():
            for dependencies, witness in routes:
                if all((key, dep) in native for dep in dependencies):
                    ready[key, fluid] = witness
                    break
        if not ready:
            break
        # Each witness depends only on sources established in an earlier pass.
        for (key, fluid), witness in ready.items():
            row = materials[key]['fluids'][fluid]
            row['native'] = True
            row['example'] = witness
            native.add((key, fluid))
            del pending[key, fluid]
    for key, fluid in pending:
        materials[key]['fluids'][fluid]['unresolvedLiquidRoutes'] = len(pending[key, fluid])
    return dict(sorted(materials.items()))


def build(recipe_export, catalog, registry, resource_index, ore_resources):
    resources = {row['id']: row for row in json.load(gzip.open(resource_index, 'rt'))['resources']}
    for rid, row in json.load(gzip.open(ore_resources, 'rt'))['resources'].items():
        if rid in resources:
            resources[rid]['tags'] = row.get('tags', [])
    _, rows, reverse = registry_forms(registry, resources)
    fluid_materials = defaultdict(set)
    # Registration identifies matching molten/plasma phases. The selected
    # solidifier routes supply exact mappings for differently named fluids.
    for rid, resource in resources.items():
        if resource.get('kind') == 'fluid':
            token = normal(rid.split('.', 1)[1] if rid.startswith(('molten.', 'plasma.')) else rid)
            if token in rows:
                fluid_materials[rid].add(token)
    for recipe in catalog['recipes']:
        route = solidifier_route(recipe, reverse)
        if route:
            fluid_materials[route[2]].add(route[0])

    meta, count = {}, 0

    def recipes():
        nonlocal count
        for section, key, row in records(recipe_export):
            if section == 'meta':
                meta[key] = row
            elif section == 'recipes':
                count += 1
                yield row

    result = source_index(recipes(), reverse, fluid_materials)
    digest = hashlib.sha256(Path(recipe_export).read_bytes()).hexdigest()
    if (meta['datasetVersionId'] != catalog['source']['datasetId']
            or digest != catalog['source']['sha256']):
        raise ValueError('Catalog and material sources came from different recipe exports')
    return {'policy': 'native-material-sources-v1', 'datasetVersionId': meta['datasetVersionId'],
            'recipeExportSha256': digest, 'recipeCount': count, 'materials': result}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('recipes', 'catalog', 'registry', 'resources', 'ore_resources', 'output'):
        parser.add_argument(name)
    args = parser.parse_args()
    catalog = json.load(gzip.open(args.catalog, 'rt'))
    registry = json.loads(Path(args.registry).read_text(encoding='utf-8-sig'))
    result = build(args.recipes, catalog, registry, args.resources, args.ore_resources)
    Path(args.output).write_text(json.dumps(result, indent=2) + '\n')
    fluids = [f for row in result['materials'].values() for f in row['fluids'].values()]
    print(result['recipeCount'], 'recipes;', sum(f['native'] for f in fluids),
          'native liquid sources;', sum(row['solid']['count'] > 0 for row in result['materials'].values()),
          'materials with direct ingot production')
