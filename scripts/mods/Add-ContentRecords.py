"""
Add-ContentRecords.py

Adds records to Thornswood-Content.esp, and edits the subrecords of ones already
in it.

WHY

Patrick, 21 September: "the woodworker should be able to make handles that the
smith needs for Pickaxes, Shovels, Axes and other items that have wooden handles
like that", on top of "axes, pickaxes and shovels can eventually break and you
have to get a new one from a smith making them".

A tool that breaks has to be replaceable, and the only honest replacement is one
somebody made. Two of the three already are: ThornswoodRecipeWeaponPickaxe and
ThornswoodRecipeWeaponAxe ship in this plugin, both Smith/Edgewright, one iron
ingot each at a forge. The shovel had no recipe at all, so the sentence a farmer
reads when their shovel snaps was not true for them. And nothing anywhere needed
a woodworker, so a smith could make every tool in the game on their own.

So this adds:

    ThornswoodRecipeKeyMold       one iron ingot into a blank key mold.
    ThornswoodRecipeKey           one iron ingot into a key, named server side
                                  for whichever stamped mold is in the pack.

                                  Both added 23 September, at a forge. The
                                  property system's two items had no maker:
                                  the only mold in the world was conjured by
                                  /mold at a door, so the ceremony had to
                                  happen before the object existed and a smith
                                  on their own could never reach a key.
                                  Patrick: "you make a mold, mold gets used on
                                  door to assign mold to the door, than key
                                  uses that mold during crafting to make a key
                                  to specifically that house and it can be
                                  reused".

    ThornswoodMiscToolHandle      the handle itself. A MISC, cloned from the
                                  charcoal, which already uses
                                  Clutter\\Quest\\TG06CharcoalStick.nif: a stick,
                                  which is what a handle looks like. No new mesh
                                  has to ship.
    ThornswoodRecipeToolHandle    the woodworker turns firewood into handles.
    ThornswoodRecipeToolShovel    the smith makes the shovel that had no recipe.

and edits ThornswoodRecipeWeaponPickaxe and ThornswoodRecipeWeaponAxe so that
both of them want a handle as well as the ingot. After this, no tool in the game
exists without a woodworker and a smith between them.

WHICH BENCH THE HANDLE IS MADE AT, AND THE ONE THAT WAS TRIED FIRST

The handle is made at the charcoal kiln, which is a bench woodworkers already
stand at. The sister half rule means a Woodwright gets the novice work of the
Charburner for nothing, so both halves can cut handles.

WHAT WAS TRIED AND TAKEN BACK OUT, because it is worth somebody not trying it
again. The first attempt overrode all three of Skyrim's chopping block FURN
records, turning WBDT from 00ff, not a bench, to 01ff, the create-object bench
the cooking pot and the tanning rack use, so that every chopping block in the
province became a crafting table. Patrick, the same day: "The chopping block
shouldn't be a bench just for getting the firewood and not usable by non
woodworkers and also have the animation script". So the records are Bethesda's
and untouched, and the chopping block is answered server side in gamemode.js by
chopWood instead: the Woodwright's verb, axe required, firewood out.

THE EXECUTION BLOCK'S SCRIPT, TAKEN OFF (issue #400)

The plugin came from another server, and the last trace of that server's name
in it was a script: FURN 0x05DF7B34, ThornswoodExecutionerChoppingBlock, the
headsman's block placed once in Solitude (REFR 0x05DFCC75), carried a VMAD
attaching KzlChop, with one property pointing at Skyrim.esm's executioner
swing, IDLE 0x0F95BE. KzlChop.pex was never in C:\\Thornswood\\Game, the
Steam copy or any pack, measured 20 and 24 September, so it has never run for
anybody here. It is the headsman's block, not a woodcutting one: firewood comes
from the three vanilla chopping blocks, answered server side by chopWood.

Every way Patrick can settle that block (left as scenery, playing the
executioner's swing from the front plugin, or taken out of Solitude) starts
with the dead attachment gone, so this drops the VMAD from that one record and
touches no other subrecord of it. The form id, the editor id, the name, the
mesh and the placed reference all stay, so the gamemode, the load order check
and every other record see the same plugin with one subrecord fewer. Renaming
the script instead would have needed a compiled Papyrus script under the new
name shipping in a pack, for a feature that does not exist yet.

WHAT IT PROVES BEFORE IT WRITES

The same discipline as Rename-ContentRecords.ps1, Remove-DeadRecords.ps1 and
Remove-DeadConditions.py, whose parser this shares. It serialises the file back
byte for byte before it edits anything. Afterwards it checks that every record
that was there is still there, in the same order, with the same form id, type and
flags; that every record it was not asked to touch has the bytes it started with;
that the new records parse back to exactly what was built; that no form id it
allocates is already taken; that the header's record count matches what is
actually in the file; and that the other server's name (Kzl, kzolivar) is in
no record, compressed ones included.

It will not touch a compressed record, and it refuses to add a record whose
editor id is already in the file, because two records with one name is the kind
of thing that is found months later.

THIS IS A SHIPPED FILE, so its size changing means a release and every client
downloading it again.

Usage (both default to game\\content\\Thornswood-Content.esp in this repo):
    python scripts/mods/Add-ContentRecords.py --check
    python scripts/mods/Add-ContentRecords.py

Exit code 1 if the parse does not round trip, if the result does not verify, or
if anything it was asked to add is already there.
"""

import argparse
import os
import struct
import sys
import zlib

COMPRESSED = 0x00040000

# The headsman's block in Solitude, whose VMAD named KzlChop (see the top).
EXECUTION_BLOCK = 0x5DF7B34

# The other server's naming, in either spelling the plugin used. Lower case,
# because the comparison is.
OTHER_SERVER = (b'kzl', b'kzolivar')

# Form ids for the three new records. The plugin's own records all sit in the
# 0x05______ space; 0x501548E is the highest of the 0x0501____ family in use, so
# these follow it with a gap rather than butting against it.
HANDLE = 0x5015490
RECIPE_HANDLE = 0x5015491
RECIPE_SHOVEL = 0x5015492

# ONE DEED RECORD FOR EVERY PROPERTY IN THE GAME.
#
# Patrick settled the property system on 21 September and this is the measurement
# that made "every building in the game is claimable" affordable: Inventory::Entry
# in the fork carries an optional per-instance name, serialised by name in
# Inventory.h, so one BOOK becomes "Deed to Breezehome" or "Deed to Honeyside" in
# the pack without a record per building. There are 852 claimable buildings and
# this is one record rather than 852.
#
# It is cloned from a passage book, which is a BOOK this plugin already ships and
# already reads as a plain document rather than a spell tome or a skill book.
DEED = 0x5015493

# A KEY AND A KEY MOLD, AND WHY BOTH ARE MISC RATHER THAN KEYM.
#
# Skyrim has a record type for keys and this does not use it. A KEYM lands in the
# Keys tab, which is a list the game treats as yours: a vanilla key is weightless,
# is not dropped, and is not what a pickpocket takes.
#
# Patrick, 21 September, on what a key is for here: it "can be given to people
# used by you or pickpocketed or taken out of unlocked chests or lockpicked", and
# "a stolen key only gets you in". Every one of those is a thing a MISC does and a
# KEYM does not. So a key here is an object somebody carries and can lose, which
# is the whole point of it, and the Keys tab is the wrong home for it.
#
# Both are one record for the whole game, named per instance in the pack exactly
# as the deed is: "Key to Breezehome", "Key mold for Honeyside".
KEY = 0x5015494
MOLD = 0x5015495
RECIPE_MOLD = 0x5015496
RECIPE_KEY = 0x5015497

DEED_WORDS = (
    '<p align="center"><font size="30">Deed</font></p>'
    '<br><br>'
    'This deed sets out the holding of the property written on its cover.'
    '<br><br>'
    '<font size="18">Whoever carries it holds the place. There is no copy and no '
    'register but this. Keep it somewhere a thief will not look, or do not keep it '
    'at all.</font>')

# What the recipes are made of and what they make. Every one of these was read
# out of a record already in this file or out of TOOLS in gamemode.js, never
# remembered.
FIREWOOD = 0x0006F993        # the CNTO of ThornswoodRecipeCharcoalTier1
IRON_INGOT = 0x0005ACE4      # the CNTO of ThornswoodRecipeWeaponPickaxe
SHOVEL = 0x000F5D05          # TOOLS.farmer.give in gamemode.js
KILN_KEYWORD = 0x501547F     # the BNAM of every charcoal recipe
FORGE_KEYWORD = 0x0088105    # the BNAM of the pickaxe and axe recipes

# A handle is worth a little more than the firewood it came from and weighs the
# same as a charcoal stick. Nothing in the rulebook sets either number.
HANDLE_VALUE = 5
HANDLE_WEIGHT = 0.5


def cnto(base, count):
    return struct.pack('<II', base, count)


class Rec(object):
    def __init__(self, tag, flags, fid, extra, data):
        self.tag, self.flags, self.fid = tag, flags, fid
        self.extra, self.data = extra, data

    def bytes(self):
        return (self.tag + struct.pack('<III', len(self.data), self.flags, self.fid)
                + self.extra + self.data)

    @property
    def compressed(self):
        return (self.flags & COMPRESSED) != 0

    def editor_id(self):
        if self.compressed:
            return ''
        for tag, body in subrecords(self.data):
            if tag == b'EDID':
                return body.rstrip(b'\x00').decode('ascii', 'replace')
        return ''


class Grup(object):
    def __init__(self, label, kids):
        self.label, self.kids = label, kids

    def bytes(self):
        body = b''.join(k.bytes() for k in self.kids)
        return b'GRUP' + struct.pack('<I', len(body) + 24) + self.label + body


def subrecords(data):
    out, i = [], 0
    while i + 6 <= len(data):
        tag = data[i:i + 4]
        size = struct.unpack_from('<H', data, i + 4)[0]
        if i + 6 + size > len(data):
            break
        out.append((tag, data[i + 6:i + 6 + size]))
        i += 6 + size
    return out


def pack_subrecords(pairs):
    return b''.join(t + struct.pack('<H', len(b)) + b for t, b in pairs)


def zstr(s):
    return s.encode('ascii') + b'\x00'


def parse(buf, start, end):
    kids, p = [], start
    while p + 24 <= end:
        tag = buf[p:p + 4]
        size = struct.unpack_from('<I', buf, p + 4)[0]
        if tag == b'GRUP':
            kids.append(Grup(buf[p + 8:p + 24], parse(buf, p + 24, p + size)))
            p += size
        else:
            flags, fid = struct.unpack_from('<II', buf, p + 8)
            kids.append(Rec(tag, flags, fid, buf[p + 16:p + 24],
                            buf[p + 24:p + 24 + size]))
            p += 24 + size
    return kids


def every_record(kids):
    for k in kids:
        if isinstance(k, Grup):
            for r in every_record(k.kids):
                yield r
        else:
            yield k


def top_group(tree, tag):
    for k in tree:
        if isinstance(k, Grup) and k.label[:4] == tag:
            return k
    raise SystemExit('no top level %s group in this plugin' % tag.decode())


def clone(src, fid, editor_id, sets=None, after=None, drop=None):
    """A copy of src with a new id and editor id, and named subrecords changed.

    sets    tag -> bytes, replacing the first subrecord with that tag.
    after   tag -> list of (tag, bytes) to insert after the last one with that tag.
    drop    tags to leave out.
    """
    sets, after, drop = sets or {}, after or {}, set(drop or ())
    pairs = [(t, b) for t, b in subrecords(src.data) if t not in drop]
    pairs = [(t, sets.pop(t, b)) if t in sets else (t, b) for t, b in pairs]
    if sets:
        raise SystemExit('nothing to replace for ' + ','.join(t.decode() for t in sets))
    out = []
    for i, (t, b) in enumerate(pairs):
        out.append((t, b))
        last = max(j for j, (tt, _) in enumerate(pairs) if tt == t) if t in after else -1
        if t in after and i == last:
            out.extend(after[t])
    out = [(t, zstr(editor_id)) if t == b'EDID' else (t, b) for t, b in out]
    return Rec(src.tag, src.flags, fid, src.extra, pack_subrecords(out))


def wants_handle(rec):
    """One more input on a recipe that already has one, and the count bumped."""
    pairs = subrecords(rec.data)
    have = sum(1 for t, _ in pairs if t == b'CNTO')
    out = []
    for i, (t, b) in enumerate(pairs):
        if t == b'COCT':
            out.append((t, struct.pack('<I', have + 1)))
            continue
        out.append((t, b))
        if t == b'CNTO' and i == max(j for j, (tt, _) in enumerate(pairs) if tt == b'CNTO'):
            out.append((b'CNTO', cnto(HANDLE, 1)))
    rec.data = pack_subrecords(out)


def drop_script(rec):
    """Takes the VMAD off a record and leaves every other subrecord as it was.

    True when there was one to take. Refuses (SystemExit) when the record's
    subrecords do not pack back to its own bytes, because then dropping one of
    them would be a guess about the rest."""
    pairs = subrecords(rec.data)
    if pack_subrecords(pairs) != rec.data:
        raise SystemExit('STOP. 0x%07X does not read back as its own subrecords. '
                         'Nothing was written.' % rec.fid)
    kept = [(t, b) for t, b in pairs if t != b'VMAD']
    if len(kept) == len(pairs):
        return False
    rec.data = pack_subrecords(kept)
    return True


def other_server_names(rec):
    """Where the other server's name is in one record: its editor id, or a
    script its VMAD attaches. A compressed record is inflated to be read, and
    never written back from here."""
    data = rec.data
    if rec.compressed:
        data = zlib.decompress(data[4:])
    found = []
    for tag, body in subrecords(data):
        low = body.lower()
        if tag == b'EDID' and low.startswith(OTHER_SERVER):
            found.append('editor id ' + body.rstrip(b'\x00').decode('ascii', 'replace'))
        elif tag == b'VMAD' and any(n in low for n in OTHER_SERVER):
            found.append('a script it attaches')
    return found


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', default=os.path.normpath(
        os.path.join(here, '..', '..', 'game', 'content')))
    ap.add_argument('--plugin', default='Thornswood-Content.esp')
    ap.add_argument('--check', action='store_true', help='say what would happen, write nothing')
    args = ap.parse_args()

    path = os.path.join(args.data, args.plugin)
    raw = open(path, 'rb').read()
    print('The file')
    print('  %s' % path)
    print('  %s bytes' % format(len(raw), ','))

    header_size = struct.unpack_from('<I', raw, 4)[0]
    head = bytearray(raw[:24 + header_size])
    tree = parse(raw, 24 + header_size, len(raw))

    print('')
    print('Can the parser reproduce the file it was given')
    if bytes(head) + b''.join(k.bytes() for k in tree) != raw:
        print('STOP. the parse does not round trip. Nothing was written.')
        return 1
    print('  ok    parsed and written back byte for byte, %s bytes' % format(len(raw), ','))

    records = list(every_record(tree))
    by_edid = {}
    for r in records:
        e = r.editor_id()
        if e:
            by_edid[e] = r
    taken = set(r.fid for r in records)
    before = {r.fid: r.data for r in records}

    # ALREADY THERE IS NOT AN ERROR, BUT A DIFFERENT RECORD UNDER THE SAME NAME
    # IS. This script is run again every time the plugin grows another record, so
    # it says what is already in place and adds what is not. What it will not do
    # is write a second record with an editor id the file already uses: two
    # records under one name is the kind of thing that is found months later.
    already = set()
    for name, fid in (('ThornswoodMiscToolHandle', HANDLE),
                      ('ThornswoodRecipeToolHandle', RECIPE_HANDLE),
                      ('ThornswoodRecipeToolShovel', RECIPE_SHOVEL),
                      ('ThornswoodBookDeed', DEED),
                      ('ThornswoodMiscKey', KEY),
                      ('ThornswoodMiscKeyMold', MOLD),
                      ('ThornswoodRecipeKeyMold', RECIPE_MOLD),
                      ('ThornswoodRecipeKey', RECIPE_KEY)):
        here_already = name in by_edid
        if here_already and by_edid[name].fid != fid:
            print('')
            print('STOP. %s is already in this plugin as 0x%07X and this would add it as '
                  '0x%07X. Nothing was written.' % (name, by_edid[name].fid, fid))
            return 1
        if here_already:
            already.add(name)
        elif fid in taken:
            print('')
            print('STOP. 0x%07X is already taken. Nothing was written.' % fid)
            return 1
    if already:
        print('')
        print('Already in the plugin, so not added again')
        for name in sorted(already):
            print('  %s' % name)
    misc_src = by_edid['ThornswoodCharcoalTier1']
    cobj_charcoal = by_edid['ThornswoodRecipeCharcoalTier1']
    cobj_pickaxe = by_edid['ThornswoodRecipeWeaponPickaxe']
    cobj_axe = by_edid['ThornswoodRecipeWeaponAxe']
    # Looked up by form id, which is what the gamemode and the load order use.
    # Absent is not an error: taking the block out of the plugin is one of the
    # choices, and then there is no script to take off it.
    block = next((r for r in records if r.fid == EXECUTION_BLOCK and r.tag == b'FURN'), None)
    block_scripted = block is not None and any(t == b'VMAD' for t, _ in subrecords(block.data))

    handle = clone(misc_src, HANDLE, 'ThornswoodMiscToolHandle', sets={
        b'FULL': zstr('Tool Handle'),
        b'DATA': struct.pack('<If', HANDLE_VALUE, HANDLE_WEIGHT),
    })
    make_handle = clone(cobj_charcoal, RECIPE_HANDLE, 'ThornswoodRecipeToolHandle', sets={
        b'CNTO': cnto(FIREWOOD, 1),
        b'CNAM': struct.pack('<I', HANDLE),
        b'BNAM': struct.pack('<I', KILN_KEYWORD),
    })
    # The body is the same on every deed, because there is only one record. What
    # property it is, is the per-instance name in the pack, and the words below
    # are why a stolen one is worth stealing: whoever carries it holds the place.
    deed = clone(by_edid['ThornswoodPassageWhiterun'], DEED, 'ThornswoodBookDeed', sets={
        b'FULL': zstr('Deed'),
        b'DESC': zstr(DEED_WORDS),
    })
    # A key and its mold, both cloned from the charcoal MISC for the same reason
    # the handle was: it already uses a small clutter mesh, so no new art ships.
    key = clone(misc_src, KEY, 'ThornswoodMiscKey', sets={
        b'FULL': zstr('Key'),
        b'DATA': struct.pack('<If', 0, 0.0),
    })
    mold = clone(misc_src, MOLD, 'ThornswoodMiscKeyMold', sets={
        b'FULL': zstr('Key Mold'),
        b'DATA': struct.pack('<If', 25, 1.0),
    })
    # THE MOLD AND THE KEY ARE BOTH MADE BY A SMITH, WHICH IS WHAT MAKES THE
    # CHAIN START AT ALL.
    #
    # Patrick, 23 September: "Wait how tf does someone use a mold if you can't
    # make a key to own the building make this shit make sense make a fucking
    # mold item craftable dude this would solve alot", and then the whole
    # shape: "The key should be too what should happen is you make a mold,
    # mold gets used on door to assign mold to the door, than key uses that
    # mold during crafting to make a key to specifically that house and it can
    # be reused".
    #
    # He is right and it was circular. Both records have been in this plugin
    # since the property system was built and nothing in the game made either
    # one: the only mold in the world was conjured out of nothing by /mold at
    # a door, so the ceremony had to happen before the object existed, and a
    # smith on their own could never reach a key at all.
    #
    # ONE IRON INGOT EACH, at a forge, the same shape as the pickaxe and the
    # axe beside them. The mold is the blank; the door stamps it; the key
    # recipe is answered server side by which stamped mold is in the pack, so
    # the key comes out named for that house and THE MOLD IS NOT CONSUMED.
    # That is why the mold is not an input here: a CNTO is taken away by the
    # engine before the server is asked, and he asked for it to be reusable.
    #
    # Both cloned from the charcoal recipe rather than the pickaxe, because
    # the pickaxe wants a handle as well and carries COCT 2. These take one
    # input each.
    make_mold = clone(cobj_charcoal, RECIPE_MOLD, 'ThornswoodRecipeKeyMold', sets={
        b'CNTO': cnto(IRON_INGOT, 1),
        b'CNAM': struct.pack('<I', MOLD),
        b'BNAM': struct.pack('<I', FORGE_KEYWORD),
    })
    make_key = clone(cobj_charcoal, RECIPE_KEY, 'ThornswoodRecipeKey', sets={
        b'CNTO': cnto(IRON_INGOT, 1),
        b'CNAM': struct.pack('<I', KEY),
        b'BNAM': struct.pack('<I', FORGE_KEYWORD),
    })
    make_shovel = clone(cobj_pickaxe, RECIPE_SHOVEL, 'ThornswoodRecipeToolShovel', sets={
        b'CNAM': struct.pack('<I', SHOVEL),
    }, after={b'CNTO': [(b'CNTO', cnto(HANDLE, 1))]})
    # The clone copied COCT 1 from the pickaxe and the shovel now has two inputs.
    make_shovel.data = pack_subrecords(
        [(t, struct.pack('<I', 2)) if t == b'COCT' else (t, b)
         for t, b in subrecords(make_shovel.data)])

    print('')
    print('What goes in')
    print('  MISC 0x%07X ThornswoodMiscToolHandle      Tool Handle, %d gold, %s weight'
          % (HANDLE, HANDLE_VALUE, HANDLE_WEIGHT))
    print('  COBJ 0x%07X ThornswoodRecipeToolHandle    1 firewood -> 1 handle, at the kiln'
          % RECIPE_HANDLE)
    print('  COBJ 0x%07X ThornswoodRecipeToolShovel    1 iron ingot + 1 handle -> 1 shovel, at a forge'
          % RECIPE_SHOVEL)
    print('  BOOK 0x%07X ThornswoodBookDeed            one record, named per instance in the pack'
          % DEED)
    print('  MISC 0x%07X ThornswoodMiscKey             a key somebody can lose, so MISC and not KEYM'
          % KEY)
    print('  MISC 0x%07X ThornswoodMiscKeyMold         the mold a smith cuts keys from'
          % MOLD)
    print('  COBJ 0x%07X ThornswoodRecipeKeyMold       1 iron ingot -> 1 blank mold, at a forge'
          % RECIPE_MOLD)
    print('  COBJ 0x%07X ThornswoodRecipeKey           1 iron ingot -> 1 key, at a forge, named '
          'by the stamped mold in the pack'
          % RECIPE_KEY)
    print('')
    print('What changes')
    print('  COBJ 0x%07X ThornswoodRecipeWeaponPickaxe now wants a handle as well as the ingot'
          % cobj_pickaxe.fid)
    print('  COBJ 0x%07X ThornswoodRecipeWeaponAxe     now wants a handle as well as the ingot'
          % cobj_axe.fid)
    if block_scripted:
        print('  FURN 0x%07X %s loses the script it named, which never shipped'
              % (block.fid, block.editor_id()))

    if args.check:
        print('')
        print('  --check, so nothing was written.')
        return 0

    built = [r for r in (handle, make_handle, make_shovel, deed, key, mold,
                         make_mold, make_key)
             if r.editor_id() not in already]
    # An edit that has already been made is not made twice. A recipe that already
    # asks for a handle would otherwise gain a second one on every run.
    edited = set()
    for rec in (cobj_pickaxe, cobj_axe):
        if any(t == b'CNTO' and len(b) >= 4 and
               struct.unpack_from('<I', b, 0)[0] == HANDLE
               for t, b in subrecords(rec.data)):
            continue
        wants_handle(rec)
        edited.add(rec.fid)
    if block is not None and drop_script(block):
        edited.add(block.fid)
    if not built and not edited:
        print('')
        print('  Everything this adds is already in the plugin. Nothing was written.')
        return 0
    for r in built:
        top_group(tree, r.tag).kids.append(r)

    # The header's record count, which sits in HEDR after the version float.
    #
    # IT IS SET TO THE TRUE COUNT RATHER THAN ADDED TO, because the number in
    # the file is wrong and has been for as long as this repo has had the file.
    # Measured 21 September across three copies: before the conditions edit,
    # before the manual trim, and after, the header said 408 every time, while
    # the file actually held 392, 392 and 376. So neither
    # Rename-ContentRecords.ps1 nor Remove-DeadRecords.ps1 has ever touched it,
    # and the plugin has been shipping and working at 408 against 392, which is
    # the evidence that the engine does not read it. Adding three to a wrong
    # number would keep it wrong; this writes what is actually there.
    hedr = head.find(b'HEDR')
    if hedr < 0:
        print('STOP. no HEDR in the header. Nothing was written.')
        return 1
    claimed = struct.unpack_from('<i', head, hedr + 6 + 4)[0]
    struct.pack_into('<i', head, hedr + 6 + 4, len(records) + len(built))
    if claimed != len(records):
        print('')
        print('The header record count was wrong before this ran')
        print('  it said %d and the file held %d. Setting it to %d.'
              % (claimed, len(records), len(records) + len(built)))

    out = bytes(head) + b''.join(k.bytes() for k in tree)

    print('')
    print('Does the result verify')
    after_records = list(every_record(parse(out, 24 + header_size, len(out))))
    if len(after_records) != len(records) + len(built):
        print('  STOP. %d records in, %d out, expected %d. Nothing was written.'
              % (len(records), len(after_records), len(records) + len(built)))
        return 1
    added = set(r.fid for r in built)
    seen = []
    for r in after_records:
        if r.fid in added:
            continue
        seen.append(r)
    for was_r, now in zip(records, seen):
        if was_r.fid != now.fid or was_r.tag != now.tag or was_r.flags != now.flags:
            print('  STOP. 0x%07X changed identity. Nothing was written.' % was_r.fid)
            return 1
        if now.fid not in edited and now.data != before[was_r.fid]:
            print('  STOP. 0x%07X was not on the list and its bytes changed. '
                  'Nothing was written.' % now.fid)
            return 1
    made = dict((r.fid, r) for r in after_records if r.fid in added)
    for b in built:
        if made[b.fid].data != b.data:
            print('  STOP. 0x%07X did not come back as it was built. Nothing was written.'
                  % b.fid)
            return 1
    if block is not None and block.fid in edited:
        now = next(r for r in after_records if r.fid == block.fid)
        want = [(t, b) for t, b in subrecords(before[block.fid]) if t != b'VMAD']
        if subrecords(now.data) != want:
            print('  STOP. 0x%07X lost more than its script. Nothing was written.' % block.fid)
            return 1
    left = [(r, w) for r in after_records for w in other_server_names(r)]
    if left:
        for r, w in left:
            print('  STOP. %s 0x%07X still carries the other server\'s name: %s'
                  % (r.tag.decode(), r.fid, w))
        print('  Nothing was written.')
        return 1
    count = struct.unpack_from('<i', out, hedr + 6 + 4)[0]
    if count != len(after_records):
        print('  STOP. the header says %d records and there are %d. Nothing was written.'
              % (count, len(after_records)))
        return 1
    print('  ok    %d records in, %d out, same order, same ids, same flags'
          % (len(records), len(after_records)))
    print('  ok    %d added, %d edited, every other byte untouched'
          % (len(built), len(edited)))
    print('  ok    the header record count reads %d, which is what is in the file' % count)
    print('  ok    no record carries the other server\'s name, compressed ones included')

    open(path, 'wb').write(out)
    print('')
    print('  %s bytes -> %s bytes' % (format(len(raw), ','), format(len(out), ',')))
    print('  THIS IS A SHIPPED FILE. Its size changed, so this needs a release and')
    print('  every client will download it again.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
