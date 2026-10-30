"""Made-up game folders for #2791, with nothing of anybody's in them.

    python last-plugin-fixture.py <folder>

launcher\\app\\LastPlugin.cs makes Thornswood-Last.esp on each machine from
the recipe the release carries and that machine's own plugins, and must come
to the same bytes as scripts\\mods\\last_recipe.py's apply(). The real plugins
are only on a machine that has the collection, so this writes game folders of
the same shape from the small plugins tests\\last-recipe-cases.py builds: each
folder under <folder> has Data\\Thornswood-Last.recipe written by
last_recipe.make(), the plugins and string tables it reads, and want.esp,
the plugin it must make, or want.txt, a few words the reason it makes nothing
must say. tests\\test-2791-last-plugin.ps1 runs the launcher's code on each.

  made       the plugin, its string table in an archive, an archive before it
             in name order that has none and one after it with another copy
             (the first that has one wins, as in the game)
  loose      the same, with the table loose under Data\\Strings as well, which
             wins over every archive
  long       a world record with a subrecord over 64 KiB (an XXXX size)
  other      the plugin with one byte changed: makes nothing, names it
  no-plugin  the plugin missing: makes nothing, names it
  no-table   no string table anywhere: makes nothing, names it
  later      the only table is in the later archive, and another copy is loose:
             the loose one is read, and it is not the one the recipe names

Writes only under <folder>, and the same bytes on every machine.
"""
import importlib.util
import os
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


C = load('last_recipe_cases', ROOT / 'tests' / 'last-recipe-cases.py')
A = load('from_game_fixture', ROOT / 'tests' / 'fixtures' / '2827' / 'from-game-fixture.py')
R = C.R

OTHER_TABLE = C.strings_table({42: b'Somebody Else\'s Hall'})


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def game(root, name, recipe, plugins, archives=(), loose=None, want=None, why=None):
    g = root / name
    data = g / 'Data'
    write(data / 'Thornswood-Last.recipe', recipe)
    for n, b in plugins.items():
        write(data / n, b)
    for n, files in archives:
        data.mkdir(parents=True, exist_ok=True)
        A.archive(str(data / n), files, compressed=n.startswith('Theirs'))
    if loose is not None:
        write(data / 'Strings' / 'theirs_english.strings', loose)
    if want is not None:
        write(g / 'want.esp', want)
    if why is not None:
        write(g / 'want.txt', why.encode('utf-8'))


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    root = pathlib.Path(argv[1])
    src, at = C.source_plugin()
    out, index = C.built_plugin(src, at)
    recipe, _ = R.make(out, index, [C.Source('Theirs.esp', src)],
                       {('Theirs.esp', 'strings'): ('theirs_english.strings', C.TABLE)}, 'fixture')
    assert R.apply(recipe, lambda n: src, lambda n: C.TABLE) == out
    first = ('Another.bsa', [('textures', 'nothing.dds', b'not a table')])
    theirs = ('Theirs - Strings.bsa', [('strings', 'theirs_english.strings', C.TABLE)])
    later = ('Zed.bsa', [('strings', 'theirs_english.strings', OTHER_TABLE)])
    plugins = {'Theirs.esp': src}

    game(root, 'made', recipe, plugins, [first, theirs, later], want=out)
    game(root, 'loose', recipe, plugins, [first, later], loose=C.TABLE, want=out)
    other = bytearray(src)
    other[-1] ^= 1
    game(root, 'other', recipe, {'Theirs.esp': bytes(other)}, [theirs], why='Theirs.esp is not the copy the recipe was written for')
    game(root, 'no-plugin', recipe, {}, [theirs], why='Theirs.esp is not on this machine')
    game(root, 'no-table', recipe, plugins, [first], why='theirs_english.strings is not on this machine')
    game(root, 'later', recipe, plugins, [first, later], loose=OTHER_TABLE,
         why='theirs_english.strings is not the copy the recipe was written for')

    big = bytes((i * 7) % 251 for i in range(70000))
    wsrc = C.header(['Skyrim.esm']) + C.grup(b'WRLD', C.rec(b'WRLD', 0, 0x01000100, C.sub(b'EDID', b'W\x00') + C.sub(b'OFST', big)))
    wat = wsrc.index(b'WRLD', wsrc.index(b'GRUP') + 24)
    wdata = C.sub(b'EDID', b'W\x00') + C.sub(b'OFST', big[:1000] + b'\x09' + big[1001:])
    wout = C.header(['Skyrim.esm', 'Big.esp']) + C.grup(b'WRLD', C.rec(b'WRLD', 0, 0x01000100, wdata))
    windex = {(b'WRLD', 0x01000100): (wdata, C.Entry(b'WRLD', 0x01000100, wat, 0))}
    wrecipe, _ = R.make(wout, windex, [C.Source('Big.esp', wsrc)], {}, 'fixture')
    game(root, 'long', wrecipe, {'Big.esp': wsrc}, want=wout)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
