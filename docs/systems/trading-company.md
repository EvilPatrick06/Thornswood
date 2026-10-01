# Free Skyrim Trading Company

Skyrim's hauler, and a business. A haul is a job on a notice board
with a pay and a destination hold. The company is the tenth that
stays in the box when the haul is confirmed. It also makes, sells,
and buys.

It is not the East Empire Company. The Accord is grain, wine, paper
and worked goods coming in, and ore and timber going out, and the
company is how a crate gets from one hold to another for pay. The
lore of that agreement is on the site. This page is the coin.

Carriages and ferries move people. They are not the company. See
[Carriages and ferries](carriages.md).

## Posting a haul

At the board of the hold you are sending from:

`/haul 80 riften a crate of iron ingots`

The first number is the pay. The next word is the destination hold,
one of the ten towns. The rest is what the job says.

The server takes two sums before the job goes up:

- the job fee, 30 gold, or 15 if you are a member in good standing of
  this hold's guild
- the pay, in full, which is never halved

Both go onto this hold's ledger. If the pack cannot cover both,
nothing is taken and nothing is posted.

The job shows on the board as a job, with the pay and the destination
in the line.

## Taking it

`/take` at that board, the same as any job. One taker. `/dropjob`
hands it back.

On a drop or on the poster's `/unpin` before anybody has taken it, the
pay returns to the poster's pack and the ledger goes down by that
pay. The job fee stays. The company's tenth is not taken, because
nothing was delivered.

A steward of the posting hold can cancel an open or a taken haul the
same way: the pay returns, the fee stays. There is no clock. A haul
sits until a person confirms it or cancels it. The server does not
watch the road, and it does not look in the hauler's pack for the
crate.

## Confirming it

At the destination hold's board, the poster, that hold's steward, or
that hold's factor:

`/haul done whiterun 4`

The hold named is the one that posted it. The number is the job's
number on that board. You have to be standing at the destination the
job named. Saying it at the posting board does nothing.

On confirm, the company keeps a tenth of the pay, rounded down to a
whole gold. A pay under 10 gold keeps nothing, and the hauler receives
all of it. The rest is handed to the hauler as gold. The ledger drops
by what the hauler received. The tenth, and the job fee, stay.

| Pay posted | Company keeps | Hauler receives |
| --- | --- | --- |
| 9 | 0 | 9 |
| 10 | 1 | 9 |
| 25 | 2 | 23 |
| 80 | 8 | 72 |
| 100 | 10 | 90 |

A member posting an 80 gold haul pays 15 plus 80, which is 95, onto
the ledger. On delivery the hauler receives 72. The ledger keeps 23:
the 15 fee and the 8 tenth.

Somebody who is not a member pays 30 plus 80, which is 110. On
delivery the ledger keeps 38.

The gold the hauler receives was the poster's. Creating it back into
a pack and subtracting it from the ledger is the box paying out. It
is not a new mint. See [Gold](gold.md).

## Who runs it

An application, the same shape as a Jarl. It is asked for in Discord.
The people who are accepted run it as a business: they make, they
sell, and they buy. What they wear on the road while a crate is in
the pack is their own affair, in the world. It is not a server rule.

Nobody is handed a company ware before the first haul has moved.
The Riekling pieces that stay in the open book are company wares as
well as race locked. They are named on [Cut items](cut-items.md).

## Sales that leave the world

Sometimes there is an event where someone sells a thing out of
Skyrim. The thing leaves the game. That is the point: it is gone, and
it does not come back into a chest.

When the company buys, the worker who handled the sale takes 10% of
the price, rounded down to a whole gold. Another 10% leaves the
server. The seller receives what is left. A price under 10 gold pays
the seller the whole price, and neither cut is taken. See
[Gold](gold.md).

## What is not a haul

A sale across a counter in the same town is a trade. Rent is rent. A
notice is a notice. A carriage fare is a fare. None of those pay the
tenth, and none of them are posted with `/haul`.

## Where this is

Not built. The box exists, and the note beside it says company
payment belongs in that box. Jobs exist, and the server does not pay
the taker of an ordinary job. There is no `/haul`, no tenth, and no
withdrawal from the ledger. There is no application, no event that
deletes an item, and no gold destroyed for a sale.
