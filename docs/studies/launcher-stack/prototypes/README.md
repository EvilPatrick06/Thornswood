# Launcher stack prototypes

One small window per candidate stack for the launcher stack study (#3209,
[the study](../README.md)). Each one is the same window, so the
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

| Name | Stack | Built where | Files |
|---|---|---|---|
| wpf-net481-webview2 | WPF on .NET Framework 4.8.1, page in WebView2: the launcher's stack today | anywhere with the .NET 10 SDK | [wpf-net481-webview2.csproj](wpf/wpf-net481-webview2.csproj), [Proto.cs](wpf/Proto.cs), [Directory.Build.props](wpf/Directory.Build.props) (the three WPF projects share one folder and keep apart builds) |
| wpf-net10 and wpf-net10-sc | WPF on .NET 10, needing the .NET 10 Desktop Runtime, and the same self-contained in one file | anywhere with the .NET 10 SDK | [wpf-net10.csproj](wpf/wpf-net10.csproj) |
| wpf-net10-webview2-sc | WPF on .NET 10 self-contained, page in WebView2 | anywhere with the .NET 10 SDK | [wpf-net10-webview2.csproj](wpf/wpf-net10-webview2.csproj) |
| winui3 | WinUI 3 (Windows App SDK) on .NET 10, unpackaged, self-contained | Windows only | [proto-winui3.csproj](winui3/proto-winui3.csproj), [Proto.cs](winui3/Proto.cs) |
| avalonia and avalonia-aot | Avalonia on .NET 10, self-contained, trimmed, one file; and the same compiled ahead of time to native code | the first anywhere with the .NET 10 SDK, the second on Windows only | [proto-avalonia.csproj](avalonia/proto-avalonia.csproj), [Proto.cs](avalonia/Proto.cs), [app.manifest](avalonia/app.manifest) |
| tauri | Tauri 2 (Rust), page in the system web view | Windows, or Linux with cargo-xwin | [Cargo.toml](tauri/Cargo.toml), [Cargo.lock](tauri/Cargo.lock), [build.rs](tauri/build.rs), [main.rs](tauri/main.rs), [tauri.conf.json](tauri/tauri.conf.json) |
| slint | Slint (Rust), its own renderer | Windows, or Linux with cargo-xwin | [Cargo.toml](slint/Cargo.toml), [Cargo.lock](slint/Cargo.lock), [main.rs](slint/main.rs) |
| egui | egui through eframe (Rust), immediate mode | Windows, or Linux with cargo-xwin | [Cargo.toml](egui/Cargo.toml), [Cargo.lock](egui/Cargo.lock), [main.rs](egui/main.rs) |
| wails | Wails 2 (Go), page in the system web view | anywhere with Go | [go.mod](wails/go.mod), [go.sum](wails/go.sum), [main.go](wails/main.go), [hide_windows.go](wails/hide_windows.go), [hide_other.go](wails/hide_other.go) |
| electron | Electron (TypeScript and Node), its own Chromium | anywhere with Node | [package.json](electron/package.json), [package-lock.json](electron/package-lock.json), [main.js](electron/main.js), [preload.js](electron/preload.js) |
| qt | Qt 6 Quick (C++) | Windows only for the Windows build | [CMakeLists.txt](qt/CMakeLists.txt), [main.cpp](qt/main.cpp), [Main.qml](qt/Main.qml) |
| flutter | Flutter (Dart) | Windows only for the Windows build | [pubspec.yaml](flutter/pubspec.yaml), [main.dart](flutter/main.dart), [.gitignore](flutter/.gitignore) (everything `flutter create .` makes stays out of the repository) |

[index.html](index.html) is the one page the web view stacks share, and
[.gitignore](.gitignore) keeps every build out of the repository.

## Building and measuring

On a Windows machine with Visual Studio's C++ build tools, from the
repository root:

```
pwsh -File docs\studies\launcher-stack\Measure-Prototypes.ps1
```

[Measure-Prototypes.ps1](../Measure-Prototypes.ps1) fetches every toolchain into its own work folder, builds all fourteen,
runs each five times and writes `results.md` there. `-Clean` removes the
work folder and the web view data folders afterwards. The script's own help
says the rest.
