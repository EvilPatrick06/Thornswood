# Launcher stack prototypes

One small window per candidate stack for the launcher stack study (#3209,
`docs/studies/launcher-stack/README.md`). Each one is the same window, so the
numbers compare the stacks and nothing else. None of them is the launcher and
none of them ships.

## The contract

Every prototype:

- opens a window 1220 by 800, the launcher's own size, titled
  `Thornswood <stack>`;
- draws `art.png` (the launcher's `launcher/art/thornswood-art-1536.png`)
  across the window, the word THORNSWOOD, a Play button and a line of state
  under it;
- writes the file named by the environment variable `PROTO_READY` once its
  first frame with the art on it is on screen. That moment is the start time
  `Measure-Prototypes.ps1` takes;
- four seconds later starts `loop.wav` on a loop and starts `cmd.exe /c exit
  0` as a stand-in for Play (the button does the same), then writes
  `PROTO_READY` with `.active` added. The native stacks play the sound from
  their own process (`PlaySound` in winmm); the web view stacks play it
  through an HTML `<audio>` element, the way the launcher's music plays
  today (`launcher/app/MenuMusic.cs`), so the Volume Mixer shows what each
  way really gives.

`art.png` and `loop.wav` sit beside the exe, or inside the page for the
stacks that build their page into the exe (Tauri, Wails, Electron). Sizes
never count them: those stacks are weighed from a second build without them.

## The prototypes

| Name | Stack | Folder | Built where |
|---|---|---|---|
| wpf-net481-webview2 | WPF on .NET Framework 4.8.1, page in WebView2: the launcher's stack today | `wpf` | anywhere with the .NET 10 SDK |
| wpf-net10 | WPF on .NET 10, needs the .NET 10 Desktop Runtime | `wpf` | anywhere with the .NET 10 SDK |
| wpf-net10-sc | the same, self-contained in one file | `wpf` | anywhere with the .NET 10 SDK |
| wpf-net10-webview2-sc | WPF on .NET 10 self-contained, page in WebView2 | `wpf` | anywhere with the .NET 10 SDK |
| winui3 | WinUI 3 (Windows App SDK) on .NET 10, unpackaged, self-contained | `winui3` | Windows only |
| avalonia | Avalonia on .NET 10, self-contained, trimmed, one file | `avalonia` | anywhere with the .NET 10 SDK |
| avalonia-aot | the same compiled ahead of time to native code | `avalonia` | Windows only |
| tauri | Tauri 2 (Rust), page in the system web view | `tauri` | Windows, or Linux with cargo-xwin |
| slint | Slint (Rust), its own renderer | `slint` | Windows, or Linux with cargo-xwin |
| egui | egui through eframe (Rust), immediate mode | `egui` | Windows, or Linux with cargo-xwin |
| wails | Wails 2 (Go), page in the system web view | `wails` | anywhere with Go |
| electron | Electron (TypeScript and Node), its own Chromium | `electron` | anywhere with Node |
| qt | Qt 6 Quick (C++) | `qt` | Windows only for the Windows build |
| flutter | Flutter (Dart) | `flutter` | Windows only for the Windows build |

`web/index.html` is the one page the web view stacks share.

## Building and measuring

On a Windows machine with Visual Studio's C++ build tools, from the
repository root:

```
pwsh -File docs\studies\launcher-stack\Measure-Prototypes.ps1
```

It fetches every toolchain into its own work folder, builds all fourteen,
runs each five times and writes `results.md` there. `-Clean` removes the
work folder and the web view data folders afterwards. The script's own help
says the rest.
