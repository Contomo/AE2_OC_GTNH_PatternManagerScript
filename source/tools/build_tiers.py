"""Scrape progression evidence from the versioned GTNH BetterQuesting source.

Earliest tier-chapter requirement for a registered solid material form. This is
quest progression evidence, not a proof of earliest obtainable material. Icons,
rewards, dusts, tools and non-tier chapters never become availability evidence.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
import zipfile

from import_catalog import records
from material_forms import normal, registry_forms

DEFINITIONS = json.loads((Path(__file__).parents[1] / 'data' / 'tiers.json').read_text())
NAMES = DEFINITIONS['names']
SOLIDS = {'ingot', 'ingotHot', 'gem', 'plate', 'plateDouble', 'plateTriple',
          'plateQuadruple', 'plateQuintuple', 'plateDense', 'plateSuperdense',
          'stick', 'stickLong', 'wireFine', 'foil', 'ring', 'bolt', 'screw',
          'round', 'rotor', 'gearGt', 'gearGtSmall', 'itemCasing', 'sheetmetal',
          'frameGt', 'spring', 'springSmall', 'block'}


def solid(form):
    return form in SOLIDS or form.startswith(('wire', 'cable', 'pipe'))


def required_items(value):
    """Only call on tasks. BetterQuesting uses NBT-type suffixes on JSON keys."""
    if isinstance(value, dict):
        row = {key.split(':')[0]: v for key, v in value.items()}
        if isinstance(row.get('id'), str) and row.get('Count', 0) > 0:
            yield row['id'].lower(), row.get('Damage', 0), row.get('OreDict', '')
        for child in value.values():
            yield from required_items(child)
    elif isinstance(value, list):
        for child in value:
            yield from required_items(child)


def scrape(quests, reverse, resources):
    result = {}
    tags = {}
    for rid, resource in resources.items():
        if rid in reverse:
            for tag in resource.get('tags', []):
                tags.setdefault(tag.lower(), set()).add(reverse[rid])
    for path, tier, quest in quests:
        tasks = list(quest.get('tasks:9', {}).values())
        properties = quest.get('properties:10', {}).get('betterquesting:10', {})
        if properties.get('taskLogic:8') == 'OR' and len(tasks) > 1:
            continue
        required = [t for t in tasks if 'optional' not in t.get('taskID:8', '')
                    and not t.get('requireOnlyOneItem:1', 0)]
        for name, damage, ore in required_items(required):
            if ore:
                known = tags.get(ore.lower(), set())
            else:
                rid = name + '@' + str(damage)
                found = reverse.get(rid) or (reverse.get(name) if damage == 0 else None)
                known = {found} if found else set()
            for key, form in known:
                if not solid(form):
                    continue
                evidence = {'tier': tier, 'quest': path, 'item': name, 'damage': damage, 'form': form}
                prior = result.get(key)
                if not prior or (NAMES.index(tier), path) < (NAMES.index(prior['tier']), prior['quest']):
                    result[key] = evidence
    return result


def block_aliases(export, reverse, resources):
    """Connect untagged storage blocks through their actual compression recipes."""
    def is_block(rid, material):
        label = normal(resources.get(rid, {}).get('displayName', ''))
        return label in ('blockof' + material, material + 'block', 'block' + material)
    for section, _, recipe in records(export):
        if section != 'recipes':
            continue
        ins = [e for e in recipe['inputs'] if e.get('consumed', True)]
        outs = recipe['outputs']
        if not ins or not outs or any(e['kind'] != 'item' for e in ins + outs):
            continue
        for known_side, block_side in ((ins, outs), (outs, ins)):
            if len(block_side) != 1:
                continue
            known = [reverse.get(e['id']) for e in known_side]
            if all(k and k[1] in ('ingot', 'gem', 'block') for k in known):
                materials = {k[0] for k in known}
                if len(materials) == 1:
                    key = next(iter(materials))
                    for e in block_side:
                        if is_block(e['id'], key) and e['id'] not in reverse:
                            reverse[e['id']] = (key, 'block')


def quest_records(archive):
    with zipfile.ZipFile(archive) as z:
        chapters = {}
        prefix = 'config/betterquesting/DefaultQuests/'
        for path in z.namelist():
            if prefix + 'QuestLines/' not in path or not path.endswith('.json'):
                continue
            chapter = path.split('/QuestLines/')[1].split('/')[0]
            match = re.match(r'Tier\d+(' + '|'.join(map(re.escape, NAMES)) + r')-', chapter)
            tier = match[1] if match else 'ULV' if chapter.startswith(('Tier05Steam-', 'Tier0StoneAge-')) else None
            if tier:
                basename = path.rsplit('/', 1)[1]
                prior = chapters.get(basename)
                if not prior or NAMES.index(tier) < NAMES.index(prior):
                    chapters[basename] = tier
        for path in sorted(z.namelist()):
            basename = path.rsplit('/', 1)[1]
            if prefix + 'Quests/' in path and basename in chapters:
                relative = path[path.index(prefix):]
                yield relative, chapters[basename], json.loads(z.read(path))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('archive')
    p.add_argument('--registry', required=True)
    p.add_argument('--resources', required=True)
    p.add_argument('--ore-resources', required=True)
    p.add_argument('--recipes', required=True)
    p.add_argument('--pack-version', required=True)
    p.add_argument('--commit', required=True)
    p.add_argument('--output', required=True)
    args = p.parse_args()
    with zipfile.ZipFile(args.archive) as z:
        roots = {path.split('/')[0] for path in z.namelist()}
        if len(roots) != 1 or not next(iter(roots)).endswith('-' + args.commit):
            raise ValueError('Quest archive does not match the declared source commit')
    resources = {r['id']: r for r in json.load(gzip.open(args.resources, 'rt'))['resources']}
    ores = json.load(gzip.open(args.ore_resources, 'rt'))['resources']
    for rid, r in resources.items():
        r['tags'] = ores.get(rid, {}).get('tags', [])
    registry = json.loads(Path(args.registry).read_text(encoding='utf-8-sig'))
    _, rows, reverse = registry_forms(registry, resources)
    block_aliases(args.recipes, reverse, resources)
    materials = scrape(quest_records(args.archive), reverse, resources)
    with open(args.archive, 'rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    output = {'policy': 'first-solid-task-v1', 'packVersion': args.pack_version,
              'source': 'https://github.com/GTNewHorizons/GT-New-Horizons-Modpack/tree/' + args.commit + '/config/betterquesting/DefaultQuests',
              'commit': args.commit, 'archiveSha256': digest, 'materials': materials}
    Path(args.output).write_text(json.dumps(output, indent=2) + '\n', encoding='utf-8')
    print(f'{len(materials)} / {len(rows)} registered materials have solid-form tier-chapter evidence')
    for key in ('infinity', 'titanium', 'rhodiumplatedpalladium', 'copper', 'iron'):
        print(key, materials.get(key))


if __name__ == '__main__':
    main()
