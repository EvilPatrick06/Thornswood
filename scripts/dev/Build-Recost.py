"""
Build-Recost.py

Writes game/data/recost.json: the smith recipes whose materials are priced
nothing like what they make, and the materials each one asks for instead.
scripts/mods/Build-LastPlugin.py reads it and carries each one, as the winning
record with only its input counts changed, in Thornswood-Last.esp.

WHY (issue #613)

The forge report of 25 September: "Several items are too cheap or too
expensive". Measured 21 October from game/data/recipes.json: of the 1,140
smith recipes at the forge and the Skyforge, 645 have every input priced, and
for those the item is worth a median 1.69 times its materials. 45 asked for
materials worth more than twice the item (Ancient Nord Boots, worth 25, from
133 of materials) and 59 made something worth four times its materials or
more (a Riekling armour worth 300 from 6 of leather strips). The recipes are
the mods' own; nothing in Thornswood set those numbers.

Patrick, 21 October, on the report page (q-613-forge-recipes), A: re-cost only
the outliers to the typical ratio, in a generated plugin built on One and
shipped as a release.

THE RULE, every number of it a knob below

  A row is a smith's (owner Smith) at the forge or the Skyforge, is asked of
  the server (fires), and every input it takes has a price. An item's price is
  the worth of the record a recipe makes it as, read off recipes.json; an
  input no recipe makes (ore, a hide) has none, and its row is left alone.

  Its ratio is what it makes (worth times how many) over what its inputs are
  worth. TARGET is the median ratio over every such row, worked out on each
  run from the rows' original inputs.

  A row whose ratio is under LOW or at HIGH and over is re-costed: every input
  count is multiplied by the one factor that brings the ratio to TARGET, then
  rounded, and never under one. Only the counts change: the same inputs, in
  the same order, the same output and bench. A row whose counts come out the
  same after rounding (a five gold sword asking one of each already) is
  listed under unreachable, with why, and gets no override.

WHY IT IS STABLE

  Once Thornswood-Last.esp carries the new counts, a recipes.json built from
  that load order reads them, and those rows would read as in the band. So a
  row already in recost.json keeps the ORIGINAL inputs it was first measured
  with, and the rule is asked of those, every run. A row that leaves the load
  order leaves the file. A row that newly falls outside the band joins it.

Usage:
    python scripts/dev/Build-Recost.py           writes game/data/recost.json
    python scripts/dev/Build-Recost.py --check   exit 1 when the file is not what the rule gives
"""

import argparse
import io
import json
import os
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
RECIPES = os.path.join(ROOT, 'game', 'data', 'recipes.json')
OUT = os.path.join(ROOT, 'game', 'data', 'recost.json')

OWNER = 'Smith'
BENCHES = ('CraftingSmithingForge', 'CraftingSmithingSkyforge')
LOW = 0.5    # under this, the materials are worth more than twice the item
HIGH = 4.0   # at this and over, the item is worth four times its materials


def prices(recipes):
    """Every item some recipe makes, at the worth of that record."""
    out = {}
    for section in ('recipes', 'unowned', 'refused'):
        for row in recipes.get(section, {}).values():
            if row.get('worth') is not None and row.get('out'):
                out.setdefault(row['out'], row['worth'])
    return out


def candidates(recipes, price, kept):
    """(desc, row, inputs) for every row the rule may ask, with the original
    inputs: the ones recost.json first measured, or the record's own."""
    out = []
    for desc in sorted(recipes['recipes']):
        row = recipes['recipes'][desc]
        if row.get('owner') != OWNER or row.get('benchName') not in BENCHES:
            continue
        if row.get('fires') is False or not row.get('worth'):
            continue
        if desc in kept:
            inputs = [{'item': i['item'], 'name': i['name'], 'count': i['count']} for i in kept[desc]['inputs']]
        else:
            inputs = [{'item': i['item'], 'name': i['name'], 'count': i['count']}
                      for i in row.get('inputItems', [])]
        if not inputs or any(price.get(i['item']) is None for i in inputs):
            continue
        out.append((desc, row, inputs))
    return out


def material(inputs, price):
    return sum(price[i['item']] * i['count'] for i in inputs)


def build(recipes, previous):
    price = prices(recipes)
    kept = {r['recipe']: r for r in (previous or {}).get('recipes', [])}
    kept.update({r['recipe']: r for r in (previous or {}).get('unreachable', [])})
    rows = candidates(recipes, price, kept)
    ratio = {desc: row['worth'] * row.get('makes', 1) / material(inputs, price) for desc, row, inputs in rows}
    target = statistics.median(ratio.values())
    recost, unreachable = [], []
    for desc, row, inputs in rows:
        r = ratio[desc]
        if LOW <= r < HIGH:
            continue
        makes = row['worth'] * row.get('makes', 1)
        factor = (makes / target) / material(inputs, price)
        to = [max(1, int(round(i['count'] * factor))) for i in inputs]
        entry = {
            'recipe': desc,
            'editorId': row.get('editorId', ''),
            'name': row.get('name', ''),
            'plugin': row.get('plugin', desc.split(':', 1)[1]),
            'worth': row['worth'],
            'makes': row.get('makes', 1),
            'ratioWas': round(r, 3),
            'inputs': [dict(i, to=t, price=price[i['item']]) for i, t in zip(inputs, to)],
        }
        after = [dict(i, count=t) for i, t in zip(inputs, to)]
        entry['ratioNow'] = round(makes / material(after, price), 3)
        if to == [i['count'] for i in inputs]:
            entry['why'] = ('every input is already at the count the rule rounds to (one each at the least), '
                            'so only the record\'s worth could bring it to the band, and that is not a recipe change')
            unreachable.append(entry)
        else:
            recost.append(entry)
    return {
        'version': 1,
        'builtBy': 'scripts/dev/Build-Recost.py',
        'issue': 613,
        'decision': 'Patrick, 21 October 2026, report page q-613-forge-recipes, A: re-cost only the outliers '
                    'to the typical ratio, in a generated plugin built on One and shipped as a release.',
        'readFrom': 'game/data/recipes.json: the smith rows at the forge and the Skyforge that the server is asked '
                    'about, every input priced at the worth of the record a recipe makes it as',
        'rule': {
            'owner': OWNER, 'benches': list(BENCHES), 'low': LOW, 'high': HIGH,
            'target': round(target, 4),
            'how': 'ratio = worth x makes / what the inputs are worth. A row under low or at high and over has '
                   'every input count multiplied by the one factor that brings it to target, rounded, never '
                   'under one. A row already listed keeps the original inputs it was first measured with.',
        },
        'counts': {'priced': len(rows), 'recosted': len(recost), 'unreachable': len(unreachable)},
        'recipes': recost,
        'unreachable': unreachable,
    }


def dump(data):
    return json.dumps(data, indent=1, ensure_ascii=False) + '\n'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', action='store_true')
    args = ap.parse_args()
    recipes = json.load(io.open(RECIPES, encoding='utf-8'))
    previous = json.load(io.open(OUT, encoding='utf-8')) if os.path.isfile(OUT) else None
    data = build(recipes, previous)
    text = dump(data)
    c = data['counts']
    print('%d smith rows priced, target ratio %.3f: %d re-costed, %d outside the band that no count can fix'
          % (c['priced'], data['rule']['target'], c['recosted'], c['unreachable']))
    if args.check:
        same = os.path.isfile(OUT) and io.open(OUT, encoding='utf-8').read() == text
        print('game/data/recost.json is ' + ('what the rule gives' if same else 'NOT what the rule gives; run without --check'))
        return 0 if same else 1
    with io.open(OUT, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(text)
    print('wrote game/data/recost.json')
    return 0


if __name__ == '__main__':
    sys.exit(main())
