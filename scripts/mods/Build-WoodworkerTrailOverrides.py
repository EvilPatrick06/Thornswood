"""Build Thornswood-WoodworkerTrail.esp for issue #516 (i).

The 53 Woodworker forge recipes that Thornswood-Content.esp cannot override
(Immersive Weapons, PlayFluteLuteDrum, Playable Rieklings, MoreCraftableEquipment,
FishingInSkyrim) are listed in woodworker-trail-recipes.json. This script copies
each COBJ from its source plugin, renumbers form ids into the trail plugin's
master list, and sets BNAM to ThornswoodCraftingWoodworking from Content.esp.

The trail plugin must load last in the collection. Masters (in order):
  Skyrim.esm, Update.esm, Dawnguard.esm, HearthFires.esm, Dragonborn.esm,
  Thornswood-Content.esp, MoreCraftableEquipment.esp, FishingInSkyrim.esp,
  Immersive Weapons.esp, PlayFluteLuteDrum.esp, Playable Rieklings.esp

Usage:
  python scripts/mods/Build-WoodworkerTrailOverrides.py --check
  python scripts/mods/Build-WoodworkerTrailOverrides.py --masters C:\\Thornswood\\Game\\Data

--check only verifies every listed recipe is readable from --masters and prints
what would ship. A real write needs every master esp/esm present in --masters.
Collection Nexus upload and load-order pin are Claude's (claude-queue/516).
"""
from __future__ import print_function

import argparse
import json
import os
import struct
import sys

# Reuse the Content ESP tooling rather than inventing a second writer.
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import importlib.util
spec = importlib.util.spec_from_file_location(
    "add_content", os.path.join(HERE, "Add-ContentRecords.py"))
acr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(acr)

CONTENT_KEYWORD_LOCAL = 0x0154E1  # 0x50154E1 without the 05 load index
CONTENT_PLUGIN = "Thornswood-Content.esp"
LIST_NAME = "woodworker-trail-recipes.json"
OUT_NAME = "Thornswood-WoodworkerTrail.esp"

MASTER_ORDER = [
    "Skyrim.esm",
    "Update.esm",
    "Dawnguard.esm",
    "HearthFires.esm",
    "Dragonborn.esm",
    "RaceCompatibility.esm",
    "Thornswood-Content.esp",
    "MoreCraftableEquipment.esp",
    "FishingInSkyrim.esp",
    "Immersive Weapons.esp",
    "PlayFluteLuteDrum.esp",
    "Playable Rieklings.esp",
]


def load_list():
    path = os.path.join(HERE, LIST_NAME)
    data = json.load(open(path, encoding="utf-8"))
    if data.get("count") != len(data.get("recipes") or []):
        raise SystemExit("STOP. %s count does not match recipes list." % LIST_NAME)
    return data


def zstr(s):
    return s.encode("ascii") + b"\x00"


def tes4_header(masters):
    """A minimal TES4 header for a new .esp with the given master list."""
    # HEDR: version 1.7, numRecords placeholder, nextObjectId
    hedr = struct.pack("<fiI", 1.7, 0, 0x800)
    body = [(b"HEDR", hedr), (b"CNAM", zstr("Thornswood")), (b"SNAM", zstr("Woodworker trail overrides (#516)"))]
    for m in masters:
        body.append((b"MAST", zstr(m)))
        body.append((b"DATA", struct.pack("<Q", 0)))
    data = acr.pack_subrecords(body)
    # flags: 0x01 = esm? no; esp uses 0. Record header TES4
    return acr.Rec(b"TES4", 0, 0, b"\x00" * 8, data)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--masters", default=r"C:\Thornswood\Game\Data")
    ap.add_argument("--out", default=os.path.join(HERE, "..", "..", "game", "content", OUT_NAME))
    args = ap.parse_args()

    listing = load_list()
    print("Trail list")
    print("  %s (%d recipes)" % (LIST_NAME, listing["count"]))
    print("  target keyword %s" % listing["targetKeyword"]["formIdInContent"])

    missing = [m for m in MASTER_ORDER if not os.path.isfile(os.path.join(args.masters, m))]
    print("")
    print("Masters in %s" % args.masters)
    for m in MASTER_ORDER:
        path = os.path.join(args.masters, m)
        print("  %s  %s" % ("ok   " if os.path.isfile(path) else "MISS ", m))

    # Content keyword must exist for the trail BNAM to resolve.
    candidates = [
        os.path.join(args.masters, CONTENT_PLUGIN),
        os.path.normpath(os.path.join(HERE, "..", "..", "game", "content", CONTENT_PLUGIN)),
    ]
    rec = None
    content_path = None
    for candidate in candidates:
        if not os.path.isfile(candidate):
            continue
        raw = open(candidate, "rb").read()
        header_size = struct.unpack_from("<I", raw, 4)[0]
        for r in acr.every_record(acr.parse(raw, 24 + header_size, len(raw))):
            if r.tag == b"KYWD" and r.editor_id() == "ThornswoodCraftingWoodworking":
                rec = r
                content_path = candidate
                break
        if rec is not None:
            break
    if rec is None:
        print("")
        print("STOP. ThornswoodCraftingWoodworking is not in Content.esp yet.")
        print("  Checked: %s" % ", ".join(candidates))
        print("  Run Add-ContentRecords.py on the repo copy first.")
        return 1
    print("")
    print("Content keyword")
    print("  ok    %s 0x%08X (from %s)" % (rec.editor_id(), rec.fid, content_path))

    readable = []
    unread = []
    for row in listing["recipes"]:
        master = row["plugin"]
        local = int(row["localFormId"], 16)
        path = os.path.join(args.masters, master)
        if not os.path.isfile(path):
            unread.append((row, "master file missing"))
            continue
        try:
            # from_master needs the trail's master list; for --check just confirm record exists.
            buf = open(path, "rb").read()
            src_masters = acr.masters_of(buf)
            own = len(src_masters)
            rec = acr.record_in(buf, b"COBJ", (own << 24) | (local & 0xFFFFFF))
            if rec is None:
                unread.append((row, "no COBJ 0x%06X" % local))
                continue
            if rec.editor_id() and rec.editor_id() != row["editorId"]:
                unread.append((row, "editor id %s != %s" % (rec.editor_id(), row["editorId"])))
                continue
            readable.append(row)
        except Exception as e:
            unread.append((row, str(e)))

    print("")
    print("Recipes")
    print("  readable %d / %d" % (len(readable), listing["count"]))
    if unread:
        print("  unread   %d" % len(unread))
        for row, why in unread[:12]:
            print("    %s (%s): %s" % (row["editorId"], row["plugin"], why))
        if len(unread) > 12:
            print("    ... and %d more" % (len(unread) - 12))

    print("")
    print("Load order")
    print("  " + listing["loadOrderNote"])

    if args.check or missing or unread:
        print("")
        if args.check:
            print("  --check, so nothing was written.")
        elif missing:
            print("  Masters missing under --masters; nothing was written.")
            print("  Put the collection plugins in Data (or point --masters) and run without --check.")
        elif unread:
            print("  Some recipes could not be read; nothing was written.")
        print("  When every master is present, re-run without --check to write %s." % OUT_NAME)
        print("  Collection upload remains Claude's job (claude-queue note for #516).")
        return 0 if args.check and not unread else (0 if args.check else 1)

    # Build path: create overrides with from_master into a new esp.
    # Keyword BNAM points at Content's KYWD: Content is master index 5 in MASTER_ORDER.
    content_idx = MASTER_ORDER.index(CONTENT_PLUGIN)
    wood_kw = (content_idx << 24) | CONTENT_KEYWORD_LOCAL

    built = []
    for row in listing["recipes"]:
        master = row["plugin"]
        local = int(row["localFormId"], 16)
        # Form id in the trail plugin: master's index in MASTER_ORDER, same local.
        master_idx = MASTER_ORDER.index(master)
        fid = (master_idx << 24) | (local & 0xFFFFFF)
        made = acr.from_master(args.masters, master, fid, MASTER_ORDER)
        if made.editor_id() != row["editorId"]:
            print("STOP. %s 0x%06X came back as %s." % (master, local, made.editor_id()))
            return 1
        acr.set_bnam(made, wood_kw)
        # Force the record's own form id to the trail numbering (from_master already did).
        built.append(made)

    # Assemble a new plugin: TES4 + COBJ GRUP
    header = tes4_header(MASTER_ORDER)
    # Fix HEDR record count
    pairs = acr.subrecords(header.data)
    out_pairs = []
    for t, b in pairs:
        if t == b"HEDR" and len(b) >= 8:
            b = bytearray(b)
            struct.pack_into("<i", b, 4, len(built))
            b = bytes(b)
        out_pairs.append((t, b))
    header.data = acr.pack_subrecords(out_pairs)
    # TES4 is written as raw header, not via Rec.bytes the same way - use file layout:
    # TES4 record then GRUPs. Rec.bytes works for TES4 with fid 0.
    cobj_group = acr.Grup(b"COBJ" + b"\x00" * 8 + b"\x00" * 4, built)
    out = header.bytes() + cobj_group.bytes()

    out_path = os.path.normpath(args.out)
    open(out_path, "wb").write(out)
    print("")
    print("Wrote")
    print("  %s" % out_path)
    print("  %d overrides, BNAM -> 0x%08X" % (len(built), wood_kw))
    print("  THIS IS A COLLECTION FILE. Claude ships it in the next collection revision.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
