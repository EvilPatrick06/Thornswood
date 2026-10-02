# Merchant's Guild

The Merchant's Guild is the merchant NPCs of each hold. People cannot
join it. There is no membership roll, join fee, dues, factor appointment,
strike command or membership discount. Corrected by Patrick on 2 October
2026. Earlier requirements for those systems are withdrawn.

Each hold's traders use that hold's submitted price lists. A merchant
has no profession verb and no recipes. The NPCs remain under server
authority and may wander their own hold until their exact guild sites
are chosen. Their current numbers and placements are on
[People who are not people](npcs.md).

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
down. Traders do not yet buy and sell from a purse the server tracks.
NPC purses, stock and custom quests remain the work to finish.
