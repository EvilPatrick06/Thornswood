"""
redraw.py

One-off: the join cards that went up before card.py learned to draw dressed-up
names came out as a row of boxes. This finds every card of the bot's in the
welcome channels whose person has a name the old card could not draw, draws
it again with the current card.py, and swaps the picture on the existing
message. No new messages, no new pings.

    python redraw.py          list the cards it would redraw, change nothing
    python redraw.py --go     redraw them
    python redraw.py --all    every card, not only the ones that had boxes

Reads the same bot.env.json as the bot (run.ps1 puts it in the environment).
The number on the card is the person's place in the join order among the
members still here, the same rule backfill.py used.
"""
import asyncio
import os
import re
import sys
import traceback

import discord

import card

TOKEN = os.environ.get('DISCORD_TOKEN', '').strip()
WELCOME = os.environ.get('JOIN_CHANNEL', 'welcome-travelers').strip()
GO = '--go' in sys.argv
ALL = '--all' in sys.argv
CHANNELS = [WELCOME, 'general-chat', 'general']

if not TOKEN:
    raise SystemExit('No DISCORD_TOKEN in the environment. Run through run.ps1 or set it.')

intents = discord.Intents(guilds=True, members=True)
client = discord.Client(intents=intents)


def say(*a):
    print('[redraw]', *a, flush=True)


def dressed(name):
    """True when the old card would have drawn boxes: anything outside the
       letters, digits and punctuation Georgia carries."""
    return bool(re.search(r'[^\u0000-\u024F\u2000-\u206F]', name or ''))


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

    members = [m async for m in guild.fetch_members(limit=None)]
    members = [m for m in members if m.joined_at is not None]
    members.sort(key=lambda m: m.joined_at)
    order = {}
    for i, m in enumerate(members):
        order[m.id] = i + 1
    byid = {}
    for m in members:
        byid[m.id] = m

    todo = []
    for n in CHANNELS:
        ch = discord.utils.get(guild.text_channels, name=n)
        if ch is None:
            continue
        try:
            async for msg in ch.history(limit=1000):
                if msg.author.id != guild.me.id:
                    continue
                if 'came up the road' not in (msg.content or ''):
                    continue
                if not msg.mentions:
                    continue
                who = byid.get(msg.mentions[0].id)
                if who is None:
                    say('skipping a card for someone no longer here: %s' % msg.mentions[0])
                    continue
                name = who.display_name or who.name
                if ALL or dressed(name):
                    todo.append((ch, msg, who))
        except Exception:
            say('could not read #%s:\n%s' % (n, traceback.format_exc()))

    if not todo:
        say('nothing to redraw')
        return
    for ch, msg, who in todo:
        name = who.display_name or who.name
        say('#%s %s -> card will read %r, number %d' % (
            ch.name, msg.jump_url, card.shown_name(name, who.name), order.get(who.id, 0)))

    if not GO:
        say('dry run, nothing changed. Run with --go to redraw them.')
        return

    for ch, msg, who in todo:
        name = who.display_name or who.name
        try:
            avatar = who.display_avatar.replace(size=256, format='png')
            data = await avatar.read()
            png = await asyncio.get_running_loop().run_in_executor(
                None, card.render, name, data, order.get(who.id) or None, None, who.name)
            await msg.edit(attachments=[discord.File(png, 'welcome.png')])
            say('redrew the card for %s' % who)
        except Exception:
            say('failed for %s:\n%s' % (who, traceback.format_exc()))
        await asyncio.sleep(1.5)


client.run(TOKEN, log_handler=None)
