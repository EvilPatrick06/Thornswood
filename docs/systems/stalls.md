# Market stalls

A stall in a town's market is somewhere to sell from. It is claimed the
way a building is, it costs nothing, and its keeper names every price.
It sells only while its keeper is standing at it. Patrick, 22 Oct 2026
(#3160): "fixed market stalls, claimed like property", and on whether a
stall sells while its keeper is away, "No this is an RP server".

It is not a shop. A shop is a claimed building and a notice on the
hold's board ([Property](property.md), A shop). It is not the
Merchant's Guild either, whose traders are the hold's
([Merchant's Guild](merchants-guild.md)). And it is not a trade window:
a [Trade](trade.md) is two people agreeing on one swap, and a stall is
a counter of goods with prices on them while its keeper tends it.

## Where the stalls are

The stalls are the ones already standing in the towns' markets. Nobody
puts up a new one and nobody moves one. Which stalls there are is read
out of the game's own records, the same way the woodworking benches and
the stations are placed ([Where the stations stand](station-placement.md)).

Stand at a stall's counter and a line names the lock key, X unless you
changed it: Market stall. Press it and the stall's panel opens. Nothing
is typed. Walk away and the panel closes.

## Claiming one

A stall nobody keeps offers Claim this stall. Pressing it makes it
yours. It costs nothing, and you may keep more than one, the way you
may hold more than one building.

Nobody else can claim a stall while it is kept. A dispute about who
should have it is the court's, as it is for a building.

The keeping lapses 14 real days after the last time its keeper opened
its panel. Tending it keeps it. A keeper can also let it go, with Let
the stall go.

## Laying out goods

The keeper's panel lists what they carry. Pick a piece, say how many,
name a price and press Lay it out. The pieces leave the pack and are on
the stall. Gold is never laid out; gold is a price. Worn pieces are not
offered.

A price is for one piece, and it is either:

- a number of gold; or
- a number of something else, such as 2 Iron Ingot.

To ask for goods, type part of its name in Find, and what it finds
joins the list beside every price. Gold is never on that list.

An item has no gold price of its own ([Gold](gold.md)). The panel never
suggests one: every price on a stall is its keeper's.

A stall holds 24 lines, like a trade. The same piece laid out again at
the same price joins its line; a piece that differs, a key to another
house or a sword with a different temper, is a line of its own, and it
crosses to the buyer as it is.

The keeper changes a line's price with Set price and takes goods back
into the pack with Take back.

## Buying

Anybody else at the stall sees its wares, each with its price, and
whether the keeper is here. The keeper is never named on the panel:
whoever is standing at the stall is who sells there.

Buy takes the price out of the buyer's pack, gold or the goods named,
and puts the piece in it. The price goes into the keeper's pack, because
the keeper is standing there, and they are told in their chat what
sold.

A stall sells only while its keeper is at it, in the world, as the
character who claimed it. With the keeper away, Buy is greyed, the panel
says why, and the server refuses a sale that arrives anyway. Nothing
moves.

## When a keeping ends

A keeping ends when it lapses, when its keeper lets it go, when a
steward or staff end it, or when the keeper's character is deleted.
The stall is free at once.

What was on it goes into the hold's drop box on the notice board
([Notice boards](noticeboards.md), The drop box), for its keeper, who
takes it back there like anything they put in themselves. When the
keeper's character was deleted, it goes in with no name on it, for the
hold's officers to hand out, the way the box keeps the coin of a deleted
character.

## Stewards and staff

A steward of the stall's hold (its Steward or its Jarl, by the Discord
role) has End this claim on the stall's panel. So do staff, at any
stall, and each such press is one line in the staff log as an eviction,
naming the stall, the way a staff eviction at a door is
([Property](property.md), Stewards and rent). A stall has no rent.

## Where this is

The book of stalls is `game/market-stalls.js`: who keeps each stall,
what is on it, at what price, and the words the panel sends. The
gamemode carries it, bundled by
`scripts/dev/Build-MarketStallsGamemode.js`, and the market stalls
block in `game/gamemode.js` is the world's side of it: the packs and
purses a sale moves, who stands where, the panel, and the drop box. The
register is `private/market-stalls.json`. The panel is
`game/ui/thornswood-stall.js`, and the lock key's line at a stall is in
`game/plugins/thornswood-front.js` (`stallNow`). The lines the panel
sends are in [Chat commands](commands.md), and no help names them.

The order of every move is written so a failure never makes a piece or
a coin: what is laid out leaves the pack before the book is written,
what leaves the stall leaves the book before it reaches a pack, and a
write that fails puts it back. What goes to a drop box carries a
receipt the box keeps, so it never goes in twice.

`tests/test-3160-market-stalls.js` drives every rule above through the
real property and market stalls blocks.

Which stalls there are is `game/data/market-stalls.json`, one row a
stall with the point in front of its counter and how near counts as at
the stall. The table is empty until it is read out of the game's
records, so until then no stall opens.
