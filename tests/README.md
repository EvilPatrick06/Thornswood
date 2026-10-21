# The test harnesses

## What they are

Every `test-*.js` and `test-*.ps1` here checks one thing the scripts, the
launcher, the plugins, the gamemode or the site promise, by reading the files
or by running a piece of them against a scratch copy. None of them talks to
the VPS or to GitHub unless it says so at the top (`test-branch-rules.js
--live` is one that does; `test-collection-revision-2.ps1` reads both
servers' manifests over plain HTTP unless given `-Offline`). The nightly checks (`.github/workflows/nightly.yml`) run every one of them
on the VPS each night and open an issue when one fails; on a pull request,
run the ones your change touches yourself.

A few of them run on every pull request as well, in the build check
(`.github/workflows/build.yml`), because each one's failure once sat on main
unseen: `test-ownership.js` (issue #752, a secret file reached main with no
row on `docs\OWNERSHIP.md`), and the list in its step "Run the harnesses that
went red unseen" (issues #875, #454 and #1088, the last three being the VPS
address kept in one place and deploys that are the same bytes for the same
commit). Each is under a minute. The rest are minutes together, which is why
they are nightly.

The voice service's own harnesses stay beside it in `voice\`, and the bot's in
`bot\`, because they are run from there.

## Where they look

They moved here from `tools\` on 25 September (issue #440, phase 5), and
`tools\` itself went on 29 September (phase 10). Each one finds the repository
folder from here, one folder up: a `.js` harness through `REPO_DIR`, declared at
its top as `path.join(__dirname, '..')`, and a `.ps1` harness through the line
after its `$Here = $PSScriptRoot` that points `$Here` at the repository folder.
A new harness does the same; copying the top of an existing one is the easy way.

## Running them

From the repository folder:

```
node tests\test-farming.js
pwsh -NoProfile -File tests\test-ship-rules.ps1
```

Each prints a PASS or FAIL line per check and ends on `N passed, M failed`,
and exits 1 when anything failed. A harness that reads something only one
machine has, such as the game folder, says SKIP for that part and checks the
rest.

## A harness that needs Windows

Windows PowerShell 5.1, cmd.exe, a scheduled task, a folder's ACL and the
.NET Framework are only on Windows, and the harnesses also run under pwsh on
Linux. A `.ps1` harness that needs any of them dot-sources `tests\Windows.ps1`
and asks `$OnWindows` before it names a Windows path:

```
. (Join-Path $PSScriptRoot 'Windows.ps1')
if (-not $OnWindows) {
    Write-Host 'SKIP  the runs: they need Windows PowerShell 5.1, which only Windows has'
    Done
}
$ps51 = Get-WindowsPowerShell
$cmd = Get-WindowsPath 'System32\cmd.exe'
```

Off Windows it says SKIP for that part and checks the rest, or, when the
whole harness is about Windows, prints one `NOT RUN` line saying why and
exits 0. When what it runs on the box can run here as well, it may run it in
this shell instead, and says so on a `NOTE` line. On Windows,
`Get-WindowsPowerShell` fails the harness when powershell.exe is not where
Windows keeps it, rather than letting it skip or run pwsh in its place. A
harness that loads `tests\Launcher-Csc.ps1` has `$OnWindows` from it too.

Before issue #2957 each harness found these itself, by joining onto
`$env:SystemRoot` or asking `Get-Command` for powershell.exe, and copied the
line from the harness before it; off Windows the join stopped harness after
harness on its first lines. `test-2957-windows-one-way.ps1` fails on a
harness that names `$env:SystemRoot` or `$env:WINDIR`, runs powershell or cmd
by name, asks `$IsWindows` (which 5.1 does not have), or uses `$OnWindows`
without loading `Windows.ps1`.

The temp folder is `[IO.Path]::GetTempPath()`, never a path built on
`$env:TEMP` or `$env:TMP`, which only Windows sets (#2965). A harness may set
TEMP for a script it runs and put the old value back; `test-temp-folder.ps1`
fails on any other read of them.

A path a harness compares with what a script prints is built with
`Join-Path` or `[IO.Path]::Combine`, and a key written with `\`, like the
swallow baseline's, is made from a path by replacing
`[IO.Path]::DirectorySeparatorChar`. Off Windows `\` is part of a file name.

## A harness that compiles launcher code

A `.ps1` harness that compiles C# out of `launcher\app` or `installer\setup`
dot-sources `tests\Launcher-Csc.ps1` and hands the source to
`Add-LauncherType`, which compiles it the way the build does: the Roslyn csc
beside MSBuild, the project's `LangVersion`, the .NET Framework 4.8.1
reference assemblies. It returns the loaded assembly and throws with the
compiler's words when the code does not compile. Off Windows that compiler is
not there, so the harness says SKIP for the compiled part:

```
. (Join-Path $PSScriptRoot 'Launcher-Csc.ps1')
if (-not $OnWindows) {
    Write-Host 'SKIP  Updater.IsNewer, compiled and run: its compiler is the Roslyn csc that comes with Visual Studio''s Build Tools, which only Windows has'
    Done
}
$asm = Add-LauncherType -Source $configSrc, $stub
$T = $asm.GetType('Thornswood.Updater')
```

Before issue #2821 eighteen harnesses compiled launcher code with `Add-Type`
or a `CSharpCodeProvider`, copied from one to the next: C# 5 under Windows
PowerShell and .NET 8's libraries under pwsh, never the build's compiler.
`test-2821-launcher-compiler.ps1` fails on a harness that names launcher or
setup code and gives `Add-Type` anything but C# written out in full in the
harness itself (a stand-in server or a probe of a Windows call is that), or
makes a `CSharpCodeProvider`.

## A harness that reads a child's error

pwsh's default error view wraps a script error's message at the console's
width, at a space, and starts the next line with `     | `. A check that looks
for a phrase in that text then passes or fails by how long the temp folder's
path is and how wide the console is: on 20 October two checks failed only on
the runners whose profile folder names are 16 characters longer (#2933). A
child whose error a check reads runs with `$global:ErrorView = 'NormalView'`,
which prints the message as written: as the first line of the script it
writes, or through a launcher like `Child` in `test-bad-json-records.ps1`.

## A harness that starts a service

Several builds run at once on the VPS and share its 127.0.0.1, so a harness
never gives a service a fixed port. It asks the system for one nothing holds
(listen on 0 and read the port back) and passes it in through the setting the
service already reads, `THORNSWOOD_VOICE_PORT` or `THORNSWOOD_DOCS_PORT`. A
server in the harness's own process listens on 0 and is asked on the port it
got. One that starts the voice service or the site asks nothing of the port
until that copy has printed its own `[voice] listening on` or
`[thornswood-docs] listening on` line for it, and fails saying so when the
service stops first because something else took the port. Before issue #1703
a run read another run's `/health` as its own, and before #1727 twelve site
harnesses polled the port they had let go until anything answered.
A `.ps1` harness does the same with its `Wait-OwnLine`, which reads the
child's output up to that line, and so does any stand-in it starts on a port
it let go (the GitHub stand-in in `test-site-assets.ps1`, the game server in
`test-record-sync.ps1`); before #1755 five of them drained the output unread
and polled the port. `test-1703-test-ports.js` fails on any `.js` harness here
or in `voice\` that names a fixed port, or on any `.js` or `.ps1` harness that
starts the site without waiting for that line.
