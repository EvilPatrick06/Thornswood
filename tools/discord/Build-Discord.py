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
       URL it makes and add it to the Thornswood server.
    5. Server Settings, Enable Community. Without it there are no forum
       channels, no announcement channels and no rules screen, and this falls
       back to plain text channels for those.

  The bot needs to be ABOVE the roles it creates, so drag its own role to the
  top of the role list once it has joined.
"""

import asyncio
import os
import sys

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
# Rewriting the read only posts means deleting the bot's old messages and
# sending them again, in seven channels. Doing that on every run makes a one
# channel change look like the server being rebuilt, so it is opt in now.
POSTS = os.environ.get('DISCORD_POSTS', '') == '1'
CHECK = os.environ.get('DISCORD_CHECK', '') == '1'
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
ROLES = [
    # name              colour    hoist  permissions
    ('Owner',           0xC9A24B, True,  ADMIN),
    ('Dev',             0x9B7BD4, True,  ADMIN),
    ('Moderator',       0x6FA05A, True,  MOD),
    ('Gamemaster',      0x4F9BC7, True,  GM),
    ('Loremaster',      0x57B8A0, True,  PLAIN),   # writes the world
    ('Content Creator', 0xD2603F, True,  PLAIN),
    ('Playtester',      0xC07A4E, True,  PLAIN),

    # The three Patreon tiers, worst name at the top. Patreon hands these out
    # itself once the Discord is connected in its settings, so nothing here
    # ever assigns them.
    ('Thalmor Boot-Licker', 0x9FBE6B, True, PLAIN),
    ('Talos Worshiper',     0xD8B24C, True, PLAIN),
    ('Milk Drinker',        0xBFD3DE, True, PLAIN),

    ('Booster',         0xD98FB0, True,  PLAIN),   # boosted the server itself
]

# In world. One Jarl per hold, and a hold for everybody else to belong to.
#
# Eighteen roles sounds like a lot for a small server, but Discord only shows a
# hoisted group in the member list when somebody in it is online, so the empty
# ones are invisible until they are not. A Jarl outranks their own citizens in
# the list because Jarl sits higher here.
for _h in HOLDS:
    ROLES.append(('Jarl of ' + _h, 0xE0C56A, True, PLAIN))
for _h in HOLDS:
    ROLES.append(('Citizen of ' + _h, 0x8FA9B8, True, PLAIN))

ROLES.append(('Member', 0x8D9682, False, PLAIN))   # everybody, on the way in

# THE ONE A BAN DEPENDS ON, and it was never created.
#
# docs-app/server.js has keyed access off a role called Banned since it was
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

STAFF = ('Owner', 'Dev', 'Moderator', 'Gamemaster')

# --------------------------------------------------------------- channels --
# mode:  open      anybody talks
#        read      staff post, everybody reads
#        staff     staff only, invisible to everybody else
#        pathfind  testers and staff only
#
# key is what the words in content.py point at, so a channel can be renamed
# without every mention of it going stale.
PLAN = [
 (None, [
   dict(kind='text',  name='welcome',     key='WELCOME',  mode='read',
        topic="Start here.", post=C.WELCOME),
   dict(kind='text',  name='rules',       key='RULES',    mode='read',
        topic='Seven rules. Read them.', post=C.RULES),
   dict(kind='text',  name='start-here',  key='START',    mode='read',
        topic="How to actually get in and play.",
        post=C.START),
 ]),
 ('Information', [
   dict(kind='announce', name='news',     key='NEWS',     mode='read',
        topic='What changed, every time it changes.',
        post=C.NEWS_FIRST),
   dict(kind='text',  name='updates',     key='UPDATES',  mode='read',
        topic="Restarts and outages. Check here before asking why you can't connect."),
   dict(kind='text',  name='faq',         key='FAQ',      mode='read',
        topic='Read this before you ask.', post=C.FAQ),
 ]),
 ('Help', [
   dict(kind='text',  name='tickets',     key='TICKETS',  mode='open',
        topic="Open a ticket. Nobody sees it but staff."),
   dict(kind='voice', name='Support',      mode='open'),
   dict(kind='text',  name='applications',key='APPLY',    mode='open',
        topic='Want to help run the place? Say which job and why you.'),
   dict(kind='forum', name='bugs',        key='BUGS',     mode='open',
        topic=C.BUGS_TOPIC),
   dict(kind='forum', name='suggestions', key='SUGGESTIONS', mode='open',
        topic=C.SUGGEST_TOPIC),
   dict(kind='text',  name='logs-and-crashes', key='LOGS', mode='open',
        topic='Drag the log in. Explain it after.'),
 ]),
 ('Thornswood', [
   dict(kind='text',  name='general',     key='GENERAL',  mode='open',
        topic='Whatever.'),
   dict(kind='text',  name='media',       key='MEDIA',    mode='open',
        topic='Screenshots and clips. Talk about one in a thread under it.'),
 ]),
 ('In Character', [
   dict(kind='text',  name='game-rules',  key='GAMERULES', mode='read',
        topic='How roleplay works here. Ten rules, and what we let slide.',
        post=C.GAME_RULES),
   dict(kind='text',  name='lore',        key='LORE',     mode='read',
        topic='4E 252. What happened and who you can be.',
        post=C.LORE),
   dict(kind='text',  name='character-introductions', key='CHARS', mode='open',
        topic='Who are you playing? One post each.'),
   dict(kind='forum', name='tales',       key='TALES',    mode='open',
        topic='What happened out there. One post per story.'),
   dict(kind='text',  name='rp-appreciation', key='APPREC', mode='open',
        topic='Somebody played a blinder. Say so.'),
   dict(kind='text',  name='graveyard',   key='GRAVE',    mode='open',
        topic='They had it coming. Probably.'),
 ]),

 # One channel per hold, because a hold with nowhere to talk is a line on a
 # map. These are in character: what is said here is said in the hold.
 ('The Holds', [
   dict(kind='text', name=_h.lower(), key='HOLD_' + _h.upper(), mode='open',
        topic=C.HOLD_TOPICS[_h.lower()])
   for _h in HOLDS
 ]),
 # Three, plus somewhere to be idle. Proximity voice is in the launcher, so
 # these are for before, after, and whoever is not in the world.
 ('Voice', [
   dict(kind='voice', name='AFK',               key='AFK', mode='open'),
 ]),
 ('Testing', [
   dict(kind='text',  name='test-these',   key='TESTS',   mode='pathfind',
        topic='What needs trying on the current build.'),
   dict(kind='text',  name='test-results', key='RESULTS', mode='pathfind',
        topic='Pass, fail, and what went wrong.'),
 ]),
 ('Staff', [
   dict(kind='text',  name='staff-general', mode='staff',
        topic='Nobody else can see this.'),
   dict(kind='text',  name='dev-notes',     mode='staff',
        topic='What we\u2019re on, and what broke doing it.'),
   dict(kind='text',  name='deploys',       mode='staff',
        topic='Every ship and restart lands here.'),
   dict(kind='text',  name='reports',       mode='staff',
        topic='Reports about people. Staff only.'),
   dict(kind='voice', name='Staff Room',    mode='staff'),
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
    'known-issues', 'links-and-credits',
    'Small Table', 'The Longhouse', 'Away',
    # #media does the job of both of these, and the bot channel was never used.
    'screenshots', 'clips', 'bot-commands',
    'The Bannered Mare', 'The Road',
]


def say(mark, what):
    print('  %-9s %s' % (mark, what))


def overwrites(guild, mode, roles):
    ev = guild.default_role
    deny_all  = discord.PermissionOverwrite(view_channel=False)
    read_only = discord.PermissionOverwrite(send_messages=False,
                                            add_reactions=True,
                                            create_public_threads=False,
                                            send_messages_in_threads=False)
    talk      = discord.PermissionOverwrite(view_channel=True,
                                            send_messages=True,
                                            read_message_history=True)
    if mode == 'open':
        return {}
    if mode == 'read':
        out = {ev: read_only}
        for r in STAFF:
            if roles.get(r):
                out[roles[r]] = discord.PermissionOverwrite(send_messages=True,
                                                            manage_messages=True)
        return out
    if mode == 'staff':
        out = {ev: deny_all}
        for r in STAFF:
            if roles.get(r):
                out[roles[r]] = talk
        return out
    if mode == 'pathfind':
        out = {ev: deny_all}
        for r in list(STAFF) + ['Playtester']:
            if roles.get(r):
                out[roles[r]] = talk
        return out
    return {}


async def ensure_roles(guild):
    have = {r.name: r for r in guild.roles}
    out = {}
    for name, colour, hoist, perms in ROLES:
        if name in have:
            out[name] = have[name]
            kept.append('role ' + name)
            continue
        if CHECK:
            say('would make', 'role ' + name)
            continue
        try:
            out[name] = await guild.create_role(
                name=name, colour=discord.Colour(colour), hoist=hoist,
                mentionable=True, permissions=perms,
                reason='Thornswood setup')
            made.append('role ' + name)
            say('role', name)
        except discord.Forbidden:
            failed.append('role ' + name + ' (the bot needs to be higher up '
                          'the role list than the roles it makes)')
    # Highest first, under whatever the bot's own role is.
    try:
        top = guild.me.top_role.position
        order = [out[n] for n, _, _, _ in ROLES if n in out]
        for i, role in enumerate(order):
            want = max(1, top - 1 - i)
            if role.position != want:
                await role.edit(position=want)
    except Exception:
        pass
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
    ow = overwrites(guild, spec.get('mode', 'open'), roles)

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
            if PRUNE:
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
                    'wanted. Run with -Prune to rebuild it')
        kept.append('#' + want)
        try:
            if spec.get('topic') and getattr(existing, 'topic', None) != spec['topic']:
                if CHECK:
                    say('would change', 'a server or channel setting')
                else:
                    await existing.edit(topic=spec['topic'])
        except Exception:
            pass

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

    try:
        async for old in channel.history(limit=50):
            if old.author.id == client.user.id:
                await old.delete()
    except Exception:
        pass

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
    try:
        if first:
            await first.pin()
    except Exception:
        pass
    say('wrote', '#' + channel.name)


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

        print('\n  Building %s\n' % guild.name)

        roles = await ensure_roles(guild)
        found = {}
        posts = []

        for catname, specs in PLAN:
            cat = None
            if catname:
                cat = discord.utils.get(guild.categories, name=catname)
                if cat is None:
                    mode = 'staff' if catname in ('Staff',) else (
                           'pathfind' if catname == 'Testing' else 'open')
                    cat = await guild.create_category(
                        catname, overwrites=overwrites(guild, mode, roles),
                        reason='Thornswood setup')
                    made.append(catname)
                    say('category', catname)
                else:
                    kept.append(catname)
            for spec in specs:
                ch = await ensure_channel(guild, cat, spec, roles, found)
                if spec.get('post'):
                    posts.append((ch, spec['post']))

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
                print('             run with -Prune to delete them')

        print('')
        if CHECK:
            for ch, text in posts:
                if ch is not None:
                    say('would write', '#' + ch.name)
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
                if hook is None:
                    hook = await news.create_webhook(name='Thornswood')
                    say('webhook', 'made one in #' + news.name)
                with open(WEBHOOK_OUT, 'w', encoding='utf-8') as f:
                    f.write(hook.url)
                say('webhook', 'saved to ' + os.path.basename(WEBHOOK_OUT))
            except discord.Forbidden:
                failed.append('the news webhook (no permission)')

        # Discord's own "Welcome X. Say hi!" line is a server setting, not
        # anything a bot posts, and it turns #welcome into a list of names.
        # The bot draws a proper card in #general instead, so this switches
        # the plain one off and leaves boosts and the setup tips alone.
        try:
            wel = found.get('WELCOME')
            flags = discord.SystemChannelFlags(
                join_notifications=False,
                join_notification_replies=False,
                premium_subscriptions=True,
                guild_reminder_notifications=False)
            if wel is not None:
                if CHECK:
                    say('would change', 'a server or channel setting')
                else:
                    await guild.edit(system_channel=wel, system_channel_flags=flags)
            else:
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
                if CHECK:
                    say('would change', 'a server or channel setting')
                else:
                    await guild.edit(system_channel_flags=flags)
                say('set', "Discord's own join message is off")
            except Exception:
                say('note', 'could not switch off the plain join message')
        except Exception:
            say('note', 'could not switch off the plain join message')

        # Discord moves people into AFK itself after five minutes of silence,
        # which beats a channel called Away that everybody forgets to join.
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
                print('  Nothing was deleted. Run with -Prune to clear out')
                print('  anything this no longer wants.')
        print('')
    except Exception as e:
        print('\n  stopped: %r' % (e,))
    finally:
        await client.close()


if __name__ == '__main__':
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
