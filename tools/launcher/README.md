# The launcher's voice page

## What it is

This folder holds one file, `voice-host.html`, and it is not the launcher's
source: the C# is in `tools\app` and the window's layout in `tools\ui.xaml`.
`voice-host.html` is proximity voice as the launcher runs it. The launcher
(`tools\app\Voice.cs`) opens it in a hidden WebView2 window, where a real
browser can hold the microphone, run WebRTC between people and play the
audio, none of which the game's own browser ever managed. It talks to the
voice service (`tools\voice`) on the same protocol as the in-game page. Push
to talk, the one thing it needs from the game, reaches it through the
launcher, which hears it from the game plugin over a local socket and a small
file in `Data\Platform`.

## On your machine

There is nothing to run on its own. `tools\Build-Launcher.ps1` compiles the
launcher with the .NET Framework 4 csc and puts this page inside
`Thornswood.exe` as a resource, by name, and stops if it is missing, so a
change here takes a launcher build. To compile without touching the installed
launcher or the Desktop shortcut, build into a scratch root:

```
powershell -NoProfile -File tools\Build-Launcher.ps1 -Root "$env:TEMP\ts-build" -NoPause
```

What the page reports goes to the launcher's log, `Profile\launcher.log`,
which is where to look when voice is broken.

## Where it runs

Inside `Thornswood.exe` on every machine with the launcher. On start the
launcher writes it out beside itself, in its `Launcher` folder, when the copy
there is missing or a different size, and loads it from there. It reaches
people with the launcher: Ship builds the exe and publishes it with the
release, and each launcher replaces itself when its feed has a newer one. The
dev build, on the dev feed, gets it first.
