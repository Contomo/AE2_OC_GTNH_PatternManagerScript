"""Extract versioned recipe evidence from a normalized Factory Flow export.

Desktop build step only. This deliberately does not invent recipes, resolve ore
alternatives, discard catalysts, or turn NEI coordinates into a crafting grid.
Mode compilers must make those decisions explicitly before producing an in-memory manifest.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path


def records(path):
    """Read the export's one-record-per-line layout without its runtime tables."""
    opener = gzip.open if str(path).endswith('.gz') else open
    section = None
    closed = False
    sections = set()
    with opener(path, 'rt', encoding='utf-8-sig') as stream:
        if stream.readline().strip() != '{':
            raise ValueError('Expected the normalized one-record-per-line Factory Flow export')
        for number, line in enumerate(stream, 2):
            text = line.strip().rstrip(',')
            if not text:
                continue
            if closed:
                raise ValueError(f'Trailing data after export at line {number}')
            if text == '}':
                if section is not None:
                    raise ValueError('Unterminated record array')
                closed = True
                continue
            if text == ']':
                section = None
                continue
            if text.startswith('"') and section is None:
                name, value = text.split(':', 1)
                name = json.loads(name)
                if value.strip() == '[':
                    section = name
                    sections.add(name)
                else:
                    try:
                        yield 'meta', name, json.loads(value)
                    except json.JSONDecodeError as exc:
                        raise ValueError(f'Unsupported metadata layout at line {number}') from exc
            elif section in ('recipes', 'resources') and text.startswith('{'):
                try:
                    row = json.loads(text)
                except json.JSONDecodeError as exc:
                    raise ValueError(f'Record must fit one line (line {number})') from exc
                yield section, row['id'], row
    if not closed or section is not None or not {'resources', 'recipes'} <= sections:
        raise ValueError('Incomplete normalized export: resources, recipes and closing object required')


def compact_resource(row):
    # Retain identifier/NBT/ore-membership evidence; only presentation assets go.
    return {k: v for k, v in row.items() if k not in ('iconPath', 'dominantColor', 'tooltip')}


def import_catalog(path, machines, target_version):
    machines = set(machines)
    if not target_version:
        raise ValueError('Target version is required')
    if not machines:
        raise ValueError('Select at least one exact machine/recipe-map name')
    resources, recipes, meta, counts = {}, {}, {}, dict.fromkeys(sorted(machines), 0)
    for section, key, row in records(path):
        if section == 'meta':
            if key in ('schemaVersion', 'datasetVersionId', 'gtnhVersion', 'sourceInfo'):
                meta[key] = row
        elif section == 'resources':
            if key in resources:
                raise ValueError(f'Duplicate resource ID: {key}')
            resources[key] = compact_resource(row)
        else:
            machine = row.get('source', {}).get('recipeMap') or row.get('machineType')
            if machine not in machines:
                continue
            if key in recipes:
                raise ValueError(f'Duplicate recipe ID: {key}')
            if not row.get('inputs') or not row.get('outputs'):
                raise ValueError(f'Recipe lacks inputs/outputs: {key}')
            # Ingredient rows are retained intact, including alternatives,
            # consumed:false, chance, optional, NBT and NEI slot coordinates.
            recipes[key] = {k: row[k] for k in (
                'id', 'name', 'kind', 'category', 'machineType', 'inputs', 'outputs',
                'source', 'durationTicks', 'eut', 'minimumTier', 'nei', 'notes') if k in row}
            counts[machine] += 1
    if not meta.get('gtnhVersion') or not meta.get('datasetVersionId'):
        raise ValueError('Source recipe version and dataset ID are required')
    absent = [name for name, count in counts.items() if count == 0]
    if absent:
        raise ValueError('No actual recipes for selected map(s): ' + ', '.join(absent))
    if not resources:
        raise ValueError('Source has no resource registry')
    # Include only referenced resources, closing over ore-dictionary alternatives.
    wanted = set()
    pending = []

    def references(value):
        if isinstance(value, dict):
            if isinstance(value.get('id'), str) and value['id'] in resources and value['id'] not in wanted:
                wanted.add(value['id'])
                pending.append(value['id'])
            for child in value.values():
                references(child)
        elif isinstance(value, list):
            for child in value:
                references(child)

    for recipe in recipes.values():
        references(recipe['inputs'])
        references(recipe['outputs'])
    while pending:
        rid = pending.pop()
        references(resources[rid])
    with open(path, 'rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    return {
        'version': 1,
        'source': {'datasetId': meta['datasetVersionId'], 'recipeVersion': meta['gtnhVersion'],
                   'targetVersion': target_version, 'sha256': digest, 'sourceInfo': meta.get('sourceInfo'),
                   'versionMatchesTarget': meta['gtnhVersion'] == target_version},
        'machineCounts': counts,
        'resources': {rid: resources[rid] for rid in sorted(wanted)},
        'recipes': [recipes[rid] for rid in sorted(recipes)],
        'status': 'recipe-evidence-only; mode compilation and in-world verification still required',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--machine', action='append', required=True, help='Exact recipe-map name; repeat to select more')
    parser.add_argument('--target-version', default='2.9.0-beta-3')
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    if args.source.resolve() == args.out.resolve():
        parser.error('Output must not overwrite the source export')
    data = import_catalog(args.source, args.machine, args.target_version)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.out.with_name(args.out.name + '.tmp')
    opener = gzip.open if str(args.out).endswith('.gz') else open
    with opener(temporary, 'wt', encoding='utf-8') as stream:
        json.dump(data, stream, ensure_ascii=False, separators=(',', ':'))
    temporary.replace(args.out)
    print(json.dumps({k: data[k] for k in ('source', 'machineCounts', 'status')}, indent=2))
    print(f"Retained {len(data['recipes'])} recipes and {len(data['resources'])} referenced resources")


if __name__ == '__main__':
    main()
