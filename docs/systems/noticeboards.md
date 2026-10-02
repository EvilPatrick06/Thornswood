# Notice boards

One board a town. You stand at it to post, to read the one in front of
you, and to take a job. Reading another hold's board by name does not
require standing there.

## Where a board is

A board is a place: a cell and a point. It is not a placed record, so
nothing has to be packed to every client to move one.

You are at it when you are within 400 of that point.

A steward moves it. `/board move whiterun`, standing where it should
be. `/board here` moves the one you are already at. A board a steward
has walked to is saved, and a later seeding does not put it back.

The nine mainland towns have a spot each: Solitude, Whiterun, Riften,
Windhelm, Markarth, Falkreath, Morthal, Dawnstar, Winterhold. Raven
Rock's board starts at that town's inn until a steward walks it
somewhere better. Ten boards, one per town in
[Creation](creation.md).

## A notice and a job

`/notice` followed by the words. 20 gold. It is read only. There is
nothing to take.

`/job` followed by the words. 30 gold. It can be taken.

Both fees are taken from the pack before the words go up. If the gold
is not there, nothing is posted. The fee is counted on that hold's
ledger. See [Gold](gold.md) and [Property](property.md).

A member of that hold's guild in good standing pays half: 10 and 15.
See [Merchant's Guild](merchants-guild.md).

A haul is a job with a pay and a destination. The posting fee is still
this fee. The pay is extra. See
[Free Skyrim Trading Company](trading-company.md).

A letter is a job with a named person at the other end. You post it
from the board. `/letter <name> <words>`. The words are the letter,
up to 300 characters, the same cap as `/ooc`.

It costs 35 gold up front, or 25 if you are a member of that hold's
guild in good standing. 20 of that is the board fee, 10 for a member,
and it stays with the hold. 15 is the courier's pay, and it is held
the way a haul's pay is held. If the gold is not there, nothing is
posted.

The courier does not read it. The wall shows who it is for, not the
words. `/take` takes it the way it takes a job. One taker. `/deliver`,
within the trade reach, about 10 metres, while you are looking at
the named person, hands them the words and pays the courier the 15.
A wrong person is refused. The server does not judge what the letter
says. It checks the name.

`/dropjob` puts the letter back on the board. `/unpin`, by the sender,
before it is delivered, returns the 15 and keeps the board fee. A
letter somebody has taken stays up until they hand it back or deliver
it. There is no cooldown. The sender's gold is the limit.

You post from the board. A notice sent from the other side of the
province is not a notice. A letter is the same: you write it standing
there.

## What the board shows

`/board` shows the one you are standing at. `/board riften` shows
Riften's, from anywhere.

The newest 10 that are still up are the wall. Each keeps the number of
its real place in the list. A notice taken down leaves a gap in the
numbers rather than sliding the newer ones down.

Older ones stay in the book. They are not on the wall. The line under
the ten says how many are older. `/take` uses the numbers printed.

A job line says it is a job, and says who took it once somebody has.
A letter line says it is a letter, and names who it is for.

## Taking, handing back, taking down

`/take 4`, at the board, takes job 4 onto your list. A notice cannot
be taken. A job already taken cannot be taken again. `/jobs` is your
list.

`/dropjob` hands it back, and it is open on the board again. The
server records who took it and when. It does not decide whether an
ordinary job was done, and it does not pay the taker of one. What
that job is worth, apart from a haul, is between the two people. A
letter is the exception: the server pays the 15 when it is delivered
to the named person, from gold the sender already put up.

`/unpin 4` is the poster's. The fee stays with the hold. A job
somebody has taken stays up until they hand it back.

## Where this is

Fees of 20 and 30, the reach of 400, the newest 10, the gaps, `/unpin`,
`/take`, `/dropjob`, and steward `/board move` and `/board here` are
in the server. The fee lands on the hold's ledger. Letters are not.
`/letter` and `/deliver` do not exist. A courier is not paid.

Nine boards are seeded, and each one is that hold's drop box.
Raven Rock is not among them. Solitude's spot
was corrected from a walked coordinate and still wants somebody to
stand on it. Half fees for the guild are not in the posting fee.
