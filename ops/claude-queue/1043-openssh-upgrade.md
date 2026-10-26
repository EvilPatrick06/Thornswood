# 1043: the box's OpenSSH upgraded, so ssh gets a post-quantum key exchange

- **Issue / PR:** #1043, the pull request this note came in with.
- **Where:** the box's sshd only. No Ship, no game, no site, no bot.
- **Needs first:** nothing from Patrick. He chose A on 22 Oct 2026 (#1043): the
  Desk upgrades OpenSSH at the box's restart window, checks the host key and
  checks ssh connects with no warning.
- **Staff notice:** no. Staff do nothing differently, and ssh is down only for
  the agents and lanes, for a minute or two, in the quiet hours.

Cause, in one sentence: Windows Server 2022's own OpenSSH for Windows 9.5,
which the box runs, was built by Microsoft without any post-quantum key
exchange (its `config.h.vs` leaves `USE_SNTRUP761X25519` out), so every ssh
from an OpenSSH 10 client warns, and Microsoft's 10.4 MSI is built with
mlkem768x25519 and sntrup761x25519. Measured on 26 Oct 2026, read only: the
box's `ssh -Q kex` lists no post-quantum algorithm, `sshd -T` offers
curve25519, ecdh and diffie-hellman only, and sshd_config does not set
`KexAlgorithms`.

What it changes: `scripts/vps/Upgrade-OpenSsh.ps1` has the box remove the
OpenSSH.Server and OpenSSH.Client capabilities and install Microsoft's
`OpenSSH-Win64-v10.4.0.0.msi` (pinned SHA256, Microsoft's signature checked),
keeping `C:\ProgramData\ssh` (host keys, sshd_config,
administrators_authorized_keys) as it is, both port 22 rules at 127.0.0.1, and
ssh-agent Disabled. A put back task returns the box to the inbox sshd by itself
25 minutes after the swap unless a new login with the pinned host key proves
the new one. `-WhatIf` ran against the box from a cloud thread at about 9:15 PM on
25 Oct 2026 (Patrick's time) and said `DONE 2 change(s) would be made`, with
`ALREADY sshd reads the 3 pinned host keys` and
`ALREADY OpenSSH-Win64-v10.4.0.0.msi matches its pinned SHA256 and is signed by O=Microsoft Corporation`,
and left nothing on the box.

## When

In the box's 4 AM to 6 AM window, after that morning's 4 AM update install
and any restart it needed (about 4:20 AM), and only when nothing is talking
to the box: both servers' `online.json` at 0, no Ship, deploy, backup or
lane run going. The swap cuts every ssh session, the bridge's included.

## Run, from the repository root on main after the merge

On One, or in a cloud thread after `pwsh scripts/vps/Setup-CloudSsh.ps1`.

1. **Nobody on, and the box settled.**

       curl -sS http://192.135.112.23:3000/online.json
       curl -sS http://192.135.112.23:7788/online.json
       pwsh scripts/vps/Remote.ps1 "(Get-CimInstance Win32_OperatingSystem).LastBootUpTime; (Get-ScheduledTask -TaskPath '\Microsoft\Windows\UpdateOrchestrator\' -TaskName Reboot_AC | Get-ScheduledTaskInfo).NextRunTime"

   Expect 0 online on both, and no `Reboot_AC` set for the next hour. If one
   is, wait for that restart first.

2. **What it would change.**

       pwsh -NoProfile -File scripts/vps/Upgrade-OpenSsh.ps1 -WhatIf -NoPause

   Expect step 3 `OpenSSH_for_Windows_9.5, curve25519-sha256, not post-quantum`,
   the two `ALREADY` lines above, two `WOULD` lines and `DONE 2 change(s) would be made`.

3. **Upgrade it.**

       pwsh -NoProfile -File scripts/vps/Upgrade-OpenSsh.ps1 -NoPause

   Expect step 4 to arm both tasks, step 5 a few `sshd is not answering yet`
   lines, then step 6 the swap's log ending `CHANGED sshd 10.4.0.0 is running`,
   and step 7:

       PASS  a new login gets in, so the box showed a pinned host key
       PASS  it negotiated a post-quantum key exchange (sntrup761x25519-sha512 or mlkem768x25519-sha256)
       PASS  the box says OpenSSH_for_Windows_10.4

   and step 8 `CHANGED 'Thornswood OpenSSH put back' cancelled`. A cloud
   thread's ssh (Ubuntu's 9.6) agrees on sntrup761x25519-sha512; One's 10.3
   on mlkem768x25519-sha256.

   If it stops anywhere after step 4, the put back runs by itself (at once
   when the swap failed, otherwise 25 minutes after step 4). Then:

       pwsh -NoProfile -File scripts/vps/Upgrade-OpenSsh.ps1 -Report -NoPause

   and put everything it printed on #1043. If ssh is still refused 30 minutes
   after step 4, the way back is the provider's console:
   `Get-Help ./scripts/vps/Upgrade-OpenSsh.ps1 -Full`, THE WAY BACK.

## Check afterwards

1. From One (the machine that saw the warning), one ssh with no warning:

       ssh -v Administrator@192.135.112.23 exit 2>&1 | Select-String 'kex: algorithm|post-quantum|remote software'

   Expect `kex: algorithm: mlkem768x25519-sha256`,
   `remote software version OpenSSH_for_Windows_10.4`, and no `post-quantum`
   line.
2. `pwsh -NoProfile -File scripts/vps/Harden-VPS.ps1 -WhatIf -NoPause`: every
   sshd line ALREADY, since vps-harden.ps1 now checks sshd_config with the
   sshd the service runs, not the inbox path.
3. If step 6 said `WARN Windows finishes removing the old files at its next
   restart`, after the next 4 AM restart:
   `pwsh scripts/vps/Remote.ps1 "Test-Path C:\Windows\System32\OpenSSH\sshd.exe"` says False.

Put what ran, when, what it printed and these checks on #1043 and in
`ops/status.md`, and delete this note. The pull request that drops the
scripts' filters for the post-quantum warning (they hid this warning instead
of fixing it) merges after this run, not before: until the box offers a
post-quantum key exchange those lines are still printed. #1043 closes with
that merge.

## Risks

- ssh to the box is down for the swap, about one to three minutes: every
  agent, lane and the bridge. The game, voice, site and bot are not touched.
- A swap that cannot finish leaves the inbox sshd put back by the task; one
  that leaves no sshd at all is reached through the provider's console.

## Release notes (draft)

none (box only)

## News post (draft)

none
