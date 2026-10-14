# Notice boards

One board a town. You stand at it to post, to read the one in front of
you, and to take a job. Reading another town's board does not require
standing there: J has every one, under Boards.

## Where a board is

The object is the message board. One stands at every board, wherever
the server has it: indoors or out, in Skyrim or on Solstheim. It is
put down when you are in that board's cell, or its worldspace outdoors.
You are at it when you are within 400 of that board. Click the board:
E on the board itself opens it, and nothing else does. E on a person
beside it, or on anything else near it, is answered by that, not the
board (Patrick, 12 Oct, #2298: clicking the board does only the board).

The board is Thornswood's own, built from Skyrim's own pieces (#2298):
two Windhelm sign posts, a face of stockade planks between two log
rails, a gable of shingle boards, a candle lantern on a bracket, and
notices nailed to it. On a shelf on its right post sits the hold's drop
box. It is about 3.5 metres tall and 4.4 wide with the shelf.
`scripts/mods/Build-NoticeBoard.py` builds both meshes from the game's
own archives; only the meshes ship, never a texture.

A steward moves it. Standing where it should be, they press its town
under the notice boards on the Office page of the K panel, and press
again. A board a steward has walked to is saved, and a later seeding
does not put it back.

The nine mainland towns have a spot each: Solitude, Whiterun, Riften,
Windhelm, Markarth, Falkreath, Morthal, Dawnstar, Winterhold. Raven
Rock's board starts at that town's inn, The Retching Netch, where
Geldis Sadri stands, until a steward walks it somewhere better. Ten
boards, one per town in [Creation](creation.md).

## A notice and a job

Post a notice, on the board's panel, with the words. 20 gold. It is
read only. There is nothing to take.

Post a job, with the words. 30 gold. It can be taken.

Both fees are taken from the pack before the words go up. If the gold
is not there, nothing is posted. The fee is counted on that hold's
ledger. See [Gold](gold.md) and [Property](property.md).

The fees are the same for everybody. The [Merchant's Guild](merchants-guild.md)
is the NPC traders; people cannot join it for a discount.

A haul is a job with a pay and a destination. The posting fee is still
this fee. The pay is extra. See
[Free Skyrim Trading Company](trading-company.md).

A letter is a job with a named person at the other end. You post it
from the board's panel: Write a letter, with who it is for and the
words. The words are the letter, up to 300 characters, the same cap
as `/ooc`.

It costs 35 gold up front. 20 is the board fee and stays with the hold.
15 is the courier's pay, and it is held
the way a haul's pay is held. If the gold is not there, nothing is
posted.

The courier does not read it. The wall shows who it is for, not the
words. Take takes it the way it takes a job. One taker. Looking at
the named person, within the trade reach, about 10 metres, the
courier's look prompt shows E, Hand over the letter. E hands them the
words and pays the courier the 15. The row is there only while you
carry a letter for the person you are looking at. A wrong person is
refused. The server does not judge what the letter says. It checks
the name.

Put it back puts the letter back on the board. Take down, by the
sender, before it is delivered, returns the 15 and keeps the board fee. A
letter somebody has taken stays up until they hand it back or deliver
it. There is no cooldown. The sender's gold is the limit.

You post from the board. A notice sent from the other side of the
province is not a notice. A letter is the same: you write it standing
there.

## What the board shows

Clicking the board shows the one you are standing at. J shows any
town's, from anywhere: under Boards, pick the town. That one is read
only, and Your jobs is under it.

The newest 10 that are still up are the wall. Each keeps the number of
its real place in the list. A notice taken down leaves a gap in the
numbers rather than sliding the newer ones down.

Older ones stay in the book. They are not on the wall. The line under
the ten says how many are older. The buttons use the numbers on the
wall.

A job line says it is a job, and says who took it once somebody has.
A letter line says it is a letter, and names who it is for.

## Taking, handing back, taking down

Take, beside a job at the board, puts it on your list. A notice cannot
be taken. A job already taken cannot be taken again. Your jobs is your
list, every job you have taken in every town: on the board's panel,
and under Boards on J.

Put it back, at the board you took it from, hands it back, and it is
open on the board again. The server records who took it and when. It
does not decide whether an ordinary job was done, and it does not pay
the taker of one. What that job is worth, apart from a haul, is
between the two people. A letter is the exception: the server pays
the 15 when it is delivered to the named person, from gold the sender
already put up.

Take down is the poster's. The fee stays with the hold. A job
somebody has taken stays up until they hand it back.

A guard of the hold takes down any post on its board, taken or not
(#502). The fee stays with the hold. Gold the post was holding goes back
to whoever posted it: a letter's 15, a haul's pay. When they are away it
is held for them and handed over when they are back. Whoever had taken
it is told it is off their list. At another hold's board a guard is
anybody. See [Offices](offices.md).

## Where this is

The board is a panel. Stand at the message board and click it. Notices, jobs,
taking one, taking your own down, handing a job back, Your jobs with
Put it back on this board's, the line that counts the older ones, and
leaving a price list are on that panel. Walking away closes it. A
steward moves a board from the Office page of the K panel. See
[Offices](offices.md).

J has a Boards tab (#1627): the ten towns, the board of the one you
pick, read only, from anywhere, and Your jobs under it. The town that
is lit is the one the server is showing; after a restart none is.

Nothing on a board is typed (Patrick, 4 Oct: nothing people do is a
chat command). The panel and J send the server lines nobody is told to
type, and no help text names them.

Fees of 20 and 30, the reach of 400, the newest 10, the gaps, the
older count, Take, Put it back, Take down, Your jobs, and a steward
moving a board are in the server. The fee lands on the hold's ledger.
A steward moves one of the ten boards; any other name is refused.

Letters are in the server and on the panels (#1595): Write a letter
on the board's panel, the 35, the 300 characters, the sealed line on
the wall and the panels, Take, Put it back, the 15 back on Take
down, and Hand over the letter on the look prompt, which pays the
courier the 15 out of the ledger it was held on. The name on a letter
matches the whole of a character's name or its first words. The
prompt's row comes from the server's list of who is near you, which
marks a person you carry a letter for; the key sends the id the
crosshair gives, the same as Trade, and the server checks the name,
the reach and the place again. The key is E, Skyrim's own Activate,
wherever it is bound: which key was asked on #1595, and E is the
suggested answer, because every letter is already taken and U, the
other key on a person, is Let sleep here, which can be up at the same
time. Nothing is typed for a letter, and no help text names a line
for one.

Hauls are in the server, on the panel: Send a haul, the 30 fee and
the pay on the ledger, the pay and the destination on the wall, and
Confirm under Hauls that came here at the destination. A haul handed
back is not open again: it comes down, and its pay goes back to the
poster. A steward sees Take down on every haul. There is no command
for any of it. See [Free Skyrim Trading Company](trading-company.md).

Ten boards are seeded, and each one is that hold's drop box. Raven
Rock's is at The Retching Netch, where Geldis Sadri stands, and its
message board object goes down on that spot. Nobody has yet checked
in the game that it stands clear of him; a steward can walk it to a
better one (#1597). Pressing E on
a person or an NPC near a board answers them, not the board. Solitude's
spot was corrected from a walked coordinate and still wants somebody
to stand on it. There is no guild membership discount.
