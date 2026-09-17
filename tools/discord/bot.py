"""
The Thornswood bot. This one stays running, unlike Build-Discord.py which sets
the server up once and exits.

What it does:

  Joins    draws a card and puts it in #welcome
  Tickets  a panel in #tickets, one private thread per ticket, and a copy
           pushed to the site so the inbox has it whether or not anybody was
           looking at Discord

Everything it needs is in env:

  DISCORD_TOKEN    the bot token
  THORNSWOOD_SITE  https://thornswood.net
  THORNSWOOD_KEY   shared secret the site checks on /api/ticket
  JOIN_CHANNEL     name of the channel join cards go in, default general
  TICKET_CHANNEL   public channel the panel lives in, comma separated, first wins
  TICKET_LOG       staff only channel closed tickets are recorded in
  STAFF_ROLES      comma separated, who gets pulled into every ticket thread
  CREATOR_ROLES    comma separated, added to Apply: Content Creator only

It is written to keep going when a piece of it fails. A card that will not
draw still gets a greeting, a site that is down still gets a thread, and a
thread that cannot be made still gets an answer to the person who asked.
"""
import asyncio
import json
import os
import re
import ssl
import traceback
import typing
import urllib.request

# Windows Server ships with an empty root certificate store and the automatic
# update for it switched off, so Python cannot verify discord.com and the
# handshake dies with "unable to get local issuer certificate". Install-Bot
# normally sets SSL_CERT_FILE for us; this is the belt to that braces, so a bot
# copied somewhere by hand still connects.
if not os.environ.get('SSL_CERT_FILE'):
    try:
        import certifi
        os.environ['SSL_CERT_FILE'] = certifi.where()
        os.environ.setdefault('REQUESTS_CA_BUNDLE', certifi.where())
        ssl.create_default_context()      # picked up on the next context made
    except Exception:
        pass

import discord

import card

TOKEN = os.environ.get('DISCORD_TOKEN', '').strip()
SITE = os.environ.get('THORNSWOOD_SITE', 'https://thornswood.net').rstrip('/')
KEY = os.environ.get('THORNSWOOD_KEY', '').strip()
# Joins go where people actually are, not into the read-only welcome page.
# Change JOIN_CHANNEL in bot.env.json on the VPS to move it.
WELCOME = os.environ.get('JOIN_CHANNEL',
          os.environ.get('WELCOME_CHANNEL', 'general')).strip().lower()
# Names the ticket panel will answer to, in order, first one that exists wins.
#
# This was a single name, and the single name was 'tickets'. The channel was
# then renamed to #tickets-and-applications, which moved nothing and broke
# everything: the panel message stayed where it was and still worked, so the
# server looked fine, while the bot could no longer find the channel. Every
# ticket after the rename had nowhere to open a thread and nowhere to fall back
# to. A list costs nothing and a rename stops mattering.
TICKETS = [n.strip().lower() for n in
           os.environ.get('TICKET_CHANNEL',
                          'tickets-and-applications,applications').split(',')
           if n.strip()]
TICKETS_SAID = ' or #'.join(TICKETS)

# Where a closed ticket is written down, and it is NOT the channel above.
# Everybody who can apply can read that one, so a closed application posted
# there is somebody else's answers sitting in front of the next person
# queueing up, and it buries the panel besides. Staff only, and made if it is
# not there.
TICKET_LOG = [n.strip().lower() for n in
              os.environ.get('TICKET_LOG', 'tickets,ticket-log').split(',')
              if n.strip()]
# Who gets pulled into every ticket thread.
STAFF = [r.strip().lower() for r in
         os.environ.get('STAFF_ROLES', 'Owner,Gamemaster,Dev,Loremaster,Moderator').split(',')
         if r.strip()]

# Roles that see one kind of ticket and not the rest.
#
# Content Creator is not general staff: that role is for social media, and it
# has no reason to be reading somebody's playtest application or a report about
# another person. It does have every reason to read applications to join it,
# so it is added to those threads and no others.
CREATOR = [r.strip().lower() for r in
           os.environ.get('CREATOR_ROLES', 'Content Creator').split(',')
           if r.strip()]
EXTRA_STAFF = {'creator': CREATOR}

if not TOKEN:
    raise SystemExit('No DISCORD_TOKEN. Install-Bot.ps1 sets it.')

intents = discord.Intents(guilds=True, members=True)
client = discord.Client(intents=intents)
tree = discord.app_commands.CommandTree(client)


def log(*a):
    print('[thornswood-bot]', *a, flush=True)


# ------------------------------------------------------------------ site --
def push(kind, title, detail, by, discord_id):
    """Send a ticket to the site. Runs off the event loop, and a failure here
       is never allowed to lose the ticket: the thread in Discord is the
       record, this is the convenience."""
    if not KEY:
        # Silent for as long as this has existed, which means a bot with no key
        # set looked exactly like a working one: the thread appeared, the site
        # inbox stayed empty, and nothing anywhere said why.
        log('THORNSWOOD_KEY is not set, so this ticket did NOT reach the site '
            'inbox. The thread in Discord is the only copy. Install-Bot.ps1 '
            'sets the key in bot.env.json on the VPS.')
        return
    body = json.dumps({
        'key': KEY, 'kind': kind, 'title': title,
        'detail': detail, 'by': by, 'discordId': str(discord_id)
    }).encode()
    req = urllib.request.Request(
        SITE + '/api/ticket', data=body,
        headers={'Content-Type': 'application/json'}, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=12) as r:
            r.read()
    except Exception as e:
        log('site push failed:', e)


async def push_async(*a):
    try:
        await asyncio.get_running_loop().run_in_executor(None, push, *a)
    except Exception as e:
        log('site push failed:', e)


def by_name(guild, names, kind='text'):
    """
    Find a channel by name.

    guild.channels holds categories and voice rooms as well as text channels.
    A server with a category called General sitting above a text channel called
    general hands back the category, which has no send method, and the only
    sign of it is a traceback in this log and nothing at all in Discord. So
    only ever look in the list that can actually be posted in.
    """
    pool = guild.voice_channels if kind == 'voice' else guild.text_channels
    # In the order given, not the order the server happens to list its
    # channels in. With a public #tickets-and-applications and a staff only
    # #tickets both in the server, taking whichever came first down the
    # sidebar would have put the application panel in the staff channel.
    for want in names:
        for ch in pool:
            if ch.name.lower() == want:
                return ch
    return None


async def log_channel(guild, make=True):
    """
    The staff only channel closed tickets are recorded in.

    Made rather than asked for, because the alternative is a feature that
    silently does nothing until somebody thinks to read a log. Deny first:
    @everyone cannot see it and only the staff roles are added back. Content
    Creator is left out on purpose, the same reason it is left out of every
    ticket that is not an application to join it.
    """
    ch = by_name(guild, TICKET_LOG)
    if ch is not None or not make:
        return ch

    if not guild.me.guild_permissions.manage_channels:
        log('there is no #%s to record closed tickets in, and the bot cannot '
            'make one because it does not have Manage Channels. Either give '
            'it that, or make the channel by hand with staff the only ones '
            'who can see it.' % TICKET_LOG[0])
        return None

    try:
        over = {
            guild.default_role: discord.PermissionOverwrite(view_channel=False),
            guild.me: discord.PermissionOverwrite(view_channel=True,
                                                  send_messages=True),
        }
        for r in guild.roles:
            if r.name.lower() in set(STAFF):
                over[r] = discord.PermissionOverwrite(view_channel=True,
                                                      send_messages=True)
        where = by_name(guild, TICKETS)
        ch = await guild.create_text_channel(
            TICKET_LOG[0],
            overwrites=over,
            category=(where.category if where is not None else None),
            topic='Every ticket that gets closed, with a link back to it. Staff only.')
        log('made #%s for closed tickets, staff only' % ch.name)
        return ch
    except Exception:
        log('could not make #%s:\n' % TICKET_LOG[0] + traceback.format_exc())
        return None


def thread_block(guild, ch):
    """
    Why a private thread cannot be opened in this channel, in words, or None.

    Discord answers every one of these with the same 50013 Forbidden, and the
    only place it lands is a traceback in a log on the VPS. Sending a message
    and opening a thread are separate permissions, so a bot that posted the
    panel perfectly well can still be unable to open a single ticket, and the
    symptom is an apology to the person applying and nothing anywhere else.
    Naming it here is the difference between a five minute fix and an evening.
    """
    try:
        p = ch.permissions_for(guild.me)
    except Exception:
        return None
    missing = [n for n, ok in (
        ('View Channel',             getattr(p, 'view_channel', True)),
        ('Send Messages',            getattr(p, 'send_messages', True)),
        ('Create Private Threads',   getattr(p, 'create_private_threads', True)),
        ('Send Messages in Threads', getattr(p, 'send_messages_in_threads', True)),
    ) if not ok]
    if not missing:
        return None
    return ('the bot does not have ' + ', '.join(missing) + ' in #' + ch.name)


# ----------------------------------------------------------------- joins --
@client.event
async def on_member_join(member):
    # First line in, before anything can go wrong, so the log can tell a join
    # that never reached the bot apart from one that reached it and failed.
    log('join: %s arrived in "%s"' % (member, member.guild.name))

    ch = by_name(member.guild, [WELCOME])
    if ch is None:
        log('no text channel called #%s to greet in' % WELCOME)
        return

    number = member.guild.member_count
    name = member.display_name or member.name

    png = None
    try:
        avatar = member.display_avatar.replace(size=256, format='png')
        data = await avatar.read()
        png = await asyncio.get_running_loop().run_in_executor(
            None, card.render, name, data, number, None, member.name)
    except Exception:
        log('card failed:\n' + traceback.format_exc())

    line = '%s came up the road.' % member.mention
    try:
        if png is not None:
            await ch.send(line, file=discord.File(png, 'welcome.png'))
        else:
            await ch.send(line)
    except Exception:
        log('greeting failed:\n' + traceback.format_exc())


# --------------------------------------------------------------- tickets --
# 'Apply to play' is not here on purpose. Everybody in the world right now is
# a playtester, so that is the one application to be in it, and when the doors
# open there will be no application to play at all. Leaving both up asked
# people to guess which one they wanted and half of them guessed wrong.
KINDS = [
    ('playtest',    'Apply to playtest',    'How you get in. Break it on purpose and write down how.'),
    ('jarl',        'Apply: Jarl',          'A seat in a hold. In character, and the first ones come out of these.'),
    ('gamemaster',  'Apply: Gamemaster',    'Run events, settle disputes, hold the line in character.'),
    ('loremaster',  'Apply: Loremaster',    'Keep the history straight and write the rest of it.'),
    ('moderator',   'Apply: Moderator',     'The unglamorous one. Tickets, reports, difficult people.'),
    ('dev',         'Apply: Dev',           'Server, launcher, site, mods. Anything that compiles.'),
    ('creator',     'Apply: Content Creator', 'Video, streams, screenshots, writing about the place.'),
    ('report',      'Report somebody',      'Something happened and it should not have.'),
    ('help',        'I need help',          'It will not install, will not start, or will not connect.'),
]

# The role each application is asking for, so the thread and the site inbox say
# what it is without anybody reading three answers first. None of these grant
# anything: giving out the role is still a person deciding.
ROLE_FOR = {
    'playtest':   'Playtester',
    'jarl':       'Jarl of the hold named below',
    'gamemaster': 'Gamemaster',
    'loremaster': 'Loremaster',
    'moderator':  'Moderator',
    'dev':        'Dev',
    'creator':    'Content Creator',
}

# Every job asks the same three things, because the answers that matter are the
# same three every time: what you have done, how much time you really have, and
# whether you want the job or the title.
def _job(what, examples):
    return [
        ('What experience do you have?',
         examples, True),
        ('How much time can you give it?',
         'Hours a week, and which days. Honest beats keen.', True),
        ('Why this role?',
         'What draws you to ' + what + ' rather than the rest.', True),
    ]

# Asked first, on the two tickets that are a way IN. Everything else on the
# panel is for somebody already here, who answered this to get here.
#
# It is a typed answer rather than a box to tick because Discord modals have no
# box to tick. What it is worth is the record: their own words, against their
# Discord id, at a time, kept in the thread and in the site inbox.
AGE_Q = ('Are you 18 or over?', 'Thornswood is an adult server. Yes or no.', False)
AGE_KINDS = ('playtest',)

_NO  = ('no', 'nope', 'nah', 'not ', 'under', 'minor')
_YES = ('yes', 'yep', 'yeah', 'yup', 'y ', 'ye', 'i am', 'im ', "i'm ", 'sure',
        'correct', 'of course', 'affirmative', 'over', 'above')


def said_yes(text):
    """
    Whether an answer to the age question reads as a yes.

    Generous on purpose, and it never rejects anything by itself. Somebody
    typing "27" or "im 34" has answered the question; somebody typing "no", or
    nothing at all, is the case this exists to catch. A guess about how a
    stranger types is not a good enough reason to throw an application away,
    so the worst this does is put a line at the top of the thread and leave it
    to a person.
    """
    t = (text or '').strip().lower()
    if not t:
        return False
    if t == 'n' or t.startswith(_NO):
        return False
    if t.startswith(_YES):
        return True
    for n in re.findall(r'\d+', t):
        try:
            if int(n) >= 18:
                return True
        except Exception:
            pass
    return False


QUESTIONS = {
    # The one application to be in the world. It asks about the character,
    # because that is what somebody is here for, and about testing, because
    # that is what being in it means today. It does not ask who they are
    # outside the game: that is answered by them being in the Discord.
    'playtest': [
        AGE_Q,
        ('Have you roleplayed before, and where?', 'No is a perfectly good answer.', True),
        ('Who do you want to play?', 'A sentence about the character, not a biography.', True),
        ('How much time can you give it?', 'Hours a week, and which days.', True),
        ('Describe a bug you have run into', 'What you did, what happened, what should have happened. Short.', True),
    ],
    # The only application here that is answered in character. The seats are
    # empty and the first people to hold them are picked out of these, so the
    # questions ask about the character rather than about the person, and the
    # last one asks the thing that actually decides it: whether they can lose
    # the seat and keep playing.
    'jarl': [
        ('Which hold? Second choice if you have one',
         'Whiterun, Solitude, Windhelm, Riften, Markarth, Dawnstar, Morthal, Falkreath, Winterhold.', False),
        ('Who is your character?',
         'Name, where they come from, what they have been doing until now. In character.', True),
        ('What is their claim to the seat?',
         'Blood, a war record, coin, or being the one who stayed. Something a hold would accept.', True),
        ('What would they change in the hold?',
         'What they actually do with it. Answer as them, not as you.', True),
        ('What happens if they lose the seat?',
         'A seat that cannot be lost is not a seat. Say how you play that.', True),
    ],
    'gamemaster': _job('running events',
        'Events you have run, groups you have led, tables you have DMed.'),
    'loremaster': _job('the lore',
        'Worldbuilding, wikis, writing, anything you have kept consistent over time.'),
    'moderator': _job('moderating',
        'Servers or forums you have moderated, and roughly how big.'),
    'dev': _job('the code',
        'Languages, projects, a repo link. Papyrus and C# are the useful ones here.'),
    'creator': _job('making things about Thornswood',
        'Channel, streams, a portfolio, anything you have put out.'),
    'report': [
        ('Who, and where?', 'Name and the channel or the place in the world.', False),
        ('What happened?', 'What they did, what you did, and roughly when.', True),
        ('Anything we can look at?', 'Screenshots, a clip, a time to check the log against.', True),
    ],
    'help': [
        ('What is going wrong?', 'One line.', False),
        ('What were you doing when it broke?', 'Installing, launching, connecting, playing.', True),
        ('What did it say, if anything?', 'Paste the error.', True),
    ],
}


class TicketModal(discord.ui.Modal):
    def __init__(self, kind, label):
        super().__init__(title=label[:45])
        self.kind = kind
        self.label_text = label
        self.fields = []
        for q, ph, long in QUESTIONS[kind]:
            item = discord.ui.TextInput(
                label=q[:45],
                placeholder=ph[:100],
                style=discord.TextStyle.paragraph if long else discord.TextStyle.short,
                required=not long,
                max_length=1000 if long else 200)
            self.fields.append(item)
            self.add_item(item)

    async def on_submit(self, interaction):
        await interaction.response.defer(ephemeral=True, thinking=True)
        guild = interaction.guild
        who = interaction.user

        lines = []
        for item, (q, _, _) in zip(self.fields, QUESTIONS[self.kind]):
            lines.append('**%s**\n%s' % (q, (item.value or '').strip() or 'nothing said'))
        detail = '\n\n'.join(lines)

        asking = ROLE_FOR.get(self.kind)
        if asking:
            detail = '**Asking for:** ' + asking + '\n\n' + detail

        # Anything that does not read as a yes says so at the top, in words, on
        # the line staff read first. It never stops the ticket: losing somebody's
        # application over how they phrased one answer would be worse than a
        # person spending two seconds reading it.
        if self.kind in AGE_KINDS:
            gave = ''
            for item, (q, _, _) in zip(self.fields, QUESTIONS[self.kind]):
                if q == AGE_Q[0]:
                    gave = (item.value or '').strip()
                    break
            if not said_yes(gave):
                detail = ('**CHECK THIS ONE.** Asked if they are 18 or over they '
                          'said "%s".\n\n' % (gave or 'nothing')) + detail

        title = ('%s, %s' % (self.label_text, who.display_name))[:96]

        # Mentioning a role does not put anybody in a private thread. Only
        # people who have been added to one can see it, so a ticket opened
        # without this was visible to the applicant and to nobody else, and the
        # @mention went into a room staff were not in. They are added one at a
        # time, which is the only way Discord offers.
        want = set(STAFF) | set(EXTRA_STAFF.get(self.kind, []))
        staff_roles = [r for r in guild.roles if r.name.lower() in want]
        if not staff_roles:
            log('no role matched %r, so nobody will be pulled into this ticket. '
                'Set STAFF_ROLES in bot.env.json to the role names this server '
                'actually uses.' % (sorted(want),))
        head = '%s opened this. %s' % (who.mention,
                                       ' '.join(r.mention for r in staff_roles))

        ch = by_name(guild, TICKETS)
        why = None
        opened = None
        posted = False

        if ch is None:
            why = ('there is no text channel called #%s in this server' % TICKETS_SAID)
            log(why)
        else:
            why = thread_block(guild, ch)
            if why:
                log('no ticket thread: %s' % why)
            else:
                try:
                    opened = await ch.create_thread(
                        name=title,
                        type=discord.ChannelType.private_thread,
                        invitable=False,
                        auto_archive_duration=10080)
                except Exception as e:
                    why = 'Discord refused to open the thread (%s)' % e
                    log('the ticket thread could not be created:\n'
                        + traceback.format_exc())
                    opened = None

        # From here the thread exists. Everything after it is allowed to fail
        # on its own without throwing the thread away, which is what used to
        # happen: one member who could not be added took the whole ticket down
        # and left an empty thread nobody was in.
        if opened is not None:
            try:
                await opened.add_user(who)
            except Exception as e:
                log('could not add %s to their own ticket: %s' % (who, e))

            added = 0
            seen = set()
            for r in staff_roles:
                for m in r.members:
                    if m.id == who.id or m.id in seen or m.bot:
                        continue
                    seen.add(m.id)
                    try:
                        await opened.add_user(m)
                        added += 1
                    except Exception as e:
                        log('could not add %s to the ticket thread: %s' % (m, e))

            if staff_roles and added == 0:
                log('staff roles %r matched but nobody was added to the ticket '
                    'thread. If those roles have members, the bot is missing '
                    'permissions in #%s.'
                    % ([r.name for r in staff_roles], ch.name))

            try:
                await opened.send(head[:1900], view=TicketTools())
                for chunk in _chunks(detail, 1900):
                    await opened.send(chunk)
                posted = True
            except Exception as e:
                why = 'the thread opened but nothing could be written in it (%s)' % e
                log('writing the ticket into the thread failed:\n'
                    + traceback.format_exc())

        # A ticket nobody can see is the same as no ticket. If the thread could
        # not be made, or could not be written in, the whole application goes
        # into the tickets channel as an ordinary message instead. That channel
        # is already the one the panel lives in, so it is no more public than
        # the thread would have been, and it means an application is never lost
        # to one permission somebody forgot to tick. The reason rides along
        # with it, so whoever reads it can fix the cause without going to the
        # VPS for a log.
        fell_back = False
        if not posted and ch is not None:
            note = ''
            if why:
                note = '\n_No private thread for this one: %s._' % why
            try:
                await ch.send(('**%s**\n%s%s' % (title, head, note))[:1900])
                for chunk in _chunks(detail, 1900):
                    await ch.send(chunk)
                fell_back = True
            except Exception:
                log('the ticket could not be posted in #%s either:\n'
                    % ch.name + traceback.format_exc())

        # And whatever happened in Discord, the person gets told something
        # true. The old wording promised a message that nothing ever sent.
        if not posted and not fell_back:
            try:
                await who.send(
                    'Your ticket reached staff, but Discord would not let the '
                    'bot open a thread for it. Nothing is lost: it is in the '
                    'staff inbox. Somebody will get back to you.')
            except Exception as e:
                log('could not even DM %s about the failed ticket: %s' % (who, e))

        await push_async(self.kind, '%s: %s' % (self.label_text, who.display_name),
                         detail, str(who), who.id)

        if posted:
            await interaction.followup.send(
                'Opened %s. Everything else goes in there.' % opened.mention,
                ephemeral=True)
        elif fell_back:
            await interaction.followup.send(
                'Sent. A private thread would not open, so it has gone to staff '
                'in the channel instead. Somebody will answer you.',
                ephemeral=True)
        else:
            await interaction.followup.send(
                'Sent to staff. Discord would not let a thread open for it, so '
                'the answer will come by message rather than in here.',
                ephemeral=True)


def _chunks(s, n):
    while s:
        cut = s[:n]
        if len(s) > n:
            at = cut.rfind('\n')
            if at > n // 2:
                cut = s[:at]
        yield cut
        s = s[len(cut):].lstrip('\n')


def is_staff(who, ch):
    """Staff, or anybody the channel itself trusts with threads."""
    try:
        names = set(r.name.lower() for r in getattr(who, 'roles', []))
        if names & (set(STAFF) | set(CREATOR)):
            return True
    except Exception:
        pass
    try:
        return bool(ch.permissions_for(who).manage_threads)
    except Exception:
        return False


async def close_here(interaction, why=None):
    """
    Close the ticket this was used in.

    Archived and locked rather than deleted. A ticket is the record of what
    somebody was told and when, and the one time anybody goes looking for it
    is the argument afterwards, so nothing here removes anything. Locked means
    it takes a staff member to open it again, not a stray message.
    """
    ch = interaction.channel
    if not isinstance(ch, discord.Thread):
        await interaction.response.send_message(
            'This one only works inside a ticket.', ephemeral=True)
        return

    if not is_staff(interaction.user, ch):
        await interaction.response.send_message(
            'Staff close these. Say what you need in here and somebody will.',
            ephemeral=True)
        return

    line = 'Closed by %s.' % interaction.user.mention
    if why:
        line += ' ' + why.strip()
    line += ('\nNothing is deleted. Everybody who was in here can still read it, '
             'and staff can open it again.')
    await interaction.response.send_message(line[:1900])

    # Archiving drops a thread out of the sidebar and out of the channel's
    # active list, and a private one is then behind two clicks nobody finds. A
    # closed ticket nobody can find again is barely better than a lost one, so
    # a line is written down somewhere searchable with a link straight back to
    # it. Somewhere being the staff channel, not the one people apply in.
    try:
        book = await log_channel(interaction.guild)
        if book is not None:
            note = 'Closed: **%s**. By %s.' % (
                ch.name, interaction.user.display_name)
            if why:
                note += ' ' + why.strip()
            note += '\n' + ch.jump_url
            await book.send(note[:1900])
    except Exception:
        log('could not write the ticket down:\n' + traceback.format_exc())

    # Sent first, then archived. The other way round the message never lands,
    # because an archived thread will not take one.
    try:
        await ch.edit(archived=True, locked=True)
    except Exception:
        try:
            await ch.edit(archived=True)
        except Exception:
            log('could not archive the ticket thread:\n' + traceback.format_exc())


class TicketTools(discord.ui.View):
    """Sits on the ticket's first message. Persistent, so it still works after
       the bot restarts rather than going dead the moment anything updates."""
    def __init__(self):
        super().__init__(timeout=None)

    @discord.ui.button(label='Close ticket', style=discord.ButtonStyle.secondary,
                       custom_id='thornswood:close')
    async def close(self, interaction, button):
        await close_here(interaction)


@tree.command(name='close', description='Close this ticket. Staff only.')
@discord.app_commands.describe(why='Optional. What was decided.')
async def close_cmd(interaction: discord.Interaction,
                    why: typing.Optional[str] = None):
    await close_here(interaction, why)


class TicketPanel(discord.ui.View):
    def __init__(self):
        super().__init__(timeout=None)
        self.add_item(TicketPicker())


class TicketPicker(discord.ui.Select):
    def __init__(self):
        super().__init__(
            custom_id='thornswood:ticket',
            placeholder='What do you need?',
            options=[discord.SelectOption(label=lab, value=k, description=desc[:100])
                     for k, lab, desc in KINDS])

    async def callback(self, interaction):
        k = self.values[0]
        lab = dict((a, b) for a, b, _ in KINDS)[k]
        await interaction.response.send_modal(TicketModal(k, lab))


PANEL = ('**Open a ticket**\n\n'
         'Pick the one that fits. It asks a few questions, then opens a thread '
         'only you and staff can see. Nothing here is public and nobody else in '
         'the server can read it.\n\n'
         '**Apply to playtest** is the one everybody starts with, and it is how '
         'you get into the world. **Apply: Jarl** is '
         'answered in character: the seats are empty, and the first people to '
         'hold them are picked out of what is written there.\n\n'
         'The jobs below that are open to anybody already in, and they are jobs '
         'rather than titles: each one is work somebody is currently doing '
         'instead of you.\n\n'
         'Applying for one does not give you it. Somebody reads it and answers.')


async def ensure_panel(guild):
    ch = by_name(guild, TICKETS)
    if ch is None:
        names = ', '.join('#' + c.name for c in guild.text_channels) or 'none'
        log('there is no text channel called #%s in "%s", so there is no panel '
            'and no tickets. Text channels there: %s. Set TICKET_CHANNEL in '
            'bot.env.json to one of those and run Install-Bot.ps1 again.'
            % (TICKETS_SAID, guild.name, names))
        return

    # Said at startup rather than the first time somebody applies, because the
    # first time somebody applies is the worst moment to find out.
    # Slash commands are a permission of their own, and it is granted per
    # channel. The server owner bypasses every overwrite, so /close looked
    # fine to the one person who could never have been blocked by it while
    # staff saw nothing at all. Named here rather than left to be discovered.
    try:
        blocked = []
        for r in guild.roles:
            if r.name.lower() not in (set(STAFF) | set(CREATOR)):
                continue
            if not getattr(ch.permissions_for(r), 'use_application_commands', True):
                blocked.append(r.name)
        if blocked:
            log('%s cannot use /close in #%s: Use Application Commands is off '
                'for them there. Turn it on in that channel\'s permissions. The '
                'Close button on the ticket works for them either way.'
                % (', '.join(blocked), ch.name))
    except Exception:
        pass

    book = await log_channel(guild)
    if book is not None:
        log('closed tickets are written down in #%s' % book.name)

    why = thread_block(guild, ch)
    if why:
        log('tickets in "%s" will NOT get a private thread: %s. Tick it in '
            'that channel\'s permissions, or on the bot\'s role server wide. '
            'Until then every ticket goes into #%s as a plain message.'
            % (guild.name, why, ch.name))
    else:
        log('ticket threads look fine in #%s' % ch.name)

    try:
        async for m in ch.history(limit=30):
            if m.author.id == client.user.id and m.components:
                # The options a dropdown offers live in the message that was
                # posted, not in the View this process builds on startup. So
                # leaving the old message alone is exactly why a ticket kind
                # added later never appeared for anybody: the code had it, the
                # message did not. Editing in place keeps the same message and
                # its spot in the channel and puts the current list on it.
                await m.edit(content=PANEL, view=TicketPanel())
                log('ticket panel updated in #%s' % ch.name)
                return
        await ch.send(PANEL, view=TicketPanel())
        log('ticket panel posted in #%s' % ch.name)
    except Exception:
        log('panel failed:\n' + traceback.format_exc())


@client.event
async def on_ready():
    client.add_view(TicketPanel())          # so it keeps working after a restart
    client.add_view(TicketTools())          # and so does Close on every old ticket
    log('up as %s' % client.user)

    # A global sync can take an hour to reach everybody, and it reaches people
    # unevenly while it does, which looks exactly like one person's Discord
    # being broken. Copying the commands onto the server itself and syncing
    # that is immediate and the same for everyone in it.
    #
    # Registering both, which is what this did first, puts the command in the
    # picker twice: Discord lists the server copy and the global copy as two
    # separate entries and there is no way to tell them apart. So the guild
    # copy is the one kept, and the global list is emptied straight after.
    # Clearing globals is done last because copy_global_to reads that same
    # list, and clearing it first would copy nothing.
    for g in client.guilds:
        try:
            tree.copy_global_to(guild=g)
            await tree.sync(guild=g)
            log('/close is registered in "%s"' % g.name)
        except Exception:
            log('could not register /close in "%s", the Close button still '
                'works:\n' % g.name + traceback.format_exc())
    try:
        tree.clear_commands(guild=None)
        await tree.sync()
    except Exception:
        log('could not clear the global commands, so /close may appear twice '
            'in the picker:\n' + traceback.format_exc())

    for g in client.guilds:
        await ensure_panel(g)
    log('watching %d server(s)' % len(client.guilds))

    # Three separate things have to be true for a join card to appear, and
    # when one of them is not, the only symptom is silence. So check all three
    # at startup and say which one is wrong, by name.

    # One: Discord has to be sending joins at all.
    if not client.intents.members:
        log('member joins: OFF. No join cards will ever fire. Turn on Server '
            'Members Intent at discord.com/developers, Bot page, then restart.')
        return
    log('member joins: on')

    for g in client.guilds:
        # Two: the channel has to exist, and be a text channel.
        ch = by_name(g, [WELCOME])
        if ch is None:
            names = ', '.join('#' + c.name for c in g.text_channels) or 'none'
            log('there is no text channel called #%s in "%s", so join cards '
                'have nowhere to go. Text channels there: %s. Either make one '
                'with that name, or set JOIN_CHANNEL in bot.env.json on the '
                'VPS to one of those and run Install-Bot.ps1 again.'
                % (WELCOME, g.name, names))
            continue

        # Three: the bot has to be allowed to post, and to attach the card.
        p = ch.permissions_for(g.me)
        missing = [n for n, ok in (('View Channel', p.view_channel),
                                   ('Send Messages', p.send_messages),
                                   ('Attach Files', p.attach_files)) if not ok]
        if missing:
            log('cannot post in #%s in "%s": the bot is missing %s there. Fix '
                'it in that channel\'s permissions, or give the bot role those '
                'permissions server wide.' % (ch.name, g.name, ', '.join(missing)))
        else:
            log('join cards will go to #%s in "%s"' % (ch.name, g.name))


try:
    client.run(TOKEN)
except discord.PrivilegedIntentsRequired:
    log('Discord refused the connection because Server Members Intent is off.')
    log('Go to discord.com/developers, open the Thornswood application, Bot in')
    log('the left menu, switch on SERVER MEMBERS INTENT, save, then run')
    log('Install-Bot.ps1 again.')
    raise SystemExit(1)
except discord.LoginFailure:
    log('Discord rejected the bot token. Reset it on the Bot page and run')
    log('Install-Bot.ps1 again to paste the new one.')
    raise SystemExit(1)
