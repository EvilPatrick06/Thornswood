# Offices

A title is not a profession and not a class. Jarl, steward, housecarl,
thane, captain, priest of a named temple, Ambassador, Archmage of the
College.

Most of them are empty. How one comes free is something you find out
in the world, not on a panel.

## Claiming one, and taking one

An empty title can be claimed within reason. Captain of a guard nobody
else has claimed. Priest of a temple with nobody in it.

High King is not claimed that way. A hold that already has a Jarl is
not claimed that way. Those are taken, in the world, with the person
who holds them in it. Announcing yourself Jarl of Riften while the
Jarl of Riften is asleep is not taking the chair.

Rules on death and on permanent harm still apply while you take it.
See [Death](death.md).

## What the server already treats as an office

Every office the server knows is a Discord role on the account (Patrick,
15 October, #2551), and the role is the one truth for who may hold it. The
office itself is one character's (Patrick, 16 October: "it's character
based not account based"): the server keeps which one character on the
account holds each office, and only that character acts in it. Every other
character on the account is ordinary.

- The Jarl names a character on the Office page, and the role is set on
  that character's account; that character holds the office.
- A role given anywhere else (the bot's office panel, or staff for a
  Jarl) names only an account. Each of its characters sees the office on
  the Office page of K, and the one that presses Hold it here holds it.
  Pressing it on another character moves the office there.
- Without the role there is no office: a role taken away in Discord ends
  the office at once, and the record of which character held it is
  deleted the next time the game reads the roles, so a role given back
  later is held again only when somebody chooses the character.

- **The Jarl** of a hold holds its "Jarl of <Hold>" role, which staff
  give. Nobody takes the office or picks a hold in the game. A hold has
  one Jarl: if two accounts hold the same hold's Jarl role, neither acts
  as Jarl until staff take it from all but one, and staff are told which
  accounts, in the staff channel.
- **The Court** of a hold is everybody holding its "<Hold> Court" role.
  They are officers at that hold's drop box.
- **The Steward** of a hold holds its "Steward of <Hold>" role. A steward
  is the only one who evicts, sets rent and names a hold's box, and moves
  their own hold's notice board, and the Jarl of a hold keeps it as its
  steward too.
- **The Guards** of a hold hold its "Guard of <Hold>" role (below).

The Jarl of a hold gives and takes its Court, Steward and Guard roles, for
their own hold only, two ways: in Discord, from the office panel in
#choose-your-hold, with Add and Remove beside each office, and in the
game, with Name and Remove on the Office page of the K panel. In the game
the server asks the site, and the bot's account sets the role in Discord.
Every change is said in the staff channel with who changed what, and
Discord's audit log keeps it with the reason. Staff hold no office by
being staff. All of it is buttons, and nothing is typed. See
[Property](property.md) and [Notice boards](noticeboards.md).

The roles are made for the nine holds of Skyrim and for Raven Rock
(Patrick, 16 October): "Jarl of Raven Rock", "Raven Rock Court", "Steward
of Raven Rock" and "Guard of Raven Rock". Raven Rock has no Citizen role
or hold channel. Its board, its drop box and its jail answer to them like
any hold's.

The [Merchant's Guild](merchants-guild.md) is the merchant NPCs.
It has no joinable roll or factor appointment for people.

A steward is not staff. Staff are the Discord roles named on
[Voice](voice.md): Owner, Gamemaster, Dev, Loremaster, Moderator.
A steward does not grant a quest. Guild traders do. See
[Custom quests](quests.md). The rare mine is one of those quests,
and the seam is on [Miner](classes/miner.md).

## Guards

A guard is a person in a guard's office, of one hold. There are no NPC
guards (Patrick, 11 October, #502). A guard of a hold has the cells of
that hold's jail, and no other hold's: in their own game every cell
there is open to them, and at a cell door the lock key locks or unlocks
that cell for everybody else. A cell a guard has locked opens for that
hold's guards only; anybody else has to pick the lock. A cell no guard
has turned is as the game ships it.

Each hold's jail is read from the world: Dragonsreach Dungeon, Castle
Dour Dungeon, Riften Jail, Windhelm Barracks, Cidhna Mine, Falkreath
Jail, Morthal Jail, Dawnstar Jail, The Chill and The Bulwark Jail.
Claiming the jail building does not touch its cells.

The rest of the jail, as Patrick decided on 12 October (#502):

- Only the Jarl of a hold claims its jail building. Nobody else is
  offered the claim at its door, and its deed presented by anybody else
  claims nothing. A claim made on a jail before this rule, by anybody
  but that hold's Jarl, ended once at the first server start with the
  rule, and the server log names each.
- There is no timer. Whoever is locked in stays until a guard of that
  hold unlocks the cell, or until they pick the lock, which is allowed.
- The game's own jail keys open nothing: the world does not hand one
  out, so none lies on a table and none comes out of a chest.
- `/stuck` does not move anybody out of a jail while a guard has a cell
  there locked, apart from that hold's guards. It says so, and `/helpme`
  still reaches staff.
- Dying in a cell wakes you out of the jail, where dying anywhere in
  that hold wakes you: its temple, or for Morthal, Dawnstar, Winterhold
  and Falkreath, which have none of their own, the nearest temple or
  hall of the dead ([Death](death.md)).

A guard of a hold also takes down any post on that hold's notice board,
and on no other hold's board, and so does that hold's Jarl. A guard is an
officer at that hold's drop box. See [Notice boards](noticeboards.md).

A guard holds the hold's "Guard of <Hold>" role, which its Jarl gives
and takes (Patrick, 15 October, #2551), from the office panel in Discord
or with Name and Remove on the Office page of K. A Jarl names and removes
only their own hold's guards, themselves included.

A guard of a hold also binds people in that hold, below.

## Binding

Patrick, 16 October (#2573): a guard binds somebody, and they stay bound
until a guard of the hold frees them; and only a guard puts the
Prisoner's Cuffs on somebody. Both are the Guard role's.

- **Who binds.** A guard of a hold, looking at somebody standing next to
  them (about 4 metres, the same room or the same stretch of road) in a
  place that hold answers for. The line under the crosshair names the
  bind key, 0 unless it was moved on the launcher's Controls page, as
  "Bind their hands". Nobody else binds anybody, staff included, and
  nobody is bound in a place no hold answers for. A bound person binds
  nobody.
- **Who frees.** A guard of the hold the bound person is standing in
  now, with the same key ("Free their hands"). The hold that bound them
  does not matter: somebody bound in Whiterun and walked to Riften is
  freed by Riften's guards. Staff free anybody, with the same key or
  with `/unbind <person>`. Somewhere no hold answers for, only staff free
  them.
- **What bound is.** They cannot draw a weapon, swing, block, cast or
  shout, and a weapon already out is put away. They can walk, talk, open
  doors and pick a lock, and their speed is cut to about a walk, sprint
  included. Everybody looking at them sees "bound" beside their name.
- **The cuffs.** A guard carrying a pair of Prisoner's Cuffs puts them on
  with the binding: the pair goes from the guard's pack into theirs and
  onto their wrists, and they cannot take it off while bound. Freed, the
  cuffs come off and stay in their pack. A guard with no pair binds the
  same way, with nothing on the wrists. Wearing a pair yourself does
  nothing.
- **It lasts.** There is no timer. Logging out, a restart or dying does
  not end it; the character is still bound when they come back.
- **Staff hear of it.** Each binding and freeing is said in the staff
  channel, with who, whom and where.

What the server can and cannot hold. The engine decides a blow, a spell
and a step in the bound person's own game and tells the server after, so
the server cannot refuse one (measured, and written over `mp.onTakeItem`
in `game/gamemode.js`). Being bound is the engine's own controls,
switched in their game once when they are bound and once when they are
freed: fighting off, and the speed the server sends. The game has no
switch for sprinting that the server can send, which is why the speed is
cut instead. A blow or a spell from somebody bound, which their game
should not have let go, is said in the staff channel, once a minute a
person. Being led or carried is not built: Skyrim has no way to move
somebody else's character that the server can send, so a guard walks
beside a prisoner, or staff use `/bring`.

## Ambassador

One, for the embassy in Solitude. Keeps the roll of 20, of whom 6 may
be armed. Does not evict the Accord and is not evicted by Haafingar's
steward. See [The Imperial Embassy](embassy.md).

Not in the server. The word is not a command yet. Until it is, an
admin writes the roll with `/embassy`.

## Archmage of the College

The person who holds the College, not the master perk named Archmage.
A master mage does not receive this title with the rank. Study in the
halls does not require it. Holding the doors does. See
[Magic and the College](magic.md).

Not in the server as a title. The perk is the profession, and it is
the third school plus the right to teach.

## What a hold sets

A hold sets its own titles beyond jarl and steward, what each of those
titles may do, how many people hold one, and what they are paid. The
pay is gold that already exists. A hold does not mint it.

Housecarl, thane, captain, priest, and a guard are that list. The
server does not set their number or their pay, and it sets no powers
for any of them but a guard's, above. A guard is not a bounty and is not
staff.

Jarl and steward stay the offices the server already runs. A hold does
not turn eviction, rent, the box or the board off.

## What an office does not do

It does not grant a recipe, a spell, a class verb, or a rank. It does
not mint coin. A Jarl who wants gold takes it from the hold's drop box,
which holds the fares and what people put in, or from somebody under the
theft rule. The fees are the hold's ledger, a record only: only the
payouts on the trading company page leave it. See
[Notice boards](noticeboards.md), the drop box.

## Where this is

The Jarl, the Court, the Steward and the Guards are in the server,
including eviction, rent, the box, the board and the jail. Each is a
Discord role (`bot\Build-Discord.py` makes them, never hoisted, and never
deletes them), which the site reads with the other roles and hands the
game server for each profile (`/api/allowed`); the game reads every
office through one function, `officeOf` in the property block. They are
the Office page of the K panel, which only somebody who holds an office
sees. The Jarl of a hold sees its Court, its Steward and its Guards:
who holds each, by the character that holds it (named when in the world,
and by profile with its name when not), or an account none of whose
characters holds it yet, with Remove, which asks twice, and the people in
the world who do not hold it, with Name. Naming another character of an
account that already holds the role moves the office there, and Discord
is not asked. Anybody whose account holds a role that this character does
not hold sees it with Hold it here, which asks twice. A row shows the profile beside the name, so two
characters with one name are told apart. Name and Remove send the change
to the site (`/api/office`), which checks the Jarl's role again and sets
the role in Discord with the bot's token; the game reads the roles back
at once and writes the page again. In Discord the same Jarl has the office
panel in #choose-your-hold (`bot\bot.py`). A steward sees the door they
opened in the last minute, who holds it and the rent owed there, with
Evict, Set rent and No rent; the container they opened in the last
minute, with the ten holds to make it that hold's box; and their own
hold's board, moved to where the steward stands. Evict and moving a
board ask for a second press. The Court, a Steward and a guard each see
which hold they serve and what it lets them do, and a guard which jail
they keep. A Jarl whose role another account holds too sees that they
do not act, and why. The server checks every press again and answers in
the chat. Housecarl, thane, captain, and priest are the public rules and
no command. A guard's cells are in the server (#502): the cells guards
turned are `private\law.json`, and the jails are `game\data\jails.json`,
read out of the load order by `scripts\dev\Build-JailTable.py`.
Ambassador and Archmage of the College are this plan and no command.
