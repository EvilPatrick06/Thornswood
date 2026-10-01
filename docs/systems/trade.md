# Trade

Two people, standing together, swapping what they are holding. It is
not a haul and it is not the Merchant's Guild. Those are
[Free Skyrim Trading Company](trading-company.md) and
[Merchant's Guild](merchants-guild.md). Gold does not buy a rank. See
[Gold](gold.md).

## How it starts

Look at them and press H, or `/trade` and their name. A prompt
appears on their screen with Accept and Refuse, the same prompt a
friend request uses. They do not type a command to answer. The offer
stands for 45 seconds.

You have to be within about 10 metres. 700 units. A trade that
carries on across Skyrim is a post office, and it is refused.

One trade at a time. If either of you is already in one, the new one
does not start.

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

Each line you are holding has Add 1. Add 5 appears when you have at
least five, Add 10 when you have at least ten, and All when you have
more than one. A line you have offered has Take 1 when the count is
more than one, and Take back for the whole line. Gold has Set for the
amount in the box, All for every coin you are holding, and None.

## What goes on the table

`/trade add` and the thing, and a count if it is more than one.
`/trade gold` and the amount. You cannot put up more gold than you
are holding. Each side can put up 24 lines. The buttons on the panel
send those same words. A person uses the buttons.

Both confirm with `/trade ok`. Any change to either pile clears both
confirmations. One side does not get to swap a sword for a worse one
after the other has already agreed.

`/trade cancel` ends it. Nothing has moved until both have confirmed.

If nobody touches it for 3 minutes, it ends. The check is every 2
seconds.

A trade is a conversation. It is not saved. A restart does not
remember the piles.

## Where this is

The offer, the prompt, the names, the groups, the buttons, the
distance, the two confirmations, the 24 lines, the 3 minutes, and
the gold check are in the server. Accept and Refuse on that prompt
are what a person presses.
