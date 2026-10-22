#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
  Build-Discord.py

  Builds the whole Thornswood Discord in one run: roles, categories, channels,
  permissions, and the words in the read only channels.

  Safe to run more than once. Anything already there by name is left alone,
  anything missing is made, and the read only posts are rewritten from
  content.py. So changing the rules is an edit and a re run, not forty clicks.

      pip install -U discord.py
      python Build-Discord.py

  It never deletes anything unless DISCORD_PRUNE=1 is set, and even then only
  inside the categories it made and only names it knows it no longer wants.
  The names in KEEP are never deleted, whatever any other list in here says.

  It wants a bot token. Put it in the environment rather than on the command
  line, so it does not sit in your shell history:

      $env:DISCORD_TOKEN = 'paste-it-here'
      python Build-Discord.py

  Or run Setup-Discord.ps1, which asks for it without showing it.

  Before any of that:

    1. https://discord.com/developers/applications, the same application the
       website login uses is fine, or a new one.
    2. Bot in the sidebar. Add a bot, then Reset Token and copy it.
    3. Under Bot, turn ON "Server Members Intent". Leave the other two OFF.
    4. OAuth2 then URL Generator: tick "bot", then "Administrator", open the
       URL it makes and add it to the Thornswood server. Administrator is for
       the build only. It makes the Owner and Dev roles, which carry
       Administrator, and Discord refuses that from a bot without it.
    5. Server Settings, Enable Community. Without it there are no forum
       channels, no announcement channels and no rules screen, and this falls
       back to plain text channels for those. That screen asks for a
       Community Updates and a Safety Notifications channel: take what it
       offers, and the next run of this moves both to #staff-updates.

  The bot needs to be ABOVE the roles it creates, so drag its own role to the
  top of the role list once it has joined.

  TWO PERMISSION SETS. Administrator for a build, and the smaller set below
  for the rest of the time, which is all bot.py needs to run. A build that
  finishes with nothing failed prints the invite link with that smaller set
  and a line saying to untick Administrator on the bot's role. Tick it again
  before the next build. To see that link without building anything, and
  without a token:

      python Build-Discord.py --invite <application id>

  The application id is on the developer portal's General Information page.
"""

import asyncio
import os
import sys

# ----------------------------------------------------- the running set --
# What bot.py does once the build is over, and nothing more. Each one is
# Discord's own bit number from its permissions page,
# https://docs.discord.com/developers/topics/permissions, not a discord.py
# name, so the integer can be checked against the page by hand. It is read
# off what bot.py calls:
#
#   Manage Channels           log_channel makes the staff only #tickets when
#                             there is none
#   View Channel              every channel it reads or posts in
#   Send Messages             join cards, panels, alerts, closed tickets
#   Attach Files              the join card is a picture
#   Read Message History      finds its own panels to edit in place
#   Manage Roles              the hold and ping buttons give and take roles,
#                             and the two ping roles are made when missing
#   Manage Threads            a ticket thread is private and not invitable, so
#                             only a moderator can add people to it, Close
#                             locks it, and a ticket is deleted 365 days
#                             after it closes (#2353)
#   Create Public Threads     threads the bot opens (the Live smoke session
#                             thread until 11 Oct; forum posts need only Send)
#   Create Private Threads    one per ticket
#   Send Messages in Threads  writes the ticket into its thread
#
# Left out on purpose: Administrator, Manage Server, Manage Webhooks, Manage
# Messages, Pin Messages and Embed Links, which only the build uses or
# nothing uses. Interaction replies and direct messages need no permission.
RUN_BITS = (
    ('Manage Channels',           4),
    ('View Channel',             10),
    ('Send Messages',            11),
    ('Attach Files',             15),
    ('Read Message History',     16),
    ('Manage Roles',             28),
    ('Manage Threads',           34),
    ('Create Public Threads',    35),
    ('Create Private Threads',   36),
    ('Send Messages in Threads', 38),
)
RUN_PERMISSIONS = sum(1 << bit for _, bit in RUN_BITS)


def invite_url(app_id, permissions=RUN_PERMISSIONS):
    """The bot invite, as https://docs.discord.com/developers/topics/oauth2
       describes it: the application id, scope bot, and the permissions
       integer. Opened for a bot already in the server, it sets these on the
       bot's own role."""
    return ('https://discord.com/oauth2/authorize?client_id=%s&scope=bot'
            '&permissions=%d' % (app_id, permissions))


def say_invite(app_id, role_name=None):
    """What a finished build ends on, and all --invite prints."""
    print('  Running, the bot needs these and not Administrator:')
    print('    ' + ', '.join(n for n, _ in RUN_BITS))
    print('')
    print('  Open this to give the bot\'s role exactly those, permissions %d:'
          % RUN_PERMISSIONS)
    print('    ' + invite_url(app_id))
    print('')
    print('  Then untick Administrator on the bot\'s role now the build is done:')
    print('  Server Settings, Roles, %s, Permissions. Tick it again before the '
          'next build.' % (role_name or 'the bot\'s own role'))


# THE DRY PATH. Before discord.py is imported and before any token is read,
# so it runs anywhere, connects to nothing and changes nothing.
if __name__ == '__main__' and '--invite' in sys.argv:
    _rest = sys.argv[sys.argv.index('--invite') + 1:]
    _app = (_rest[0] if _rest else os.environ.get('DISCORD_CLIENT_ID', '')).strip()
    if not _app.isdigit():
        sys.exit('Say which application: python Build-Discord.py --invite '
                 '<application id>. It is on the developer portal\'s General '
                 'Information page.')
    say_invite(_app)
    sys.exit(0)

try:
    import discord
except ImportError:
    sys.exit("discord.py is not installed. Run:  pip install -U discord.py")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import content as C

TOKEN = os.environ.get('DISCORD_TOKEN', '').strip()
# Deleting is off unless asked for, because a script that quietly removes
# channels is a script nobody should run twice.
PRUNE = os.environ.get('DISCORD_PRUNE', '') == '1'

# ROLES AND NOTHING ELSE.
#
# The whole script is safe to re-run and deletes nothing without
# DISCORD_PRUNE, but safe to re-run is not the same as changes only what I
# meant. It also creates any channel or category the plan names and the
# server has not got, rewrites the read-only posts out of content.py, and
# edits the guild's system and AFK channel settings.
#
# On 23 September the only thing wanted was the Banned role, which had
# never been created, and the permission given was for exactly that: add
# that role and reorder roles, add nothing else and remove nothing. So
# there is a switch that means it, rather than a promise that the rest
# would probably be a no-op.
#
#     python Build-Discord.py --roles-only
ROLES_ONLY = ('--roles-only' in sys.argv) or os.environ.get('DISCORD_ROLES_ONLY', '') == '1'
# Rewriting the read only posts means deleting the bot's old messages and
# sending them again, in seven channels. Doing that on every run makes a one
# channel change look like the server being rebuilt, so it is opt in now.
POSTS = os.environ.get('DISCORD_POSTS', '') == '1'
CHECK = os.environ.get('DISCORD_CHECK', '') == '1'

# ONE PART OF THE PLAN AND NOTHING ELSE (#2519).
#
# A whole run does more than the part a change was approved for: it puts
# every role back in its place, lets the bot into every gated channel it is
# not in yet, sets topics and the server's join, AFK and notice settings, and
# lists or prunes what left the plan. On 22 Oct the Gamemasters category, the
# Attach Files overwrite on #welcome-travelers and the GM Rules pin were
# approved, and a whole -Check also planned role moves, #jukebox and two
# server or channel settings. ONLY names the categories and channels a run
# may touch, comma separated:
#
#     $env:DISCORD_ONLY = 'Gamemasters,welcome-travelers'
#     python Build-Discord.py
#
# A category named here is made if missing, with every channel PLAN puts in
# it; a channel named here is made or kept in its own category, which is not
# made for it. No role is made or moved, nothing is listed for pruning or
# pruned, no post is written, no webhook is made, and no server setting is
# changed. A name PLAN does not have stops the run before Discord is asked
# anything.
ONLY = [n.strip() for n in os.environ.get('DISCORD_ONLY', '').split(',') if n.strip()]

# THE AUDIT (#3317). Reads the live server and says where it differs from this
# plan, and changes nothing: no role, channel, post, webhook or setting is
# touched, and nothing is written beside the code.
#
# Patrick asked on 22 Oct for every role's permissions to be right globally,
# per category, per channel and for the bot, and for nobody to hold two ranks
# of one staff category. The plan below only says what a channel this MAKES
# gets, and the live server was gated by hand, so the only way to know what
# people can really do is to read it. This is that read, as a tool anybody can
# run again, rather than a one-off look:
#
#     python Build-Discord.py --audit
#     .\Setup-Discord.ps1 -OnBox -Audit
#
# It says: the bot's own permissions against the running set, each role's
# permissions against ROLES, who holds each staff rank and every double rank
# (STAFF_RANKS), every planned category and channel whose overwrites differ
# from what its mode gives, and the channels the plan does not name.
AUDIT = ('--audit' in sys.argv) or os.environ.get('DISCORD_AUDIT', '') == '1'
GUILD  = os.environ.get('DISCORD_GUILD', '').strip()   # optional server id
WEBHOOK_OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           'news-webhook.txt')

# ------------------------------------------------------------------ roles --
# Top of this list is the top of the role list. Colour, whether it shows in its
# own group down the side, and what it can do.
#
# Names are Thornswood's rather than Skyrim's job titles, because "Moderator"
# beside "Jarl of Whiterun" reads like two different servers.
ADMIN = discord.Permissions(administrator=True)
MOD   = discord.Permissions(
    manage_messages=True, kick_members=True, ban_members=True,
    moderate_members=True, manage_threads=True, mute_members=True,
    move_members=True, deafen_members=True, read_message_history=True,
    view_channel=True, send_messages=True, embed_links=True,
    attach_files=True, connect=True, speak=True)
GM    = discord.Permissions(
    manage_messages=True, moderate_members=True, manage_threads=True,
    read_message_history=True, view_channel=True, send_messages=True,
    embed_links=True, attach_files=True, connect=True, speak=True,
    mute_members=True, move_members=True)
PLAIN = discord.Permissions(
    view_channel=True, send_messages=True, read_message_history=True,
    embed_links=True, attach_files=True, add_reactions=True,
    use_external_emojis=True, connect=True, speak=True, stream=True,
    create_public_threads=True, send_messages_in_threads=True,
    use_application_commands=True)

HOLDS = ['Whiterun', 'Solitude', 'Windhelm', 'Riften', 'Markarth',
         'Dawnstar', 'Morthal', 'Falkreath', 'Winterhold']

# Staff roles are JOB TITLES, not lore titles, and that is deliberate. Thane,
# Steward, Warden and Housecarl are all things somebody should be able to play,
# and a moderator wearing one of them makes every in-world use of the word
# ambiguous. another server splits it the same way.
#
# The order is the order the live server has them in, read off the role list
# on 2 October, because this list is what puts them back in order on every
# run: a role in the wrong place here drags the real one with it.
ROLES = [
    # name                  colour    hoist  permissions
    ('Owner',               0xC9A24B, True,  ADMIN),
    ('Lead Gamemaster',     0x3E8FBF, True,  GM),
    ('Dev',                 0x9B7BD4, True,  ADMIN),
    ('Gamemaster',          0x4F9BC7, True,  GM),
    ('Loremaster',          0x57B8A0, True,  PLAIN),   # writes the world
    ('Trial Gamemaster',    0x79BCDB, True,  GM),
    ('Moderator',           0x6FA05A, True,  MOD),
    ('Content Creator',     0xD2603F, True,  PLAIN),
    ('Server Booster',      0xD98FB0, True,  PLAIN),   # boosted the server itself
    ('Playtester',          0xC07A4E, True,  PLAIN),

    # The three Patreon tiers, worst name at the top. Patreon hands these out
    # itself once the Discord is connected in its settings, so nothing here
    # ever assigns them.
    ('Thalmor Boot-Licker', 0x9FBE6B, True, PLAIN),
    ('Talos Worshiper',     0xD8B24C, True, PLAIN),
    ('Milk Drinker',        0xBFD3DE, True, PLAIN),
]

# In world. One Jarl per hold, and a hold for everybody else to belong to.
#
# Eighteen roles sounds like a lot for a small server, but Discord only shows a
# hoisted group in the member list when somebody in it is online, so the empty
# ones are invisible until they are not. A Jarl outranks their own citizens in
# the list because Jarl sits higher here.
# RAVEN ROCK HAS ITS OFFICES TOO (#2551, Patrick, 16 Oct, B): its Jarl, Court,
# Steward and Guards, like the nine, because the game has its board, its drop
# box and its jail. Its Jarl is "Jarl of Raven Rock", the name the site and the
# game read for every hold. It is not one of HOLDS: it has no Citizen role and
# no hold channel, which nobody has asked for.
OFFICE_HOLDS = HOLDS + ['Raven Rock']

for _h in OFFICE_HOLDS:
    ROLES.append(('Jarl of ' + _h, 0xE0C56A, True, PLAIN))
for _h in HOLDS:
    ROLES.append(('Citizen of ' + _h, 0x8FA9B8, True, PLAIN))

# THE OFFICES A JARL GIVES (#2551). Patrick, 15 Oct: each hold has a Court, a
# Steward and its Guards, and they are Discord roles, so the role is the one
# truth for who holds one, in the game and here. That hold's Jarl gives and
# takes them, from the bot's office panel or from the Office page in the game,
# and the bot sets the role either way. "Steward of <Hold>" replaces the one
# shared steward office the game kept by itself. The role is on the account,
# and the game keeps which one character of the account holds the office
# (Patrick, 16 Oct: character based, not account based).
#
# The running bot also makes any of these, and the Jarl roles, that are
# missing when it starts (bot.py, ensure_office_roles), so they exist without
# a build; a build then puts them in this order.
#
# NOT HOISTED (Patrick, 15 Oct: "they must not be shown separately in the
# member list"). The only in-world roles shown in their own group are the
# Jarl and Citizen roles above. They sit under the Citizen roles, so a
# citizen who also holds one keeps their Citizen colour.
#
# The site reads them by these exact names (site\server.js, OFFICE_ROLE), and
# so does the bot's panel (bot.py, office_role). A name changed here and not
# there leaves the office with nobody in it.
OFFICE_ROLES = []
for _h in OFFICE_HOLDS:
    OFFICE_ROLES.append(_h + ' Court')
    OFFICE_ROLES.append('Steward of ' + _h)
    OFFICE_ROLES.append('Guard of ' + _h)
for _name in OFFICE_ROLES:
    ROLES.append((_name, 0xA8977A, False, PLAIN))

# The Free Skyrim Trading Company (#1393, docs/systems/trading-company.md).
# Applied for in Discord, the same shape as a Jarl, and given by a person.
# The site's access.company names it, and the game lets a character on an
# account that holds it buy for the company. Made here because a role the
# site reads and nothing creates is the Banned mistake below.
ROLES.append(('Trading Company', 0xB08D57, True, PLAIN))

ROLES.append(('Member', 0x8D9682, False, PLAIN))   # everybody, on the way in

# THE ONE A BAN DEPENDS ON, and it was never created.
#
# site/server.js has keyed access off a role called Banned since it was
# written: cfg.access.banned is ['Banned'] and standing() takes everything away
# from anybody holding it. This builder makes eighteen roles and that was not
# one of them, so the thing being enforced did not exist and a ban was a role
# somebody had to remember to make by hand, spelled exactly right.
#
# Not hoisted and grey on purpose: a ban is not a badge, and a hoisted role
# would put banned people in their own group at the top of the member list.
# No permissions at all, because the site is what a ban acts on. The site also
# reads a bans.json now, so a typo here stops being a security control rather
# than being one.
ROLES.append(('Banned', 0x4A4A4A, False, PLAIN))

# The bottom three, under Banned on the live server. Something else makes all
# of them, so they are here for their place in the order and nothing else.
ROLES.append(('Patreon',      0xF96854, False, PLAIN))
ROLES.append(('News Pings',   0x8D9682, False, PLAIN))
ROLES.append(('Updates Pings', 0x8D9682, False, PLAIN))

# ROLES THIS NEVER MAKES, only puts in order.
#
# Discord makes Server Booster itself the first time somebody boosts, Patreon
# makes its own when the shop is connected in its settings, and bot.py makes
# the two ping roles the hold panel's buttons hand out. Creating any of them
# here would leave a second role of the same name that nothing hands out, and
# whichever of the two Discord shows is a coin toss.
NOT_MADE = ('Server Booster', 'Patreon', 'News Pings', 'Updates Pings')

# Staff for the channel modes below: who sees a staff channel, who can post in
# a read only one.
#
# LEAD GAMEMASTER AND TRIAL GAMEMASTER ARE DELIBERATELY NOT IN HERE, even
# though both are in ROLES since 2 October and Lead Gamemaster sits above Dev
# on the live role list. Decided on 1 October with the Live smoke session
# (#1407): widening a mode widens every channel that uses it, so the lead
# gamemaster role gets the one channel it needs by name, on that channel's own
# line, through extra_roles. Both still see every hold through HOLD_STAFF.
# Moving either of them in here is a line in #staff-updates first, because it
# opens #reports and every other staff channel.
STAFF = ('Owner', 'Dev', 'Moderator', 'Gamemaster')

# Who sees the Gamemasters category (#2519). Djinn's layout of 15 Oct 2026,
# confirmed by him on 17 Oct: the gamemaster ranks and Moderator, nobody
# else, and nothing public in it ("there should be NO public channel inside
# the GM channel area", 14 Oct). So no Member, no Loremaster, no Playtester.
# Moderator is in since 15 Oct; the 14 Oct list #2547 built left them out.
# Owner and Dev hold Administrator, which Discord lets through every overwrite,
# so they see it anyway; nothing here grants it to them. Both spellings of the
# lead role are named, the same as the Test-Tasks line, because the role has
# been written both ways; _named passes over the one that is not there.
GM_AREA = ('Lead Gamemaster', 'Lead GM', 'Gamemaster', 'Trial Gamemaster',
           'Moderator')

# Who may post in #gm-rules, which everybody in GM_AREA reads (Djinn, 15 Oct:
# "only Lead Gamemaster, Owner and Dev post"). Owner and Dev are named even
# though Administrator lets them through, so the rule is in the code and not
# in who happens to hold Administrator. Read only in code, not by a hand
# change on the live guild.
GM_RULES_POST = ('Lead Gamemaster', 'Lead GM', 'Owner', 'Dev')

# The ranks of each staff category, highest first (#3317). Patrick, 22 Oct:
# "people dont have double roles like dev and lead dev, they can have Owner and
# Lead Dev as those are separate". So one person holds at most one rank in each
# of these, and ranks in two different categories are not a double. The audit
# reads it; only roles on the server today are named, both spellings of the
# lead gamemaster role included, and the lead roles #3317 makes join their
# category when they are made.
STAFF_RANKS = (
    ('Gamemasters', ('Lead Gamemaster', 'Lead GM', 'Gamemaster',
                     'Trial Gamemaster')),
)

# --------------------------------------------------------------- channels --
# mode:  public       anybody talks, including somebody not yet approved
#        read         staff post, everybody reads, including the unapproved
#        open         Members talk, invisible to anybody without Member
#        membersread  staff post, Members read
#        hold         one hold's Citizen and Jarl, and hold staff
#        staff        staff only, invisible to everybody else
#        pathfind     testers and staff only
#        gm           the gamemaster ranks and Moderator (GM_AREA),
#                     invisible to everybody else
#        gmrules      GM_AREA reads, only GM_RULES_POST posts, invisible to
#                     everybody else
#
# THE GATE, set up by hand on 23 and 24 September. Somebody who joins sees the
# Start Here category (#rules, #welcome, #start-here, #say-hello) and the
# Applications category, and nothing else until staff give them Member. A
# hold's channel opens to its own Citizen and Jarl roles, picked in
# #choose-your-hold. These modes only apply to a channel this makes, never to
# one already there, so they are what keeps a channel made by a later run
# behind that gate instead of in front of it.
#
# key is what the words in content.py point at, so a channel can be renamed
# without every mention of it going stale.
#
# extra_roles is for one channel wanting somebody its mode does not give it.
# Looked up by name on the server, so a role that is not in ROLES still counts
# and a role that is not there is passed over. It widens that channel and
# nothing else: changing a mode would widen every channel using it. keep_extra
# applies it to a channel that is already there.
#
# make=False means the channel is in the plan and is never created: the plan
# is what prune keeps, so this is how a channel that has been deleted on
# purpose stays deleted without becoming something prune would delete the
# next one of its name.
#
# THE CATEGORY A CHANNEL IS IN IS PART OF ITS NAME HERE. A channel is matched
# by name inside the category this names, so a channel dragged into another
# category looks missing and the next run makes a second one. That is how the
# live server ended up with two #game-rules, and why this list follows where
# the channels actually are rather than where they were first put.
PLAN = [
 ('Start Here', [
   dict(kind='text',  name='rules',       key='RULES',    mode='read',
        topic='Seven rules. Read them.', post=C.RULES),
   dict(kind='text',  name='welcome',     key='WELCOME',  mode='read',
        topic="Start here.", post=C.WELCOME),
   dict(kind='text',  name='start-here',  key='START',    mode='read',
        topic="How to actually get in and play.",
        post=C.START),
   dict(kind='text',  name='say-hello',   key='HELLO',    mode='public',
        topic='New here? Say hi and tell us a little about yourself. Slowmode is on.'),
 ]),
 # Where somebody applies, before they have Member. The ticket panel lives in
 # #tickets-and-applications, which is what <#TICKETS> in content.py points
 # at. #tickets is staff only, where the bot writes closed tickets, and where
 # it puts a whole ticket, reports included, when the private thread will not
 # open. So it stays staff only: open it to anybody else and a report about
 # somebody can land in front of them. The bot checks its permissions and
 # passes over a #tickets that is not staff only.
 ('Applications', [
   dict(kind='text',  name='tickets-and-applications', key='TICKETS', mode='read'),
   dict(kind='text',  name='tickets',     mode='staff'),
 ]),
 ('Information', [
   dict(kind='announce', name='news',     key='NEWS',     mode='membersread',
        topic='What changed, every time it changes.',
        post=C.NEWS_FIRST),
   dict(kind='text',  name='updates',     key='UPDATES',  mode='membersread',
        topic="Restarts and outages. Check here before asking why you can't connect."),
   dict(kind='text',  name='faq',         key='FAQ',      mode='membersread',
        topic='Read this before you ask.', post=C.FAQ),
 ]),
 ('Help', [
   dict(kind='forum', name='suggestions', key='SUGGESTIONS', mode='open',
        topic=C.SUGGEST_TOPIC),
   dict(kind='voice', name='Support',      mode='open'),
   # Both gone from the server, and still named here so prune leaves anything
   # of either name alone. content.py points at them, and post() turns a
   # mention of a channel that is not there into plain words.
   dict(kind='forum', name='bugs',        key='BUGS',     mode='open',
        topic=C.BUGS_TOPIC, make=False),
   dict(kind='text',  name='logs-and-crashes', key='LOGS', mode='open',
        topic='Drag the log in. Explain it after.', make=False),
 ]),
 # Out of character. #general-chat is the one general: it was #general until
 # Patrick renamed it, and the topic on it was written by hand, so nothing
 # here sets one.
 ('Thornswood', [
   dict(kind='text',  name='general-chat', key='GENERAL', mode='open'),
   dict(kind='text',  name='media',       key='MEDIA',    mode='open',
        topic='Screenshots and clips. Talk about one in a thread under it.'),
   # Where the join cards go, and what the server's system channel points at.
   # JOIN gives the bot Attach Files here as well (JOIN_BOT_NEEDS, #2341).
   dict(kind='text',  name='welcome-travelers', key='JOIN', mode='open'),
   dict(kind='text',  name='game-rules',  key='GAMERULES', mode='membersread',
        topic='How roleplay works here. Nine rules, and what we let slide.',
        post=C.GAME_RULES),
   dict(kind='text',  name='server-progression-and-economy', mode='open'),
 ]),
 ('In Character', [
   dict(kind='forum', name='character-introductions', key='CHARS', mode='open',
        topic='Who are you playing? One post each.'),
   dict(kind='forum', name='tales',       key='TALES',    mode='open',
        topic='What happened out there. One post per story.'),
   dict(kind='text',  name='lore',        key='LORE',     mode='membersread',
        topic='4E 252. What happened and who you can be.',
        post=C.LORE),
   dict(kind='text',  name='rp-appreciation', key='APPREC', mode='open',
        topic='Somebody played a blinder. Say so.'),
   dict(kind='text',  name='graveyard',   key='GRAVE',    mode='open',
        topic='They had it coming. Probably.'),
 ]),

 # One channel per hold, because a hold with nowhere to talk is a line on a
 # map. These are in character: what is said here is said in the hold.
 ('The Holds', [
   # Where a Member picks their hold, at the top of the category. The bot
   # posts the buttons.
   dict(kind='text', name='choose-your-hold', key='CHOOSE', mode='membersread'),
 ] + [
   dict(kind='text', name=_h.lower(), key='HOLD_' + _h.upper(), mode='hold',
        hold=_h, topic=C.HOLD_TOPICS[_h.lower()])
   for _h in HOLDS
 ]),
 # Somewhere to talk and somewhere to be idle. Proximity voice is in the
 # launcher, so these are for before, after, and whoever is not in the world.
 ('Voice', [
   dict(kind='voice', name='AFK',               key='AFK', mode='open'),
   dict(kind='voice', name='General',           mode='open'),
 ]),
 # #test-these was deleted in the channel cleanup and is NOT renamed into this
 # one: it is in RETIRED below so a re-run does not bring it back. Test-Tasks
 # was a text channel from 1 October holding the Live smoke checklist. Since
 # Patrick's card of 11 October it is a forum of test tasks, one thread each,
 # tagged Main since #2276 (bot.py, the testing channels section), #test-results is
 # #test-findings, and #known-issues is new. The bot's one-time
 # `python bot.py --setup-channels --apply` moves an existing server across;
 # these lines are what a fresh server is made with. The old text channel is
 # kept as test-tasks-archive, never made and never pruned.
 #
# WHY THAT ONE HAS extra_roles AND THE OTHER TWO DO NOT.
# Patrick locked who may start, reset and refresh a Live smoke session on
# 1 October: Owner, Dev and Lead GM. pathfind grants the STAFF roles and
# Playtester, and the lead gamemaster role is in neither list, so somebody
# holding only that one passed the bot's admin check and could not see the
# channel they were meant to run it in. Both spellings are named because the
# role has been written both ways and the scrub is not finished; _named looks
# each up on the server and passes over the one that is not there. Only this
# channel gets them: test-results and play-testing are pathfind for the same
# people they always were, and nothing else moves.
 ('Testing', [
   dict(kind='forum', name='test-findings', key='RESULTS', mode='pathfind',
        topic='Pass, fail, and what went wrong.'),
   dict(kind='forum', name='Test-Tasks',   key='TESTS',   mode='pathfind',
        extra_roles=('Lead Gamemaster', 'Lead GM'),
        topic='One thread per test task, tagged Main.'),
   dict(kind='text',  name='known-issues', key='KNOWN',   mode='pathfind',
        topic='Known issues the team is working on. Kept by the bot.'),
   dict(kind='text',  name='test-tasks-archive', mode='pathfind', make=False),
   dict(kind='voice', name='play-testing', mode='pathfind'),
 ]),
 # The gamemasters' own room (#2519). Djinn's layout of 15 Oct, confirmed on
 # 17 Oct, with #gm-discipline kept from the 14 Oct list as a sixth channel.
 # Every channel in it is gm or gmrules, and nothing public goes in here: a
 # public scene listing goes in the Discord's Events channel later, not here.
 # GM Rules v1.0 is pinned in #gm-rules by hand; its text is not in this
 # repository. #gm from the 14 Oct list is named with make=False, so prune
 # leaves it alone if a run of #2547 ever made it, and nothing makes it again.
 ('Gamemasters', [
   dict(kind='text',  name='gm-rules',           mode='gmrules',
        topic='The GM Rules. Lead Gamemaster, Owner and Dev post here.'),
   dict(kind='text',  name='gm-scene-summaries', mode='gm',
        topic='What happened in a scene you ran, after it ends.'),
   dict(kind='text',  name='gm-chat',            mode='gm',
        topic='Planning, handoffs and questions between gamemasters.'),
   dict(kind='text',  name='gm-suggestions',     mode='gm',
        topic='Ideas for scenes, events and how we run them.'),
   dict(kind='text',  name='gm-discipline',      mode='gm',
        topic='Reprimands, punishments and bans only. Nothing else.'),
   dict(kind='voice', name='GM Voice',           mode='gm'),
   dict(kind='text',  name='gm',                 mode='gm', make=False),
 ]),
 ('Staff', [
   # The staff #news. Not the public #news in Information: that one carries
   # the key, and the release webhook with it. The watchdog does not speak
   # here; it speaks in #staff-updates (bot.py, staff-channel.txt, #2501).
   dict(kind='announce', name='news',      mode='staff'),
   dict(kind='forum', name='dev-test-results', mode='staff'),
   # The test tasks someone on dev has to measure (Patrick, 12 Oct). Made by
   # the bot's one-time `python bot.py --setup-channels --apply`, which finds
   # it by id from then on, never by this: named here so -Prune leaves it and
   # a run does not make a second one. The topic is the bot's DEV_TOPIC.
   dict(kind='forum', name='dev-test-tasks', mode='staff', make=False,
        topic='Test tasks someone on dev has to measure, from the board. Kept '
              'by the bot: a post goes when its issue closes as fixed or its '
              'test task no longer says Server: Dev.'),
   dict(kind='text',  name='staff-general', mode='staff',
        topic='Nobody else can see this.'),
   dict(kind='voice', name='Staff Room',    mode='staff'),
   # Gone from the server. Named here so prune leaves them alone, never made
   # again: #staff-updates, #staff-general and #dev-test-results carry all
   # three now.
   dict(kind='text',  name='dev-notes',     mode='staff', make=False,
        topic='What we\u2019re on, and what broke doing it.'),
   dict(kind='text',  name='deploys',       mode='staff', make=False,
        topic='Every ship and restart lands here.'),
   dict(kind='text',  name='reports',       mode='staff', make=False,
        topic='Reports about people. Staff only.'),
 ]),
]

# ----------------------------------------------------------------- engine --
# Only what is actually used. Asking for message_content as well made Discord
# refuse the whole connection, because it is a privileged intent that is off by
# default and nothing here reads a message's text: the bot posts, and deletes
# its own posts by author id.
client = discord.Client(intents=discord.Intents(guilds=True, members=True))
made, kept, failed = [], [], []


# Channels an earlier version of this made and this one does not want. Named
# rather than worked out, so moving one somewhere else does not save it.
RETIRED = [
    'tech-help', 'looking-for-group', 'off-topic', 'downloads',
    # known-issues was retired here once, and came back on 11 October as the
    # bot's list of open findings (Testing above), so it is not in this list.
    'links-and-credits',
    'Small Table', 'The Longhouse', 'Away',
    # #media does the job of both of these, and the bot channel was never used.
    'screenshots', 'clips', 'bot-commands',
    'The Bannered Mare', 'The Road',
    # Deleted in the channel cleanup and replaced by #test-tasks, which is a
    # new channel rather than this one renamed. Here so a re-run of this
    # script does not make it again.
    'test-these',
]

# NEVER DELETED, by prune or by anything else in here.
#
# Patrick's channels, the ones with his words and his people's posts in them.
# Every one of them is in PLAN as well, which is what keeps prune off them,
# and they are named again here because the cost of the plan being wrong once
# is somebody's channel. This list wins over RETIRED and over the plan: a name
# in both is kept.
#
# Added 2 October after a run made channels again that had been moved or
# renamed, and -Prune was one keystroke from taking the originals with it.
KEEP = (
    'general-chat', 'welcome-travelers', 'server-progression-and-economy',
    'play-testing', 'dev-test-results', 'test-results', 'test-tasks',
    'test-findings', 'test-tasks-archive', 'known-issues', 'dev-test-tasks',
    # Where staff status updates go (Patrick, 11 Oct), and where the bot says
    # the watchdog's messages and the sessions that went wrong, by the id in
    # staff-channel.txt. Not in PLAN, so without this a run would list it as
    # no longer in the plan and -Prune would delete it (#2501).
    'staff-updates',
    # Gamemasters category (#2519). Named so -Prune cannot take them.
    'gm-rules', 'gm-scene-summaries', 'gm-chat', 'gm-suggestions',
    'gm-discipline', 'gm voice', 'gm',
) + tuple(
    # The in-world roles (#2551, Patrick, 15 Oct: the office roles go in the
    # never-delete list). Nothing in this script deletes a role today; these
    # are named so that nothing added later ever may. A role holds who is in
    # an office, and deleting one empties that office in the game as well.
    ['Jarl of ' + _h for _h in OFFICE_HOLDS] + ['Citizen of ' + _h for _h in HOLDS] +
    OFFICE_ROLES
)


def refused(e):
    """Discord's answer to a request it turned down, for the "did not
       manage" list: the status and its own words."""
    return ('%s %s' % (getattr(e, 'status', ''), getattr(e, 'text', '') or e)).strip()


def say(mark, what):
    print('  %-9s %s' % (mark, what))


# THE BOT'S OWN WAY IN, in every channel that shuts everybody else out.
#
# To Do List 223, "The bot is invited with Administrator and keeps it".
# Administrator overrides every channel overwrite, and that is the only
# reason the bot can see the staff channels, the channels behind Member and
# the holds, and post in the read only ones: nothing below ever named it.
# Untick Administrator and the @everyone deny lands on the bot too, since
# nothing here gives it Member, a staff role or a hold. The trouble alerts
# and the watchdog's messages, both in #staff-updates (bot.py, TROUBLE_ID,
# WATCH_ID and staff-channel.txt), go quiet, the hold panel cannot be posted
# in #choose-your-hold, and -Posts can no longer write the rules, welcome,
# news and faq posts.
#
# So the bot gets an overwrite for itself as a member, the way bot.py's
# log_channel already makes #ticket-log. Discord applies a member's own
# overwrite last, after @everyone and every role, so it wins over the deny.
# Three permissions and no more: see the channel, post in it, and read
# back what is there, which is how post() finds its old messages to delete.
# The build itself still wants Administrator, because it makes the Owner and
# Dev roles with Administrator on them and Discord refuses that from a bot
# which does not hold it.
BOT_NEEDS = ('view_channel', 'send_messages', 'read_message_history')

# And two more in the channel bot.py opens its ticket threads in. The read
# mode that channel has in PLAN denies @everyone Send Messages in Threads, and
# the live one was gated by hand, so without Administrator the bot could open
# a private thread there and then not write the ticket into it. A thread takes
# its permissions from the channel it is in, so the bot's role having them
# server wide is not enough once the channel's @everyone deny lands on it.
TICKET_BOT_NEEDS = BOT_NEEDS + ('create_private_threads',
                                'send_messages_in_threads')

# What a role named in a channel's extra_roles gets there: the same three the
# talk overwrite below hands a staff role, and nothing else.
TALK_NEEDS = ('view_channel', 'send_messages', 'read_message_history')


# And one more in the channel the join cards go to (#2341). The card is a
# picture sent as a file (bot.py, on_member_join), the one thing the bot
# attaches anywhere, and posting a file needs Attach Files in that channel.
# The three above were all this channel's overwrite named, so once
# Administrator came off the bot's role (#455) the card depended on the
# role's server-wide bits and the channel's @everyone overwrite both letting
# it through. On 12 Oct the bot's start said it could not post there:
# "the bot is missing Attach Files there". Naming it in the bot's own
# overwrite, which Discord applies last, makes the channel give it whatever
# the role or @everyone say, the way the ticket channel's thread bits do.
JOIN_BOT_NEEDS = BOT_NEEDS + ('attach_files',)


def bot_needs(spec):
    key = spec.get('key')
    if key == 'TICKETS':
        return TICKET_BOT_NEEDS
    if key == 'JOIN':
        return JOIN_BOT_NEEDS
    return BOT_NEEDS


def with_bot(guild, out, needs=BOT_NEEDS):
    me = getattr(guild, 'me', None)
    if me is not None:
        out[me] = discord.PermissionOverwrite(**dict((n, True) for n in needs))
    return out


def shuts_out(ch, needs=BOT_NEEDS):
    """Whether @everyone's overwrite on this channel takes away one of the
       ones the bot needs there.

       Read off the channel as it stands rather than off its mode in PLAN.
       The gate on the live server was set by hand, and the modes only say
       what a channel this makes gets, so a mode can be wrong about a channel
       that is already there in either direction. Nothing this makes names the
       bot's own role, so without Administrator this deny is what keeps the
       bot out, and where there is none the bot's role already lets it in."""
    ev = getattr(getattr(ch, 'guild', None), 'default_role', None)
    if ev is None:
        return False
    have = ch.overwrites_for(ev)
    return any(getattr(have, n) is False for n in needs)


async def keep_bot(ch, needs=BOT_NEEDS):
    """Give the bot its own overwrite in a channel that is already there.

       overwrites() only reaches a channel when it is made, and every channel
       on the live server was made, or gated by hand, before this existed, so
       without this a re-run would let the bot into nothing. Only a channel
       that shuts @everyone out is touched, and only the bot's own overwrite
       on it. Only the ones it needs are set, anything else already on it
       stays as it is, and a channel that already has all of them is not written
       to at all, so running this again after Administrator is gone changes
       nothing and asks Discord for nothing.

       A channel PLAN names more needs for than the three (the ticket
       channel, the join channel) is touched whether or not @everyone is shut
       out: those bits are the channel's own job, and the bot's role holding
       them server wide is not something a build can see while it still has
       Administrator (#2341)."""
    if ch is None:
        return
    if tuple(needs) == BOT_NEEDS and not shuts_out(ch, needs):
        return
    me = getattr(getattr(ch, 'guild', None), 'me', None)
    if me is None:
        return
    have = ch.overwrites_for(me)
    need = dict((n, True) for n in needs if getattr(have, n) is not True)
    if not need:
        return
    what = '#' + ch.name + ' lets the bot in without Administrator'
    if CHECK:
        say('would change', what)
        return
    have.update(**need)
    try:
        await ch.set_permissions(me, overwrite=have,
                                 reason='Thornswood setup, the bot keeps its '
                                        'channels without Administrator')
        say('bot', what)
    except discord.HTTPException:
        failed.append(what + ' (Discord refused it)')


async def keep_extra(ch, spec, roles):
    """
    Give a channel's extra_roles their overwrite when the channel is already
    there.

    The same reason keep_bot exists: overwrites() only reaches a channel when
    it is made, so a #test-tasks made by hand, or one made by a run from
    before the role existed, would shut out the very people its extra_roles
    name. Only those roles are touched, only the three permissions they need
    are set, anything else already on them stays, and a role that has all
    three is not written to at all, so a second run asks Discord for nothing.
    """
    names = spec.get('extra_roles') or ()
    guild = getattr(ch, 'guild', None)
    if ch is None or not names or guild is None:
        return
    for name in names:
        r = _named(guild, roles, name)
        if r is None:
            continue
        have = ch.overwrites_for(r)
        need = dict((n, True) for n in TALK_NEEDS if getattr(have, n) is not True)
        if not need:
            continue
        what = '#' + ch.name + ' lets ' + name + ' in'
        if CHECK:
            say('would change', what)
            continue
        have.update(**need)
        try:
            await ch.set_permissions(r, overwrite=have,
                                     reason='Thornswood setup, the channel\'s '
                                            'extra roles')
            say('role', what)
        except discord.HTTPException:
            failed.append(what + ' (Discord refused it)')


# Who can see every hold. Wider than STAFF: the gamemaster ranks and the
# Loremaster run things in the holds too. Looked up by name, so one that is
# not on the server yet is passed over rather than stopping the build.
HOLD_STAFF = ('Owner', 'Dev', 'Lead Gamemaster', 'Moderator',
              'Trial Gamemaster', 'Gamemaster', 'Loremaster')


def _named(guild, roles, name):
    return roles.get(name) or discord.utils.get(guild.roles, name=name)


def _also(guild, roles, out, extra, talk):
    """
    The roles one channel wants on top of what its mode gives everybody.

    A mode is the gate the whole server is built from, so widening one to
    suit a single channel widens every channel that uses it. extra_roles on
    that channel's own line in PLAN is the narrow way to do it: these are
    looked up by name on the server, so a role that is not in ROLES is still
    found, and one that is not there at all is passed over rather than
    guessed at.

    Nothing to add on a public channel, which has no overwrites at all,
    because there is nothing being denied for this to get around.
    """
    for name in (extra or ()):
        r = _named(guild, roles, name)
        if r is not None:
            out[r] = talk
    return out


def overwrites(guild, mode, roles, hold=None, needs=BOT_NEEDS, extra=None):
    ev = guild.default_role
    deny_all  = discord.PermissionOverwrite(view_channel=False)
    read_only = discord.PermissionOverwrite(send_messages=False,
                                            add_reactions=True,
                                            create_public_threads=False,
                                            send_messages_in_threads=False)
    talk      = discord.PermissionOverwrite(view_channel=True,
                                            send_messages=True,
                                            read_message_history=True)
    # Every mode but public shuts @everyone out of something the bot needs,
    # so every one of them names the bot as well.
    if mode == 'public':
        return {}
    if mode in ('open', 'membersread'):
        out = {ev: deny_all}
        member = _named(guild, roles, 'Member')
        if member is not None:
            out[member] = talk if mode == 'open' else discord.PermissionOverwrite(
                view_channel=True, read_message_history=True, send_messages=False)
        for r in STAFF:
            if roles.get(r):
                out[roles[r]] = talk
        return with_bot(guild, _also(guild, roles, out, extra, talk), needs)
    if mode == 'hold':
        out = {ev: deny_all}
        names = list(HOLD_STAFF)
        if hold:
            names += ['Jarl of ' + hold, 'Citizen of ' + hold]
        for n in names:
            r = _named(guild, roles, n)
            if r is not None:
                out[r] = talk
        return with_bot(guild, _also(guild, roles, out, extra, talk), needs)
    if mode == 'read':
        out = {ev: read_only}
        for r in STAFF:
            if roles.get(r):
                out[roles[r]] = discord.PermissionOverwrite(send_messages=True,
                                                            manage_messages=True)
        return with_bot(guild, _also(guild, roles, out, extra, talk), needs)
    if mode == 'staff':
        out = {ev: deny_all}
        for r in STAFF:
            if roles.get(r):
                out[roles[r]] = talk
        return with_bot(guild, _also(guild, roles, out, extra, talk), needs)
    if mode == 'pathfind':
        out = {ev: deny_all}
        for r in list(STAFF) + ['Playtester']:
            if roles.get(r):
                out[roles[r]] = talk
        return with_bot(guild, _also(guild, roles, out, extra, talk), needs)
    if mode == 'gm':
        out = {ev: deny_all}
        for n in GM_AREA:
            r = _named(guild, roles, n)
            if r is not None:
                out[r] = talk
        return with_bot(guild, _also(guild, roles, out, extra, talk), needs)
    if mode == 'gmrules':
        out = {ev: deny_all}
        reader = discord.PermissionOverwrite(view_channel=True,
                                             read_message_history=True,
                                             send_messages=False,
                                             create_public_threads=False,
                                             send_messages_in_threads=False)
        for n in GM_AREA:
            r = _named(guild, roles, n)
            if r is not None:
                out[r] = reader
        for n in GM_RULES_POST:
            r = _named(guild, roles, n)
            if r is not None:
                out[r] = talk
        return with_bot(guild, _also(guild, roles, out, extra, talk), needs)
    return {}


def role_moves(order):
    """(role, position) for each role in order that is not where the plan
       wants it, highest first.

       The roles keep the positions they hold between them and are only put
       in the plan's order among those, so a role the plan does not name
       stays where it is, and so does one something else manages (Server
       Booster, Patreon's), which Discord never moves. Counting from the
       bot's own role down instead put every role after Server Booster one
       place off on the live server, and a -Check on 22 Oct planned 50 moves
       for roles already in order (#2519)."""
    movable = [r for r in order if not getattr(r, 'managed', False)]
    slots = sorted((r.position for r in movable), reverse=True)
    return [(r, p) for r, p in zip(movable, slots) if r.position != p]


async def ensure_roles(guild):
    have = {r.name: r for r in guild.roles}
    out = {}
    new = set()
    for name, colour, hoist, perms in ROLES:
        if name in have:
            out[name] = have[name]
            kept.append('role ' + name)
            continue
        if ONLY:
            continue
        if name in NOT_MADE:
            say('note', 'there is no ' + name + ' role, and Discord, Patreon '
                'or the bot makes that one, not this')
            continue
        if CHECK:
            say('would make', 'role ' + name)
            continue
        try:
            out[name] = await guild.create_role(
                name=name, colour=discord.Colour(colour), hoist=hoist,
                mentionable=True, permissions=perms,
                reason='Thornswood setup')
            new.add(name)
            made.append('role ' + name)
            say('role', name)
        except discord.Forbidden:
            failed.append('role ' + name + ' (the bot needs to be higher up '
                          'the role list than the roles it makes)')
    if ONLY:
        return out
    # A role made just now is at the bottom. It goes straight under the one
    # the plan puts above it, so it has a place among the others before they
    # are put in order.
    order = [out[n] for n, _, _, _ in ROLES if n in out]
    for i, role in enumerate(order):
        if i and role.name in new:
            above = order[i - 1]
            try:
                await role.edit(position=max(1, above.position - 1))
            except discord.HTTPException as e:
                failed.append('role %s could not be put under %s (%s)' % (role.name, above.name, refused(e)))
    # Highest first, among the positions the plan's roles already hold
    # (role_moves). One at a time, and a refusal on one is not allowed to
    # leave the rest of the list unsorted: each is asked, and one Discord will
    # not move is named under "did not manage" with Discord's answer (#2736;
    # it used to be dropped unsaid, and -Check moved roles it only meant to
    # look at).
    for role, want in role_moves(order):
        if CHECK:
            say('would move', 'role ' + role.name)
            continue
        try:
            await role.edit(position=want)
        except discord.HTTPException as e:
            failed.append('role %s could not be moved to its place (%s)' % (role.name, refused(e)))
    return out


async def ensure_channel(guild, cat, spec, roles, found):
    name = spec['name']
    kind = spec['kind']
    want = name.lower().replace(' ', '-') if kind != 'voice' else name

    existing = None
    for ch in guild.channels:
        if ch.name == want and getattr(ch, 'category', None) == cat:
            existing = ch
            break
    ow = overwrites(guild, spec.get('mode', 'open'), roles, spec.get('hold'),
                    bot_needs(spec), spec.get('extra_roles'))

    if existing is None and not spec.get('make', True):
        # In the plan so prune leaves the name alone, gone on purpose, and not
        # made again.
        kept.append('#' + want + ' (not there, and not made again)')
        return None
    if existing is None and CHECK:
        say('would make', ('voice ' if kind == 'voice' else '#') + want)
        return None
    if existing is None:
        try:
            if kind == 'voice':
                existing = await guild.create_voice_channel(
                    name, category=cat, overwrites=ow, reason='Thornswood setup')
            elif kind == 'forum':
                try:
                    existing = await guild.create_forum(
                        want, category=cat, topic=spec.get('topic'),
                        overwrites=ow, reason='Thornswood setup')
                except Exception:
                    # No Community on this server yet. A text channel does the
                    # same job with less shape to it, and turning Community on
                    # later plus another run makes the forum.
                    existing = await guild.create_text_channel(
                        want, category=cat, topic=spec.get('topic'),
                        overwrites=ow, reason='Thornswood setup')
                    say('note', want + ' is a text channel for now, turn on '
                        'Community and run this again for a forum')
            else:
                existing = await guild.create_text_channel(
                    want, category=cat, topic=spec.get('topic'),
                    overwrites=ow, reason='Thornswood setup')
            made.append('#' + want)
            say('channel', want)
        except discord.Forbidden:
            failed.append('#' + want + ' (no permission)')
            return None
    else:
        # Made before Community was on, so it came out as a text channel where
        # a forum was wanted. Discord cannot convert one into the other, so the
        # only fix is to delete it and make it again, which is why this says so
        # loudly rather than quietly leaving it wrong.
        if kind == 'forum' and not isinstance(existing, getattr(discord, 'ForumChannel', ())):
            if PRUNE and want in KEEP:
                say('note', '#' + want + ' is a text channel where a forum was '
                    'wanted, and it is never deleted. Make the forum by hand '
                    'if it is wanted')
            elif PRUNE:
                try:
                    await existing.delete(reason='wrong kind, rebuilding as a forum')
                    existing = await guild.create_forum(
                        want, category=cat, topic=spec.get('topic'),
                        overwrites=ow, reason='Thornswood setup')
                    made.append('#' + want + ' (rebuilt as a forum)')
                    say('rebuilt', want + ' is a forum now')
                except Exception:
                    failed.append('#' + want + ' could not be rebuilt as a forum')
            else:
                say('note', '#' + want + ' is a text channel where a forum was '
                    'wanted. The only fix for that deletes it, so ask first')
        kept.append('#' + want)
        if spec.get('topic') and getattr(existing, 'topic', None) != spec['topic']:
            if CHECK:
                say('would change', 'a server or channel setting')
            else:
                try:
                    await existing.edit(topic=spec['topic'])
                except discord.HTTPException as e:
                    failed.append('#%s kept its old topic (%s)' % (want, refused(e)))
        await keep_bot(existing, bot_needs(spec))
        await keep_extra(existing, spec, roles)

    if kind == 'announce' and isinstance(existing, discord.TextChannel):
        try:
            if existing.type is not discord.ChannelType.news:
                if CHECK:
                    say('would change', 'a server or channel setting')
                else:
                    await existing.edit(type=discord.ChannelType.news)
        except Exception:
            say('note', want + ' could not become an announcement channel, '
                'which needs Community on')

    if spec.get('key'):
        found[spec['key']] = existing
    return existing


async def post(channel, text, found):
    """Put the words in, replacing anything this bot put there before, so the
       rules can be edited in content.py and re run rather than in Discord."""
    if channel is None or text is None:
        return
    for token, ch in found.items():
        if ch is not None:
            text = text.replace('<#' + token + '>', ch.mention)
    # Anything left pointing at a channel that does not exist becomes plain
    # words rather than a broken mention.
    import re
    text = re.sub(r'<#([A-Z]+)>', lambda m: '#' + m.group(1).lower(), text)

    # The old posts go first, or the new ones would sit under them twice
    # over. A channel whose old posts cannot be read or removed is left as it
    # is and named under "did not manage" (#2736): writing beside them is how
    # a channel came to say its rules twice.
    try:
        async for old in channel.history(limit=50):
            if old.author.id == client.user.id:
                try:
                    await old.delete()
                except discord.NotFound:
                    pass  # gone already, which is what this wanted
    except discord.HTTPException as e:
        failed.append('#%s was not rewritten: its old posts could not be removed (%s)'
                      % (channel.name, refused(e)))
        return

    chunks, cur = [], ''
    for para in text.split('\n\n'):
        if len(cur) + len(para) + 2 > 1900:
            chunks.append(cur.strip())
            cur = ''
        cur += para + '\n\n'
    if cur.strip():
        chunks.append(cur.strip())

    first = None
    for c in chunks:
        m = await channel.send(c)
        first = first or m
    if first:
        try:
            await first.pin()
        except discord.HTTPException as e:
            failed.append('#%s: its first post could not be pinned (%s)' % (channel.name, refused(e)))
    say('wrote', '#' + channel.name)


def _flags_differ(guild, flags):
    """True when the server's system-channel flags are not the ones wanted.

    A flag this discord.py does not know is left out, so the older library
    is compared on the flags it has.
    """
    cur = getattr(guild, 'system_channel_flags', None)
    if cur is None:
        return True
    for name in ('join_notifications', 'join_notification_replies',
                 'premium_subscriptions', 'guild_reminder_notifications'):
        if not hasattr(flags, name):
            continue
        if getattr(cur, name, None) != getattr(flags, name):
            return True
    return False


async def apply_welcome_and_afk(guild, found):
    """Discord's plain join line, and where it moves people who go quiet.

    The plain "Welcome X" line is a server setting, not a post, and it turns
    #welcome into a list of names. The bot draws a card instead, so this
    switches the plain one off and leaves boosts and the setup tips alone.
    The system channel is set only when the server has none yet: it was set
    by hand to #welcome-travelers, and a re-run must not move it back.

    Discord moves people into AFK itself after five minutes of silence.

    Under -Check this says would change only when the server is not already
    that way, and it never says set.
    """
    try:
        wel = found.get('WELCOME')
        flags = discord.SystemChannelFlags(
            join_notifications=False,
            join_notification_replies=False,
            premium_subscriptions=True,
            guild_reminder_notifications=False)
        # Only when the server has none yet. It was set by hand to
        # #welcome-travelers, where the join cards go, and a re-run moving
        # it back to #welcome would undo that.
        if wel is not None and guild.system_channel is None:
            if CHECK:
                say('would change', 'a server or channel setting')
            else:
                await guild.edit(system_channel=wel, system_channel_flags=flags)
        elif _flags_differ(guild, flags):
            if CHECK:
                say('would change', 'a server or channel setting')
            else:
                await guild.edit(system_channel_flags=flags)
        if not CHECK:
            say('set', "Discord's own join message is off, the bot's card replaces it")
    except TypeError:
        # Older discord.py has no join_notification_replies.
        try:
            flags = discord.SystemChannelFlags(
                join_notifications=False,
                premium_subscriptions=True,
                guild_reminder_notifications=False)
            if _flags_differ(guild, flags):
                if CHECK:
                    say('would change', 'a server or channel setting')
                else:
                    await guild.edit(system_channel_flags=flags)
                    say('set', "Discord's own join message is off")
            elif not CHECK:
                await guild.edit(system_channel_flags=flags)
                say('set', "Discord's own join message is off")
        except Exception:
            say('note', 'could not switch off the plain join message')
    except Exception:
        say('note', 'could not switch off the plain join message')

    try:
        afk = found.get('AFK')
        if afk is not None and guild.afk_channel != afk:
            if CHECK:
                say('would change', 'a server or channel setting')
            else:
                await guild.edit(afk_channel=afk, afk_timeout=300)
                say('set', 'AFK after five minutes goes to ' + afk.name)
    except Exception:
        say('note', 'could not set the AFK channel')


# Discord's own notices about the server (#2955): Community Updates and Safety
# Notifications, the second about raids, DM spam and moderation, some of it
# about named people. Both go to #staff-updates, where staff notices go
# (Patrick, 20 Oct), and never to #staff-general, which is for talk. By the id
# in staff-channel.txt, the one bot.py speaks in, not by name: a name can be
# two channels. They were a hand step on the Enable Community screen, written
# up in the README as #staff-general, until this set them from the plan.
STAFF_CHANNEL_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                  'staff-channel.txt')


async def apply_notice_channels(guild):
    """Points Discord's Community Updates and Safety Notifications channels at
    #staff-updates.

    Neither field exists until Community is on, and the closing lines of a
    run already say to turn it on and run again, so a server without it is
    left alone. Under -Check this says would change only when either one
    points somewhere else, and it never says set. What it cannot do goes
    under "did not manage" with the reason.
    """
    if 'COMMUNITY' not in set(getattr(guild, 'features', []) or []):
        return
    what = "Discord's own community and safety notices"
    try:
        with open(STAFF_CHANNEL_FILE, encoding='utf-8') as f:
            want_id = int(f.read().strip())
    except (OSError, ValueError) as e:
        failed.append('%s: staff-channel.txt gives no channel id (%s)' % (what, e))
        return
    want = guild.get_channel(want_id)
    if want is None:
        failed.append('%s: this server has no channel %d, the id in '
                      'staff-channel.txt' % (what, want_id))
        return
    have = (getattr(guild.public_updates_channel, 'id', None),
            getattr(guild.safety_alerts_channel, 'id', None))
    if have == (want_id, want_id):
        say('left alone', '%s already go to #%s' % (what, want.name))
        return
    if CHECK:
        say('would change', '%s to #%s' % (what, want.name))
        return
    try:
        await guild.edit(public_updates_channel=want, safety_alerts_channel=want,
                         reason='Thornswood setup')
    except discord.HTTPException as e:
        failed.append('%s: could not move them to #%s (%s)' % (what, want.name, refused(e)))
        return
    say('set', '%s go to #%s' % (what, want.name))


def plan_for(only):
    """PLAN, or the part of it ONLY names (#2519): a named category with
       all its channels, and a named channel in its own category. A name
       PLAN does not have is a ValueError naming it."""
    if not only:
        return PLAN
    def key(spec):
        return spec['name'] if spec['kind'] == 'voice' else spec['name'].lower().replace(' ', '-')
    cats = set(c for c, _ in PLAN if c)
    chans = set(key(s) for _, specs in PLAN for s in specs)
    unknown = [n for n in only if n not in cats and n not in chans]
    if unknown:
        raise ValueError('not in the plan: ' + ', '.join(unknown) +
                         '. ONLY takes category names and channel names from PLAN')
    out = []
    for catname, specs in PLAN:
        if catname and catname in only:
            out.append((catname, specs))
            continue
        picked = [s for s in specs if key(s) in only]
        if picked:
            out.append((catname, picked))
    return out


# The gate a category this makes is given. A category's channels carry their
# own modes; this is the category's own, which the audit reads as well.
CATEGORY_MODE = {'Staff': 'staff', 'Testing': 'pathfind',
                 'Gamemasters': 'gm',
                 'The Holds': 'hold',
                 'Start Here': 'public',
                 'Applications': 'public'}


# discord.py hands View Channel back under its old name, read_messages. The
# audit says it the way Discord's own permissions page and this file do.
SAID = {'read_messages': 'view_channel'}


def perm_names(p):
    """The permissions a Permissions holds, by discord.py's names, sorted."""
    return sorted(SAID.get(n, n) for n, v in p if v)


def _ow_dict(o):
    """A PermissionOverwrite as {name: True or False}, the unset left out."""
    return dict((SAID.get(n, n), v) for n, v in o if v is not None)


def perm_diff(have, want):
    """(extra, missing): what have holds that want does not, and the other
       way round, by name."""
    h, w = set(perm_names(have)), set(perm_names(want))
    return sorted(h - w), sorted(w - h)


def target_name(guild, t):
    """Who an overwrite is for, in words: a role's name, the bot, or a
       member by id. A member is never named, so the audit's channel lines
       say nothing about people."""
    if getattr(t, 'id', None) == getattr(getattr(guild, 'me', None), 'id', -1):
        return 'the bot'
    if hasattr(t, 'permissions'):
        return t.name
    return 'member %s' % getattr(t, 'id', '?')


def overwrite_diff(guild, live, want):
    """What differs between two {target: PermissionOverwrite} maps, as one
       line per target that differs, by the target's name. A target only in
       live is said with everything it sets; one only in want is said as
       missing."""
    a = dict((target_name(guild, t), o) for t, o in (live or {}).items())
    b = dict((target_name(guild, t), o) for t, o in (want or {}).items())
    out = []
    for name in sorted(set(a) | set(b)):
        la = _ow_dict(a[name]) if name in a else {}
        wb = _ow_dict(b[name]) if name in b else {}
        if name not in a:
            out.append('%s: no overwrite, the plan gives %s'
                       % (name, _ow_words(wb)))
            continue
        if name not in b:
            out.append('%s: not in the plan, has %s' % (name, _ow_words(la)))
            continue
        diff = []
        for perm in sorted(set(la) | set(wb)):
            if la.get(perm) != wb.get(perm):
                diff.append('%s is %s, plan %s' % (perm, _tri(la.get(perm)),
                                                    _tri(wb.get(perm))))
        if diff:
            out.append('%s: %s' % (name, '; '.join(diff)))
    return out


def _tri(v):
    return 'allowed' if v is True else 'denied' if v is False else 'unset'


def _ow_words(d):
    allow = sorted(k for k, v in d.items() if v is True)
    deny = sorted(k for k, v in d.items() if v is False)
    parts = []
    if allow:
        parts.append('allow ' + ', '.join(allow))
    if deny:
        parts.append('deny ' + ', '.join(deny))
    return '; '.join(parts) or 'nothing'


def doubles(members, ranks=None):
    """[(member, category, [rank, ...])] for everybody holding two or more
       ranks of one staff category (STAFF_RANKS)."""
    out = []
    for m in members:
        mine = set(r.name for r in getattr(m, 'roles', ()) or ())
        for cat, names in (ranks or STAFF_RANKS):
            held = [n for n in names if n in mine]
            if len(held) > 1:
                out.append((m, cat, held))
    return out


def _who(m):
    return getattr(m, 'display_name', None) or getattr(m, 'name', None) or str(getattr(m, 'id', '?'))


async def audit(guild):
    """Says, and changes nothing. See AUDIT at the top."""
    have = dict((r.name, r) for r in guild.roles)
    roles = dict((n, have[n]) for n, _, _, _ in ROLES if n in have)
    planned = dict((n, p) for n, _, _, p in ROLES)
    bad = [0]

    def line(what):
        print('  ' + what, flush=True)

    def off(what):
        bad[0] += 1
        line('DIFFERS  ' + what)

    print('\n  Audit of %s, read only\n' % guild.name, flush=True)

    print('  The bot', flush=True)
    me = guild.me
    mine = me.guild_permissions
    if mine.administrator:
        off('the bot holds Administrator; running, it needs only the set in '
            'RUN_BITS (untick Administrator on its role after a build)')
    extra, missing = perm_diff(mine, discord.Permissions(RUN_PERMISSIONS))
    if missing:
        off('the bot is missing ' + ', '.join(missing))
    if extra and not mine.administrator:
        off('the bot holds more than it needs: ' + ', '.join(extra))
    line('its roles: ' + ', '.join(r.name for r in me.roles if r != guild.default_role))

    print('\n  @everyone', flush=True)
    line('server wide: ' + (', '.join(perm_names(guild.default_role.permissions)) or 'nothing'))

    print('\n  Roles against the plan', flush=True)
    for name, _, _, want in ROLES:
        r = roles.get(name)
        if r is None:
            if name not in NOT_MADE:
                off('role %s is not on the server' % name)
            continue
        if name in NOT_MADE or getattr(r, 'managed', False):
            continue
        extra, missing = perm_diff(r.permissions, want)
        if extra:
            off('role %s holds more than the plan: %s' % (name, ', '.join(extra)))
        if missing:
            off('role %s is missing %s' % (name, ', '.join(missing)))
    for r in guild.roles:
        if (r.name not in planned and r != guild.default_role
                and not getattr(r, 'managed', False)):
            off('role %s is not in the plan, holds %s, %d member(s)'
                % (r.name, ', '.join(perm_names(r.permissions)) or 'nothing',
                   len(r.members)))

    print('\n  Who holds each staff rank', flush=True)
    staff_names = []
    for _, names in STAFF_RANKS:
        staff_names += list(names)
    for n in list(STAFF) + list(GM_AREA) + ['Loremaster', 'Content Creator']:
        if n not in staff_names:
            staff_names.append(n)
    for n in staff_names:
        r = have.get(n)
        if r is not None:
            line('%s: %s' % (n, ', '.join(sorted(_who(m) for m in r.members)) or 'nobody'))
    for n in ('Playtester', 'Member', 'Banned'):
        r = have.get(n)
        if r is not None:
            line('%s: %d member(s)' % (n, len(r.members)))
    for m, cat, held in doubles(guild.members):
        off('%s holds %s, two ranks of %s' % (_who(m), ' and '.join(held), cat))

    print('\n  Categories and channels against the plan', flush=True)
    ours = set()
    for catname, specs in PLAN:
        cat = discord.utils.get(guild.categories, name=catname) if catname else None
        if catname and cat is None:
            off('category %s is not on the server' % catname)
            continue
        if cat is not None:
            for d in overwrite_diff(guild, cat.overwrites,
                                    overwrites(guild, CATEGORY_MODE.get(catname, 'open'), roles)):
                off('category %s, %s' % (catname, d))
        for spec in specs:
            kind = spec['kind']
            want = spec['name'].lower().replace(' ', '-') if kind != 'voice' else spec['name']
            ours.add((catname, want.lower()))
            ch = None
            for c in guild.channels:
                if c.name == want and getattr(c, 'category', None) == cat:
                    ch = c
                    break
            if ch is None:
                if spec.get('make', True):
                    off('#%s is not in %s' % (want, catname))
                continue
            plan = overwrites(guild, spec.get('mode', 'open'), roles, spec.get('hold'),
                              bot_needs(spec), spec.get('extra_roles'))
            for d in overwrite_diff(guild, ch.overwrites, plan):
                off('#%s, %s' % (want, d))
    for c in guild.channels:
        if isinstance(c, discord.CategoryChannel):
            continue
        cat = getattr(c, 'category', None)
        if (getattr(cat, 'name', None), c.name.lower()) in ours:
            continue
        where = getattr(cat, 'name', 'no category')
        if c.name.lower() in KEEP:
            # #staff-updates and the like: kept by name, never made by PLAN.
            line('#%s in %s is kept by name and not made by the plan' % (c.name, where))
        else:
            off('#%s in %s is not in the plan' % (c.name, where))

    print('\n  %d difference(s). Nothing was changed.\n' % bad[0], flush=True)
    return bad[0]


@client.event
async def on_ready():
    try:
        guild = None
        if GUILD:
            guild = client.get_guild(int(GUILD))
        elif len(client.guilds) == 1:
            guild = client.guilds[0]
        if guild is None:
            print('\nThe bot is in more than one server. Say which:')
            for g in client.guilds:
                print('  %-40s %s' % (g.name, g.id))
            print('\n  $env:DISCORD_GUILD = "<that number>"')
            return await client.close()

        if AUDIT:
            await audit(guild)
            return

        print('\n  Building %s\n' % guild.name)

        roles = await ensure_roles(guild)

        if ROLES_ONLY:
            # Nothing below this line runs: no category, no channel, no
            # post, no webhook, no guild setting. ensure_roles has already
            # made anything missing and put every role in its place, and
            # the tally below says which of those it did.
            say('roles only', 'nothing else was touched')
            print('')
            print('  made %d, already there %d' % (len(made), len(kept)))
            return await client.close()

        found = {}
        posts = []

        for catname, specs in plan_for(ONLY):
            cat = None
            if catname:
                cat = discord.utils.get(guild.categories, name=catname)
                if cat is None and ONLY and catname not in ONLY:
                    # Under ONLY a category is made only when it is named
                    # itself, never for a channel named inside it.
                    say('note', 'there is no ' + catname + ' category, and '
                        'only ' + catname + ' itself would make it')
                    continue
                if cat is None and CHECK:
                    # -Check makes nothing, a category included (#2519: the
                    # -Check of 22 Oct, 3:59 AM, made Gamemasters).
                    say('would make', 'category ' + catname)
                    for spec in specs:
                        if spec.get('make', True):
                            say('would make', ('voice ' if spec['kind'] == 'voice' else '#') +
                                (spec['name'] if spec['kind'] == 'voice' else
                                 spec['name'].lower().replace(' ', '-')))
                    continue
                if cat is None:
                    mode = CATEGORY_MODE.get(catname, 'open')
                    cat = await guild.create_category(
                        catname, overwrites=overwrites(guild, mode, roles),
                        reason='Thornswood setup')
                    made.append(catname)
                    say('category', catname)
                else:
                    kept.append(catname)
                    if not ONLY or catname in ONLY:
                        await keep_bot(cat)
            done = []
            for spec in specs:
                ch = await ensure_channel(guild, cat, spec, roles, found)
                done.append(ch)
                if spec.get('post'):
                    posts.append((ch, spec['post']))
            # A channel somebody made by hand inside one of these categories
            # is shut to @everyone like the gate around it, and the bot only
            # saw it because of Administrator. The staff #news the site
            # watcher speaks in is one: bot.py says it sits in Staff, and the
            # plan does not name it. keep_bot only writes where @everyone is
            # shut out, so this keeps what the bot can see today and widens
            # nothing, and a channel open to everybody is left alone.
            if cat is not None and (not ONLY or catname in ONLY):
                for ch in list(getattr(cat, 'channels', None) or []):
                    if ch not in done:
                        await keep_bot(ch)

        if ONLY:
            # Nothing past the parts named: no prune list, no post, no
            # webhook, no server setting.
            say('only', ', '.join(ONLY) + '. Nothing else was touched')
            print('\n  made %d, already there %d' % (len(made), len(kept)))
            if failed:
                print('\n  did not manage:')
                for f in failed:
                    print('    ' + f)
            print('')
            return

        # ------------------------------------------------------- pruning --
        # Only inside the categories this script manages, and only names it
        # knows it does not want. Anything anybody added themselves survives.
        mine = set()
        for catname, specs in PLAN:
            for spec in specs:
                mine.add(spec['name'].lower().replace(' ', '-')
                         if spec['kind'] != 'voice' else spec['name'].lower())
        ours = set(c for c, _ in PLAN if c)

        extra = []
        for ch in list(guild.channels):
            if isinstance(ch, discord.CategoryChannel):
                continue
            cat = getattr(ch, 'category', None)
            name = ch.name.lower()
            if name in KEEP:
                continue
            retired = name in [r.lower().replace(' ', '-') for r in RETIRED] \
                      or ch.name in RETIRED
            inside = cat is not None and cat.name in ours
            if retired or (inside and name not in mine):
                extra.append(ch)

        if extra:
            print('')
            if PRUNE:
                for ch in extra:
                    if CHECK:
                        say('would remove', '#' + ch.name)
                        continue
                    try:
                        await ch.delete(reason='Thornswood setup, no longer in the plan')
                        say('removed', '#' + ch.name)
                    except Exception:
                        failed.append('could not remove #' + ch.name)
            else:
                say('note', 'these are not in the plan any more:')
                for ch in extra:
                    print('             #' + ch.name)
                print('             -Prune is what deletes them, and a channel')
                print('             somebody is using belongs in the plan')
                print('             instead. Ask in #staff-updates first.')

        print('')
        if CHECK and POSTS:
            for ch, text in posts:
                if ch is not None:
                    say('would write', '#' + ch.name)
        elif CHECK and posts:
            # What the same run without -Check does: it leaves them alone.
            # This said would write for all seven whether or not -Posts was
            # given (#2519, 22 Oct).
            say('left alone', '%d read only post(s). -Posts rewrites them.' % len(posts))
        elif POSTS:
            for ch, text in posts:
                await post(ch, text, found)
        elif posts:
            say('left alone', '%d read only post(s). -Posts rewrites them.' % len(posts))

        # A webhook in news, so a release can announce itself without the bot
        # having to be running.
        news = found.get('NEWS')
        if news is not None:
            try:
                hooks = await news.webhooks()
                hook = discord.utils.get(hooks, name='Thornswood')
                if CHECK:
                    # Neither made nor written down: -Check changes nothing,
                    # a file beside the code included (#2519).
                    if hook is None:
                        say('would make', 'the news webhook in #' + news.name)
                    else:
                        say('left alone', 'the news webhook in #' + news.name)
                else:
                    if hook is None:
                        hook = await news.create_webhook(name='Thornswood')
                        say('webhook', 'made one in #' + news.name)
                    with open(WEBHOOK_OUT, 'w', encoding='utf-8') as f:
                        f.write(hook.url)
                    say('webhook', 'saved to ' + os.path.basename(WEBHOOK_OUT))
            except discord.Forbidden:
                failed.append('the news webhook (no permission)')

        await apply_welcome_and_afk(guild, found)
        await apply_notice_channels(guild)

        print('\n  made %d, already there %d' % (len(made), len(kept)))
        if failed:
            print('\n  did not manage:')
            for f in failed:
                print('    ' + f)
        print('')
        feats = set(getattr(guild, 'features', []) or [])
        if 'COMMUNITY' not in feats:
            print('  Server Settings, Enable Community, then run this again.')
            print('  Until then the forums are text channels and #news cannot')
            print('  be an announcement channel.')
        else:
            if guild.rules_channel is None:
                print('  Community then Safety Setup: point the rules screen')
                print('  at #rules. Nothing makes people accept them until you do.')
            if not PRUNE:
                print('  Nothing was deleted. -Prune is what deletes, and it')
                print('  goes through #staff-updates before anybody runs it.')
        print('')
        # Only after a real build that did all it set out to. After -Check
        # nothing was built, and after a failure the run that fixes it still
        # wants Administrator.
        if not CHECK and not failed:
            app = (getattr(client, 'application_id', None) or
                   getattr(getattr(client, 'user', None), 'id', None))
            if app:
                role = (getattr(guild, 'self_role', None) or
                        getattr(getattr(guild, 'me', None), 'top_role', None))
                say_invite(app, getattr(role, 'name', None))
                print('')
    except Exception as e:
        print('\n  stopped: %r' % (e,))
    finally:
        await client.close()


if __name__ == '__main__':
    try:
        plan_for(ONLY)
    except ValueError as e:
        sys.exit('DISCORD_ONLY: ' + str(e) + '. Nothing was asked of Discord.')
    if not TOKEN:
        sys.exit('No token. Set DISCORD_TOKEN first, or run Setup-Discord.ps1.')
    try:
        client.run(TOKEN, log_handler=None)
    except discord.LoginFailure:
        sys.exit('Discord refused that token.')
    except discord.PrivilegedIntentsRequired:
        sys.exit('Discord refused the intents. Under Bot in the developer '
                 'portal, "Server Members Intent" must be ON. Check the token '
                 'belongs to that same application.')
