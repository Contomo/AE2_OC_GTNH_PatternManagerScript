"""Scrape progression evidence from the versioned GTNH BetterQuesting source.

Material availability guidance from quest items, recipe ingredients and ore placement.
Side chapters inherit prerequisite tiers. Ores and dusts count; tools, icons and
rewards do not. Ore access is explicitly marked as an estimate.
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
from build_usage import RECOVERY_MACHINES

DEFINITIONS = json.loads((Path(__file__).parents[1] / 'data' / 'tiers.json').read_text())
NAMES = DEFINITIONS['names']
SOLIDS = {'dust', 'dustSmall', 'dustTiny', 'rawOre', 'crushed', 'crushedPurified', 'crushedCentrifuged', 'nugget', 'ingot', 'ingotHot', 'gem', 'plate', 'plateDouble', 'plateTriple',
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
        # This is availability guidance, not a list of mandatory quest gates.
        # Optional ingredient lists and alternate forms still document a material.
        required = []
        for task in tasks:
            if task.get('requireOnlyOneItem:1', 0):
                alternatives, missing = set(), False
                for name, damage, ore in required_items(task):
                    known = tags.get(ore.lower(), set()) if ore else set()
                    if not known:
                        found = reverse.get(name + '@' + str(damage)) or reverse.get(name)
                        known = {found} if found else set()
                    missing = missing or not known
                    alternatives.update(key for key, form in known)
                # Ingot/dust alternatives of one material are useful evidence.
                # Choosing bronze OR a later material does not unlock both.
                if missing or len(alternatives) != 1:
                    continue
            required.append(task)
        for name, damage, ore in required_items(required):
            if ore:
                known = tags.get(ore.lower(), set())
                if not known:
                    found = reverse.get(name + '@' + str(damage)) or reverse.get(name)
                    known = {found} if found else set()
            else:
                rid = name + '@' + str(damage)
                found = reverse.get(rid) or (reverse.get(name) if damage == 0 else None)
                known = {found} if found else set()
            for key, form in known:
                if not solid(form):
                    continue
                evidence = {'tier': tier, 'quest': path, 'item': name, 'damage': damage, 'form': form, 'kind': 'quest item'}
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


def ore_aliases(reverse, resources):
    tags = {}
    for rid, resource in resources.items():
        if rid in reverse:
            for tag in resource.get('tags', []):
                tags.setdefault(tag, set()).add(reverse[rid])
    for tag, forms in tags.items():
        if len(forms) == 1:
            reverse['oredict:' + tag] = next(iter(forms))


def inherit_tiers(quests, anchors):
    """Follow prerequisite edges for side chapters; do not infer from titles/icons."""
    tiers = dict(anchors)
    while True:
        additions = {}
        for key, (path, quest) in quests.items():
            if key in tiers:
                continue
            refs = [(q['questIDHigh:4'], q['questIDLow:4'])
                    for q in quest.get('preRequisites:9', {}).values()]
            known = [tiers[r] for r in refs if r in tiers]
            logic = quest.get('properties:10', {}).get('betterquesting:10', {}).get('questLogic:8', 'AND')
            if known and (logic == 'OR' or len(known) == len(refs)):
                additions[key] = (min if logic == 'OR' else max)(known, key=NAMES.index)
        if not additions:
            break
        tiers.update(additions)
    return [(path, tiers[key], quest) for key, (path, quest) in quests.items() if key in tiers]


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
        quests, anchors = {}, {}
        for path in sorted(z.namelist()):
            if prefix + 'Quests/' not in path or not path.endswith('.json'):
                continue
            quest = json.loads(z.read(path))
            key = (quest['questIDHigh:4'], quest['questIDLow:4'])
            quests[key] = (path[path.index(prefix):], quest)
            tier = chapters.get(path.rsplit('/', 1)[1])
            if tier:
                anchors[key] = tier
                quest['_tierAnchor'] = True
        yield from inherit_tiers(quests, anchors)


def ingredient_evidence(export, quests, reverse, result):
    """One actual recipe hop covers materials behind required products (e.g. drums).

    Ignore high-voltage alternatives, catalysts, chance byproducts and recycling.
    This augments direct quest evidence without expanding arbitrary recipe trees.
    """
    wanted = {}
    for path, tier, quest in quests:
        if not quest.get('_tierAnchor'): continue
        tasks = [t for t in quest.get('tasks:9', {}).values() if not t.get('requireOnlyOneItem:1', 0)]
        for name, damage, ore in required_items(tasks):
            rid = name + '@' + str(damage)
            wanted.setdefault(rid, []).append((path, tier))
            if damage == 0: wanted.setdefault(name, []).append((path, tier))
    producers, floors = {}, {}
    for section, _, recipe in records(export):
        if section != 'recipes': continue
        if recipe.get('machineType') in RECOVERY_MACHINES or recipe.get('machineType') == 'Arc Furnace':
            continue
        for output in recipe['outputs']:
            found = reverse.get(output['id'])
            if not found or found[1] not in ('ingot', 'ingotHot', 'gem'): continue
            ins = [e for e in recipe['inputs'] if e.get('consumed', True)]
            if not any(e['kind'] == 'item' for e in ins): continue
            if any(e['id'].startswith('gregtech:gt.metatool') or
                   e['id'].startswith('gregtech:gt.blockmachines') and e['id'] not in reverse for e in ins):
                continue
            same = [reverse.get(e['id']) for e in ins]
            # Turning an existing material's dust/ore into ingots does not
            # establish when that material can first be created.
            if any(k and k[0] == found[0] for k in same): continue
            voltage = recipe.get('eut')
            if voltage is None and recipe.get('kind') not in ('crafting', 'crafting_shaped', 'crafting_shapeless', 'furnace', 'smelting'):
                continue
            if output.get('chance', 1) != 1: continue
            eut = voltage or 0
            tier = next((name for name, limit in zip(NAMES, DEFINITIONS['voltages']) if eut <= limit), 'MAX')
            prior = floors.get(found[0])
            if not prior or eut < prior['eut']:
                floors[found[0]] = {'tier': tier, 'eut': eut, 'recipe': recipe['id']}
        if len(recipe['outputs']) != 1: continue
        source = (recipe.get('machineType', '') + ' ' + recipe.get('name', '')).lower()
        if any(word in source for word in ('recycl', 'macerat', 'arc furnace', 'disassembl')): continue
        out = recipe['outputs'][0]
        if out.get('chance', 1) != 1 or out['id'] not in wanted: continue
        ins = [e for e in recipe['inputs'] if e.get('consumed', True)]
        known = {reverse[e['id']][0]: (e['id'], reverse[e['id']][1])
                 for e in ins if e['id'] in reverse and solid(reverse[e['id']][1])}
        producers.setdefault(out['id'], []).append((recipe, known))
    for rid, requirements in wanted.items():
        for path, tier in requirements:
            eligible = [(recipe, known) for recipe, known in producers.get(rid, [])
                        if recipe.get('eut') is None or recipe['eut'] <= DEFINITIONS['voltages'][NAMES.index(tier)]]
            if not eligible: continue
            # Alternative recipes do not prove that every ingredient material is
            # available. Require the material in ALL routes, including routes
            # without a registered material ingredient (which make this empty).
            common = set(eligible[0][1])
            for _, known in eligible[1:]: common.intersection_update(known)
            recipe, known = eligible[0]
            for key in common:
                if key not in floors: continue
                prior = result.get(key)
                if prior and prior.get('form') in ('ingot', 'ingotHot', 'gem', 'dust', 'dustSmall', 'dustTiny'):
                    continue
                if not prior or NAMES.index(tier) < NAMES.index(prior['tier']):
                    item, form = known[key]
                    name, _, damage = item.partition('@')
                    result[key] = {'tier': tier, 'quest': path, 'item': name,
                                   'damage': int(damage or 0), 'form': form,
                                   'kind': 'quest recipe ingredient', 'recipe': recipe['id']}
    return floors


def ore_evidence(archive, quests, rows, result):
    """Read ore placement rules; planet access comes from tiered rocket quests.

    Ore access is an estimate, so direct material/recipe quest evidence takes
    precedence. Overworld placement needs no rocket and is ULV.
    """
    with zipfile.ZipFile(archive) as z:
        dimension_path = next(p for p in z.namelist() if p.endswith('/DimensionDef.java'))
        dimensions = re.findall(r'(?m)^    (\w+)\(new ModDimensionDef', z.read(dimension_path).decode())
        access = {'OW': ('ULV', 'Overworld')}
        for path, tier, quest in quests:
            properties = quest.get('properties:10', {}).get('betterquesting:10', {})
            icon = properties.get('icon:10', {}).get('id:8', '').lower()
            desc = properties.get('desc:8', '')
            if 'rocket' not in icon or not re.search(r'visit|planet|moon|travel', desc, re.I): continue
            arrivals = '\n'.join(paragraph for paragraph in desc.split('\n\n')
                if re.search(r'new (?:planets|places|moons)|can (?:now )?visit|now (?:have|get) access', paragraph, re.I))
            for dimension in dimensions:
                words = re.sub(r'([a-z])([A-Z])', r'\1 \2', dimension).split()
                pattern = r'\b' + r'\s*'.join(map(re.escape, words)) + r'\b'
                if re.search(pattern, arrivals, re.I):
                    prior = access.get(dimension)
                    if not prior or NAMES.index(tier) < NAMES.index(prior[0]): access[dimension] = (tier, path)
        for filename, builder in (('OreMixes.java', 'OreMixBuilder'), ('SmallOres.java', 'SmallOreBuilder')):
            path = next(p for p in z.namelist() if p.endswith('/' + filename))
            source = z.read(path).decode()
            for block in re.split(r'(?m)^    \w+\(new ' + builder, source)[1:]:
                dims = [d.strip() for group in re.findall(r'\.enableInDim\(([^)]*)\)', block)
                        for d in group.split(',')]
                known = [(d, access[d]) for d in dims if d in access]
                if not known: continue
                dimension, (tier, origin) = min(known, key=lambda d: NAMES.index(d[1][0]))
                for material in re.findall(r'\.(?:primary|secondary|inBetween|sporadic|ore)\(Materials\.(\w+)\)', block):
                    key = normal(material)
                    if key not in rows: continue
                    prior = result.get(key)
                    if prior and NAMES.index(prior['tier']) <= NAMES.index(tier): continue
                    result[key] = {'tier': tier, 'kind': 'ore access estimate', 'source': path,
                                   'dimension': dimension, 'accessSource': origin}


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
    p.add_argument('--gt-source', required=True)
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
    ore_aliases(reverse, resources)
    quests = list(quest_records(args.archive))
    materials = scrape(quests, reverse, resources)
    floors = ingredient_evidence(args.recipes, quests, reverse, materials)
    ore_evidence(args.gt_source, quests, rows, materials)
    for key, evidence in materials.items():
        floor = floors.get(key)
        if floor and evidence['kind'] != 'quest item' and NAMES.index(floor['tier']) > NAMES.index(evidence['tier']):
            evidence['accessTier'] = evidence['tier']
            evidence['tier'] = floor['tier']
            evidence['productionFloor'] = floor
    with open(args.archive, 'rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    output = {'policy': 'quest-and-ore-access-v2', 'packVersion': args.pack_version,
              'source': 'https://github.com/GTNewHorizons/GT-New-Horizons-Modpack/tree/' + args.commit + '/config/betterquesting/DefaultQuests',
              'commit': args.commit, 'archiveSha256': digest, 'gtSourceSha256': hashlib.sha256(Path(args.gt_source).read_bytes()).hexdigest(), 'materials': materials}
    Path(args.output).write_text(json.dumps(output, indent=2) + '\n', encoding='utf-8')
    print(f'{len(materials)} / {len(rows)} registered materials have quest or ore-access tier evidence')
    for key in ('infinity', 'titanium', 'rhodiumplatedpalladium', 'copper', 'iron'):
        print(key, materials.get(key))


if __name__ == '__main__':
    main()
