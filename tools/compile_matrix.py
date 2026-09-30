"""Desktop-only compiler: material rows + shared forms/items/recipe rules.

The normalized oracle export is evidence, never the deployed runtime library.
No machine recipe is inferred merely because an item is registered.
"""
import argparse
import gzip
import hashlib
import json
import re
from pathlib import Path
from material_forms import descriptor, registry_forms, resolve


def compile_matrix(catalog, registry, compatible_targets=(), compatibility_basis='', resources=None, registry_names=None):
    resources = dict(resources or {})
    for rid, resource in catalog['resources'].items():
        resources[rid] = {**resources.get(rid, {}), **resource}
    # Recipe item IDs are also registration evidence for focused fixture imports.
    for recipe in catalog['recipes']:
        for e in recipe['inputs'] + recipe['outputs']:
            if e['kind'] == 'item':
                resources.setdefault(e['id'], {'kind': 'item'})
    families, rows, reverse = registry_forms(registry, resources)
    items, item_index, rules, observations = [], {}, {}, {}

    def literal(rid):
        if rid not in item_index:
            name, damage = descriptor(rid)
            item = {'name': name, 'damage': damage}
            if resources.get(rid, {}).get('displayName'):
                item['label'] = resources[rid]['displayName']
            if name == 'gregtech:gt.metaitem.01' and damage in (1649, 2649):
                item['option'] = 'pvc'
            if name == 'gregtech:gt.metaitem.01' and damage in (1633, 2633):
                item['option'] = 'pdms'
            if name == 'gregtech:gt.metaitem.01' and damage == 29631:
                item['option'] = 'pps'
            item_index[rid] = len(items) + 1
            items.append(item)
        return item_index[rid]

    # The two coating classes are determined by the evidence, not material names.
    coating_standard = set()
    for recipe in catalog['recipes']:
        if recipe['machineType'] == 'Cable Coating' and recipe['outputs'][0]['id'] in reverse:
            key, _ = reverse[recipe['outputs'][0]['id']]
            if not any(e['id'] == 'gregtech:gt.metaitem.01@29631' for e in recipe['inputs']):
                coating_standard.add(key)
    bender_forms = {'plate', 'plateDouble', 'plateTriple', 'plateQuadruple',
                    'plateQuintuple', 'plateDense', 'foil'}
    def bender_route(recipe):
        if recipe['machineType'] != 'Bending Machine':
            return None
        inputs = recipe['inputs']
        consumed = [e for e in inputs if e.get('consumed', True)]
        catalysts = [e for e in inputs if not e.get('consumed', True)]
        if (len(recipe['outputs']) != 1 or len(inputs) != 2 or
                len(consumed) != 1 or len(catalysts) != 1 or
                consumed[0].get('kind') != 'item' or
                catalysts[0].get('kind') != 'item' or
                catalysts[0]['id'].split('@')[0] != 'gregtech:gt.integrated_circuit' or
                catalysts[0]['amount'] != 1 or
                recipe['outputs'][0].get('kind') != 'item'):
            return None
        source = reverse.get(consumed[0]['id'])
        destination = reverse.get(recipe['outputs'][0]['id'])
        if (not source or not destination or source[0] != destination[0] or
                source[1] != 'ingot' or destination[1] not in bender_forms):
            return None
        return source[0], destination[1], consumed[0]['id']

    # If both a canonical ingot and an alternate item are listed for the same
    # material/output, keep the canonical route. If only the alternate exists,
    # retain its actual descriptor as a resolver override.
    bender_inputs = {}
    for recipe in catalog['recipes']:
        route = bender_route(recipe)
        if route:
            bender_inputs.setdefault(route[:2], set()).add(route[2])
    excluded = 0
    excluded_outputs = {}
    for recipe in sorted(catalog['recipes'], key=lambda r: r['id']):
        mode = {'Wiremill': 'wiremill', 'Cable Coating': 'coating',
                'Bending Machine': 'bender'}.get(recipe['machineType'])
        if not mode:
            continue
        if mode == 'bender':
            # The selected stage is ingot -> product with a stocked circuit.
            # Other real bender recipes (plate -> multi-plate, springs, etc.)
            # remain outside this mode rather than becoming inferred routes.
            route = bender_route(recipe)
            if not route:
                continue
            canonical_ingot = rows[route[0]]['_forms'].get('ingot')
            alternatives = bender_inputs[route[:2]]
            if canonical_ingot in alternatives and route[2] != canonical_ingot:
                continue
        output = reverse.get(recipe['outputs'][0]['id'])
        if not output:
            excluded += 1
            label = recipe['outputs'][0].get('displayName', recipe['outputs'][0]['id'])
            excluded_outputs[label] = excluded_outputs.get(label, 0) + 1
            continue
        polymer = None
        if mode == 'coating':
            polymers = {'gregtech:gt.metaitem.01@1649': 'pvcSmall', 'gregtech:gt.metaitem.01@2649': 'pvc',
                        'gregtech:gt.metaitem.01@1633': 'pdmsSmall', 'gregtech:gt.metaitem.01@2633': 'pdms'}
            found = {polymers[e['id']] for e in recipe['inputs'] if e['id'] in polymers}
            if not found:
                continue
            if len(found) != 1:
                raise ValueError('Ambiguous insulation polymer: ' + recipe['id'])
            polymer = found.pop()
        key, output_form = output
        row = rows[key]

        def entry(e):
            rid, n = e['id'], e['amount']
            resource = resources.get(rid, {})
            if e.get('nbt') or e.get('tag') or resource.get('nbt') or resource.get('tag'):
                raise ValueError('Ingredient requires an explicit NBT resolver: ' + rid)
            alternatives = e.get('alternatives')
            if alternatives and not any(a['id'] == rid and a['amount'] in (1, n)
                                        and not a.get('nbt') and not a.get('tag') for a in alternatives):
                raise ValueError('Primary item is not an exact listed alternative: ' + rid)
            if e.get('chance', 1) != 1:
                raise ValueError('Chance ingredient needs explicit handling: ' + rid)
            known = reverse.get(rid)
            if known and known[0] == key:
                form = known[1]
                prior = row.setdefault('_recipeForms', {}).get(form)
                if prior and prior != rid:
                    raise ValueError('Conflicting primary recipe forms: ' + row['name'] + '/' + form)
                row['_recipeForms'][form] = rid
                return {'f': form, 'n': n}
            return {'i': literal(rid), 'n': n}

        rule = {'mode': mode, 'inputs': [], 'outputs': [], 'stock': []}
        for side in ('inputs', 'outputs'):
            for e in recipe[side]:
                if e['kind'] == 'fluid':
                    if side == 'outputs':
                        raise ValueError('Fluid output requires a fluid mode')
                    rule['stock'].append({'fluid': e['id'], 'n': e['amount']})
                elif e.get('consumed') is False:
                    if side != 'inputs':
                        raise ValueError('Unexpected unconsumed output')
                    rule['stock'].append(entry(e))
                else:
                    rule[side].append(entry(e))
        rule['requires'] = sorted({e['f'] for side in ('inputs', 'outputs', 'stock') for e in rule[side] if 'f' in e})
        if mode == 'coating':
            rule['polymer'] = polymer
            rule['coating'] = 'standard' if key in coating_standard else 'pps'
            row['coating'] = rule['coating']
        else:
            source = next((e['f'] for e in rule['inputs'] if 'f' in e), 'special')
            target = 'wire' if re.fullmatch(r'wire(1|2|4|8|12|16)', output_form) else output_form
            rule['process'] = source + '_' + target
            row.setdefault('processes', {})[rule['process']] = True
        encoded = json.dumps(rule, sort_keys=True, separators=(',', ':'))
        if encoded not in rules:
            # Descriptive rule identity, stable across material additions.
            stem = mode + '.' + (rule.get('process') or rule['coating']) + '.' + output_form
            rule['id'] = stem + '.' + hashlib.sha256(encoded.encode()).hexdigest()[:10]
            rules[encoded] = rule
        observations.setdefault(key, set()).add(rules[encoded]['id'])

    def rule_order(rule):
        form = rule['outputs'][0].get('f', '')
        match = re.fullmatch(r'(wire|cable)(1|2|4|8|12|16)', form)
        if match:
            return (0, int(match[2]), match[1], rule['id'])
        bender_order = ['plate', 'plateDouble', 'plateTriple', 'plateQuadruple',
                        'plateQuintuple', 'plateDense', 'foil']
        return (1, bender_order.index(form) if form in bender_order else 99, form, rule['id'])
    rules = sorted(rules.values(), key=rule_order)
    capabilities, cap_index, production, production_index = [], {}, [], {}
    for key, row in rows.items():
        row['_forms'].update(row.pop('_recipeForms', {}))
        available = sorted(row['_forms'])
        cap = tuple(available)
        if cap not in cap_index:
            cap_index[cap] = len(capabilities) + 1
            capabilities.append(dict.fromkeys(available, True))
        row['a'] = cap_index[cap]
        overrides = {}
        for form, rid in row['_forms'].items():
            try:
                expected = resolve(families, row, form)
            except KeyError:
                expected = None
            actual = descriptor(rid)
            if expected != actual:
                overrides[form] = {'name': actual[0], 'damage': actual[1]}
        if overrides:
            row['overrides'] = overrides
        # Form presence and production-route flags select generic rules. Explicit
        # removals record unusual GTNH behavior; no material stores a recipe list.
        denied = {}
        for rule in rules:
            eligible = (row.get('coating') == rule.get('coating') if rule['mode'] == 'coating'
                        else row.get('processes', {}).get(rule['process'], False))
            if eligible and all(form in row['_forms'] for form in rule['requires']):
                if rule['id'] not in observations.get(key, set()):
                    denied[rule['id']] = True
        if denied:
            row['deny'] = denied
        processes = row.pop('processes', {})
        if processes:
            identity = tuple(sorted(processes))
            if identity not in production_index:
                production_index[identity] = len(production) + 1
                production.append(processes)
            row['p'] = production_index[identity]
        del row['_forms'], row['_rank']
    return {'version': 2, 'source': {**catalog['source'], 'registryVersion': registry.get('gtVersion'),
                                   'alternativePolicy': 'primary-listed', 'excludedRecipes': excluded,
                                   'excludedOutputs': excluded_outputs,
                                   'compatibleTargets': list(compatible_targets), 'compatibilityBasis': compatibility_basis},
            'families': families, 'capabilities': capabilities, 'production': production, 'items': items, 'rules': rules,
            'registryNames': registry_names or {},
            'materials': sorted(rows.values(), key=lambda row: row['name'].lower())}


def lua(value, depth=0):
    if isinstance(value, dict):
        entries = ['[' + lua(k) + '] = ' + lua(v, depth+1) for k, v in value.items()]
        if len(entries)<=4 and all(not isinstance(v, (dict,list)) for v in value.values()):
            return '{' + ', '.join(entries) + '}'
    if isinstance(value, list):
        entries = [lua(v, depth+1) for v in value]
        if len(entries)<=6 and all(not isinstance(v, (dict,list)) for v in value):
            return '{' + ', '.join(entries) + '}'
    if isinstance(value, (dict,list)):
        indent = '  ' * (depth+1)
        return '{\n' + ',\n'.join(indent+entry for entry in entries) + '\n' + '  '*depth + '}'
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if value is None:
        return 'nil'
    return str(value)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('catalog')
    parser.add_argument('registry')
    parser.add_argument('output')
    parser.add_argument('--resources', help='Full registered resource index (gzip JSON)')
    parser.add_argument('--ore-resources', help='Source-annotated ore dictionary resources (gzip JSON)')
    parser.add_argument('--compatible-target', action='append', default=[])
    parser.add_argument('--compatibility-basis', default='')
    parser.add_argument('--registry-names', help='Case-preserving source registration import')
    args = parser.parse_args()
    catalog = json.load(gzip.open(args.catalog, 'rt', encoding='utf-8'))
    registry = json.loads(Path(args.registry).read_text(encoding='utf-8-sig'))
    resources = json.load(gzip.open(args.resources, 'rt', encoding='utf-8'))['resources'] if args.resources else []
    resources = {r['id']: r for r in resources}
    if args.ore_resources:
        for rid, resource in json.load(gzip.open(args.ore_resources, 'rt', encoding='utf-8'))['resources'].items():
            if rid in resources:
                resources[rid] = {**resources[rid], 'tags': resource.get('tags', [])}
    names = json.loads(Path(args.registry_names).read_text())['names'] if args.registry_names else {}
    model = compile_matrix(catalog, registry, args.compatible_target, args.compatibility_basis, resources, names)
    content = 'return ' + lua(model) + '\n'
    if len(content.encode()) > 4 * 1024 * 1024:
        raise ValueError('Library exceeds the absolute 4 MB budget')
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    output = Path(args.output)
    # wget transfers whole readable files; there is no per-paste restriction.
    for old in output.parent.glob('matrix_*.lua'):
        old.unlink()  # These are this compiler's generated chunks.
    output.write_text(content, encoding='utf-8')
    print(f"{len(model['materials'])} materials, {len(model['rules'])} shared rules, "
          f"{len(model['items'])} shared literal items; {len(content.encode())} bytes; "
          f"{sum(len(m.get('deny', {})) for m in model['materials'])} recipe exceptions")
