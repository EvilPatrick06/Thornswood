# Icons

Three icon files. Each one has one job. They are not interchangeable.

## Main launcher

`launcher/app.ico` is the Main launcher icon. Every frame is the full
round Thornswood badge: 16, 24, 32, 48, 64, 128 and 256. Windows draws
shortcuts and the taskbar from the small frames, so those have to be
the badge too, not a crop of it.

`scripts/release/Build-Launcher.ps1` finds it at line 157, embeds it as
`app.ico` at lines 301 to 302, and stamps it on the exe as `/win32icon`.
`launcher/app/Icons.cs` writes that same artwork out beside the exe as
`icon-<hash>.ico` (line 106). The hash is the first four bytes of the
SHA-256 of the file. When `app.ico` changes, the name changes, and
Windows has no cached picture of the old one to show. `Icons.Ensure`
then points every shortcut at the new file (lines 315 to 333).

## Dev launcher

`launcher/app-dev.ico` is the Dev launcher icon, the TF monogram.
`Build-Launcher.ps1` line 176 requires it, and lines 301 to 302 embed
it next to the Main icon. `Icons.cs` lines 81 to 88 pick it when
`Art.Dev` is set. It stays its own file.

## Website tab

`site/public/favicon.ico` is the website tab only. It is the crest
alone, not the badge. `site/public/index.html` line 7 and
`site/public/home.html` line 52 point the tab at it. It is never
embedded in the launcher.

## Why they must stay apart

On 5 Oct, #1581 put the crest-only favicon art into the 16, 24, 32, 48
and 64 frames of `launcher/app.ico`. The 128 and 256 frames kept the
badge picture (same pixels, a new PNG encoding). Windows then drew the
Main shortcut and the taskbar from the crest, so Main looked like the
website tab. That shipped in 1.1.106 and 1.2.0.

Djinn, 11 Oct 2026: the Main icon is the full badge at every size. The
Dev icon stays the TF monogram. The crest belongs only to the favicon.

`tests/test-launcher-icons.js` fails if any frame of `app.ico` matches
a frame of the favicon, or if `app.ico` and `app-dev.ico` share a
frame.

The Main icon reaches the installed launcher only after a launcher
version bump and a Ship. Changing the file here does not change what
is already installed.
