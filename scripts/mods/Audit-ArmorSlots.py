#!/usr/bin/env python3
"""
Find the armour that makes Thornswood strip you.

The server rejects an equipment update when any two equipped items claim the
same biped slot bit. ActionListener::OnUpdateEquipment ORs the slot flags of
everything you have on, and on the first overlap it refuses the whole update
and sends an UnequipItem snippet for EVERY item involved. That is what
"looting gear unequips your current gear and won't let you equip it" is.

This reads the armour records straight out of the plugins and reports which
slots each mod claims, so the collision can be found without waiting for it to
happen to somebody.

  python Audit-ArmorSlots.py "C:\\Thornswood\\Game\\Data"
  python Audit-ArmorSlots.py --settings "C:\\path\\to\\server-settings.json"

Reads .esp/.esm/.esl directly. No Skyrim, no xEdit, no dependencies.
"""

import os
import sys
import json
import zlib
import struct
import argparse
from collections import defaultdict

# Biped slots are a 32 bit mask where bit 0 is slot 30. Names are the vanilla
# meanings; mods reuse the free ones and that is where collisions come from.
SLOT_NAMES = {
    30: "head", 31: "hair", 32: "body", 33: "hands", 34: "forearms",
    35: "amulet", 36: "ring", 37: "feet", 38: "calves", 39: "shield",
    40: "tail", 41: "long hair", 42: "circlet", 43: "ears", 44: "face/mouth",
    45: "neck", 46: "chest primary", 47: "back", 48: "misc/other",
    49: "pelvis primary", 50: "decapitated head", 51: "decapitate",
    52: "pelvis secondary", 53: "leg primary", 54: "leg secondary",
    55: "face alternate", 56: "behind", 57: "chest secondary",
    58: "shoulder", 59: "arm secondary", 60: "arm primary",
    61: "misc 2", 62: "fx01",
}

# Slots the vanilla game leaves free, which is exactly where mod authors put
# cloaks, backpacks and scarves, and exactly where they collide with each other.
CONTESTED = {44, 45, 46, 47, 48, 55, 56, 57, 58, 59, 60, 61}


def slots_of(mask):
    return [30 + b for b in range(32) if mask & (1 << b)]


def read_subrecords(data):
    """Walk one record's payload. XXXX carries an oversized length for the
    subrecord after it, which is the only real trap in this format."""
    i = 0
    override = None
    n = len(data)
    while i + 6 <= n:
        sig = data[i:i + 4]
        size = struct.unpack_from("<H", data, i + 4)[0]
        i += 6
        if override is not None:
            size = override
            override = None
        if sig == b"XXXX":
            override = struct.unpack_from("<I", data, i)[0]
            i += size
            continue
        yield sig, data[i:i + size]
        i += size


def walk(buf, start, end, out, masters, plugin):
    """Records and groups are the same 24 byte header shape, told apart by the
    GRUP signature. Groups nest; records do not."""
    i = start
    while i + 24 <= end:
        sig = buf[i:i + 4]
        size = struct.unpack_from("<I", buf, i + 4)[0]
        if sig == b"GRUP":
            walk(buf, i + 24, min(i + size, end), out, masters, plugin)
            i += size
            continue

        flags = struct.unpack_from("<I", buf, i + 8)[0]
        form_id = struct.unpack_from("<I", buf, i + 12)[0]
        body = buf[i + 24:i + 24 + size]
        i += 24 + size

        if sig != b"ARMO":
            continue

        if flags & 0x00040000:          # compressed record
            try:
                body = zlib.decompress(body[4:])
            except zlib.error:
                continue

        edid = name = None
        mask = None
        for sub, val in read_subrecords(body):
            if sub == b"EDID":
                edid = val.split(b"\0")[0].decode("latin-1")
            elif sub == b"FULL":
                name = val.split(b"\0")[0].decode("latin-1", "replace")
            elif sub in (b"BOD2", b"BODT") and len(val) >= 4:
                mask = struct.unpack_from("<I", val, 0)[0]

        if not mask:
            continue

        # The top byte of a form id is the load order index of the plugin that
        # owns it, so an overridden vanilla record is still reported here under
        # the plugin doing the overriding, which is what we want.
        out.append({
            "plugin": plugin,
            "formId": form_id & 0x00FFFFFF,
            "edid": edid or "",
            "name": name or "",
            "mask": mask,
            "slots": slots_of(mask),
        })


def parse(path):
    with open(path, "rb") as fh:
        buf = fh.read()
    if buf[:4] != b"TES4":
        return []
    header_size = struct.unpack_from("<I", buf, 4)[0]
    out = []
    walk(buf, 24 + header_size, len(buf), out, [], os.path.basename(path))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("data_dir", nargs="?", help="the game's Data folder")
    ap.add_argument("--settings", help="server-settings.json, to use its load order")
    args = ap.parse_args()

    if args.settings:
        with open(args.settings, encoding="utf-8-sig") as fh:
            files = json.load(fh).get("loadOrder", [])
    elif args.data_dir:
        files = []
        for entry in sorted(os.listdir(args.data_dir)):
            if entry.lower().endswith((".esp", ".esm", ".esl")):
                files.append(os.path.join(args.data_dir, entry))
    else:
        ap.error("give me a Data folder or --settings")

    records = []
    for path in files:
        if not os.path.exists(path):
            print("  missing, skipped: %s" % path)
            continue
        try:
            records.extend(parse(path))
        except Exception as exc:
            print("  could not read %s: %s" % (os.path.basename(path), exc))

    if not records:
        print("No armour records found.")
        return

    by_plugin = defaultdict(lambda: defaultdict(list))
    for r in records:
        for s in r["slots"]:
            by_plugin[r["plugin"]][s].append(r)

    print("=" * 74)
    print("ARMOUR SLOTS BY PLUGIN   (%d armour records across %d plugins)"
          % (len(records), len(by_plugin)))
    print("=" * 74)
    for plugin in sorted(by_plugin):
        slots = sorted(by_plugin[plugin])
        marked = ",".join(("*%d" % s) if s in CONTESTED else str(s) for s in slots)
        print("\n%s\n    %s" % (plugin, marked))

    print("\n" + "=" * 74)
    print("CONTESTED SLOTS   (* above). Two mods here can strip you.")
    print("=" * 74)
    holders = defaultdict(set)
    for r in records:
        for s in r["slots"]:
            if s in CONTESTED:
                holders[s].add(r["plugin"])

    trouble = False
    for slot in sorted(holders):
        who = sorted(holders[slot])
        if len(who) < 2:
            continue
        trouble = True
        print("\nslot %d (%s) is claimed by %d plugins:"
              % (slot, SLOT_NAMES.get(slot, "unused in vanilla"), len(who)))
        for plugin in who:
            items = [r for r in records
                     if r["plugin"] == plugin and slot in r["slots"]]
            print("    %-44s %d items" % (plugin, len(items)))
            for r in items[:4]:
                print("        %08x  %-28s %s"
                      % (r["formId"], r["edid"][:28], r["name"][:24]))
            if len(items) > 4:
                print("        ... and %d more" % (len(items) - 4))

    if not trouble:
        print("\nNo contested slot is claimed by more than one plugin.")
        print("The unequip problem is not a slot collision between mods.")
    else:
        print("\n" + "-" * 74)
        print("Any two of the items listed above worn together are refused by")
        print("the server and BOTH come off. Wearing one at a time is fine.")
        print("To confirm against reality, grep the server log for:")
        print("    share armor slot flags")
        print("It names the exact form ids each time it happens.")


if __name__ == "__main__":
    main()
