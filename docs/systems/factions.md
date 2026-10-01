# Factions and businesses

A book a group keeps together. It is a tab on J, beside the personal
journals on [Journals](journal.md). It is not a page in those
journals, and it does not count toward the 12.

It is not the [Free Skyrim Trading Company](trading-company.md) and
it is not a hold's [Merchant's Guild](merchants-guild.md). Those have
their own coin and their own rolls. This book is the group's prices,
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

## Founding one

Business Owner may found one business, and name it.

Faction Owner may found one faction, and name it.

An account that holds both may found one of each. A second of the
same kind is refused. Founding is on the account, so another
character on the same account does not get a second book. Any
character on that account can open the book as its owner.

On the tab, or typed the same way `/journal` matches J:

`/book new business The Bee`

`/book new faction The North Gate`

The rest of the line is the name. Staff can found one only when they
also hold the Discord role. They do not need the role to open a book
that already exists.

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
with Read and Speak. The owner changes that on the tab. Prices,
invites, and roles are the tab. They are a poor fit for a slash
command.

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

## The people

40 members, counting the owner. A 41st accept is refused.

Each row is the character, their role, whether they are in the world,
and the last time that character left the world. In the world, the
row says they are here. Away, it says when they left. A character who
has never left yet has no time on the row.

Online is the same fact a friend list already uses: they are in the
world right now. Last played is new. It is a time, not a place.

You invite the character in front of you, or by name the way
`/friend` does. The offer stands for 45 seconds. They accept. Until
they accept, they do not see the tab.

`/book invite` and the name. `/book leave` drops this character. If
this account is in more than one book, the group's name follows
leave.

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

Personal journals, J, and sharing a page with a friend are in the
server. This tab is not. There is no price list, no group role, and
no group chat.

The server already knows who is in the world, and a friend row
already uses that. It does not store the time a character last left.

Staff seats already read Owner, Gamemaster, Dev, Loremaster, and
Moderator off the Discord account. Business Owner and Faction Owner
are not roles that read looks for.
