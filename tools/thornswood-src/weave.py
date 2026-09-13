#!/usr/bin/env python3
"""Weave the character creation module into the gamemode body."""
import re, sys

body = open('body.js', encoding='utf-8').read()
chargen = open('chargen_body.js', encoding='utf-8').read()

def once(hay, needle, what):
    if hay.count(needle) != 1:
        sys.exit('expected exactly one %s, found %d' % (what, hay.count(needle)))

# 1. a best-effort notification helper, next to the other small helpers
NOTIFY = '''
/**
 * Try to put a line on somebody's screen. Debug.Notification is implemented on
 * the server, but it finds its target actor through the Papyrus stack, which is
 * empty when the call starts here rather than in a game event. So this may well
 * do nothing, and nothing is allowed to depend on it: the log line below is the
 * one that is guaranteed.
 */
function notify(actorId, text) {
  log('say', actorId.toString(16), text);
  try {
    mp.callPapyrusFunction('global', 'Debug', 'Notification', null, [text]);
  } catch (e) {
    // no stack actor, or the class is not registered. expected; ignore.
  }
}

function dist2(ax, ay, bx, by) {'''
marker = '\nfunction dist2(ax, ay, bx, by) {'
once(body, marker, 'dist2 definition')
body = body.replace(marker, NOTIFY)

# 2. the module itself, ahead of the handlers
HANDLERS = ('// ---------------------------------------------------------------------------\n'
            '// event handlers\n')
once(body, HANDLERS, 'event handlers banner')
body = body.replace(HANDLERS, chargen.rstrip() + '\n\n' + HANDLERS)

# 3. register the property and start the timer
once(body, '\nensureProperties();\n', 'ensureProperties call')
body = body.replace('\nensureProperties();\n', '\nensureProperties();\nstartChargenTimer();\n')

OLD_PROPS = """    mp.makeProperty(SKILL_PROPERTY, {
      isVisibleByOwner: true,
      isVisibleByNeighbors: false,
      updateOwner: '',
      updateNeighbor: '',
    });"""
NEW_PROPS = OLD_PROPS + """
    mp.makeProperty(CHARGEN_PROPERTY, {
      isVisibleByOwner: false,
      isVisibleByNeighbors: false,
      updateOwner: '',
      updateNeighbor: '',
    });"""
once(body, OLD_PROPS, 'skill property registration')
body = body.replace(OLD_PROPS, NEW_PROPS)

# 4. chargen books get first look at onReadBook
OLD_READ = """mp.onReadBook = guard('onReadBook', function (actorId, baseId) {
  for (const d in MANUALS) {"""
NEW_READ = """mp.onReadBook = guard('onReadBook', function (actorId, baseId) {
  if (chargenReadBook(actorId, baseId)) return;

  for (const d in MANUALS) {"""
once(body, OLD_READ, 'onReadBook handler')
body = body.replace(OLD_READ, NEW_READ)

# 5. stations should try to speak, not only log
OLD_STATION = """  log('station', baseDesc, 'by', casterRefrId, '-', message);
  return false;"""
NEW_STATION = """  notify(casterRefrId, message);
  return false;"""
once(body, OLD_STATION, 'station log line')
body = body.replace(OLD_STATION, NEW_STATION)

# 6. say so at load
OLD_LOAD = """log('gamemode loaded:',
    Object.keys(DATA.cellToHold).length + ' cells mapped,',
    Object.keys(MANUALS).length + ' manuals,',
    Object.keys(STATIONS).length + ' station types');"""
NEW_LOAD = """log('gamemode loaded:',
    Object.keys(DATA.cellToHold).length + ' cells mapped,',
    Object.keys(MANUALS).length + ' manuals,',
    Object.keys(STATIONS).length + ' station types,',
    Object.keys(CLASSES).length + ' trades,',
    Object.keys(PASSAGES).length + ' starting towns');"""
once(body, OLD_LOAD, 'load banner')
body = body.replace(OLD_LOAD, NEW_LOAD)

open('gamemode_body.js', 'w', encoding='utf-8').write(body)
print('woven: %d lines' % body.count('\n'))
