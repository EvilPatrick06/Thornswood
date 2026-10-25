# 3213: the restart an update needs comes in 4 AM to 6 AM

- **Issue / PR:** #3213, the pull request this note came in with.
- **Where:** the box (Windows Update policy only). No Ship, no game, no site, no bot.
- **Needs first:** Patrick's answer on q-3213-tonight-restart (the report page, 23 Oct). Option A is the default if he has not answered by tonight: change nothing before Windows' own 2:33 AM restart, and apply this afterwards.
- **Staff notice:** no. Nothing staff do changes, and a restart in 4 AM to 6 AM is the decided window.

What it changes: `vps-harden.ps1` sets `AlwaysAutoRebootAtScheduledTime 1` and
`AlwaysAutoRebootAtScheduledTimeMinutes 15`, so Windows restarts 15 minutes
after the 4 AM install of an update that needs it, about 4:20 AM, instead of
whenever it chooses outside active hours. Measured on 23 Oct: the 4 AM install
needed a restart at 4:06 AM, and Windows set `UpdateOrchestrator\Reboot_AC`
for 2:33:33 AM on 24 Oct. These values do not move a restart Windows set
before they were, so the run reads Reboot_AC and says WARN when it stands
outside the window.

## Run, from the repository root on main after the merge

Under option A, after Windows' 2:33 AM restart on 24 Oct:

1. **The box came back.** `LastBootUpTime` after 2:33 AM, and the servers, the bot and the site up:

       pwsh scripts/vps/Remote.ps1 "(Get-CimInstance Win32_OperatingSystem).LastBootUpTime"
       curl -sS -o /dev/null -w '%{http_code}\n' https://thornswood.net/feed-dev/version.json

   Put what is down on #3213 before step 2.

2. **What it would change.**

       pwsh -NoProfile -File scripts/vps/Harden-VPS.ps1 -WhatIf -NoPause

   Expect `DONE 2 change(s) would be made`: the two AlwaysAutoReboot values,
   every other line ALREADY, and `ALREADY Windows has no restart for an update set`.

3. **Set it.**

       pwsh -NoProfile -File scripts/vps/Harden-VPS.ps1 -NoPause

   Expect `DONE 2 change(s) made.` and step 5's three PASS lines. sshd_config is
   already as it wants, so sshd is not restarted.

Under option B or C the same steps 2 and 3 run as soon as he answers (C after
its restart).

## Check afterwards

The next 4 AM install that needs a restart: `LastBootUpTime` between 4 AM and
6 AM that morning, and no Reboot_AC run outside that window. Put it on #3213,
then close it.

## Risks

- Windows restarts the box about 15 minutes after a 4 AM install that needs one,
  whoever is on. Nobody is on before 7 AM; that is the decided window.

## Release notes (draft)

none (box only)

## News post (draft)

none
