"""Recover case-preserving IDs from pinned registration code and recipe references.

The normalized recipe export loses registry case. This desktop import uses
source declarations, never material examples or guessed title-casing.
"""
import argparse
import gzip
import hashlib
import json
import re
import zipfile
from pathlib import Path


def recover(archive, registry, catalog, enderio_item, enderio_objects, item_registry=None,
            reference_archives=()):
    names, evidence = {}, {}
    wanted = {e['id'].split('@')[0] for r in catalog['recipes']
              for e in r['inputs'] + r['outputs'] if e['kind'] == 'item'}

    def add(name, source):
        key = name.lower()
        if key not in wanted:
            return
        if key in names and names[key] != name:
            raise ValueError('Conflicting registry spelling: ' + key)
        names[key], evidence[key] = name, source

    with zipfile.ZipFile(archive) as z:
        def source(suffix):
            path = next(p for p in z.namelist() if p.endswith(suffix))
            return z.read(path).decode('utf-8')

        mods = source('gregtech/api/enums/Mods.java')
        constants = dict(re.findall(r'String\s+(\w+)\s*=\s*"([^"]+)"', mods))
        mod_ids = {name: constants[key] for name, key in
                   re.findall(r'(\w+)\(ModIDs\.(\w+)\)', mods) if key in constants}
        def references(text, path):
            for mod, item in re.findall(r'getModItem\(\s*(\w+)\.ID\s*,\s*"([^"]+)"', text):
                if mod in mod_ids:
                    add(mod_ids[mod] + ':' + item, path.split('/src/', 1)[-1])
        for path in z.namelist():
            if not path.endswith('.java'):
                continue
            text = z.read(path).decode('utf-8')
            references(text, path)

        component = source('gtPlusPlus/core/item/base/BaseItemComponent.java')
        assert '"item" + componentType.COMPONENT_NAME + material.getUnlocalizedName()' in component
        components = re.findall(r'\w+\("([^"]+)",\s*"[^"]+",\s*"[^"]+",\s*OrePrefixes\.\w+\)', component)
        # GT++ can register components for both its own materials and wrapped
        # GT Materials (e.g. Clay plates). Both use the same source formula.
        for material in set(registry['gtppMaterials']) | set(registry['materials'].values()):
            for form in components:
                add('miscutils:item' + form + material, 'gtPlusPlus/core/item/base/BaseItemComponent.java + registry material declarations')

        bw = source('bartworks/system/material/BWMetaGeneratedItems.java')
        generic = source('gregtech/api/items/GTGenericItem.java')
        assert 'super("bwMetaGenerated" + orePrefixes.getName()' in bw
        assert 'mName = "gt." + aUnlocalized' in generic
        for forms in registry['prefixes'].values():
            for form in forms:
                add('bartworks:gt.bwMetaGenerated' + form, 'bartworks/system/material/BWMetaGeneratedItems.java + gregtech/api/items/GTGenericItem.java')

    for reference_archive in reference_archives:
        with zipfile.ZipFile(reference_archive) as z:
            for path in z.namelist():
                if path.endswith('.java'):
                    references(z.read(path).decode('utf-8'), path)

    # EnderIO registers the enum's unlocalisedName, which is exactly name().
    item_text = Path(enderio_item).read_text()
    objects = Path(enderio_objects).read_text()
    assert 'unlocalisedName = name()' in objects
    for name in re.findall(r'registerItem\(this, ModObject\.(\w+)\.unlocalisedName\)', item_text):
        assert re.search(r'\b' + re.escape(name) + r'\s*[,;]', objects)
        add('EnderIO:' + name, 'EnderIO/material/ItemAlloy.java + ModObject.java')
    if item_registry:
        # NEI's item list uses the actual case-sensitive Forge IDs. Ignore
        # comments and metadata; only recover IDs present in the recipe export.
        for line in Path(item_registry).read_text().splitlines():
            line = line.split('#', 1)[0].strip()
            match = re.match(r'^([A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+)(?:\s|$)', line)
            if match and match.group(1).lower() not in names:
                add(match.group(1), 'GTNH config/NEI/hiddenitems.cfg')
    result = {'names': dict(sorted(names.items())), 'evidence': dict(sorted(evidence.items())),
            'gtArchiveSha256': hashlib.sha256(Path(archive).read_bytes()).hexdigest(),
            'gtVersion': registry['gtVersion'],
            'enderioItemSha256': hashlib.sha256(Path(enderio_item).read_bytes()).hexdigest(),
            'enderioObjectsSha256': hashlib.sha256(Path(enderio_objects).read_bytes()).hexdigest()}
    if item_registry:
        result['itemRegistrySha256'] = hashlib.sha256(Path(item_registry).read_bytes()).hexdigest()
    return result


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    for key in ('archive', 'registry', 'catalog', 'enderio_item', 'enderio_objects', 'output'):
        p.add_argument(key)
    p.add_argument('--item-registry', help='GTNH NEI item configuration with case-preserving Forge IDs')
    p.add_argument('--reference-archive', action='append', default=[],
                   help='Additional pinned mod source archive with case-preserving getModItem references')
    a = p.parse_args()
    result = recover(a.archive, json.loads(Path(a.registry).read_text()),
                     json.load(gzip.open(a.catalog, 'rt')), a.enderio_item, a.enderio_objects,
                     a.item_registry, a.reference_archive)
    Path(a.output).write_text(json.dumps(result, indent=2) + '\n')
    print(len(result['names']), 'case-preserving registry IDs recovered')
