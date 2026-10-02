# Property

A building is claimed at its door. The claim is whose it is. The deed is
the paper in a pack. Locks and keys are how the door behaves. Rent, when
a steward sets it, is what the hold is owed.

Shops, halls and palaces are buildings. Claiming one costs nothing. You
may hold more than one. A dispute about who should have it is the
court's, and the server does not pick a side.

## A claim

Stand at the door and open it, then say `/claim`. The door you opened is
the building. A door opened more than a minute ago does not count, so a
door you passed on the way across town is not the one you claim from a
field.

If nobody holds it, it is yours. If you already hold it, the server says
so. If somebody else holds it, it names them and stops. It does not take
the building off them.

The claim lapses 14 real days after the last time the holder opened one
of its doors. Living there keeps it. When it lapses, the register drops
the claim and the doors unlock. What is in the chests stays in the
chests.

A farm plot has its own claim, made in the field, and it lapses 14 real
days after the last work on it. The two clocks use the same 14 days. A
house and the ground it sits on are settled together by the people
involved. The server does not glue them into one record.

## The deed

Claiming hands you a deed there and then. Every building uses one book.
The name on that copy is the building: Deed to Breezehome is not Deed
to Honeyside.

`/deed` lists what you hold.

The register is the record that decides the holder. It lives with the
server, not in the pack. A deed can be stolen. A stolen deed does not
move the claim. A book somebody renamed by hand is not a deed, because
the server never issued it.

## Locks and keys

The holder says `/lock` and `/unlock` at the door. A lock reaches
everybody on the next moment the list changes. A door whose cell was
not loaded yet is caught within 4 seconds of it loading.

A key is a smith's work, at a forge, with `/key`. The holder's own door
needs no mold. Anybody else's door needs a mold cut at that door with
`/mold`. The key opens that building.

A key can be lifted, the same as any other thing in a pack. The server
does not change which key a door wants.

## Stewards and rent

A jarl names stewards. Only a steward can `/evict`, and only at the
door. Eviction ends the claim. It does not empty the house. It does not
take a key back, so a tenant who kept one can still walk in. That is a
person's problem, handled like a person.

Rent is optional. A steward at the door says `/rent 50` and the place
owes 50 gold every 7 real days, or `/rent -` and it owes nothing.
`/rent` with no amount says what is owed.

The server counts the debt. It does not take the gold out of a pack.
Rent is handed to a steward, or put in the hold's box. Gold put in the
box pays rent owed by that person first. What is left is the hold's.

## The hold's box

Each hold has one box, and it is that hold's notice board. The nine
mainland towns already have a spot each, the coordinates given for
the boards. You are at the box when you are within 400 of that spot.
A steward who moves the board moves the box with it. See
[Notice boards](noticeboards.md).

A price list is not dropped in as an item. Someone with the Prices
permission on a faction or business book stands at the board and
submits the list. The guild of that hold keeps the copy. The rules
are on [Factions and businesses](factions.md) and
[Merchant's Guild](merchants-guild.md).

A steward can still mark a container with `/box whiterun`. Only gold
goes in that chest. Anything else is handed back, still in the hand.
The board itself is enough to submit a list.

The number `/box` reports is a ledger of what has been paid in. Gold
dropped in the chest is also in the chest. A fee taken for a notice is
counted on the ledger and is not sitting in the chest. Nothing
withdraws from the ledger except the payouts named on
[Free Skyrim Trading Company](trading-company.md).

Notice fees, job fees, rent, Merchant's Guild payments and company
payment all use this box. There is no second treasury.
See [Notice boards](noticeboards.md), [Gold](gold.md),
[Merchant's Guild](merchants-guild.md).

## What a home is for

A bed you own, rent, or were allowed to use is the bed on
[Exhaustion](exhaustion.md): 80 rest an hour, and the logout fill.
A bedroll is the campfire rate, 35. Saying `/rest bed` in the street
is not a bed.

The holder sets who may sleep there, and what the night costs.
`/bed 20` at the building sets the gold for one night. `/bed -` means
a night is free for someone the holder has allowed. `/bed` with no
amount says the price. The gold is handed to the holder. It is not a
server price, and it is not the same in every house. An inn is this
rule. The person who holds the inn sets the night. Once that gold is
paid, the inn room is 50 rest an hour.

The fire in the hearth is a fire. It warms the way any fire does on
[Temperature and weather](temperature.md). A claim does not make it
hotter.

Chests and barrels in the building are storage. A claim does not add
slots. The server already owns containers. When a claim ends, the
containers stay as they are for the next holder.

An outhouse or a pot would be relief for the optional meter on
[The body](body.md). That meter is not built unless a vote after the
server is fully live says to add it. Until then the server does not
treat an outhouse or a pot as furniture.

## A shop

A shop is a claimed building and a notice on the hold's board. No rank
mints a vendor, and the guild does not own the counter. Prices are
what the two people agree when they trade. Coin moves as
[Gold](gold.md) says.

## What is not a house

Nails, hinges, a lock, and iron fittings are refused at the forge.
They are parts for building a house, and a house here is a place
already standing. The four recipes are in
[the refused list](lists/refused.md).

The Hearthfire building rows, 487 of them, stay out of
[Cut items](cut-items.md). They are not a public craft and they are
not company wares.

## Where this is

Claims, deeds, the 14 day lapse, locks, molds, keys, stewards,
eviction, rent, and the gold-only box are in the server. The register
is `private/property.json`.

`/rest bed` still believes the word. It does not look for a bed.
A holder cannot set a price for a night. `/bed` does not exist.
Outhouses and pots stay unknown until the vote on
[The body](body.md). The company payout that
withdraws from the ledger is not built. The four house parts are
already refused. The drop box is the notice board. Standing at the
board is standing at the box. A price list is not an item in the
chest. Someone with Prices stands there and submits a copy. The book
stays in the journal. The guild average of those copies is kept.
