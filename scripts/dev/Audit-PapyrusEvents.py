#!/usr/bin/env python3
"""
Audit-PapyrusEvents.py

Which scripts in the load order can still do anything under Thornswood, and
which mods are only their records.

WHY IT EXISTS

On 20 September Patrick reported that "a lot of the mods in our list are just
straight up not present in the game". It is not the load order: every plugin
loads, and the ones that look missing are light plugins the load order file
cannot see (entry 168). They are loaded and doing nothing, because the client
blocks Papyrus events, and from a chair that is indistinguishable from not
being installed. Entry 323 asks for a decision per event, which ones the server
could allow, and for the mods that only work through blocked events to come
out of the collection. Neither can be decided without knowing which events the
collection's scripts wait on, and nothing in this repo had ever read a .pex.
This does.

THE RULE, as the fork has it. skymp5-client's BlockPapyrusEventsService turns
the blocker on at the first tick. skyrim-platform's FridaHooks.cpp:43-72, on
thornswood/engine-changes, hooks the VM's SendEvent and blanks the event name
unless it is exactly OnUpdate, or unless one of the scripts attached to the
same object is named SKI_ something (SkyUI; four characters compared with
case) or defaultDisableHavokOnLoad (compared without). The entry's first plan
pointed at Patch-Client.ps1, which is gone; the rule is in the fork's source.

WHAT COUNTS AS AN EVENT. A .pex does not mark an event as different from a
function, so this takes the game's own word for it. A native script declares
the events native code will send it as empty functions: Form.pex declares
OnUpdate and OnMenuOpen, ObjectReference.pex OnActivate, PO3_Events_Form.pex
OnQuestStageChange. So every empty, non-native, non-global function in a
script that has native functions is an event name. Add OnInit, which the VM
sends to every script and no script declares, and every callback a script
names in RegisterForModEvent. Leave out onBeginState and onEndState: every
compiled script carries them and GotoState calls them, so they start nothing.
Anything else a script calls OnSomething, SkyUI's OnPageReset for one, is an
ordinary function called by another script, and this hook does not touch it.

A script handles an event when it, or a script it extends, has a body for it
in any state. The nearest definition wins, so a child that declares an event
empty has switched its parent's off.

A TIMER HAS TO BE STARTED. OnUpdate only arrives after RegisterForUpdate or
RegisterForSingleUpdate. For every script that handles OnUpdate this follows
the script's calls to itself from each event and lists the events that reach a
registration. The timer is counted as never starting, rather than as working,
only when all three hold: every event that reaches a registration is blocked;
no script anywhere calls in, by name, to a function on the way to one; and
nothing else the plugin attaches registers a timer on another object, the way
QuickLootIE's load alias starts its maintenance quest. Anything less certain
than that is counted as able to run.

WHAT IT READS. The five masters and plugins.txt, masters first as the engine
sorts them. The VMAD of every record in every plugin: the scripts on each
record and on each quest alias, and the fragment script on quests, dialogue,
scenes, packages and perks. The last plugin to define a record decides its
scripts, and a script is credited to the plugin that first put it there, so a
patch carrying a vanilla script forward does not make it the patch's. Scripts
come from Data\\Scripts first, then from the archives, a later one winning, as
the game reads them.

WHAT IT DOES NOT KNOW, and says so rather than guess.
  Fragments. Quest stage, dialogue, scene, package and perk fragments are
  functions the engine calls by name, Fragment_0 and on, not events. Whether
  that call passes through the hook has not been checked, so they are counted
  and not judged.
  Whether a given event reaches SendEvent at all. The rule above blanks what
  passes through it. Nothing here was measured in the game.
  A placed reference and its base object are one object in the game, so a
  defaultDisableHavokOnLoad on a reference unblocks its base's scripts there.
  This judges each record and alias on its own.
  A timer another script starts, by calling into this one or registering it.
  An archive named after no plugin is counted as loaded, which is right for
  the Skyrim - ones the ini lists and may be wrong for a stray one.

Read only. It writes nothing unless --json names a file.

  python scripts/dev/Audit-PapyrusEvents.py
  python scripts/dev/Audit-PapyrusEvents.py --json papyrus-events.json
  python scripts/dev/Audit-PapyrusEvents.py --data D:\\Game\\Data --plugins D:\\plugins.txt
"""

import argparse
import io
import json
import os
import struct
import sys
import zlib
from collections import defaultdict

import bsa

MASTERS = ['Skyrim.esm', 'Update.esm', 'Dawnguard.esm', 'HearthFires.esm', 'Dragonborn.esm']

# FridaHooks.cpp:44, the one event name the blocker lets through.
ALLOWED = 'onupdate'
# FridaHooks.cpp:56-66. The SkyUI test compares four characters with case; the
# other is stricmp.
EXEMPT_PREFIX = 'SKI_'
EXEMPT_NAME = 'defaultdisablehavokonload'

IMPLICIT_EVENTS = {'oninit': 'OnInit'}
NOT_EVENTS = {'onbeginstate', 'onendstate'}
TIMER_CALLS = {'registerforupdate', 'registerforsingleupdate'}
MOD_EVENT_CALL = 'registerformodevent'

FLAG_MASTER = 0x00000001
COMPRESSED = 0x00040000
# Never scripted, and the bulk of the compressed records in the masters.
UNSCRIPTED = {b'LAND', b'NAVM', b'NAVI'}
FRAGMENT_TYPES = {b'INFO', b'PACK', b'PERK', b'QUST', b'SCEN'}

# How many operands each Skyrim Papyrus opcode takes, by opcode. The three calls
# (callmethod, callparent, callstatic) take a counted list of arguments after.
OPERANDS = [0, 3, 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3,
            1, 2, 2, 3, 2, 3, 1, 3, 3, 3, 2, 2, 3, 3, 4, 4]
CALLMETHOD, CALLPARENT, CALLSTATIC = 0x17, 0x18, 0x19
PEX_MAGIC = 0xFA57C0DE

STATUS_ORDER = ['works', 'partial', 'timer never starts', 'dead',
                'fragments only', 'no events', 'records only']


# ---------------------------------------------------------------------------
# .pex

class Pex(object):
    """A reader over one big endian .pex."""

    def __init__(self, data):
        self.b, self.p = data, 0

    def u8(self):
        v = self.b[self.p]
        self.p += 1
        return v

    def u16(self):
        v = struct.unpack_from('>H', self.b, self.p)[0]
        self.p += 2
        return v

    def u32(self):
        v = struct.unpack_from('>I', self.b, self.p)[0]
        self.p += 4
        return v

    def wstr(self):
        n = self.u16()
        s = self.b[self.p:self.p + n]
        self.p += n
        return s.decode('latin-1')

    def value(self):
        """One operand: (type, payload). Identifiers and strings are indexes
        into the string table, 1 and 2; the rest are skipped."""
        t = self.u8()
        if t == 0:
            return 0, None
        if t in (1, 2):
            return t, self.u16()
        if t == 3:
            v = struct.unpack_from('>i', self.b, self.p)[0]
            self.p += 4
            return 3, v
        if t == 4:
            self.p += 4
            return 4, None
        if t == 5:
            self.p += 1
            return 5, None
        raise ValueError('operand type %d at %d' % (t, self.p - 1))


def _function(r, names):
    """One function: its flags, whether it has a body, the functions of its own
    script it calls, the methods it calls on anything else, whether it starts a
    timer on itself, and the mod event callbacks it registers."""
    r.u16()
    r.u16()
    r.u32()
    flags = r.u8()
    for _ in range(r.u16()):
        r.u16()
        r.u16()
    for _ in range(r.u16()):
        r.u16()
        r.u16()
    count = r.u16()
    calls, outside, timer, callbacks = set(), set(), False, set()
    for _ in range(count):
        op = r.u8()
        if op >= len(OPERANDS):
            raise ValueError('opcode %d' % op)
        args = [r.value() for _ in range(OPERANDS[op])]
        if op in (CALLMETHOD, CALLPARENT, CALLSTATIC):
            t, n = r.value()
            if t != 3:
                raise ValueError('call without an argument count')
            args += [r.value() for _ in range(n)]
        if op == CALLMETHOD:
            method = names[args[0][1]].lower()
            on_self = args[1][0] == 1 and names[args[1][1]].lower() == 'self'
            if on_self:
                calls.add(method)
                if method in TIMER_CALLS:
                    timer = True
            else:
                outside.add(method)
            if method == MOD_EVENT_CALL and len(args) >= 5 and args[4][0] == 2:
                callbacks.add(names[args[4][1]])
        elif op == CALLPARENT:
            calls.add(names[args[0][1]].lower())
    return {'flags': flags, 'body': count > 0, 'calls': calls, 'outside': outside,
            'timer': timer, 'callbacks': callbacks}


def parse_pex(data):
    """The first object in a .pex: its name, the script it extends, whether it
    has native functions, and its functions merged across states."""
    r = Pex(data)
    if r.u32() != PEX_MAGIC:
        raise ValueError('not a .pex')
    r.u8()
    r.u8()
    r.u16()
    r.p += 8
    r.wstr()
    r.wstr()
    r.wstr()
    names = [r.wstr() for _ in range(r.u16())]
    if r.u8():
        r.p += 8
        for _ in range(r.u16()):
            r.p += 7
            lines = r.u16()
            r.p += 2 * lines
    for _ in range(r.u16()):
        r.u16()
        r.u8()
    objects = r.u16()
    if objects < 1:
        raise ValueError('no object')
    name = names[r.u16()]
    # The object's size field is not trusted. Measured 24 September, the four
    # QuickLootIE scripts, built by Caprica, carry sizes in the billions and the
    # game loads them anyway. Reading to the end of the file exactly is the
    # check instead.
    r.u32()
    parent = names[r.u16()]
    r.u16()
    r.u32()
    r.u16()
    for _ in range(r.u16()):
        r.u16()
        r.u16()
        r.u32()
        r.value()
    for _ in range(r.u16()):
        r.u16()
        r.u16()
        r.u16()
        r.u32()
        f = r.u8()
        if f & 4:
            r.u16()
        else:
            if f & 5 == 1:
                _function(r, names)
            if f & 6 == 2:
                _function(r, names)
    functions = {}
    for _ in range(r.u16()):
        state = names[r.u16()]
        for _ in range(r.u16()):
            fname = names[r.u16()]
            fn = _function(r, names)
            key = fname.lower()
            had = functions.get(key)
            if had is None:
                functions[key] = dict(fn, name=fname, declared=(state == '' and not fn['body']))
            else:
                had['body'] = had['body'] or fn['body']
                had['calls'] |= fn['calls']
                had['outside'] |= fn['outside']
                had['timer'] = had['timer'] or fn['timer']
                had['callbacks'] |= fn['callbacks']
                if state == '':
                    had['declared'] = not fn['body']
                    had['flags'] = fn['flags']
    if objects == 1 and r.p != len(data):
        raise ValueError('read to %d of %d bytes' % (r.p, len(data)))
    native = any(f['flags'] & 2 for f in functions.values())
    return {'name': name, 'parent': parent, 'native': native, 'functions': functions}


# ---------------------------------------------------------------------------
# Plugins

def _wstr(data, p):
    n = struct.unpack_from('<H', data, p)[0]
    return data[p + 2:p + 2 + n].decode('latin-1'), p + 2 + n


def _scripts(data, p, version, count):
    """The script list of a VMAD, or of one quest alias: names in order."""
    out = []
    for _ in range(count):
        name, p = _wstr(data, p)
        if version >= 4:
            p += 1
        props = struct.unpack_from('<H', data, p)[0]
        p += 2
        for _ in range(props):
            _pname, p = _wstr(data, p)
            kind = data[p]
            p += 1
            if version >= 4:
                p += 1
            if kind == 1:
                p += 8
            elif kind == 2:
                _s, p = _wstr(data, p)
            elif kind in (3, 4):
                p += 4
            elif kind == 5:
                p += 1
            elif kind in (11, 12, 13, 14, 15):
                n = struct.unpack_from('<I', data, p)[0]
                p += 4
                if kind == 11:
                    p += 8 * n
                elif kind == 12:
                    for _ in range(n):
                        _s, p = _wstr(data, p)
                elif kind in (13, 14):
                    p += 4 * n
                else:
                    p += n
            else:
                raise ValueError('property type %d' % kind)
        out.append(name)
    return out, p


def read_vmad(sig, data):
    """(scripts, {alias id: scripts}, fragment script or None) out of one VMAD.

    Only a quest has anything after its fragments, its aliases, so only a
    quest's fragments are read in full. The others stop at the fragment file
    name, which is all this needs from them.
    """
    version, fmt, count = struct.unpack_from('<hhH', data, 0)
    scripts, p = _scripts(data, 6, version, count)
    aliases, fragment = {}, None
    if sig not in FRAGMENT_TYPES or p >= len(data):
        return scripts, aliases, fragment
    if sig == b'QUST':
        p += 1
        frags = struct.unpack_from('<H', data, p)[0]
        p += 2
        fragment, p = _wstr(data, p)
        for _ in range(frags):
            p += 9
            _s, p = _wstr(data, p)
            _s, p = _wstr(data, p)
        n = struct.unpack_from('<H', data, p)[0]
        p += 2
        for _ in range(n):
            if fmt == 1:
                alias = struct.unpack_from('<h', data, p + 4)[0]
            else:
                alias = struct.unpack_from('<h', data, p + 2)[0]
            p += 8
            aversion, _afmt, acount = struct.unpack_from('<hhH', data, p)
            p += 6
            names, p = _scripts(data, p, aversion, acount)
            aliases[alias] = names
        if p != len(data):
            raise ValueError('quest VMAD read to %d of %d bytes' % (p, len(data)))
    elif sig == b'PERK':
        fragment, p = _wstr(data, p + 1)
    else:
        fragment, p = _wstr(data, p + 2)
    return scripts, aliases, (fragment or None)


def plugin_header(buf):
    """(flags, masters in lower case, where the records start)."""
    if buf[:4] != b'TES4':
        raise ValueError('not a plugin')
    size, flags = struct.unpack_from('<II', buf, 4)
    masters, p, end = [], 24, 24 + size
    while p + 6 <= end:
        sig = buf[p:p + 4]
        n = struct.unpack_from('<H', buf, p + 4)[0]
        if sig == b'MAST':
            masters.append(buf[p + 6:p + 6 + n].split(b'\0')[0].decode('latin-1').lower())
        p += 6 + n
    return flags, masters, end


def records(buf, start, masters, own, stats):
    """(record type, key, VMAD bytes or None) for every record in a plugin.

    Groups are walked into rather than over, since what is inside a group is
    just more records. The key is (plugin that made the form, form id), which is
    the same record however many plugins override it. VMAD always comes first
    or straight after EDID, so only those two are looked at. Measured 24
    September against a scan of every subrecord of every record in the 99
    plugins: 26,937 VMADs either way, none later than that, none on the types
    skipped here.
    """
    p, end, count = start, len(buf), len(masters)
    while p + 24 <= end:
        sig = buf[p:p + 4]
        size = struct.unpack_from('<I', buf, p + 4)[0]
        if sig == b'GRUP':
            p += 24
            continue
        flags, fid = struct.unpack_from('<II', buf, p + 8)
        body_at, p = p + 24, p + 24 + size
        if sig in UNSCRIPTED:
            continue
        idx = fid >> 24
        key = (masters[idx] if idx < count else own, fid & 0xFFFFFF)
        if flags & COMPRESSED:
            try:
                body = zlib.decompress(buf[body_at + 4:p])
            except zlib.error:
                stats['unreadable records'] += 1
                continue
            q, stop = 0, len(body)
        else:
            body, q, stop = buf, body_at, p
        vmad = None
        for _ in range(2):
            if q + 6 > stop:
                break
            tag = body[q:q + 4]
            n = struct.unpack_from('<H', body, q + 4)[0]
            if tag == b'VMAD':
                vmad = body[q + 6:q + 6 + n]
                break
            if tag != b'EDID':
                break
            q += 6 + n
        yield sig, key, vmad


def load_order(data_dir, plugins_txt):
    """The masters, then plugins.txt, with master flagged plugins first the way
    the engine sorts them. Returns (order, missing)."""
    listed = list(MASTERS)
    with io.open(plugins_txt, encoding='utf-8-sig', errors='replace') as fh:
        lines = fh.read().splitlines()
    for line in lines:
        line = line.strip()
        if not line or line.startswith('#') or not line.startswith('*'):
            continue
        name = line[1:].strip()
        if name.lower() not in [n.lower() for n in listed]:
            listed.append(name)
    first, rest, missing = [], [], []
    for name in listed:
        path = os.path.join(data_dir, name)
        if not os.path.isfile(path):
            missing.append(name)
            continue
        with open(path, 'rb') as fh:
            head = fh.read(12)
        flags = struct.unpack_from('<I', head, 8)[0] if len(head) == 12 else 0
        if flags & FLAG_MASTER or name.lower().endswith(('.esm', '.esl')):
            first.append(name)
        else:
            rest.append(name)
    return first + rest, missing


# ---------------------------------------------------------------------------
# Scripts

def script_index(data_dir, order, stats):
    """{script name in lower case: (where it came from, bytes)}, as the game
    would find it: archives in load order, a later one winning, then loose
    files over all of them."""
    stems = [os.path.splitext(n)[0].lower() for n in order]
    ranked = []
    for archive in os.listdir(data_dir):
        if not archive.lower().endswith('.bsa'):
            continue
        stem = archive[:-4].lower()
        rank = -1
        for i, s in enumerate(stems):
            if stem == s or stem.startswith(s + ' - '):
                rank = i
        ranked.append((rank, archive.lower(), archive))
    index = {}
    for _rank, _low, archive in sorted(ranked):
        try:
            files = bsa.read(os.path.join(data_dir, archive), 'scripts')
        except (ValueError, struct.error, zlib.error, IndexError) as exc:
            stats['unreadable archives'].append('%s: %s' % (archive, exc))
            continue
        for path, data in files.items():
            if path.endswith('.pex'):
                index[path.split('/')[-1][:-4]] = (archive, data)
                stats['archive scripts'] += 1
    loose = os.path.join(data_dir, 'Scripts')
    if os.path.isdir(loose):
        for f in os.listdir(loose):
            if f.lower().endswith('.pex'):
                with open(os.path.join(loose, f), 'rb') as fh:
                    index[f[:-4].lower()] = ('Data\\Scripts', fh.read())
                stats['loose scripts'] += 1
    return index


class Scripts(object):
    """Every script parsed once, the event names the game declares, and what
    each script handles once its parents are counted in."""

    def __init__(self, index):
        self.index = index
        self.parsed, self.bad = {}, {}
        for name, (_src, data) in index.items():
            try:
                self.parsed[name] = parse_pex(data)
            except (ValueError, struct.error, IndexError, UnicodeDecodeError) as exc:
                self.bad[name] = str(exc)
        self.events = dict(IMPLICIT_EVENTS)
        self.declared_in = {k: 'the VM, to every script' for k in IMPLICIT_EVENTS}
        # Every method name any script calls on something other than itself.
        # A timer whose registration sits behind one of these could be started
        # by another script, so it is not called stuck.
        self.called_from_outside = set()
        for pex in self.parsed.values():
            for fn in pex['functions'].values():
                self.called_from_outside |= fn['outside']
            if not pex['native']:
                continue
            for key, fn in pex['functions'].items():
                if fn['declared'] and not fn['flags'] & 3 and key not in NOT_EVENTS:
                    self.events.setdefault(key, fn['name'])
                    self.declared_in.setdefault(key, pex['name'])
        self.cache = {}

    def chain(self, name):
        """The script and every script it extends that is here to read."""
        out, seen = [], set()
        key = name.lower()
        while key and key in self.parsed and key not in seen:
            seen.add(key)
            out.append(self.parsed[key])
            key = self.parsed[key]['parent'].lower()
        return out

    def handles(self, name):
        """What one script does: the events it handles, and for a timer, which
        of its events reach a registration. None when the script is not there
        or could not be read."""
        key = name.lower()
        if key in self.cache:
            return self.cache[key]
        chain = self.chain(key)
        if not chain:
            self.cache[key] = None
            return None
        funcs = {}
        for pex in chain:
            for fkey, fn in pex['functions'].items():
                funcs.setdefault(fkey, fn)
        callbacks = {}
        for fn in funcs.values():
            for cb in fn['callbacks']:
                callbacks[cb.lower()] = cb
        events = {}
        for fkey, fn in funcs.items():
            if not fn['body'] or fn['flags'] & 3:
                continue
            if fkey in self.events:
                events[fkey] = self.events[fkey]
            elif fkey in callbacks:
                events[fkey] = callbacks[fkey]
        out = {'name': chain[0]['name'], 'events': events,
               'source': self.index[key][0], 'extends': chain[0]['parent'],
               'registersOthers': any(fn['outside'] & TIMER_CALLS for fn in funcs.values())}
        if ALLOWED in events:
            # Every function from which a registration can be reached through
            # the script's calls to itself, found by growing the set until it
            # stops growing.
            reach = {f for f, fn in funcs.items() if fn['timer']}
            grew = True
            while grew:
                grew = False
                for f, fn in funcs.items():
                    if f not in reach and fn['calls'] & reach:
                        reach.add(f)
                        grew = True
            out['starters'] = sorted(events[f] for f in reach if f in events and f != ALLOWED)
            out['calledIn'] = sorted(funcs[f]['name'] for f in reach
                                     if f not in events and f in self.called_from_outside)
        self.cache[key] = out
        return out


def exempt(name, scripts):
    """FridaHooks.cpp:56-66, on the name the .pex gives itself when it is
    there, since that is the name the VM carries."""
    got = scripts.parsed.get(name.lower())
    real = got['name'] if got else name
    return real.startswith(EXEMPT_PREFIX) or real.lower() == EXEMPT_NAME


# ---------------------------------------------------------------------------
# The audit

def audit(data_dir, plugins_txt):
    stats = defaultdict(int)
    stats['unreadable archives'] = []
    order, missing = load_order(data_dir, plugins_txt)

    # Every scripted record and alias, and every plugin that defined it after,
    # in load order. A plugin that overrides a scripted record without a VMAD
    # takes its scripts away, which is how the engine reads an override.
    chains, kinds, subkeys = {}, {}, defaultdict(set)
    bad_vmad = defaultdict(int)
    for idx, plugin in enumerate(order):
        with open(os.path.join(data_dir, plugin), 'rb') as fh:
            buf = fh.read()
        try:
            _flags, masters, start = plugin_header(buf)
        except (ValueError, struct.error):
            stats['unreadable plugins'] += 1
            continue
        for sig, rkey, vmad in records(buf, start, masters, plugin.lower(), stats):
            defined = {}
            if vmad is not None:
                try:
                    scripts, aliases, fragment = read_vmad(sig, vmad)
                except (ValueError, struct.error, IndexError):
                    bad_vmad[plugin] += 1
                    continue
                defined[rkey + ('record',)] = tuple(scripts)
                for alias, names in aliases.items():
                    defined[rkey + ('alias', alias)] = tuple(names)
                if fragment:
                    defined[rkey + ('fragment',)] = (fragment,)
            known = subkeys.get(rkey)
            if not defined and not known:
                continue
            for k in set(defined) | (known or set()):
                chains.setdefault(k, []).append((idx, defined.get(k, ())))
                kinds[k] = sig.decode('latin-1')
            subkeys[rkey].update(defined)

    index = script_index(data_dir, order, stats)
    scripts = Scripts(index)

    # Credit each script on each record to the plugin that first put it there,
    # following the run of overrides back from the one that wins.
    credited = defaultdict(list)
    for k, chain in chains.items():
        last_idx, last = chain[-1]
        if not last:
            continue
        free = any(exempt(n, scripts) for n in last) if k[2] != 'fragment' else False
        for name in last:
            who = last_idx
            for j in range(len(chain) - 2, -1, -1):
                if name.lower() in [n.lower() for n in chain[j][1]]:
                    who = chain[j][0]
                else:
                    break
            credited[who].append((k, name, free))

    plugins, events = [], {}
    for idx, plugin in enumerate(order):
        rows = credited.get(idx, [])
        per_script, fragments, quiet, absent, unread = {}, 0, 0, set(), set()
        # Whether anything this plugin attaches, fragments included, starts a
        # timer on something other than itself. QuickLootIE's load alias does,
        # GetOwningQuest().RegisterForSingleUpdate(), and that is the only way
        # its maintenance quest's timer starts.
        starts_others = False
        for k, name, free in rows:
            got = scripts.handles(name)
            if got is not None and got['registersOthers']:
                starts_others = True
            if k[2] == 'fragment':
                fragments += 1
                continue
            if got is None:
                (unread if name.lower() in scripts.bad else absent).add(name)
                continue
            if not got['events']:
                # Holds properties, or is a fragment script listed on its own
                # record as well. Nothing in it waits on anything.
                quiet += 1
                continue
            row = per_script.get(got['name'])
            if row is None:
                row = per_script[got['name']] = {
                    'attached': 0, 'exempt': 0, 'on': set(),
                    'events': sorted(got['events'].values()),
                    'alive': set(), 'blocked': set(),
                    'source': got['source'], 'extends': got['extends'],
                }
                if 'starters' in got:
                    row['timerStartsFrom'] = got['starters']
                    row['timerCalledInBy'] = got['calledIn']
            row['attached'] += 1
            if free:
                row['exempt'] += 1
            row['on'].add(kinds[k] + (' alias' if k[2] == 'alias' else ''))
            for key, ev in got['events'].items():
                if free or key == ALLOWED:
                    row['alive'].add(ev)
                else:
                    row['blocked'].add(ev)

        # A timer counts as running unless every way this script has of
        # starting it is a blocked event, nothing anywhere calls in to the
        # functions that register it, and nothing else in the plugin registers
        # a timer on another object.
        live, blocked, stuck = False, False, False
        for row in per_script.values():
            if ('timerStartsFrom' in row and row['exempt'] == 0 and not starts_others
                    and row['timerStartsFrom'] and not row['timerCalledInBy']):
                row['timerNeverStarts'] = True
                stuck = True
            elif row['alive']:
                live = True
            blocked = blocked or bool(row['blocked'])
            for e in row['blocked']:
                slot = events.setdefault(e, {'plugins': set(), 'scripts': 0})
                slot['plugins'].add(plugin)
                slot['scripts'] += 1
            row['alive'] = sorted(row['alive'])
            row['blocked'] = sorted(row['blocked'])
            row['on'] = sorted(row['on'])

        if not rows:
            status = 'records only'
        elif not per_script:
            status = 'fragments only' if fragments else 'no events'
        elif live and not blocked:
            status = 'works'
        elif live:
            status = 'partial'
        elif stuck:
            status = 'timer never starts'
        else:
            status = 'dead'
        plugins.append({
            'plugin': plugin, 'master': plugin in MASTERS, 'status': status,
            'scripts': per_script, 'fragments': fragments,
            'attachedWithoutEvents': quiet,
            'missingScripts': sorted(absent),
            'unreadableScripts': sorted(unread),
            'unreadableVmads': bad_vmad.get(plugin, 0),
        })

    return {
        'rule': {
            'source': 'skyrim-platform/src/platform_se/skyrim_platform/FridaHooks.cpp:43-72 '
                      'on thornswood/engine-changes',
            'allowed': 'OnUpdate',
            'exemptWhenTheObjectCarries': 'a script named SKI_*, or defaultDisableHavokOnLoad',
        },
        'loadOrder': order,
        'missingPlugins': missing,
        'counts': {
            'plugins': len(order),
            'looseScripts': stats['loose scripts'],
            'archiveScripts': stats['archive scripts'],
            'scriptsRead': len(scripts.parsed),
            'scriptsUnreadable': len(scripts.bad),
            'eventNames': len(scripts.events),
            'unreadableRecords': stats['unreadable records'],
            'unreadableVmads': sum(bad_vmad.values()),
            'unreadablePlugins': stats['unreadable plugins'],
        },
        'unreadableArchives': stats['unreadable archives'],
        'unreadableScripts': scripts.bad,
        'eventNames': {scripts.events[k]: scripts.declared_in[k] for k in scripts.events},
        'plugins': plugins,
        'blockedEvents': {
            e: {'plugins': sorted(v['plugins']), 'scripts': v['scripts']}
            for e, v in sorted(events.items(), key=lambda kv: (-len(kv[1]['plugins']), kv[0]))
        },
    }


def report(result, out=sys.stdout):
    c = result['counts']
    w = out.write
    w('Papyrus events under Thornswood\n')
    w('  The rule: every event except OnUpdate is blanked, unless a SKI_ script\n')
    w('  or defaultDisableHavokOnLoad shares the object. %s\n' % result['rule']['source'])
    w('  %d plugins. %d scripts read, %d unreadable. %d loose and %d in archives,\n'
      '  a loose one winning over an archived one of the same name.\n'
      % (c['plugins'], c['scriptsRead'], c['scriptsUnreadable'], c['looseScripts'],
         c['archiveScripts']))
    w('  %d event names, from the game\'s own native scripts.\n' % c['eventNames'])
    if result['missingPlugins']:
        w('  NOT IN DATA, skipped: %s\n' % ', '.join(result['missingPlugins']))
    for a in result['unreadableArchives']:
        w('  COULD NOT READ %s\n' % a)
    if c['unreadableVmads'] or c['unreadableRecords']:
        w('  %d VMADs and %d compressed records could not be read.\n'
          % (c['unreadableVmads'], c['unreadableRecords']))

    groups = defaultdict(list)
    for p in result['plugins']:
        groups[p['status']].append(p)
    w('\nBy plugin\n')
    for s in STATUS_ORDER:
        w('  %-20s %3d\n' % (s, len(groups[s])))

    for s in ('dead', 'timer never starts', 'partial'):
        if not groups[s]:
            continue
        w('\n%s\n' % s.upper())
        for p in groups[s]:
            blocked = sorted({e for row in p['scripts'].values() for e in row['blocked']})
            stuck = sorted(n for n, row in p['scripts'].items() if row.get('timerNeverStarts'))
            runs = sorted(n for n, row in p['scripts'].items()
                          if row['alive'] and n not in stuck)
            w('  %s%s\n' % (p['plugin'], '  (master)' if p['master'] else ''))
            w('      waits on  %s\n' % _short(blocked))
            if runs:
                w('      can run   %s\n' % _short(runs))
            if stuck:
                w('      a timer only a blocked event starts  %s\n' % _short(stuck))

    if groups['works']:
        w('\nWORKS\n')
        for p in groups['works']:
            how = []
            for row in p['scripts'].values():
                if row['exempt']:
                    how.append('exempt')
                elif row['alive'] and not row.get('timerNeverStarts'):
                    how.append('timer')
            w('  %s  (%s)\n' % (p['plugin'], ', '.join(sorted(set(how)))))

    w('\nBlocked events the load order waits on, by how many plugins\n')
    for e, v in list(result['blockedEvents'].items())[:40]:
        w('  %-32s %3d plugins  %4d scripts\n' % (e, len(v['plugins']), v['scripts']))
    more = len(result['blockedEvents']) - 40
    if more > 0:
        w('  and %d more, in the JSON\n' % more)


def _short(names, n=8):
    names = list(names)
    if len(names) <= n:
        return ', '.join(names)
    return '%s and %d more' % (', '.join(names[:n]), len(names) - n)


def main():
    ap = argparse.ArgumentParser(description='Which scripts can still do anything under the event blocker.')
    ap.add_argument('--data', default=r'C:\Thornswood\Game\Data')
    ap.add_argument('--plugins', default=r'C:\Thornswood\Profile\Default\plugins.txt')
    ap.add_argument('--json', help='also write the full result here')
    args = ap.parse_args()

    if not os.path.isdir(args.data):
        print('STOP. %s is not a folder.' % args.data)
        return 1
    if not os.path.isfile(args.plugins):
        print('STOP. %s is not there.' % args.plugins)
        return 1
    result = audit(args.data, args.plugins)
    report(result)
    if args.json:
        with io.open(args.json, 'w', encoding='utf-8') as fh:
            json.dump(result, fh, indent=1, sort_keys=True)
            fh.write(u'\n')
        print('\nWrote %s' % args.json)
    return 0


if __name__ == '__main__':
    sys.exit(main())
