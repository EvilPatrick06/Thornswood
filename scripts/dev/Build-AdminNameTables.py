"""
Build-AdminNameTables.py

Writes the ADMIN_NAMES block in game\\gamemode.js: every named item a pack can
hold and every named actor in the load order, by the name the game shows,
with the record it is. /give and /spawn read them after their own tables.

WHY

Patrick, 27 September: "/give is an admin/tester command I should be able
/give any item I like and /span any npc I like not just animals but trolls,
giants, skeletons, etc". /give only knew what some other table had named for
another reason (ores, plants, the recipe table's outputs and ingredients), and
/spawn only knew the animals in the hunt tables. Both are behind the
playtester gate, so the whole load order is theirs to reach.

WHAT IS IN IT

  items   ALCH AMMO ARMO BOOK INGR KEYM MISC SCRL SLGM WEAP with a FULL name.
          ARMO and WEAP with the record's non playable flag (0x4) are left out:
          those are skins and creature weapons, not things anybody carries.
          Gold is in, as Gold: /give is a tester's tool, not a mint, and
          tests\\test-one-mint.js exempts this block by name.
  actors  NPC_ with a name. A record that takes its name from a template
          (Use Base Data, 0x80 in ACBS) is named by that template, followed
          while it is another NPC_. Trolls, giants, skeletons, draugr, dragons
          and people are all NPC_ records, so all of them are here.

WHEN TWO RECORDS SHARE A NAME the one from the earliest plugin wins, in load
order with the five masters first, which is the record people mean when they
type the vanilla name. Between records of one plugin an actor with its own
traits wins over one built from a template (a template pointing at a levelled
list is a different creature every time), and then the lowest form id. Any
record at all can still be reached by its form id: /spawn 23ab7 or
/give 12eb7:Skyrim.esm.

Read only except for gamemode.js, which it rewrites between the markers. It
adds the markers after ITEM_NAMES the first time.

Usage:
  python scripts\\dev\\Build-AdminNameTables.py
  python scripts\\dev\\Build-AdminNameTables.py --data <Data> --plugins <plugins.txt> --gamemode <file>
"""

import argparse
import importlib.util
import io
import json
import os
import struct
import sys

import bsa
import own_plugins

HERE = os.path.dirname(os.path.abspath(__file__))

# The one plugin reader, loaded the way Build-CastTable.py loads it.
_spec = importlib.util.spec_from_file_location(
    'door_table', os.path.join(HERE, 'Build-DoorTable.py'))
door_table = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(door_table)
Plugin = door_table.Plugin
subrecords = door_table.subrecords
MASTERS = door_table.MASTERS

ITEM_TYPES = (b'ALCH', b'AMMO', b'ARMO', b'BOOK', b'INGR', b'KEYM', b'MISC', b'SCRL', b'SLGM', b'WEAP')
WANTED = ITEM_TYPES + (b'NPC_',)
NON_PLAYABLE = 0x4        # record header flag on ARMO and WEAP
DELETED = 0x20
USE_TRAITS = 0x0001
USE_BASE_DATA = 0x0080

START = '  // ==== ADMIN_NAMES ===='
END = '  // ==== end ADMIN_NAMES ===='
AFTER = '  // ==== end ITEM_NAMES ===='

# Update.esm's own Creation Club records (#479): every Special Edition has
# them, but their art comes with the Creation Club files Thornswood leaves
# out, so /give and /spawn never hand one out. scripts\mods\Check-CreationForms.js
# --write keeps the list; tests\test-special-edition-only.js holds this to it.
CREATION_LIST = os.path.join(HERE, '..', '..', 'records', 'update-creation-club.json')


def creation_records():
    """'<id>:Update.esm' for each of Update.esm's own Creation Club records."""
    with io.open(CREATION_LIST, encoding='utf-8') as f:
        return set(k + ':Update.esm' for k in json.load(f)['records'])


def u32(b, off=0):
    return struct.unpack_from('<I', b, off)[0]


def read(pl, rank, recs):
    """Every wanted record in one plugin into recs[desc], last plugin wins."""
    buf = pl.buf

    def eat(start, end):
        p = start
        while p + 24 <= end:
            tag = buf[p:p + 4]
            size = u32(buf, p + 4)
            if tag == b'GRUP':
                eat(p + 24, p + size)
                p += size
                continue
            flags, fid = struct.unpack_from('<II', buf, p + 8)
            d = pl.desc(fid)
            if d and tag in WANTED:
                if flags & DELETED:
                    recs.pop(d, None)
                else:
                    row = {'type': tag, 'flags': flags, 'owner': d.split(':', 1)[1], 'fid': fid & 0xFFFFFF}
                    for st, body in subrecords(pl.data(p, size, flags)):
                        if st == b'FULL':
                            row['name'] = pl.text(body).strip()
                        elif st == b'TPLT' and len(body) >= 4:
                            row['template'] = pl.desc(u32(body))
                        elif st == b'ACBS' and len(body) >= 20:
                            row['uses'] = struct.unpack_from('<H', body, 18)[0]
                    recs[d] = row
            p += 24 + size

    p = 24 + pl.header
    while p + 24 <= len(buf):
        size = u32(buf, p + 4)
        if buf[p:p + 4] != b'GRUP':
            break
        if buf[p + 8:p + 12] in WANTED:
            eat(p + 24, p + size)
        p += size


def actor_name(recs, d):
    """The name the game shows for an actor, following Use Base Data."""
    seen = set()
    while d and d not in seen:
        seen.add(d)
        r = recs.get(d)
        if not r or r['type'] != b'NPC_':
            return ''
        if r.get('uses', 0) & USE_BASE_DATA and r.get('template'):
            nxt = recs.get(r['template'])
            if nxt and nxt['type'] == b'NPC_':
                d = r['template']
                continue
        return r.get('name', '')
    return ''


def table(recs, rank, pick_items, creation=frozenset()):
    best = {}
    for d, r in recs.items():
        if pick_items != (r['type'] in ITEM_TYPES):
            continue
        if d in creation:
            continue
        if pick_items:
            if r['type'] in (b'ARMO', b'WEAP') and r['flags'] & NON_PLAYABLE:
                continue
            name = r.get('name', '')
            templated = 0
        else:
            name = actor_name(recs, d)
            templated = 1 if (r.get('uses', 0) & USE_TRAITS and r.get('template')) else 0
        if not name or name.lower() == '__proto__':
            continue
        key = name.lower()
        score = (rank.get(r['owner'].lower(), 10 ** 6), templated, r['fid'])
        if key not in best or score < best[key][0]:
            best[key] = (score, name, d)
    return dict((k, (v[1], v[2])) for k, v in best.items())


def block(items, actors, plugins):
    out = [START,
           '  /* Built by scripts\\dev\\Build-AdminNameTables.py out of the %d plugins in the load order.' % plugins,
           '     Do not hand edit. %d item names and %d actor names, for /give and /spawn, which' % (len(items), len(actors)),
           '     read them after their own tables. Lower-case name -> [name as written, record]. */']
    for var, tab in (('ADMIN_ITEMS', items), ('ADMIN_ACTORS', actors)):
        out.append('  var %s = {' % var)
        keys = sorted(tab)
        for i, k in enumerate(keys):
            out.append('    %s: [%s, %s]%s' % (json.dumps(k), json.dumps(tab[k][0]), json.dumps(tab[k][1]),
                                              ',' if i < len(keys) - 1 else ''))
        out.append('  };')
    out.append(END)
    return '\n'.join(out) + '\n'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', default=r'C:\Thornswood\Game\Data')
    ap.add_argument('--plugins', default=r'C:\Thornswood\Profile\OwnGame\plugins.txt')
    ap.add_argument('--gamemode', default=os.path.join(HERE, '..', '..', 'game', 'gamemode.js'))
    a = ap.parse_args()

    order = own_plugins.load_order(a.plugins)
    missing = [n for n in order if not os.path.isfile(own_plugins.plugin_path(a.data, n))]
    if missing:
        print('STOP. %d plugin(s) are not in %s: %s' % (len(missing), a.data, ', '.join(missing[:6])))
        return 1
    canon = dict((n.lower(), n) for n in order)
    rank = dict((n.lower(), i) for i, n in enumerate(order))
    recs, failed = {}, 0
    for name in order:
        pl = Plugin(own_plugins.plugin_path(a.data, name), name)
        if not pl.ok:
            continue
        pl.masters = [canon.get(m.lower(), m) for m in pl.masters]
        if pl.localised:
            pl.strings = bsa.load_strings(a.data, name)
        read(pl, rank, recs)
        failed += pl.failed

    creation = creation_records()
    items = table(recs, rank, True, creation)
    actors = table(recs, rank, False, creation)
    print('%d plugins, %d records read, %d failed to inflate' % (len(order), len(recs), failed))
    print('%d item names, %d actor names' % (len(items), len(actors)))
    for probe in ('troll', 'frost troll', 'giant', 'skeleton', 'draugr', 'mammoth', 'gold', 'iron sword', 'dragon'):
        tab = items if probe in ('gold', 'iron sword') else actors
        print('  %-12s %s' % (probe, tab.get(probe)))

    raw = io.open(a.gamemode, encoding='utf-8', newline='').read()
    s = raw.replace('\r\n', '\n')
    text = block(items, actors, len(order))
    if START in s:
        i = s.index(START)
        j = s.index(END, i) + len(END) + 1
        s = s[:i] + text + s[j:]
    else:
        i = s.index(AFTER) + len(AFTER) + 1
        s = s[:i] + '\n' + text + s[i:]
    io.open(a.gamemode, 'w', encoding='utf-8', newline='').write(s)
    print('wrote the ADMIN_NAMES block into ' + a.gamemode)
    return 0


if __name__ == '__main__':
    sys.exit(main())
