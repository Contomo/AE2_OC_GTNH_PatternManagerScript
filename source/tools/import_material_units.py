"""Import material amounts from pinned GT source, without material-specific guesses."""
import argparse
import ast
import hashlib
import json
import re
import zipfile
from pathlib import Path


def amount(expression, material_unit):
    """Evaluate only the integer arithmetic used by OrePrefixBuilder."""
    def evaluate(node):
        if isinstance(node, ast.Constant) and type(node.value) is int:
            return node.value
        if isinstance(node, ast.Name) and node.id == 'M':
            return material_unit
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub):
            return -evaluate(node.operand)
        if isinstance(node, ast.BinOp):
            left, right = evaluate(node.left), evaluate(node.right)
            if isinstance(node.op, ast.Add):
                return left + right
            if isinstance(node.op, ast.Sub):
                return left - right
            if isinstance(node.op, ast.Mult):
                return left * right
            if isinstance(node.op, ast.Div):
                return left // right
        raise ValueError('Unsupported material amount: ' + expression)
    return evaluate(ast.parse(expression, mode='eval').body)


def extract(prefix_source, values_source):
    constants = dict(re.findall(r'public static final long ([ML]) = (\d+);', values_source))
    material_unit, fluid_unit = int(constants['M']), int(constants['L'])
    forms = {}
    for name, block in re.findall(
            r'public static final OrePrefixes (\w+)\s*=\s*(.*?\.build\(\));',
            prefix_source, re.S):
        match = re.search(r'\.materialAmount\((.*?)\)\s*\n', block)
        if not match:
            continue
        units = amount(match[1], material_unit)
        if units <= 0:
            continue
        conductor = re.fullmatch(r'(wire|cable)Gt(\d+)', name)
        if conductor:
            name = conductor[1] + str(int(conductor[2]))
        forms[name] = units / material_unit
    if forms.get('ingot') != 1 or fluid_unit <= 0:
        raise ValueError('Missing material unit anchors')
    return {'fluidPerIngot': fluid_unit, 'forms': dict(sorted(forms.items()))}


def import_units(archive):
    with zipfile.ZipFile(archive) as source:
        def read(suffix):
            return source.read(next(p for p in source.namelist() if p.endswith(suffix))).decode()
        result = extract(read('/OrePrefixes.java'), read('/GTValues.java'))
    return {'policy': 'ore-prefix-material-units-v1',
            'source': {'archive': Path(archive).name,
                       'sha256': hashlib.sha256(Path(archive).read_bytes()).hexdigest(),
                       'definitions': ['gregtech/api/enums/OrePrefixes.java',
                                       'gregtech/api/enums/GTValues.java']}, **result}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive')
    parser.add_argument('output')
    args = parser.parse_args()
    result = import_units(args.archive)
    Path(args.output).write_text(json.dumps(result, indent=2) + '\n')
    print(len(result['forms']), 'material form amounts imported')
