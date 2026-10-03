# Merchant's Guild

The Merchant's Guild is the merchant NPCs of each hold. People cannot
join it. There is no membership roll, join fee, dues, factor appointment,
strike command or membership discount. Corrected by Patrick on 2 October
2026. Earlier requirements for those systems are withdrawn.

Each hold's traders use that hold's submitted price lists. A merchant
has no profession verb and no recipes. The NPCs remain under server
authority. Each hold has one guild site, recorded below. A later walk
can move a spot. Traders are not relocated by that record. Their current
numbers and placements are on [People who are not people](npcs.md).

A person's shop is a claim, as [Property](property.md) says. Anyone may
post at the board or trade with an NPC. Notice and job fees stay 20 and
30 gold for everybody. Two people still agree their own price when they
[trade](trade.md).

## What the traders charge

A guild trader buys and sells at the hold's price. The numbers come
from the price lists in faction and business books, submitted at
that hold's drop box. See
[Factions and businesses](factions.md) and [Property](property.md).

For each item, the buy price is the average of the buy prices
submitted to that hold. The sell price is the average of the sell
prices. A blank is not a number. 0 is free, and it counts. The
average is rounded to the nearest gold. A half rounds up.

A hold with no submitted buy for an item uses the average of the
holds that did submit one. The same for a sell price. A hold that
did submit its own price uses that price, so two holds can differ.

If no submitted list anywhere names a buy price, no trader buys it.
If none names a sell price, no trader sells it.

## The trader's purse

Each guild trader starts with 250 gold. It is once, when that trader
is first stood up. After that the purse
changes only when they buy and sell, the way a person's purse does.
They do not mint. They do not receive the starting 40. An empty
purse refuses a buy. An empty shelf refuses a sale.

They start with gold and no goods. Stock is what they have bought.
The quests they give are on [Custom quests](quests.md). A supply
quest pays out of this same purse. A scene quest does not. Its gold
is created, at the amount written on that quest, and it does not
run out. A letter is not a quest of theirs. The sender pays the
courier, on the notice board.

## Guild sites

One spot a hold, taken from the notice-board seeds. Raven Rock has no
seeded board coordinate. Its site is the town inn, at Geldis Sadri on
the trader list, which is where that town's board starts. A later walk
can move any of these. Traders are not relocated by this list.

| Hold | Book hold | Spot |
| --- | --- | --- |
| Haafingar | solitude | Solitude, the notice board |
| Whiterun | whiterun | Whiterun, the notice board |
| the Rift | riften | Riften, the notice board |
| Eastmarch | windhelm | Windhelm, the notice board |
| the Reach | markarth | Markarth, the notice board |
| Falkreath | falkreath | Falkreath, the notice board |
| Hjaalmarch | morthal | Morthal, the notice board |
| the Pale | dawnstar | Dawnstar, the notice board |
| Winterhold | winterhold | Winterhold, the notice board |
| Solstheim | ravenrock | Raven Rock, the town inn, at Geldis Sadri |

## Where this is

The hold's box is in the server, and the note beside it says guild
ledgers belong in that box. The box takes gold. A price list is not
an item in the chest. Someone with Prices stands at the box and
submits a copy, and the average of those copies is kept for that
hold. A marked chest also requires the same known cell and a current
distance of at most 400. Remembering a chest does not permit a remote
submission. A failed save keeps both the previous saved file and the
previous live prices. Failed book edits, disbands and membership saves
also restore the previous live state. Empty buy and sell columns keep
their positions; zero is a free offer. Prices must fit the server's
whole-gold inventory range, from 0 through 2,147,483,647.

An unreadable book, invalid permission relationship or submission without
its matching book prevents the book service from loading. A reload revokes
the old service before checking the saved state, including any retained
reference to that service. It does not start an empty ledger. Renaming a
book or editing its prices keeps its earlier submitted copy valid.

Posting is 20 and 30 for everybody. Rent is the only debt the box pays
down. The 249 retained, authored traders receive their one-time 250 balance
and empty stock when admitted by the Dev server controller. The authoritative
ledger is in the private folder, with atomic replacement, integrity checking
and a record of references not yet initialized. The per-NPC property mirrors
it. A lost NPC save restores the ledger balance, including zero, rather than
handing out 250 again. Missing or damaged ledger state refuses service.
The initial merchant total is 62,250 gold across those 249 references. The
server's minute report lists the verified count and first-time grants.
Failed startup revokes the new service; paths into served resources, including
Windows junctions, are refused before any ledger is written.

Buying and selling use the hold's submitted price. The trader's purse
falls when it buys and rises when it sells. Purchased goods stay on that
trader's shelf. An empty purse refuses a buy. An empty shelf refuses a
sale. A supply turn-in is five of an item at that same buy price, paid
from the same purse, and it will not be offered again for six hours.
Scene quests are not paid from the purse.

The person must be the authenticated character and within 400 of that
trader in the same place. Press E on the trader. /merchant and the
trader's id still opens the same panel. The panel only sends /merchant.
It does not move gold or goods. People cannot join, and there is no due
or discount.

Gold and goods move only through the native merchant transfer. Until
that transfer is present the server refuses the trade and leaves the
purse and the shelf as they were. A transfer that has started and is
not yet durable stays on the trader and is not paid twice.

Exact counts and places are in [Merchant trader counts](merchant-traders.md).
Pressing E on a trader opens the panel. The two CWGuardTemplates
quartermasters are priced: the Imperial one as Haafingar, the Stormcloak
one as Eastmarch. Their cell is not in a hold. The guild site for each
hold is below. A later walk can move a spot. Traders are not moved by it.
