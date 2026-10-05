# Trade

Two people, standing together, swapping what they are holding. It is
not a haul and it is not the Merchant's Guild. Those are
[Free Skyrim Trading Company](trading-company.md) and
[Merchant's Guild](merchants-guild.md). Gold does not buy a rank. See
[Gold](gold.md).

## How it starts

Look at them and press H, or press Trade beside them under Near you
on the P panel. A prompt appears on their screen with Accept and
Refuse, the same prompt a friend request uses. Nobody types a command
to offer or to answer. The offer stands for 45 seconds.

You have to be within about 10 metres. 700 units. A trade that
carries on across Skyrim is a post office, and it is refused.

One trade at a time. If either of you is already in one, the new one
does not start. Asking while you are in one brings its window back
up, in case it was closed.

## The panel

The window shows the names of what you are holding. A localized name
that the game stores as a string index is never shown as a number.
When there is no readable name, the editor id is spaced out, so
SteelSword reads as Steel Sword.

What you are holding is grouped. The groups are Gold, Weapons, Armor
and clothes, Ammunition, Potions and food, Ingredients, Books and
notes, Keys, Miscellaneous, Soul gems, Scrolls, Lights, and Other.
Chips along the top narrow the list to one group, and a find box
narrows it by name. The type is the same size as the rest of the K
panel, large enough to read at the distance the window sits.

Each line you are holding has a box for a count, and Add sends that
count. An empty box, or a count of zero, sends one. Add 1 is always
there. Add 5 appears when you have at least five, Add 10 when you
have at least ten, and All when you have more than one. A line you
have offered has the same box, Take for that count, Take 1 when the
count is more than one, and Take back for the whole line. Gold has
Set for the amount in the box, All for every coin you are holding,
and None.

## What goes on the table

The buttons on the panel put a thing up, with a count, and Set puts
up gold. You cannot put up more gold than you are holding. Each side
can put up 24 lines. A person uses the buttons; nobody types a
command for any of it.

Both press Agree. Any change to either pile clears both
confirmations. One side does not get to swap a sword for a worse one
after the other has already agreed.

Walk away, or Escape, ends it. Nothing has moved until both have
confirmed.

If nobody touches it for 3 minutes, it ends. The check is every 2
seconds.

A trade is a conversation. It is not saved. A restart does not
remember the piles.

## A sale out of Skyrim

Somebody the [Free Skyrim Trading Company](trading-company.md) has
taken on sees one more button, Buy for the company. Pressed, the
trade is the company buying: what the other person puts up leaves
Skyrim instead of crossing, and the gold the worker puts up is the
price. Both see the split before they agree. Pressing it again makes
it an ordinary trade. Either way both confirmations are cleared.

## Where this is

The offer, the prompt, the names, the groups, the buttons, the
distance, the two confirmations, the 24 lines, the 3 minutes, and
the gold check are in the server. H and Trade under Near you on P
offer it. Accept and Refuse on that prompt are what a person presses.
So are Agree, Walk away and Buy for the company. The key and the
buttons send the server the lines `/trade` and its verbs once were,
and nobody is told to type them.
