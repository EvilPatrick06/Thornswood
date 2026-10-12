# Factions and businesses

A book a group keeps together. It is a tab on J, beside the personal
journals on [Journals](journal.md). It is not a page in those
journals, and it does not count toward the 12.

It is not the [Free Skyrim Trading Company](trading-company.md) and
it is not a hold's [Merchant's Guild](merchants-guild.md). Those have
their own purposes. The Merchant's Guild is the NPC traders and cannot
be joined. This book is the group's prices,
its people, and a place to talk when they are not standing together.

The book is kept by the server for the group. It is not stored on one
character. It survives a restart, and it is still there when the
owner is away.

## Who can see the tab

The tab is not drawn at all unless one of these is true.

- The Discord account holds Business Owner, or Faction Owner.
- This character has been invited into a faction or a business, and
  has accepted.
- The Discord account is staff.

Staff are the roles the server already uses for a staff seat: Owner,
Gamemaster, Dev, Loremaster, Moderator.

Anyone else never sees the tab. There is no empty page and no locked
row.

## Named factions

Some factions have a lead seat: Imperial Embassy, Thalmor Remnant,
Dark Brotherhood, The Companions, and the Free Skyrim Trading
Company. The names live in `bot/factions.json`. Applying is
Apply: Faction Leader in Discord. A faction has one leader. No GM or staff member (Loremaster, Discord Moderator, or any other staff role) may hold an in-game RP role with faction leadership, such as a Jarl or a faction lead.

The Discord role Faction Owner is separate: it lets an account found
a faction book in the game. It is not granted by this application,
and this application does not make a new Discord role.

## Founding one

Business Owner may found one business, and name it.

Faction Owner may found one faction, and name it.

An account that holds both may found one of each. A second of the
same kind is refused. Founding is on the account, so another
character on the same account does not get a second book. Any
character on that account can open the book as its owner.

On the tab: type the name, then New business or New faction. A Dev
may found one business and one faction without holding Business
Owner or Faction Owner. Any other staff seat can found one only when
they also hold that Discord role. They do not need the role to open a
book that already exists.

## Roles

The founder is the owner inside the book. The owner makes the roles
and sets what each role may do. A member cannot take the owner's
permissions away.

| Permission | What it allows |
| --- | --- |
| Read | The price list, the people, and the chat |
| Prices | Add, change, and remove a price line |
| Invite | Invite someone, and remove someone who is not the owner |
| Roles | Make a role, rename it, and set its permissions |
| Speak | Write in the group's chat |

A person who just accepted is on a role called Member. Member starts
with Read and Speak. The owner changes that on the tab: each role is
a row, and each permission on it is a button that is lit while the
role holds it. New role and Rename role are beside them. Prices,
invites, and roles are the tab, and nothing in the book is typed into
the chat.

The owner can rename the book. The owner can disband it. A member
can leave.

Staff have every permission on every book, including a book they were
not invited to. Staff can rename, remove someone, disband, and hand
ownership to a character who is already a member. Removing someone
from the book does not take a Discord role off the account.

## The price list

Each line is a name they type, a buy price, and a sell price. A blank
buy means the group does not buy it. A blank sell means they do not
sell it. A price is a whole number of gold. 0 is free.

100 lines. A 101st is refused.

The list does not move gold and it does not move items. A sale is
still a [trade](trade.md), or coin handed over. The list is what they
posted, so a customer can read it when they have been invited, and so
the group can agree a price before anyone meets.

Someone with the Prices permission can submit the list at a hold's
drop box. The box is on [Property](property.md). The submission is a
copy. The book stays in the journal. A later submission from the
same book replaces the earlier one in that hold. The
[Merchant's Guild](merchants-guild.md) of that hold averages the
copies it has, and its traders buy and sell at that average. A book
can be submitted to more than one hold. Each hold keeps its own copy.

## The people

40 members, counting the owner. A 41st accept is refused.

Each row is the character, their role, whether they are in the world,
and the last time that character left the world. In the world, the
row says they are here. Away, it says when they left. A character who
has never left yet has no time on the row.

Online is the same fact a friend list already uses: they are in the
world right now. Last played is new. It is a time, not a place.

You invite the character in front of you, or by name. Open J while
looking at them, and the tab has Invite with their name on it. The
name field beside it is for someone in the world who is not in front
of you. The offer stands for 45 seconds. It comes up on their P
prompt, which names the book, with Accept and Refuse. Until they
accept, they do not see the tab.

Leave on the tab drops this character from that book.

A character may belong to more than one book. Founding is what the
Discord role caps, not membership.

## The chat

Each book has a text channel on the same tab. It is how the group
asks a question when they are not in the same place. It is out of
character. A line is drawn in brackets, the same way `/ooc` is, and
it does not happen in the world.

It does not float above a head. It does not use the local distances
on [Text chat](chat.md). Everyone in the group who is in the world
can read it, wherever they are standing. It is not voice.

The box on the tab is the only way in. A line typed into the world
chat never lands here.

A line longer than 300 characters is cut to 300. The last 50 lines
are kept, and they survive a restart, so a question is still there
when someone comes back.

Speak is the permission. Read is the permission for seeing them.
Staff can read and speak in every book's chat.

A personal text mute, on [Voice](voice.md), hides that person's lines
here too, for you only. A staff silence stops them writing here at
all, for everybody.

## Where this is

The tab, the price list, the group role, and the group chat are in
the server. Everything in the book is done on J: founding, the price
lines, the chat, inviting the person in front of you or by name,
setting a role's permissions, renaming a role, removing someone,
leaving, renaming and disbanding. The invite reads as one on the P
prompt (#1591). The panel sends the server a line for each button;
nobody is told to type it, and no help names it (#1630). The book is
kept for the group and survives a restart. The time a character last
left is kept too. J draws the tab only for
a Discord account that holds Business Owner or Faction Owner, for a
character who has accepted an invite, and for staff.

Someone with the Prices permission stands at that hold's notice
board, which is the drop box, and submits a copy of the list. The book stays in the journal. A later
submission from the same book replaces the earlier one in that hold.
Each hold keeps its own copy. The average of those copies is what
that hold's traders would charge. Traders do not yet buy and sell
from a purse the server tracks.

Staff seats read Owner, Gamemaster, Dev, Loremaster, and Moderator
off the Discord account. Business Owner and Faction Owner are read
the same way. A Dev may found one of each. Any other staff seat
founds only when the account also holds the matching role. Founding
one book of each kind is capped on the account.
