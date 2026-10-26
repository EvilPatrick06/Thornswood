# The launcher

## What it is

Everything `Thornswood.exe` is built from. The C# is in `launcher\app`, in C# 13,
built with MSBuild from `launcher\app\Thornswood.csproj` (#498), and
`launcher\app\ARCHITECTURE.md` says what each
class owns and how Play runs. The window's layout is `ui.xaml`, parsed at
startup, so a control renamed there and not in the C# is found by
`scripts\dev\Check-Controls.ps1` rather than by somebody pressing it. Beside them are
the icon (`app.ico`), the emblem (`logo.png`, `logo-192.png`), the strip of art
behind the title (`launcher-header.jpg` and `.mp4`), the key template the
launcher writes when a machine has none (`Thornswood.ini`), and the WebView2
libraries in `lib\webview2`.

`voice-host.html` is proximity voice as the launcher runs it. The launcher
(`launcher\app\Voice.cs`) opens it in a hidden WebView2 window, where a real
browser can hold the microphone, run WebRTC between people and play the
audio, none of which the game's own browser ever managed. It talks to the
voice service (`voice`) on the same protocol as the in-game page. Push to
talk reaches it through the launcher, which hears it from the game plugin over
a local socket and a small file in `Data\Platform`.

Five files in `launcher\app` are touched from every machine and need a line in
#staff-updates before they change: Shell.cs, Checks.cs, Keep.cs, Hold.cs and
Updater.cs.

## On your machine

`scripts\release\Build-Launcher.ps1` builds the launcher with MSBuild from
`launcher\app\Thornswood.csproj` (and the setup program from
`installer\setup\Setup.csproj`), which put the window, the art, the key
template, the voice page and the client build record inside `Thornswood.exe`
as resources, by name, and stop if one is missing. A build writes the exe into `<Root>\Launcher` and touches
nothing else; the shortcut and the icon are `scripts\release\Install-Launcher.ps1`,
which Ship runs. To compile without replacing an installed launcher, build
into a scratch root:

```
.\scripts\release\Build-Launcher.ps1 -Root "$env:TEMP\ts-build" -NoPause
```

It needs Visual Studio 2022 Build Tools with MSBuild and the .NET Framework
4.8.1 targeting pack (`scripts\release\Find-MSBuild.ps1 -Report` says
whether a machine has them; Developer-Guide.md "Setting up a machine" has the
install line). A resource added to the launcher goes into Thornswood.csproj
and into the list in `tests\test-498-msbuild.ps1`, which checks every
resource in the built exe against its file byte for byte.

What the launcher does is written to its own log, `Profile\launcher.log`,
which is where to look first when anything about it is wrong, voice included.

## Where it runs

On every machine with Thornswood. Ship builds the exe and publishes it with
the release, and each launcher replaces itself when its feed has a newer one;
the dev build, on the dev feed, gets it first. The voice page is written out
beside the exe on start, when the copy there is missing or a different size,
and loaded from there. Moved here from `tools\` on 25 September (issue #440,
phase 7).
