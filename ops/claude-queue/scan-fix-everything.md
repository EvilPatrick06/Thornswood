# 2627 Scan and Fix fix everything they can, and our light plugin is served

- **Lane:** Claude (overnight agent, 17 Oct)
- **Issue / PR:** #2627 (and #2403, folded in), #2633 (not merged yet; head 6df689b0)
- **Channel:** dev (dev gamemode, then a dev Ship); main later, on Patrick's word
- **Staff status updates:** #staff-updates (1549254991082946570)
- **Needs first:** #2633 merged on a green `Launcher builds`. Then step 1 before step 2: a launcher that asks for `/plugins/light-<index>.bin` from a server whose gamemode does not publish it gets a 404 and says "the server did not hand over its copy", which is true and harmless, but the fix only works once the gamemode is out.

## Order and risk
1. Deploy-DevGamemode, so the dev server names Thornswood-Last.esp in its manifest's `served` list and publishes it at `/api/servers/thornswood/plugins/light-<index>.bin`. The client never reads `served`, and a launcher before this marks only full plugins as served, so nothing changes for anybody until step 2.
2. A dev Ship, so the dev launcher has the new Scan and Fix.
3. On a dev install (One's `C:\Thornswood-DevBuild` is the one Patrick measured), the check below.
4. Separately, #2403's other half: put One's Steam copy back the way the dev build's first Fix found it on 11 Oct (below). This writes into the Steam copy of Skyrim on One, which is Patrick's own: run it on his word.

## Run
From a fresh worktree at the merge commit or later (not `ops-batch`, not the shared clone's checkout):

    .\scripts\deploy\Deploy-DevGamemode.ps1

Then the dev Ship, with the release notes below:

    .\scripts\release\Ship.ps1 -Channel dev "Scan and Fix put right everything they can find
    - Scan on the Diagnostics page now looks at the whole install: an update waiting, Thornswood's game folder behind Vortex or missing files, this build's own files changed, Windows' Skyrim folders left pointed at Thornswood after a crash, the shortcut icon, the multiplayer client, Steam and the Skyrim build.
    - Fix puts right everything it can, then looks again and says only what is still wrong, why, and what will put it right.
    - Fix now downloads the server's copy of Thornswood's last plugin when you do not have it, and puts it in the server's place in your load order.
    - Fix brings the game folder up to date from Vortex first and takes a waiting update last.
    - The Repair, Restore and Bring it up to date buttons are gone from Diagnostics: Scan and Fix do all three."

With the main Ship that carries this, on Patrick's word, and not before (the site's help page is read by people on the main launcher): the live gamemode (`Deploy-Server.ps1 -GamemodeOnly`, which carries the light publish), and the help page, which says what Scan and Fix do now (`site\data\help.md`); this replaces only that document, after a .bak of the live copy:

    .\scripts\deploy\Deploy-Docs.ps1 -Docs help

## Check afterwards
- After step 1, over http, nothing over ssh:

      (Invoke-WebRequest http://192.135.112.23:7788/api/servers/thornswood/manifest.json -UseBasicParsing).Content | ConvertFrom-Json | Select-Object -ExpandProperty served
      # Expect Thornswood-Content.esp and Thornswood-Last.esp
      $m = (Invoke-WebRequest http://192.135.112.23:7788/api/servers/thornswood/manifest.json -UseBasicParsing).Content | ConvertFrom-Json
      $i = [array]::IndexOf(@($m.light | ForEach-Object { $_.filename }), 'Thornswood-Last.esp'); $i
      (Invoke-WebRequest ("http://192.135.112.23:7788/api/servers/thornswood/plugins/light-" + $i + ".bin") -UseBasicParsing).RawContentLength
      # Expect the size the manifest's light entry for Thornswood-Last.esp gives

  The dev server's log says "[thornswood] 2 of our plugin files published at /api/servers/thornswood/plugins/ for the launcher".
- After step 2, on a dev install that is behind (the Thornswood-Last.esp case, or any): Diagnostics, Scan. The card lists every problem with what Fix does. Press Fix with Skyrim closed. launcher.log shows the folder brought up to date first if it was behind, each step's line, then either "Fix put right everything Scan found." or "Fix is done. Still wrong, and what will put it right:" with one "blocks Play:" or "worth knowing:" line each, and never "Fix put N things right". A waiting update is taken last. The Fix button is greyed when nothing on the card is something Fix can do.
- With no game folder of its own (a fresh dev install before Make it), Scan says only that, and Fix asks to make the folder and writes nothing into the Steam copy.

## Risks and how to put it back
- The gamemode change is the manifest block alone (served list and the light files). `.\scripts\deploy\Deploy-DevGamemode.ps1 -PutBack` puts the previous gamemode back.
- The launcher: the next dev Ship replaces it. Fix runs the same steps the old buttons and Play ran (Bring it up to date, Repair, Restore, the client repair, Keep), now from one button; what is new is fetching our light plugin and switching it on in the server's place, and moving a plugin out of Your Mods into Profile\Isolated (never deleted).
- Fix's Downgrade and own-folder steps ask first, as their buttons always did.

## #2403: One's Steam copy (on Patrick's word)
Measured 17 Oct, read only: `C:\Thornswood-DevBuild\Profile\Isolated\20261011-1750` still holds the 23 Creation Club plugins the dev build's first Fix moved out of the Steam copy on 11 Oct (`*.thornswood-off`, with `restore.txt` naming where each was), none of them is back in `C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition\Data`, and that folder's `Thornswood-Content.esp` is still the 146,446-byte release copy Fix wrote there, not Vortex's. To put them back, from any folder, with Skyrim, Vortex and the launchers closed:

    $bin = 'C:\Thornswood-DevBuild\Profile\Isolated\20261011-1750'
    $lines = Get-Content -LiteralPath (Join-Path $bin 'restore.txt'); for ($i = 0; $i -lt $lines.Count - 1; $i++) { if ($lines[$i] -match 'was: (.+)$') { $was = $Matches[1].Trim(); if ($lines[$i + 1] -match 'now: (.+)$') { $now = $Matches[1].Trim(); if ((Test-Path -LiteralPath $now) -and -not (Test-Path -LiteralPath $was)) { Move-Item -LiteralPath $now -Destination $was; "back: $was" } } } }

It prints one "back:" line for each file it moved, up to 23; a file whose place is taken again is left in the Isolated folder and not printed. Then, in Vortex on the Thornswood profile, Deploy Mods, which puts Vortex's own Thornswood-Content.esp back in the Steam copy (a Vortex step). Check: `(Get-Item 'C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition\Data\Thornswood-Content.esp').Length` is the collection's size (141,023 bytes on 12 Oct), not 146,446. Record what ran on #2403 and close it once #2633 is on main with its test task.

## Release notes (draft)
Scan and Fix put right everything they can find
- Scan on the Diagnostics page now looks at the whole install: an update waiting, Thornswood's game folder behind Vortex or missing files, this build's own files changed, Windows' Skyrim folders left pointed at Thornswood after a crash, the shortcut icon, the multiplayer client, Steam and the Skyrim build.
- Fix puts right everything it can, then looks again and says only what is still wrong, why, and what will put it right.
- Fix now downloads the server's copy of Thornswood's last plugin when you do not have it, and puts it in the server's place in your load order.
- Fix brings the game folder up to date from Vortex first and takes a waiting update last.
- The Repair, Restore and Bring it up to date buttons are gone from Diagnostics: Scan and Fix do all three.

## News post (draft)
none (the release notes carry it)

## Test task (draft, for closing the issue once the fix is on main)
Test task: Scan and Fix put things right
Server: Main
1. Close Skyrim. In the launcher, open Diagnostics and press Scan.
2. If the card lists anything, press Fix and wait until the launcher has finished.
3. Read the card and the last lines of the launcher log (Settings, Open log).
What should happen: Fix puts right what the card listed, then the card says everything is put right, or lists only what is still wrong, each with what will put it right. It never just says how many things it did. Play works afterwards unless the card says why not.

## Ran
- 17 Oct 2:18 PM (Claude): Deploy-DevGamemode from 18a836da (SWAP OK; the dev server serves Thornswood-Last.esp at /api/servers/thornswood/plugins/light-54.bin, 5,984,128 bytes), dev release 20261017-141806-dev (launcher 1.2.4.11). Left: the live gamemode and `Deploy-Docs.ps1 -Docs help` with the main Ship, and #2403's Steam copy step, both on Patrick's word.

- 17 Oct (Claude): #2403 step run on Patrick's yes: all 23 Creation Club plugins back in the Steam copy. Left: Patrick presses Deploy Mods in Vortex (Thornswood profile).
