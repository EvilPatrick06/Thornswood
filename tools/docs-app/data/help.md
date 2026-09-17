# Help

## Installing it the first time

Thornswood does not touch your Steam copy of Skyrim. It installs its own copy
in its own folder, with its own mods and its own launcher, and leaves whatever
you already play alone.

From the [Downloads](/downloads) page take **both** files, the exe and the zip,
into the same folder. Downloads works. Anywhere works. They just have to be
beside each other, because the exe reads the zip.

Then run the exe. Do not unzip anything yourself.

The first run copies about twenty gigabytes into place, so give it time and
leave it alone while it works.

## Starting it after that

Open Thornswood from the desktop shortcut. Not Skyrim, not Steam, not SKSE.
The launcher checks for updates, patches anything that changed, and the Play
button starts the game and connects you. There is no password to type and no
address to enter.

If an update is waiting, the launcher takes it before it lets you play. That is
on purpose: everybody has to be running the same files or nobody can connect.

## Voice

Voice runs in the launcher, not in the game. Leave the launcher open while you
play.

Push to talk is the default. The indicator in the launcher says whether you are
being heard. Whisper and yell change how far your voice carries in the world.

If nobody can hear you, check that the launcher is still open and that Windows
has not handed your microphone to something else.

## When something goes wrong

1. Look at [Known Issues](/known) first. A lot of what looks like a bug is a
   limit of how a shared Skyrim works, and it is written down there with the
   reason.
2. If it is not there, [report it](/report). One line about what happened is
   enough to start with.
3. If you have a screenshot or a crash log, put it on the [Uploads](/uploads)
   page and say so in the report.

## Where the logs are

Crash logs, if the game closed itself:

```
C:\Thornswood\Profile\SKSE\CrashLogger\
```

The launcher's own log, for anything that went wrong before the game started:

```
C:\Thornswood\Profile\launcher.log
```

Drag either onto the [Uploads](/uploads) page. They are plain text and they are
usually the difference between a fix and a guess.

## Things that are normal here

- No saving. The server holds your character. Quitting is safe.
- Mod settings menus forget themselves every session, because there is no save
  to write them to.
- NPCs stand still when nobody is near them.
- No levelling, no fast travel, and the difficulty is fixed.

All of that is deliberate and explained on [Known Issues](/known).

## Restart warnings

When an update is going out, a warning appears in the game before anything
happens. A notice means the server might stutter for a moment and you can keep
playing. An update or a restart counts down and then puts you back to the
launcher, where the Play button will pick the new version up.
