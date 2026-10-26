# A more modern launcher and installer: the options (#3209)

Patrick asked on 21 Oct 2026 for a more modern launcher and installer,
"whether that means changing the language it uses, the way it's built or
anything", and for the study to "actually look and see if a different
language would be beneficial". The rule for the pick is the issue's: the
one-time cost of rewriting is not a criterion and never a tiebreaker, what
people who play notice comes first, and where two options are equal for them
the differences for the team decide.

This page is the comparison and the recommendation. Patrick makes the pick on
his report page, and the pick is then split into smaller issues.

## Where things stand today, measured

| | Today | Measured |
|---|---|---|
| Launcher | `Thornswood.exe`, WPF on .NET Framework 4.8.1, C# 13 | Main 1.2.5 is 3,937,024 bytes on the feed (26 Oct 2026), with the header art, the header video and the WebView2 DLLs inside it |
| What it needs on the machine | .NET Framework 4.8.1 and the WebView2 Runtime | Both come with Windows 11 22H2 and later; Windows 10 has 4.8 and needs the 4.8.1 update |
| Window | `launcher/ui.xaml`, about 1,480 lines, parsed at run time | A renamed control is not a build error; `scripts/dev/Check-Controls.ps1` stands in for the compiler |
| Music and voice | Hidden WebView2 pages (`MenuMusic.cs`, `Voice.cs`) | The music moved into WebView2 because WPF's own MediaPlayer needs the Media Feature Pack, which One lacks (`MenuMusic.cs`) |
| Self update | In house: `Updater.cs`, `SelfSwap.cs` | |
| Installer | `Thornswood-Setup.exe` (`installer/setup/Bootstrap.cs`, 2,126 lines) runs `Setup-Thornswood.ps1` (994 lines) in its window | The payload it fetches is 89,962,865 bytes (`/api/payload`, 26 Oct 2026) |
| Signing | Authenticode through Azure Artifact Signing, profile ThornswoodRelease | Launcher, installer and setup stub are all signed, and Ship refuses an unsigned one (`docs/SIGNED-RELEASES.md`, #3312). The issue's first point, "sign the binaries first", is done |

## How it was measured

One small prototype per stack, all the same window: the launcher's art across
1220 by 800, the word THORNSWOOD, a Play button that starts a process, and the
music playing ([prototypes/README.md](prototypes/README.md) has the contract and the code). The
native stacks play the music from their own process; the web view stacks play
it through an HTML `<audio>` element, the way the launcher does today.

- **Sizes** are measured on the Windows builds, made in a cloud session on
  26 Oct 2026 for the eleven builds that can be made off Windows. "Install"
  is every file the build needs beside it, "zip" the same files compressed,
  which is about what it adds to a download. Neither counts the art, the
  music or debug symbols.
- **Linux**: every stack that claims Linux was built for Linux and started
  under a virtual display in the same session (appendix). That answers "does
  it run there", not how fast: the display has no graphics card.
- **Start time, memory and the Volume Mixer entry** need a real Windows
  desktop. [Measure-Prototypes.ps1](Measure-Prototypes.ps1) builds all fourteen on One and measures
  each five times; its results go on #3209 and into the table below. The
  three Windows-only builds (WinUI 3, Qt, Flutter, and Avalonia compiled to
  native code) get their sizes from that run too.

## The comparison

What the builds need beside them on a Windows 11 machine: "WebView2" means
the WebView2 Runtime, which Windows 11 has; ".NET 10" means the .NET 10
Desktop Runtime, which Windows does not have and whose installer is
60,035,296 bytes (10.0.14, 25 Oct 2026).

| Candidate | Language | Install MB | Zip MB | Needs on the machine | Start, memory, mixer | Linux | Built in the cloud |
|---|---|---|---|---|---|---|---|
| WPF on .NET Framework 4.8.1 with WebView2 (today) | C# | 1.17 | 0.39 | .NET Framework 4.8.1, WebView2 | from the One run | no | yes |
| WPF on .NET 10, framework dependent | C# | 0.16 | 0.08 | .NET 10 | from the One run | no | yes |
| WPF on .NET 10, self-contained | C# | 61.85 | 56.62 | nothing | from the One run | no | yes |
| WPF on .NET 10, self-contained, with WebView2 | C# | 63.00 | 57.13 | WebView2 | from the One run | no | yes |
| WinUI 3, unpackaged, self-contained | C# | from the One run | from the One run | nothing | from the One run | no | no (needs Windows tools, measured) |
| Avalonia on .NET 10, self-contained, trimmed | C# | 19.84 | 14.87 | nothing | from the One run | yes | yes |
| Avalonia, untrimmed | C# | 46.33 | 41.18 | nothing | | yes | yes |
| Avalonia compiled to native code | C# | from the One run | from the One run | nothing | from the One run | yes | no (native compile needs Windows) |
| Tauri 2 | Rust and the page in HTML | 3.20 | 1.44 | WebView2 | from the One run | yes | yes |
| Slint | Rust | 8.19 | 4.67 | nothing | from the One run | yes | yes |
| egui | Rust | 7.87 | 3.73 | nothing | from the One run | yes | yes |
| Wails 2 | Go and the page in HTML | 10.43 | 4.24 | WebView2 | from the One run | yes | yes |
| Electron 45 | TypeScript | 356.67 | 154.82 | nothing | from the One run | yes | yes |
| Qt 6 Quick | C++ | from the One run | from the One run | nothing | from the One run | yes | no for Windows |
| Flutter 3.47 | Dart | from the One run | from the One run | nothing | from the One run | yes | no for Windows |
| Python (PySide6 or similar, frozen) | Python | not built | | | | | |

Python was not built. Freezing a Python program into an exe (PyInstaller and
the like) unpacks the interpreter at every start, gives a large exe once Qt
is in it, and is among the things antivirus flags most often, which is the
worst place to be for the first program a new tester runs. None of that is
offset by anything Python does better here.

What the launcher being open means: it stays open while the game runs (the
feed is read every thirty seconds, `docs/FEED.md`), so its memory is taken
from a heavily modded Skyrim for the whole session. That makes idle memory
the number that matters most after the download, and it is the one the One
run brings.

## The options, with pros and cons

Each option below is a whole direction. Its pros and cons come first for the
people who play, then for the team.

### A. Stay on WPF, move to .NET 10

For people who play:
- Pro: the window looks and behaves as it does today, and WPF on .NET 9 and
  later has a Fluent theme for a newer look with little work.
- Pro: framework dependent it is the smallest download of all (0.08 MB
  zipped), once the .NET 10 Desktop Runtime is on the machine.
- Con: that runtime is not part of Windows. Either the installer fetches it
  (60 MB, once, and again when a new major version is wanted) or the
  launcher carries it self-contained, and then it is the second largest
  option here (57 MB zipped, against 0.39 MB today).
- Con: Windows only. No Linux or Steam Deck launcher, ever.

For the team:
- Pro: WPF and C# are what everybody who works here already reads, and
  Claude threads work well in it.
- Pro: measured: the .NET 10 SDK builds WPF on Linux, so cloud threads and
  Linux CI can build and check the launcher, which they cannot do today with
  .NET Framework and MSBuild.
- Pro: compiled XAML (an `x:Class` window with generated fields) makes a
  renamed control a build error and lets `Check-Controls.ps1` go.
- Con: WPF is in maintenance at Microsoft: fixes and the theme, few new
  features.

### B. WinUI 3 (Windows App SDK)

For people who play:
- Pro: the most native looking Windows 11 window of all: Mica, the Windows 11
  controls and animations.
- Con: Windows 10 1809 or newer and Windows only.
- Con: unpackaged and self-contained it carries the Windows App SDK runtime;
  its size comes from the One run.

For the team:
- Con: measured: it cannot be built off Windows (the Windows App SDK build
  needs Windows' own tools), so no cloud thread can build or check it, and
  every build goes to the Windows runners whose hosted minutes run out.
- Con: unpackaged WinUI 3 has more rough edges than WPF (window sizing,
  single file publish), and fewer people and examples to learn from.

### C. Avalonia on .NET 10 (C#, cross-platform)

For people who play:
- Pro: self-contained and trimmed it needs nothing on the machine and is
  15 MB zipped; compiled to native code it starts faster (sizes and times
  from the One run).
- Pro: it draws every pixel itself with Skia, so the window looks the same on
  every Windows version, and themes and animation are first class.
- Pro: measured: it runs on Linux, so a Linux or Steam Deck launcher is a
  build away if Thornswood ever installs without Vortex (see "Linux and the
  Steam Deck").
- Con: it is not a Windows control set, so it looks like itself, not like
  Windows 11 (it can be styled to).
- Con: its open source packages have no web view control, so voice and the
  music need a native answer (#3208) or a wrapper around WebView2.

For the team:
- Pro: C# and XAML, close to WPF, so the same people and Claude threads work
  in it; compiled bindings make a renamed control a build error.
- Pro: measured: builds on Linux, so cloud threads and Linux CI can build it.
- Con: one more framework to keep up with than WPF; Avalonia moves faster
  than WPF (version 12 is current), so upgrades come more often.

### D. Uno Platform (C#, WinUI's API everywhere)

Not built: on Windows desktop it renders with Skia like Avalonia, so it lands
where Avalonia does on size and look, with WinUI's API. For people who play it
is the same as C. For the team it is a heavier toolchain and project layout
than Avalonia for the same result, so it is not taken further.

### E. Tauri 2 (Rust, the window is a web page)

For people who play:
- Pro: the smallest self-contained download of the lot (1.4 MB zipped).
- Pro: HTML and CSS make the most modern looking window the easiest to get,
  with animation and video.
- Pro: a built-in updater and installer bundler (NSIS or MSI).
- Pro: measured: runs on Linux (with WebKitGTK there).
- Con: the window lives in WebView2, the browser engine #3208 is asking to
  get away from: memory for a browser beside the game while it runs (One run
  numbers), and the Volume Mixer showing WebView2's processes (#3207).

For the team:
- Pro: Tauri is mature and well documented; measured, it builds for Windows
  from Linux (cargo-xwin), so cloud threads can build it.
- Con: Rust is a new language in the repository beside C#, PowerShell,
  JavaScript, Python and the engine's C++. Fewer people here read it.
- Con: two halves to keep in step, Rust for the work and HTML for the window.

### F. Slint or egui (Rust, native)

For people who play:
- Pro: small (4.7 MB and 3.7 MB zipped), nothing needed on the machine, and
  no browser at all.
- Pro: measured: both run on Linux.
- Con: egui redraws the window as a game would and looks plain unless every
  part is painted by hand; it suits tools more than a launcher.
- Con: Slint's widget set is smaller than WPF's or Avalonia's, so more of the
  window is built by hand.

For the team:
- Pro: measured: both build for Windows from Linux.
- Con: Rust is a new language here (as in E).
- Con: Slint is free for desktop programs under its royalty-free licence,
  which asks for an attribution in the program; egui is MIT.

### G. Electron (TypeScript)

For people who play:
- Con: measured: 155 MB zipped and 357 MB installed for this one window,
  which on its own is bigger than the whole payload a new tester downloads
  today (90 MB).
- Con: a whole Chromium beside the game while it runs; its memory comes from
  the One run.
- Pro: the most freedom for a web looking window, and a mature updater.

For the team:
- Pro: TypeScript and JavaScript are already in the repository (site, voice,
  gamemode).
- Con: every Chromium security release means a new launcher release.

### H. Wails 2 (Go, the window is a web page)

For people who play: as Tauri, a little bigger (4.2 MB zipped), with the same
WebView2 cons.

For the team: Go is not used anywhere in Thornswood; its Windows build is the
simplest of all (one `go build`, measured from Linux), but the stack has a
smaller community than Tauri and its next version is still in beta.

### I. Qt 6 (C++)

For people who play:
- Pro: native speed and a mature, themeable widget and Quick (QML) set.
- Pro: measured: runs on Linux.
- Con: its deploy set is tens of megabytes (from the One run), and its web
  view (Qt WebEngine) is a whole Chromium if a page is ever needed.

For the team:
- Con: the free licence is the LGPL: Qt has to stay as separate DLLs that a
  person could swap, with its notices shipped. The commercial licence costs
  money, which is ruled out.
- Con: C++ is the language with the most ways to crash; the engine already
  uses it, but nobody works on a C++ window here.
- Con: measured: the Windows build needs Windows (MSVC and the Qt kit), so
  cloud threads cannot build it.

### J. Flutter (Dart)

For people who play:
- Pro: smooth, animated, fully themed windows; measured: runs on Linux.
- Con: an engine and runtime of its own beside the exe (size from the One
  run), and audio and web views only through plugins.

For the team:
- Con: Dart is new here; the Windows build needs Windows and Visual Studio
  (measured: it cannot be made from Linux).

## The installer

Whatever the window is drawn with, the install itself has its own options.
They apply to every option above.

| Option | For people who play | For the team |
|---|---|---|
| Keep the C# bootstrapper running `Setup-Thornswood.ps1` | Works today; but a PowerShell script running hidden is what antivirus looks hardest at, and its progress is lines of text | Two languages for one job; the script is tested by the harnesses |
| The bootstrapper does the whole install in compiled code (the PowerShell retired) | One window, real progress, nothing for antivirus to read as a script | One language with the launcher; the install steps become testable code |
| Velopack (install and self-update for .NET, Rust and JavaScript programs) | Installs with no admin prompt, updates with deltas, one Setup.exe; by default it installs under the person's own profile, not in `<Root>\Launcher` beside the game, so either the layout changes or its install folder option is used | Replaces `Updater.cs` and `SelfSwap.cs` for the launcher itself; the game payload stays our own feed |
| WiX (MSI and a Burn bundle) | A classic installer with the Windows Installer rules, repair and uninstall | Heavy to write and debug; MSI's rules fight an install into a folder the person picks on any drive |
| Inno Setup or NSIS | Small, familiar installers | Their own script languages; the install logic moves from PowerShell into another scripting language |
| MSIX | Clean install and removal through Windows | The launcher writes beside the game and into the Steam copy, which MSIX's container makes hard; Windows only |

The game payload update (packs, the release record, the client runtime) is
Thornswood's own and stays our own feed whichever stack wins; only the
launcher's own update moves to a framework.

## Linux and the Steam Deck

Every stack but WPF and WinUI 3 runs on Linux (measured). What a native Linux
launcher would get people today is limited by what it launches: the
collection installs through Vortex, which is Windows only, and the game
itself runs on Linux only under Proton. So a Linux build is worth having only
if Thornswood decides to install without Vortex, or to run its Windows
launcher under Proton, where a self-contained build with no WebView2 and no
.NET Framework has the best chance. That is the first question below.

## Recommendation

Pending the One run, which can still change it: **C. Avalonia on .NET 10,
self-contained and compiled to native code, with the install done in compiled
code and Velopack for the launcher's own updates, and no web view in the
launcher once #3208 settles voice.**

Why, for the people who play: it needs nothing on the machine, it is 15 MB
zipped or less (WPF self-contained is 57, Electron 155), it carries no browser
beside the game if voice and the music move out of WebView2, and it keeps the
door to Linux and the Steam Deck open at no cost today. Why, between the
options that are equal for them, for the team: it is C# and XAML, the language
the launcher, the installer and the people here already use, its bindings are
checked when it builds, and it builds on Linux, so cloud threads and Linux CI
can build and check it while hosted Windows minutes are short.

What would change it, once the One run is in:
- If Slint's idle memory or start time is clearly better than Avalonia's
  native build, Slint (F) is better for the people who play, and the team
  cost of Rust is what is left to weigh.
- If Linux and the Deck are ruled out for good, WPF on .NET 10 (A) is equal
  for the people who play in look and close in memory, and stays easier for
  the team.
- If #3208 keeps a web view for voice, the launcher keeps WebView2 under any
  stack, and Tauri's case (E) gets stronger.

Whatever is picked:
1. Signing is already done (#3312).
2. The install moves out of PowerShell into compiled code, so
   `Setup-Thornswood.ps1`, `Setup.bat` and `Install.bat` can be retired.
3. The launcher's own update moves to a framework (Velopack for C#), and the
   game payload update stays our own feed (#3201, #3202).
4. The web view question is settled with #3208 before the window work
   starts.

## Questions for Patrick

1. Do we want a Linux or Steam Deck launcher at all, given Vortex is Windows
   only?
2. What download size is acceptable for the launcher on its own: about 15 MB
   (Avalonia), about 60 MB (WPF self-contained), or over 150 MB (Electron)?
3. The signing certificate is ThornswoodRelease (done, #3312).
4. Can the payload update share the launcher's update channel? Recommended
   no: the payload is Thornswood's own feed with its release record, and only
   the launcher's own exe moves to a framework.

## Appendix: the Linux runs

26 Oct 2026, cloud session, a virtual display at 1920 by 1080 with software
drawing (no graphics card), four processors. Start is the time to the first
frame with the art, in milliseconds, for four runs; memory is the resident
size of the program and every process under it, so pages shared between
them are counted more than once. These say each stack runs on Linux; they
are not the Windows numbers.

| Build | Start ms | Memory MB | Processes |
|---|---|---|---|
| Qt | 2746, 277, 280, 292 | 182 to 188 | 1 |
| Slint | 398, 209, 220, 174 | 133 to 147 | 2 |
| egui | 508, 375, 237, 256 | 140 to 147 | 2 |
| Tauri (WebKitGTK) | 3019, 1023, 1031, 944 | 506 to 523 | 4 |
| Wails (WebKitGTK) | 408, 453, 428, 415 | 373 to 374 | 4 |
| Flutter | 755, 401, 408, 391 | 255 to 308 | 1 |
| Avalonia, trimmed | 988, 1088, 1031, 937 | 139 to 145 | 1 |
| Electron | 834, 253, 285, 318 | 656 to 759 | 7 |
