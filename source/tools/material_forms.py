"""Registered material forms and reversible, family-aware item resolvers.

Registration is evidence of an item, not evidence of a machine recipe.
"""
import re


def normal(name):
    return re.sub('[^a-z0-9]', '', name.lower())


def descriptor(rid):
    name, sep, damage = rid.rpartition('@')
    return (name, int(damage)) if sep else (rid, 0)


def registry_forms(registry, resources):
    families = {'gt': {}, 'bw': {}, 'gtpp': {}}
    for name, prefixes in registry['prefixes'].items():
        for index, form in enumerate(prefixes):
            if form not in ('null', '___placeholder___'):
                families['gt'][form] = {'name': name, 'prefix': index * 1000}
                families['bw'][form] = {'name': 'bartworks:gt.bwmetagenerated' + form.lower(), 'prefix': 0}
    for component, form in registry.get('gtppComponents', {}).items():
        families['gtpp'][form] = {'template': 'miscutils:item' + component + '%s'}
    families['gt'].update(frameGt={'name': 'gregtech:gt.blockframes', 'prefix': 0},
                          sheetmetal={'name': 'gregtech:gt.sheetmetal', 'prefix': 0})
    families['bw'].update(frameGt={'name': 'gregtech:bw.frames', 'prefix': 0},
                          sheetmetal={'name': 'gregtech:bw.sheetmetal', 'prefix': 0},
                          casingBolted={'name': 'bartworks:bw.werkstoffblockscasing.01', 'prefix': 0},
                          casingRebolted={'name': 'bartworks:bw.werkstoffblockscasingadvanced.01', 'prefix': 0})
    families['gtpp']['frameGt'] = {'template': 'miscutils:blockframegt%s'}
    rows, reverse = {}, {}
    # Prefer the normal GT resolver; explicit cross-family forms remain overrides.
    def add(label, family, suffix, form, rid, priority=0):
        key = normal(label)
        row = rows.setdefault(key, {'name': label, 'family': family, 'dsf': suffix, '_forms': {}, '_rank': {}})
        reverse[rid] = (key, form)
        if form not in row['_forms'] or priority > row['_rank'][form]:
            row['_forms'][form] = rid
            row['_rank'][form] = priority
        if family == 'gt' and row['family'] != 'gt':
            row['family'], row['dsf'], row['name'] = family, suffix, label

    # The pinned BartWorks enum does not enumerate every registered Werkstoff.
    # Recover omitted suffixes from two actual registered forms, never from a
    # guessed material name or a recipe that might refer to an absent item.
    bw_materials = dict(registry.get('bwMaterials', {}))
    for rid, resource in resources.items():
        match = re.fullmatch(r'bartworks:gt\.bwmetageneratedingot@(\d+)', rid)
        if not match or match[1] in bw_materials:
            continue
        label = re.fullmatch(r'(.+) Ingot', resource.get('displayName', ''))
        if label and f'bartworks:gt.bwmetageneratedplate@{match[1]}' in resources:
            bw_materials[match[1]] = label[1]

    for family, names in [('gt', registry['materials']), ('bw', bw_materials)]:
        for suffix, label in names.items():
            for form, resolver in families[family].items():
                rid = resolver['name'] + '@' + str(resolver['prefix'] + int(suffix))
                if rid in resources:
                    add(label, family, int(suffix), form, rid, 2 if family == 'gt' else 1)
    for label in registry.get('gtppMaterials', []):
        for form, resolver in families['gtpp'].items():
            rid = resolver['template'] % normal(label)
            if rid in resources:
                add(label, 'gtpp', normal(label), form, rid)
    names = {normal(label): (label, family, int(suffix)) for family, table in
             [('bw', bw_materials), ('gt', registry['materials'])]
             for suffix, label in table.items()}
    names.update({normal(label): (label, 'gtpp', normal(label))
                  for label in registry.get('gtppMaterials', []) if normal(label) not in names})
    tag_forms = {form: form for family in families.values() for form in family}
    tag_forms.update({'wireGt%02d' % size: 'wire' + str(size) for size in [1, 2, 4, 8, 12, 16]})
    tag_forms.update({'cableGt%02d' % size: 'cable' + str(size) for size in [1, 2, 4, 8, 12, 16]})
    aliases = {}
    for rid, resource in resources.items():
        if rid in reverse:
            for tag in resource.get('tags', []):
                for prefix in sorted(tag_forms, key=len, reverse=True):
                    if tag.startswith(prefix):
                        token = normal(tag[len(prefix):])
                        if token not in names and not token.startswith('any'):
                            aliases[token] = reverse[rid][0]
                        break
    for rid, resource in resources.items():
        if resource.get('kind', 'item') != 'item':
            continue
        for tag in resource.get('tags', []):
            for prefix in sorted(tag_forms, key=len, reverse=True):
                token = normal(tag[len(prefix):])
                if tag.startswith(prefix) and (token in names or token in aliases):
                    if token in aliases:
                        row = rows[aliases[token]]
                        label, family, suffix = row['name'], row['family'], row['dsf']
                    else:
                        label, family, suffix = names[token]
                    add(label, family, suffix, tag_forms[prefix], rid)
                    break
    wire_sizes = [1, 2, 4, 8, 12, 16]
    pipe_sizes = {'Tiny': 0, 'Small': 1, '': 2, 'Large': 3, 'Huge': 4, 'Quadruple': 5, 'Nonuple': 6}
    wire_labels = {}
    for rid, resource in resources.items():
        match = re.fullmatch(r'(1|2|4|8|12|16)x (.+) (Wire|Cable)', resource.get('displayName', resource.get('name', '')))
        if match and rid in reverse:
            wire_labels[normal(match[2])] = reverse[rid][0]
    for rid, resource in resources.items():
        if resource.get('kind', 'item') != 'item':
            continue
        label = resource.get('displayName', resource.get('name', ''))
        match = re.fullmatch(r'(1|2|4|8|12|16)x (.+) (Wire|Cable)', label)
        pipe = re.fullmatch(r'(?:(Tiny|Small|Large|Huge|Quadruple|Nonuple) )?(Restrictive )?(.+) (Fluid|Item) Pipe', label)
        if not match and not pipe:
            continue
        if match:
            size, material, kind = match.groups()
            form, group = kind.lower() + size, 'conductor'
            offset = wire_sizes.index(int(size)) + (6 if kind == 'Cable' else 0)
        else:
            size, restrictive, material, kind = pipe.groups()
            size = size or ''
            group = 'pipe' + kind + ('Restrictive' if restrictive else '')
            form, offset = group + (size or 'Medium'), pipe_sizes[size]
        key = reverse[rid][0] if rid in reverse else wire_labels.get(normal(material), normal(material))
        if key not in rows:
            rows[key] = {'name': material, 'family': 'literal', '_forms': {}, '_rank': {}}
        row = rows[key]
        name, damage = descriptor(rid)
        resolver = {'name': name, 'base': damage - offset}
        if group == 'conductor' and group in row and row[group] != resolver:
            raise ValueError('Conflicting registered ' + group + ' bases: ' + material)
        row.setdefault(group, resolver)
        row['_forms'][form] = rid
        reverse[rid] = (key, form)
    return families, rows, reverse


def solidifier_route(recipe, reverse):
    """The supported, stocked-mold route shared by compilation and source checks."""
    if recipe['machineType'] != 'Fluid Solidifier':
        return None
    consumed = [e for e in recipe['inputs'] if e.get('consumed', True)]
    catalysts = [e for e in recipe['inputs'] if e.get('consumed') is False]
    outputs = recipe['outputs']
    if (len(consumed) != 1 or len(catalysts) != 1 or len(outputs) != 1 or
            consumed[0].get('kind') != 'fluid' or
            catalysts[0].get('kind') != 'item' or
            catalysts[0].get('amount') != 1 or
            not re.fullmatch(r'gregtech:gt\.metaitem\.01@323\d+', catalysts[0]['id']) or
            outputs[0].get('kind') != 'item'):
        return None
    destination = reverse.get(outputs[0]['id'])
    if not destination or destination[1] in ('dust', 'gem'):
        return None
    return destination[0], destination[1], consumed[0]['id']


def resolve(families, material, form):
    if form in material.get('overrides', {}):
        item = material['overrides'][form]
        return item['name'], item['damage']
    match = re.fullmatch(r'(wire|cable)(1|2|4|8|12|16)', form)
    if match:
        item = material['conductor']
        offset = [1, 2, 4, 8, 12, 16].index(int(match[2])) + (6 if match[1] == 'cable' else 0)
        return item['name'], item['base'] + offset
    match = re.fullmatch(r'(pipeFluid|pipeItemRestrictive|pipeItem)(Tiny|Small|Medium|Large|Huge|Quadruple|Nonuple)', form)
    if match:
        item = material[match[1]]
        return item['name'], item['base'] + ['Tiny', 'Small', 'Medium', 'Large', 'Huge', 'Quadruple', 'Nonuple'].index(match[2])
    rule = families[material['family']][form]
    if 'template' in rule:
        return rule['template'] % material['dsf'], 0
    return rule['name'], rule['prefix'] + material['dsf']
