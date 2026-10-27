# 3807: the box turns off every inbound rule nothing uses

- **Issue / PR:** #3807, the pull request this note came in with.
- **Where:** the box's firewall only. No Ship, no restart, no game, site or bot change.
- **Needs first:** nothing. The merge is the go ahead: it only turns off rules for ports nothing on the box serves, and keeps every rule the game, the site and ssh use.
- **Staff notice:** no. Nothing staff see or do changes.

What it changes: `Set-InboundRules.ps1` turns off every enabled inbound Allow
rule that `records/prod-parity.json` "inboundRules" does not list. Measured
read only from a cloud thread on 26 Oct 2026, 6:50 PM MT (the dry run below):
40 rules, among them "Allow WinRM HTTPS" (TCP 5986 from any address, made by
hand before 22 Oct, no group or description; the WinRM service is already
stopped and set to Disabled, so nothing listens there), "SkyMP game UDP 7777"
and "SkyMP web TCP 3000" (old copies of the Thornswood game rules), Teredo,
IP-HTTPS and IPv6-in-IPv4 (the box has no IPv6 address but link-local, so no
tunnel is in use), Delivery Optimization, DIAL, Cast to Device, AllJoyn, mDNS,
Media Foundation and the Store apps' own rules. Kept: the eight Thornswood
game, dev game and web rules (required: if one is missing or off the run stops
before anything changes), both ssh rules (127.0.0.1 only), and Windows' Core
Networking rules for DHCP, ICMPv6 and path MTU.

## Run, from the repository root on main after the merge

In a cloud thread, `pwsh scripts/vps/Setup-CloudSsh.ps1` first.

1. **What it would change.**

       pwsh -NoProfile -File scripts/vps/Set-InboundRules.ps1 -WhatIf -NoPause

   Expect `DONE 40 change(s) would be made. Nothing was changed.` (more if a
   new rule appeared since), one `WOULD turn off` line per rule, and no
   `REQUIRED` line. Six Store app rules (Start, Windows Search and the like)
   are among the 40.

2. **Turn them off.**

       pwsh -NoProfile -File scripts/vps/Set-InboundRules.ps1 -NoPause

   Expect `DONE 40 change(s) made.` and a `CHANGED turned off` line each.

3. **Check.**

       pwsh -NoProfile -File scripts/vps/Set-InboundRules.ps1 -Check -NoPause
       pwsh -NoProfile -File scripts/vps/Check-Site.ps1

   Expect `0 rule(s) outside the list, 0 required rule(s) missing or off`,
   exit 0, and the site answering. From One (a cloud thread reaches no raw
   port), the live and dev resources still answer from outside:

       curl.exe -sS -o NUL -w "%{http_code}`n" http://play.thornswood.net:3000/api/servers/thornswood/manifest.json
       curl.exe -sS -o NUL -w "%{http_code}`n" http://play.thornswood.net:7788/api/servers/thornswood/manifest.json

   Each prints 200.

Put what each step printed on #3807. Close #3807 once step 3 is clean.

## Risks

- None for anybody on: the game, resources, web and ssh rules stay as they
  are, and a connection already open stays open.
- The way back for one rule, on the box: `Enable-NetFirewallRule -Name '<Name from its CHANGED line>'`.
- Edge's updater adds a "Microsoft Edge (mDNS-In)" rule for each new version
  (the firewall log shows one added 24 Oct 2026 by its setup.exe). After a
  run, a new one shows in `Set-InboundRules.ps1 -Check` and
  `Check-ProdParity.ps1`; that is #3896.

## Release notes (draft)

none (box only)

## News post (draft)

none
