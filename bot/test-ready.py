"""
test-ready.py

Startup does the one-off things once, and the panel is read before it is
written.

From the To Do List: "on_ready re-registers views, re-syncs commands and
re-edits the panel on every reconnect... On a flaky evening the bot is one of
the things making the evening worse for itself, and a rate-limited sync writes
a traceback the log viewer then hides."

on_ready is not a startup hook. It fires every time the gateway connection
drops and comes back, which is exactly when Discord is already unhappy, and
every one of those was three writes to Discord that changed nothing plus an
edit to the ticket panel.

The real bot module is imported and the real coroutine is run. Only the things
that touch Discord are replaced: the guild list, the command tree's three
calls, and the stamp file, which is pointed at a temporary folder so this
cannot touch the one beside the code.

Read only. Never connects to anything.
"""
import asyncio
import json
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
# bot.py refuses to load without one, and never uses it unless client.run is
# called, which nothing here does.
os.environ.setdefault('DISCORD_TOKEN', 'not-a-real-token')

import bot  # noqa: E402

PASS = []
FAIL = []


def yes(what, cond):
    (PASS if cond else FAIL).append(what)
    print(('PASS  ' if cond else 'FAIL  ') + what)


class Guild(object):
    def __init__(self, gid, name):
        self.id = gid
        self.name = name


class Tree(object):
    """
    The command tree, counting instead of calling Discord.

    copied, synced and cleared are the three writes. A sync is the one Discord
    rate limits hardest, so the number that matters in every check below is
    synced.
    """

    def __init__(self, names):
        self._names = names
        self.copied = 0
        self.synced = 0
        self.cleared = 0

    def get_commands(self):
        return [type('C', (object,), {'name': n})() for n in self._names]

    def copy_global_to(self, guild=None):
        self.copied += 1

    def clear_commands(self, guild=None):
        self.cleared += 1

    async def sync(self, guild=None):
        self.synced += 1


class Client(object):
    def __init__(self, guilds):
        self.guilds = guilds


def run(names, guilds, force=0):
    """One start of the bot, with the real register_commands."""
    tree = Tree(names)
    was_tree, was_client, was_force = bot.tree, bot.client, bot.FORCE_SYNC
    bot.tree, bot.client, bot.FORCE_SYNC = tree, Client(guilds), force
    try:
        asyncio.run(bot.register_commands())
    finally:
        bot.tree, bot.client, bot.FORCE_SYNC = was_tree, was_client, was_force
    return tree


TMP = tempfile.mkdtemp(prefix='thornswood-ready-')
bot.STAMP = os.path.join(TMP, 'commands-synced.json')

try:
    HOME = [Guild(1, 'Thornswood')]

    # ------------------------------------------------ the first start ever
    first = run(['close'], HOME)
    yes('a first start registers the commands', first.synced == 2 and first.copied == 1)
    yes('and clears the global list, so nothing appears twice in the picker',
        first.cleared == 1)
    yes('and writes down what it registered', os.path.exists(bot.STAMP))

    # ------------------------------------------------- THE ONE THIS IS FOR
    second = run(['close'], HOME)
    yes('a reconnect or a restart registers nothing at all',
        second.synced == 0 and second.copied == 0 and second.cleared == 0)

    # ------------------------------------------------------ a new command
    third = run(['close', 'roll'], HOME)
    yes('adding a command registers again', third.synced == 2)
    fourth = run(['close', 'roll'], HOME)
    yes('and then stops again', fourth.synced == 0)

    # The order commands come back in is not something to depend on.
    fifth = run(['roll', 'close'], HOME)
    yes('the same commands in a different order are the same commands',
        fifth.synced == 0)

    # ---------------------------------------------------- a second server
    both = [Guild(1, 'Thornswood'), Guild(2, 'Thornswood dev')]
    sixth = run(['close', 'roll'], both)
    yes('a server the bot has just been added to is registered',
        sixth.synced == 3 and sixth.copied == 2)
    seventh = run(['close', 'roll'], both)
    yes('and the next start after that does nothing', seventh.synced == 0)

    # A server it was in and is no longer does not make it register again.
    eighth = run(['close', 'roll'], HOME)
    yes('leaving a server does not set it off', eighth.synced == 0)

    # ------------------------------------------------------- the override
    ninth = run(['close', 'roll'], HOME, force=1)
    yes('FORCE_COMMAND_SYNC registers whatever the stamp says', ninth.synced == 2)

    # ------------------------------------------ and it fails the safe way
    #
    # A stamp that cannot be read is a stamp that says nothing was registered,
    # so the commands go up. An unnecessary sync costs one rate limit slot; a
    # skipped one costs a slash command nobody has.
    with open(bot.STAMP, 'w') as f:
        f.write('this is not json')
    tenth = run(['close', 'roll'], HOME)
    yes('an unreadable stamp registers rather than assuming', tenth.synced == 2)

    # A folder that cannot be written to is the same answer: it registers
    # every start, which is what it did before any of this.
    bot.STAMP = os.path.join(TMP, 'no-such-folder', 'commands-synced.json')
    eleventh = run(['close'], HOME)
    yes('a stamp that cannot be written registers every time', eleventh.synced == 2)
    twelfth = run(['close'], HOME)
    yes('and says so by doing it again rather than by going quiet',
        twelfth.synced == 2)

    # ------------------------------------------------------- the panel --
    #
    # The options a dropdown offers live in the message that was posted, not
    # in the View this process builds on startup, so both have to be compared.

    class Option(object):
        def __init__(self, value, label):
            self.value = value
            self.label = label

    class Item(object):
        def __init__(self, options):
            self.options = options

    class Row(object):
        def __init__(self, children):
            self.children = children

    class Message(object):
        def __init__(self, content, pairs):
            self.content = content
            self.components = [Row([Item([Option(v, l) for v, l in pairs])])]

    live = [(k, lab) for k, lab, _ in bot.KINDS]

    yes('a panel that already says the right thing is left alone',
        bot.panel_is_current(Message(bot.PANEL, live)))

    changed = live[:-1] + [(live[-1][0], live[-1][1] + ' (new wording)')]
    yes('a renamed ticket kind is edited', not bot.panel_is_current(Message(bot.PANEL, changed)))

    added = live + [('newkind', 'Apply: something new')]
    yes('A KIND ADDED LATER IS EDITED, which is the bug the comment records',
        not bot.panel_is_current(Message(bot.PANEL, added)))

    dropped = live[:-1]
    yes('a kind taken away is edited', not bot.panel_is_current(Message(bot.PANEL, dropped)))

    yes('different words with the same options are edited',
        not bot.panel_is_current(Message(bot.PANEL + ' and something else', live)))

    yes('the same words in a different order are not the same panel',
        not bot.panel_is_current(Message(bot.PANEL, list(reversed(live)))))

    # A message with no components at all, or one this cannot read: it is
    # edited. Failing that way round costs one audit log line; the other way
    # costs somebody a ticket they cannot open.
    blank = Message(bot.PANEL, live)
    blank.components = []
    yes('a message whose dropdown cannot be read is edited', not bot.panel_is_current(blank))

    broken = Message(bot.PANEL, live)
    broken.components = None
    yes('and so is one with nothing there at all', not bot.panel_is_current(broken))

    # ------------------------------------- the views are not in on_ready --
    src = open(os.path.join(HERE, 'bot.py'), encoding='utf-8').read()
    ready = src[src.index('async def on_ready():'):]
    yes('the persistent views are registered once, not on every reconnect',
        'add_view' not in ready and 'async def setup_hook' in src)

finally:
    shutil.rmtree(TMP, ignore_errors=True)

print('')
print('%d passed, %d failed' % (len(PASS), len(FAIL)))
sys.exit(1 if FAIL else 0)
