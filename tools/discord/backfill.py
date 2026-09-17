"""
backfill.py

One-off: post the join card for everybody who came in while the bot had no
channel to post it in (#general had been renamed, so on_member_join logged
"no text channel called #general to greet in" and gave up).

    python backfill.py          list who would get a card, post nothing
    python backfill.py --go     post them, oldest join first

Reads the same bot.env.json as the bot (run.ps1 puts it in the environment).
Who already has a card is worked out from the channels themselves: every card
message is the bot's, says "came up the road." and mentions the person, so the
mentioned ids across #welcome-travelers and #general-chat are the people done.
Anybody else who joined after the newest existing card, and is not a bot, is
owed one. Their number is their place in the join order among the members
still here, which is what member_count was when they arrived if nobody has
left since.
"""
import asyncio
import os
import sys
import traceback

import discord

import card

TOKEN = os.environ.get('DISCORD_TOKEN', '').strip()
WELCOME = os.environ.get('JOIN_CHANNEL', 'welcome-travelers').strip()
GO = '--go' in sys.argv

if not TOKEN:
    raise SystemExit('No DISCORD_TOKEN in the environment. Run through run.ps1 or set it.')

intents = discord.Intents(guilds=True, members=True)
client = discord.Client(intents=intents)


def say(*a):
    print('[backfill]', *a, flush=True)


async def done_ids(guild, names):
    """User ids that already have a card, and when the newest card was posted."""
    ids = set()
    newest = None
    for n in names:
        ch = discord.utils.get(guild.text_channels, name=n)
        if ch is None:
            continue
        try:
            async for m in ch.history(limit=1000):
                if m.author.id != guild.me.id:
                    continue
                if 'came up the road' not in (m.content or ''):
                    continue
                for u in m.mentions:
                    ids.add(u.id)
                if newest is None or m.created_at > newest:
                    newest = m.created_at
        except Exception:
            say('could not read #%s:\n%s' % (n, traceback.format_exc()))
    return ids, newest


@client.event
async def on_ready():
    try:
        await work()
    except Exception:
        say('failed:\n' + traceback.format_exc())
    finally:
        await client.close()


async def work():
    guild = client.guilds[0]
    say('server: %s, %d members' % (guild.name, guild.member_count))
    ch = discord.utils.get(guild.text_channels, name=WELCOME)
    if ch is None:
        say('no text channel called #%s' % WELCOME)
        return

    members = [m async for m in guild.fetch_members(limit=None)]
    members = [m for m in members if m.joined_at is not None]
    members.sort(key=lambda m: m.joined_at)
    say('%d members with a join date' % len(members))

    have, newest = await done_ids(guild, [WELCOME, 'general-chat', 'general'])
    say('%d people already have a card; newest card %s' % (len(have), newest.isoformat(timespec='minutes') if newest else 'none found'))

    owed = []
    for i, m in enumerate(members):
        if m.bot or m.id in have:
            continue
        if newest is not None and m.joined_at <= newest:
            continue
        owed.append((i + 1, m))

    if not owed:
        say('nobody is owed a card')
        return
    for number, m in owed:
        say('owed: #%d %s (%s) joined %s' % (number, m.display_name or m.name, m, m.joined_at.isoformat(timespec='minutes')))

    if not GO:
        say('dry run, nothing posted. Run with --go to post them.')
        return

    for number, m in owed:
        name = m.display_name or m.name
        png = None
        try:
            avatar = m.display_avatar.replace(size=256, format='png')
            data = await avatar.read()
            png = await asyncio.get_running_loop().run_in_executor(None, card.render, name, data, number, None, m.name)
        except Exception:
            say('card failed for %s:\n%s' % (m, traceback.format_exc()))
        line = '%s came up the road.' % m.mention
        try:
            if png is not None:
                await ch.send(line, file=discord.File(png, 'welcome.png'))
            else:
                await ch.send(line)
            say('posted #%d %s' % (number, m))
        except Exception:
            say('posting failed for %s:\n%s' % (m, traceback.format_exc()))
        await asyncio.sleep(1.5)


client.run(TOKEN, log_handler=None)
