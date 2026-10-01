# Text chat

What you type. Enter opens the box. A line that starts with `/` is a
command. A line that does not is speech.

Speech is local. Two people on the Whiterun road are not read by a
smith in Markarth.

Same cell first. Two people at the same coordinates in different
cells are not in earshot. The distances are in the same units as
`/ooc`, which is 4000 units, about 57 metres.

| How you say it | Who hears it |
| --- | --- |
| A plain line | About 57 metres, same cell |
| `/me` and what the character does | The same |
| `/do` and what there is to see | The same |
| `/w` or `/whisper` | A quarter of that, about 14 metres |
| `/s`, `/shout`, `/y`, or `/yell` | Three times that, about 171 metres |

`/me draws a sword` is an attempt. Whether it lands is the other
person's. A plain line cannot say that.

## Out of character

`/ooc` or `/o`, and the words. The same 57 metres and the same cell.
The line is drawn in brackets, so a scene can see that it stepped
out. It is how a scene asks for the yes on [Death](death.md).
`/ooc can we not` ends the scene. It does not undo what already
happened.

A line longer than 300 characters is cut to 300. If nobody is near
enough, you are told.

## Above the head

A line that is speech also sits above the head, for the people close
enough to read it.

What floats:

- A line that does not start with `/`.
- `/me`, and what the character does.
- `/ooc` and `/o`.

What does not float: every other command. `/do`, `/w`, `/whisper`,
`/s`, `/shout`, `/yell`, `/y`, `/trade`, `/party`, and the rest stay
in the box.

The float uses the same reach as the table above. A plain line, a
`/me`, and an `/ooc` float for people in the same cell and inside
about 57 metres. A `/do` does not float, even for the people inside
that distance.

One line at a time. A newer line replaces it. It stays for 6 seconds.
The float is cut at 80 characters. The full line stays in the box,
and an `/ooc` in the box is still cut at 300.

The float has the same shape as the box. A plain line is the words.
A `/me` is the action. An `/ooc` is in brackets.

You see your own float. Someone who has turned off your text does not
see it, in the box or above the head. That switch is on
[Voice](voice.md). The speaking mark on that page is the microphone.
It is not this text.

## Where this is

`/ooc` is local, 4000 units, same cell, in the server.

Plain speech is not. The switch that would make it local ships off,
so today a plain line goes to everybody who has the game open.
`/me`, `/do`, `/w`, and `/s` are only caught while that switch is on.
While it is off they go to the game server like any other slash.

Nothing floats above a head. There is no 6 second line and no 80
character cut above a head. When the float is built, it uses the 57
metres in the table. It does not follow the worldwide box.
