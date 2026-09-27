# How to join

## What you need

**Skyrim Special Edition** on Steam, on build **1.6.1170**. Steam moves the
game past that build on its own, so most copies are newer. The launcher has a
**Downgrade** button that asks Steam for the right build under your own
account. Nothing comes from anywhere but Steam.

**Anniversary Edition is not required** and never will be. If you own it,
nothing breaks. If you do not, nothing is missing.

**Vortex**, with a free Nexus Mods account. The mods come from a collection on
Nexus, and a collection is a Vortex thing: Mod Organizer cannot install it.

Thornswood leaves the Skyrim you already have alone. The launcher builds a
game folder of its own, `C:\Thornswood\Game`, out of your Steam copy and what
Vortex put into it. Most of it is hard links to your own files, which take no
extra space, and the few files other programs rewrite are real copies. Vortex keeps the mods in a profile of their own, so
switching back to your usual profile and running Purge Mods leaves your own
Skyrim the way it was.

## 1. Apply

**Thornswood is eighteen and over.** Applying is you stating that you are. The
[rules](/rules) say what that is about before they say anything else.

**Thornswood is in alpha.** Anyone can download and install it. The world stays
locked until you have applied in the Discord and been given the role, so
applying is the first thing to do.

Come into the Discord and open a ticket. Say who you are, roughly what you are
after, and whether you have played on a server like this before. A few lines is
plenty, it is not an essay and nobody is marking it.

We are taking people in small numbers on purpose. A bug found by four people is
a bug that gets fixed by the weekend. The same bug found by two hundred is a
bad week for everybody, and a first impression nobody comes back from.

If you are accepted, your Discord account is what lets you in. There is nothing
else to sign up for, no second password, and no form on this site.

If you are not accepted yet, you are not being turned away. Stay in the Discord
and you will be asked when there is room.

## 2. Take the installer

One file, from the [Downloads](/downloads) page. Download it and run it.

It is small because the mods are not in it. It fetches Thornswood's own content
while you watch, about half a gigabyte, and a connection that drops carries on
where it stopped rather than starting again. It puts in the launcher, the
script extender and Thornswood's own content, and nothing else.

## 3. Install the collection in Vortex

Not optional. Without it you have a launcher and no mods, and the server turns
you away when you press Play.

The link is on the [Downloads](/downloads) page and on the launcher's Add-ons
tab. Open it and Vortex takes it from there: it makes a profile for Thornswood,
downloads every mod from its own author, and deploys them. Give it time.

If the wrong profile is active in Vortex, the launcher says so before you press
Play.

## 4. Connect your Discord in the launcher

Open Thornswood from the desktop shortcut and press **Connect Discord** on the
main page. Your browser opens, you say yes, and it closes itself.

You never do this again.

## 5. Press Play

Not Skyrim. Not Steam. Not SKSE. Always the Thornswood shortcut.

The launcher checks for updates and takes any that are waiting, because
everybody has to be running the same files or nobody can connect. It also
compares every plugin with the server's copy, byte for byte. If one differs it
says so, and **Fix** downloads the server's copy of that plugin.

Then the game loads to its main menu and asks who you are today: one of your
characters, or a new one. Pick and press Play.

A new character arrives in a quiet hall and the race menu opens, and that is
where you make your face. When you are done, a panel opens on its own for the
three choices on the [Professions](/classes) page: your class, your
profession and the half of it you will make your own, and the town you wake
up in. Take them in any order; the last one sends you to your inn. You arrive
in the clothes you stand in and nothing else. The same panel is behind **K**
from then on, for your skill points.

There is no address to type and no password to remember.

---

## Voice

Voice runs in the launcher, not the game, so leave the launcher open while you
play. Push to talk. Whisper and yell change how far your voice carries in the
world.

## If it goes wrong

Check the [known issues](/known) first. A lot of what looks like a bug is a
limit of how a shared Skyrim works, and it is written down with the reason. The
[help](/help) page has the usual fixes.

If it is not there, say so in the Discord with what you were doing, what you
expected, and what happened instead, or use the [report](/report) page.

The launcher's own log is at `C:\Thornswood\Profile\launcher.log`. Crash logs,
if the game closed itself, are in `C:\Thornswood\Profile\MyGames\SKSE`,
because Thornswood keeps its own My Games folder. The launcher's Logs page
lists them and opens them. Drag either straight into the channel.
