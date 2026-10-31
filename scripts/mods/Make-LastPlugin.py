"""
Make-LastPlugin.py

Makes Thornswood-Last.esp from its recipe, game/data/last-plugin.recipe, out of
the plugins and string tables a machine already has (#2791, Patrick's A of 26
Oct 2026 on #3721). The plugin copies the winning record of each cell, world,
quest and placed actor it changes out of about 31 other authors' plugins, so
Thornswood never hands the plugin on: a release carries only the recipe, and
each machine makes the plugin from its own copies of those plugins.

WHO RUNS IT

  the box    every deploy that puts the plugin on a game server
             (scripts/deploy/LastPluginOnBox.ps1): into the deploy's stage,
             from the stage's plugins and then the server's, with the string
             tables of the box's game archive store; the stage check holds it
             to the sha256 game/data/last-plugin.json names before the swap
  a box run  scripts/mods/OnBox.ps1, so every builder of the content chain
             reads this commit's plugin and not the server's copy
  builders   Build-LastPlugin.py --verify, and the harnesses that read the
             plugin's records on a machine with the game (tests/last-plugin-made.js)
  people     the launcher, launcher/app/LastPlugin.cs, the same steps in C#

WHERE IT READS FROM

  A plugin from the first --data folder that holds it, in the order given, so
  a deploy's stage (this commit's Thornswood-Content.esp) is read before the
  server's plugins. A string table the way the game finds it, and the way
  Build-LastPlugin.py found it when it wrote the recipe: the loose file under
  Strings\\ first, in each folder of --tables and then --data, then each
  archive (*.bsa) of all of them in name order, as if they were one Data
  folder (on the box the archives live apart from the plugins,
  C:\\Thornswood-GameData, OnBox.ps1 says why).

  The recipe names the size and sha256 of every plugin and table it reads and
  of the plugin it makes (last_recipe.py). Another copy of any of them makes
  nothing, and the line says which.

WHAT IT WRITES

  --out, whole: a file beside it first, then renamed over it, so a reader
  never sees half a plugin and a refusal leaves what was there. Prints

      MADE <bytes> <sha256> from <n> plugins and string tables

  and exits 0; or STOP. <why>, writes nothing and exits 1.

Usage:
    python scripts/mods/Make-LastPlugin.py --data <folder> [--data <folder> ...]
        [--tables <folder> ...] [--recipe <file>] [--out <file>]

--out defaults to Thornswood-Last.esp in the first --data folder, --recipe to
the repository's game/data/last-plugin.recipe.
"""

import argparse
import hashlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'scripts', 'dev'))  # bsa.py, the archive reader
sys.path.insert(0, HERE)
import last_recipe  # noqa: E402  (the recipe's format, apply() and make_from(), #2791)

PLUGIN = 'Thornswood-Last.esp'
RECIPE = os.path.join(ROOT, 'game', 'data', 'last-plugin.recipe')


def write_whole(path, data):
    tmp = path + '.making'
    with open(tmp, 'wb') as f:
        f.write(data)
    os.replace(tmp, path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', action='append', required=True,
                    help='a folder of plugins, the first that holds one is read; give it more than once')
    ap.add_argument('--tables', action='append', default=[],
                    help='a folder of string tables (Strings\\) and archives, read before --data')
    ap.add_argument('--recipe', default=RECIPE)
    ap.add_argument('--out', default='')
    args = ap.parse_args()
    out = args.out or os.path.join(args.data[0], PLUGIN)
    try:
        with open(args.recipe, 'rb') as f:
            recipe = f.read()
    except OSError as x:
        print('STOP. the recipe %s could not be read (%s). Nothing was written.' % (args.recipe, x))
        return 1
    try:
        plugin = last_recipe.make_from(recipe, args.data, args.tables)
    except last_recipe.RecipeError as x:
        print('STOP. %s could not be made from its recipe: %s. Nothing was written.' % (PLUGIN, x))
        return 1
    write_whole(out, plugin)
    print('MADE %d %s from %d plugins and string tables'
          % (len(plugin), hashlib.sha256(plugin).hexdigest(), len(last_recipe.read_header(recipe)[2])))
    return 0


if __name__ == '__main__':
    sys.exit(main())
