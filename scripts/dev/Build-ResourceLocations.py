"""List source-derived fishing and hunting supply; never invent placement coordinates."""
import argparse
import collections
import csv
import importlib.util
import json
import pathlib
import re

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('population', HERE / 'Build-NpcPopulation.py')
P = importlib.util.module_from_spec(spec)
spec.loader.exec_module(P)
C = P.C
ROOT = HERE.parent.parent


def js_table(source, name):
    match = re.search(r'^(?:var|const) ' + name + r' = (\{.*?^\});', source, re.M | re.S)
    if not match:
        raise ValueError('Missing production table: ' + name)
    return json.loads(match.group(1))


def write_csv(filename, rows, columns):
    with (ROOT / 'docs' / filename).open('w', encoding='utf-8', newline='') as output:
        writer = csv.DictWriter(output, fieldnames=columns)
        writer.writeheader()
        writer.writerows({key: row.get(key, '') for key in columns} for row in rows)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--settings', required=True)
    parser.add_argument('--strings-dir', required=True)
    args = parser.parse_args()
    settings = json.loads(pathlib.Path(args.settings).read_text(encoding='utf-8-sig'))
    population = json.loads((ROOT / 'game/data/npc-population.json').read_text(encoding='utf-8'))
    paths = settings['loadOrder']
    order = [pathlib.Path(path).name for path in paths]
    if order != [row['name'] for row in population['loadOrder']]:
        raise ValueError('Resource locations and population use different plugin orders')
    tables = {tag: {} for tag in C.WANTED}
    tables.update({b'ACHR': {}, b'REFR': {}, b'ECZN': {}})
    for path, provenance in zip(paths, population['loadOrder']):
        plugin = C.Plugin(path, pathlib.Path(path).name)
        if P.hashlib.sha256(plugin.buf).hexdigest() != provenance['sha256']:
            raise ValueError('Resource plugin changed: ' + provenance['name'])
        if plugin.localised:
            plugin.strings = C.bsa.load_strings(args.strings_dir, plugin.name)
        C.read(plugin, tables)
        P.read_details(plugin, tables)
        if plugin.failed:
            raise ValueError('Failed compressed records: ' + plugin.name)
    context = C.Cast(tables)
    source = (ROOT / 'game/gamemode.js').read_text(encoding='utf-8')
    fish = js_table(source, 'FISH_BY_BASE')
    racks = js_table(source, 'GAME_BY_BASE')
    waters = json.loads((ROOT / 'game/data/waters.json').read_text(encoding='utf-8'))
    catches, hanging = [], []
    returns = {'novice': 10, 'advanced': 30, 'expert': 60, 'master': 240}
    for identity, row in sorted(tables[b'REFR'].items()):
        base = row.get('base')
        produce = fish.get(base) or racks.get(base)
        if not produce or row.get('deleted') or context.off(identity):
            continue
        position = row.get('pos')
        if not position or len(position) != 3 or not all(P.math.isfinite(v) for v in position):
            raise ValueError('Invalid resource placement: ' + identity)
        hold, via = context.place(dict(row, pos=position[:2]), None)
        water = waters['where'].get(row.get('cell')) or waters['where'].get(row.get('world'))
        water_record = waters['waters'].get(water, {})
        item = dict(ref=identity, base=base, hold=context.hold_name(hold) if hold else 'no hold',
            holdFrom=via, location=context.cell_label(row), cell=row.get('cell'), world=row.get('world'),
            x=position[0], y=position[1], z=position[2], source=produce['from'],
            produce=produce['name'], item=produce['produce'], rank=produce['rank'],
            returnMinutes=returns[produce['rank']], sharedStock=1,
            water=water, waterType=water_record.get('e', ''), waterClass=water_record.get('c', ''),
            access='Fisher' if base in fish else 'Hunter')
        (catches if base in fish else hanging).append(item)
    hunts = json.loads((ROOT / 'game/data/hunts.json').read_text(encoding='utf-8'))['hunts']
    animals = []
    for row in population['npcs']:
        if not row['keep'] or row['role'] != 'animal':
            continue
        hunt = hunts.get(row['base'])
        products = hunt['gives'] if hunt else []
        animals.append(dict(row, x=row['pos'][0], y=row['pos'][1], z=row['pos'][2],
            rank=hunt['rank'] if hunt else '', access='Hunter' if hunt else 'No dressing yield',
            products='; '.join(item['name'] for item in products),
            productIds='; '.join(item['item'] for item in products),
            yieldByRank=json.dumps(hunt['yield'], separators=(',', ':')) if hunt else '',
            sharedStock=1, rewardRule='One dressing per life' if hunt else 'None'))
    resource_columns = ['ref', 'base', 'hold', 'location', 'cell', 'world', 'x', 'y', 'z',
        'source', 'produce', 'item', 'rank', 'access', 'returnMinutes', 'sharedStock',
        'water', 'waterType', 'waterClass', 'holdFrom']
    write_csv('FISHING-SPOTS.csv', catches, resource_columns)
    write_csv('HANGING-GAME-SPOTS.csv', hanging, resource_columns)
    write_csv('HUNTING-SPOTS.csv', animals, ['ref', 'name', 'base', 'hold', 'locationName',
        'location', 'habitat', 'role', 'species', 'tier', 'cap', 'returnMinutes', 'leash',
        'cell', 'world', 'x', 'y', 'z', 'rank', 'access', 'products', 'productIds',
        'yieldByRank', 'sharedStock', 'rewardRule'])
    payload = {'version': 1, 'builtBy': 'scripts/dev/Build-ResourceLocations.py',
        'loadOrder': population['loadOrder'], 'fishing': catches, 'hangingGame': hanging}
    with (ROOT / 'game/data/resource-locations.json').open('w', encoding='utf-8', newline='\n') as output:
        json.dump(payload, output, ensure_ascii=False, separators=(',', ':'))
        output.write('\n')
    print(json.dumps({'fishingSpots': len(catches), 'hangingGameSpots': len(hanging),
        'animalPlacements': len(animals), 'dressablePlacements': sum(bool(row['products']) for row in animals),
        'fishingByRank': dict(collections.Counter(row['rank'] for row in catches))}))


if __name__ == '__main__':
    main()
