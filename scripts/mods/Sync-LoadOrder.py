#!/usr/bin/env python3
"""
Make the server's load order the same list the game actually loads.

The client builds its list from Game.getModCount / Game.getModName and compares
it against the server's POSITIONALLY, on filename, byte size and crc32. Any
disagreement is a red LOAD ORDER ERROR. Three things make that list, and none
of them are obvious from plugins.txt:

  * The base masters are not in plugins.txt at all. Skyrim loads them first.
  * ESM flagged plugins load before ESP flagged ones whatever order
    plugins.txt lists them in.
  * Light plugins do not appear in Game.getModName at all, so they must NOT be
    in the server's list either. That includes .esl files and any .esp carrying
    the light flag in its header.

So this reads the TES4 header of every active plugin, sorts them the way the
engine does, drops the light ones, and writes the result into
server-settings.json. Everything else in that file is left alone.

  python Sync-LoadOrder.py

Run it with no arguments for the Thornswood layout, or override the paths.
"""

import os
import sys
import json
import zlib
import struct
import argparse
import collections

# Not in plugins.txt, always loaded, always first, in this order.
IMPLICIT_MASTERS = [
    "Skyrim.esm", "Update.esm", "Dawnguard.esm", "HearthFires.esm",
    "Dragonborn.esm",
]

FLAG_MASTER = 0x00000001
FLAG_LIGHT = 0x00000200


def header_flags(path):
    """The record flags out of the TES4 header, which is always first."""
    with open(path, "rb") as fh:
        head = fh.read(16)
    if len(head) < 16 or head[:4] != b"TES4":
        raise ValueError("not a plugin: %s" % os.path.basename(path))
    return struct.unpack_from("<I", head, 8)[0]


def crc32_of(path):
    crc = 0
    with open(path, "rb") as fh:
        while True:
            chunk = fh.read(1 << 20)
            if not chunk:
                break
            crc = zlib.crc32(chunk, crc)
    return crc & 0xFFFFFFFF


def active_plugins(plugins_txt):
    out = []
    with open(plugins_txt, encoding="utf-8-sig") as fh:
        for line in fh:
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            if s.startswith("*"):            # * means enabled
                out.append(s[1:].strip())
    return out


def default_settings():
    # The fork is the engine\skymp submodule of this repository: the same
    # rule as scripts\release\Where.ps1, which the PowerShell scripts ask.
    # This file is in scripts\mods, so the repository is three folders up.
    # It was two until 28 September, which since phase 8 of issue #440 found
    # scripts\engine\skymp, missed, and fell back to the old folder no
    # machine has any more (that fallback went the same day).
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.dirname(os.path.dirname(here))
    fork = os.path.join(repo, "engine", "skymp")
    return os.path.join(fork, "build", "dist", "server", "server-settings.json")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--plugins",
                    default=r"C:\Thornswood\Profile\LocalAppData\Plugins.txt")
    ap.add_argument("--data", default=r"C:\Thornswood\Game\Data")
    ap.add_argument("--settings", default=default_settings())
    ap.add_argument("--server-data", default="C:/Thornswood/Game/Data",
                    help="how the SERVER sees its Data folder, forward slashes")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    listed = active_plugins(args.plugins)
    names = [m for m in IMPLICIT_MASTERS if m.lower() not in
             {x.lower() for x in listed}] + listed

    masters, normals, light, missing = [], [], [], []
    for name in names:
        path = os.path.join(args.data, name)
        if not os.path.exists(path):
            missing.append(name)
            continue
        try:
            flags = header_flags(path)
        except ValueError as exc:
            print("  skipped, %s" % exc)
            continue
        if flags & FLAG_LIGHT or name.lower().endswith(".esl"):
            light.append(name)
        elif flags & FLAG_MASTER or name.lower().endswith(".esm"):
            masters.append(name)
        else:
            normals.append(name)

    order = masters + normals

    print("=" * 70)
    print("active in plugins.txt : %d" % len(listed))
    print("light, excluded       : %d" % len(light))
    print("missing from Data     : %d" % len(missing))
    print("FINAL SERVER ORDER    : %d" % len(order))
    print("=" * 70)
    for i, n in enumerate(order):
        print("  %3d  %s" % (i, n))

    if light:
        print("\nExcluded as light (the client never reports these):")
        for n in light:
            print("    %s" % n)
    if missing:
        print("\nLISTED BUT NOT IN %s:" % args.data)
        for n in missing:
            print("    %s" % n)
        print("  Fix these before trusting the result.")

    with open(args.settings, encoding="utf-8-sig") as fh:
        cfg = json.load(fh, object_pairs_hook=collections.OrderedDict)

    before = len(cfg.get("loadOrder", []))
    cfg["loadOrder"] = ["%s/%s" % (args.server_data.rstrip("/"), n)
                        for n in order]

    print("\nloadOrder: %d -> %d entries" % (before, len(order)))

    if args.dry_run:
        print("dry run, nothing written")
        return

    with open(args.settings, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps(cfg, indent=2) + "\n")
    print("wrote %s" % args.settings)

    print("\nThe server needs these %d files present at %s on the machine it"
          % (len(order), args.server_data))
    print("runs on. Copy any it does not already have, then restart it.")


if __name__ == "__main__":
    main()
