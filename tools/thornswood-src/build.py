#!/usr/bin/env python3
"""
Assemble gamemode.js.

The four data blobs were recovered from the deployed gamemode.js rather than
rebuilt from the plugin, because the intermediate JSON that mkgamemode.py read
did not survive. They are byte-identical to what the server is running now,
apart from the alchemy novice manual added below: the earlier plugin shipped Advanced,
Expert and Master for that track and no Novice, which left tier 1 unreachable.
"""
import json

data = json.load(open('data.json'))
stations = json.load(open('stations.json'))
manuals = json.load(open('manuals.json'))
items = json.load(open('items.json'))

# The arrival rotations were read straight out of each marker's REFR DATA field,
# which stores radians. Both properties they end up in, spawnPoint and
# locationalData, take degrees: the stock SkyMP start point is angleZ 72 and a
# live change form reads angle [12.38, 0, 290.14]. Every value in the table is a
# multiple of pi/2, so this has been quietly landing everybody facing north since
# the respawn system shipped. Convert once, here, where it is visible.
import math

def to_degrees(rot):
    return [round(math.degrees(v), 2) for v in rot]

converted = 0
for slots in data['destinations'].values():
    for s in slots.values():
        if max(abs(v) for v in s['rot']) <= 2 * math.pi:
            s['rot'] = to_degrees(s['rot'])
            converted += 1

ALCHEMY_NOVICE = 'e80001:Thornswood-Content.esp'
if ALCHEMY_NOVICE not in manuals:
    manuals[ALCHEMY_NOVICE] = {'track': 'alchemy', 'tier': 1}

for track in ('mining', 'smithing', 'woodcutter', 'alchemy'):
    tiers = sorted(m['tier'] for m in manuals.values() if m['track'] == track)
    assert tiers == [1, 2, 3, 4], (track, tiers)

body = open('gamemode_body.js', encoding='utf-8').read()
js = (body
      .replace('/*__DATA__*/null', json.dumps(data, separators=(',', ':')))
      .replace('/*__STATIONS__*/null', json.dumps(stations, separators=(',', ':')))
      .replace('/*__MANUALS__*/null', json.dumps(manuals, separators=(',', ':')))
      .replace('/*__ITEMS__*/null', json.dumps(items, separators=(',', ':'))))

assert '__DATA__' not in js and '__ITEMS__' not in js

import os
os.makedirs('/mnt/user-data/outputs/thornswood', exist_ok=True)
out = '/mnt/user-data/outputs/thornswood/gamemode.js'
open(out, 'w', encoding='utf-8').write(js)
print('wrote %s  %d bytes' % (out, len(js)))
print('  cells mapped  %d' % len(data['cellToHold']))
print('  manuals       %d' % len(manuals))
print('  stations      %d' % len(stations))
print('  rotations converted to degrees  %d' % converted)
