# Thornswood

A Skyrim roleplay server set fifty years after the civil war. One install,
and it does not touch the Skyrim you already have.

## Download

https://thornswood.net/downloads

## You need

- Skyrim Special Edition on Steam, on this PC
- 25 GB free
- Steam signed in and running

## Install

Run **Thornswood-Setup.exe**, with the zip sitting next to it. Windows says
"Windows protected your PC" because it isn't signed → **More info** → **Run
anyway**. Press Install and leave it alone.

It shows you which zip it found before you press anything, so if it says the zip
is missing, the two files aren't in the same folder yet.

It copies the base game out of your Steam folder into `C:\Thornswood` and
sets that copy up with the whole mod list already installed. **No Nexus
account, no Vortex, no Nemesis, no mods to install.**

Your Steam copy is only read from. Nothing there is renamed, patched or
deleted, so whatever else you play with it keeps working.

### If it asks for depot commands

Our server runs game build **1.6.1170** and Steam ships something newer. If
yours is newer, the installer shows three `download_depot` commands and puts
them on your clipboard. Paste them into the Steam console **one at a time** and
wait for each to print `Done`. There's no progress bar. Then press Enter in
the installer.

That's Steam giving you an older build of a game you already own. It downloads
into Steam's own folder and doesn't change your installed game.

## Playing

Desktop shortcut: **Thornswood**.

**First time only:**
1. New character, **named after yourself**. That's what everyone sees above
   your head, and changing it means a new character.
2. **Save once** before connecting.

Then press Play and connect to the address in the launcher. Password is in
Discord.

`F2`: party, who's online, teleport to someone, chat.

## Different from normal Skyrim

| | |
| --- | --- |
| Sleeping and waiting | Do nothing. Time is shared across the server. |
| Menus | Don't pause. Don't sort your bags mid fight. |
| Food, water, warmth | You need all three. Cold is worst at night and up north. |
| Quests | Party up first, one person leads. |
| Steam's Verify Integrity | Never. It drags your Steam copy to the current version. |

## Adding your own mods

**Textures, meshes, sounds: fine.** Launcher → Mods → *Your own*, drop them in
that folder and they get copied in every launch.

**Anything with a plugin: no.** The launcher checks your list before it lets
you play and will stop you, because a mismatched list desyncs the whole server.

## Updates

The launcher checks on startup and you get only the files that changed, not the
whole thing again. Take them when it offers. Mismatched lists can't play
together.

## Something's wrong

The launcher's Play page has five checks. Any red row is the actual problem.
Screenshot it and send it to Patrick.

---

<sub>Build and publish tooling is in [`tools/`](tools). Setup notes in
[SETUP.md](SETUP.md).</sub>
