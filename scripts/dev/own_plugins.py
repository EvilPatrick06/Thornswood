"""
own_plugins.py

Where a builder reads a plugin of the load order from (#2923).

Thornswood's own plugins (Thornswood-Content.esp, Thornswood-Last.esp,
Thornswood-WoodworkerTrail.esp, and any other file in game/content) are made
and shipped from this repository's game/content. A game folder holds whichever
release last reached it, so a table read from there describes a plugin nobody
ships. Every plugin whose name is a file in game/content is read from there,
and every other plugin from the game's Data folder. The same rule is
OwnPlugins.js and OwnPlugins.ps1; tests/test-2923-own-plugins.js holds the
three to it.

    import own_plugins
    path = own_plugins.plugin_path(data, 'Thornswood-Content.esp')
"""

import os

OWN_DIR = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'game', 'content'))


def is_own(name):
    return os.path.isfile(os.path.join(OWN_DIR, name))


def plugin_path(data, name):
    return os.path.join(OWN_DIR, name) if is_own(name) else os.path.join(str(data), name)
