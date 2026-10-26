# 1178 Other authors' files our old packs shipped leave every install

- **Lane:** Claude (cloud issue thread)
- **Issue / PR:** #1178, the pull request that adds this note.
- **Box:** One (the Steam copy step), then the next dev Ship and the next main Ship.
- **Needs first:** the pull request merged. Patrick approved the Steam-copy scrub, its removal and the in-game check on 21 Oct (board review #3192).

What changed: `records\shipped-not-ours.json` names 165 of the 166 files (67.6 MB) of other authors that our packs shipped until the scrub of 29 Sep, each at the sha256 it had. The 166th, the other server's haybale, cannot be named in any tracked file (#400), so the launcher's `Leaks.cs` takes it out of Thornswood's own folder by its shape and bytes at every start; that part needs the new launcher, which the dev Ship carries. Publish-Update now puts every one in each release record as `:gone:<path>` at that sha256. The launcher's sync (#1261) deletes such a file only while it still has those bytes and Vortex does not deploy the path, so a copy somebody installed themselves is never touched. No release before this one listed them, so every install the old packs reached still has them, One's main install `C:\Thornswood\Game` included.

## Order and risk

1. The next dev Ship carries the lines by itself; nothing extra to run for it. Ship-Rules stops the Ship, naming the file, if the record ever names something that is not another author's loose file.
2. The Steam copy on One: `Profile\OwnGame` never takes a hand-placed file from it, so nothing flows back, but the issue's Done when asks for it to be clean. The run below deletes only a file whose bytes match the record and which Vortex does not deploy, the same rule as the launcher, and prints every path it touched.
3. The main Ship that follows (when Patrick says) carries the lines to main; One's `C:\Thornswood\Game` is cleaned by its own launcher on the next update after that.

Risk: none to anybody's own files (sha256 match plus the Vortex check). The files leaving are other mods' copies the collection either provides itself or never should have had: RaceMenu's loose interface, IED, old MCM Helper scripts, body refits, the other server's haybale, a Creation Kit face tint export.

## Run

Step 2, on One, from a worktree at the merge commit or later (PowerShell 7):

    $steam = 'C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition'
    $doc = Get-Content -Raw .\records\shipped-not-ours.json | ConvertFrom-Json
    $dep = Get-Content -Raw (Join-Path $steam 'Data\vortex.deployment.json') | ConvertFrom-Json
    $vortex = @{}; foreach ($f in $dep.files) { $vortex['Data\' + $f.relPath] = $true }
    foreach ($p in $doc.files.PSObject.Properties) {
        $full = Join-Path $steam $p.Name
        if (-not (Test-Path -LiteralPath $full) -or $vortex.ContainsKey($p.Name)) { continue }
        if ((Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash -ne $p.Value.sha256) { "kept (other bytes): $($p.Name)"; continue }
        Remove-Item -LiteralPath $full; "removed: $($p.Name)"
    }

It prints one line per file it found. On 12 Oct the Steam copy still had the two face tint `.tga` files, so expect those two `removed:` lines and nothing else.

## Check afterwards

- The dev record the next dev Ship writes has `:gone:` lines at a 64 hex value for the 165 paths of the record (`Data\Scripts\MCM_ConfigBase.pex` = `0bf7f4e5...`), less any path the release ships.
- On a dev install that took the old packs, the dev launcher's log says `removed Data\...` for each such file it had, and a line that it removed a file another server made, and the files are gone.
- In game on dev, the check the issue still owes: nothing visible changed (male faces and beards, hoods and robes, the noble end table, travel clothes, the character menu). That needs a human dev client; post it as a Dev test task.

## Draft release notes

Old copies of other mods' files that earlier updates left in the game folder are cleaned up, so they no longer override the collection's own versions.
