# 3806: voice /health says only ok from outside

- **Issue / PR:** #3806, the pull request this note came in with (Refs #3721).
- **Where:** the box, both voice services (dev first, then live). No Ship, no game, no site, no bot, no Caddy change.
- **Needs first:** the merge. Dev voice any time; live voice at the quiet hour (`online.json` on 3000 at 0).
- **Staff notice:** no. Nothing staff do changes; voice drops for a few seconds per service and reconnects on its own.

What it changes: `voice/voice-server.js` answers `/health` with `{"ok":true}`
and nothing more to anything that is not a caller on the box itself (loopback
socket with no X-Forwarded-* header, the same test the gamemode's routes use
since #1797). Caddy writes X-Forwarded-For on everything it carries, so
https://thornswood.net/voice/health and /voice-dev/health stop telling anybody
the build, the deploy record's commit, zip and hash, the bind, TURN state and
the live counts. Get-Logs, Install-Voice, the watchdog and Go.ps1 read the
detail on the box. The build becomes `...-own-reports-1-health-here-1`.

## Run, from the repository root on main after the merge

1. **Before: the site still leaks** (so the after can be told apart). Prints the whole JSON with `build` and `deploy`:

       curl -sS https://thornswood.net/voice-dev/health

2. **Dev voice.** Keeps the running bind, chat range and relay by itself.

       pwsh -NoProfile -File scripts/deploy/Install-Voice.ps1 -Root C:\Thornswood-Voice-Dev -Port 7789 -TaskName 'Thornswood Dev Voice' -NoPause

   Expect `voice is up on 7789 running ...-health-here-1` and
   `Reached it through https://thornswood.net/voice-dev, which says ok.`

3. **Check dev.**

       curl -sS https://thornswood.net/voice-dev/health
       pwsh scripts/vps/Remote.ps1 "(Invoke-WebRequest -UseBasicParsing 'http://127.0.0.1:7789/health').Content"

   The first prints exactly `{"ok":true}`. The second prints the whole
   answer, `build` ending `health-here-1` and `deploy.commit` the merge commit.

4. **Live voice, at the quiet hour.** Read `http://play.thornswood.net:3000/online.json` first, and run when it says 0.

       pwsh -NoProfile -File scripts/deploy/Install-Voice.ps1 -NoPause
       curl -sS https://thornswood.net/voice/health
       pwsh scripts/vps/Remote.ps1 "(Invoke-WebRequest -UseBasicParsing 'http://127.0.0.1:7778/health').Content"

   Same three answers as dev, on 7778.

5. **Get-Logs still gets the detail.**

       pwsh -NoProfile -File scripts/vps/Get-Logs.ps1 -NoPause

   Expect `health.json  build ...health-here-1, asked on the box at 127.0.0.1:7778`
   and `the site carries it: https://thornswood.net/voice/health says ok`.

## Check afterwards

Both public URLs answer `{"ok":true}` and nothing more, and every reader on
the box still gets the detail. Put the output of steps 3 to 5 on #3806, then
close it (box only, no Test task: nobody in the game would notice).

## Risks

- Each Install-Voice restarts that voice service: voice and typed chat drop
  for a few seconds and the pages reconnect on their own. `-PutBack` puts the
  previous files back.
- The launcher's voice line reads only the status code, so it is unchanged.

## Release notes (draft)

none (server only, nothing anybody would notice)

## News post (draft)

none
