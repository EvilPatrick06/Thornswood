# 3896: the box's own policy holds every firewall rule, and Edge comes off the box

- **Issue / PR:** #3896, the pull request this note came in with.
- **Where:** the box's firewall and the in-box Microsoft Edge. No Ship, no restart, no game, site or bot change.
- **Needs first:** #3807's note (`3807-inbound-rules.md`) has run, so only the rules the box keeps are still on. Patrick's answer on q-3896-local-firewall-rules (the report page, 27 Oct: A and B) is the go ahead.
- **Staff notice:** no. Nothing staff see or do changes.

What it changes, Patrick's A and B:

- **A.** `Set-InboundRules.ps1 -Own` copies every enabled inbound Allow rule
  on the box's list (`records/prod-parity.json` "inboundRules") and every
  enabled Block rule (the runner fences and the RDP block among them) into
  the box's own firewall policy (the local Group Policy store, `-PolicyStore
  localhost`), refreshes Group Policy, reads each back from the policy, and
  only then sets `AllowLocalFirewallRules False` on every profile. From then
  on a rule an installer makes (Edge's and WebView2's mDNS rules, measured
  26 Oct) is ignored. Every script that makes a rule makes it in the policy
  from this pull request on (`scripts/vps/BoxFirewall.ps1` says how).
- **B.** `Harden-VPS.ps1` sets the EdgeUpdate policy
  `Install{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}` 0, so the updater never
  installs Edge again, and runs Edge's own uninstall. The WebView2 Runtime
  stays (the Visual Studio C++ workload requires it) and the updater keeps
  patching it.

Unmeasured, so the run measures it before it changes anything: whether the
store takes a rule under the name `localhost`. The first thing `-Own` does is
make a disabled probe rule in the policy and read it back; if that fails it
says `STOP` and nothing is copied or turned off. This replaces
`/mnt/project-files/threads/3896/probe-policy-store.ps1`, which never ran.

## Run, from the repository root on main after the merge

In a cloud thread, `pwsh scripts/vps/Setup-CloudSsh.ps1` first.

1. **What it would change.**

       pwsh -NoProfile -File scripts/vps/Set-InboundRules.ps1 -Own -WhatIf -NoPause

   Expect three `PROFILE` lines (Domain, Private, Public) taking local rules,
   one `MOVE` line per rule to copy (the eight Thornswood rules, ssh's two,
   the Core Networking ones the list keeps, the runner fences and the RDP
   block), no `REQUIRED` line, `WOULD` for the probe, each copy and local
   rules off, and `DONE <n> change(s) would be made. Nothing was changed.`
   An `IGNORED` line names each local rule that would be left behind (Edge's
   mDNS rules among them). A `STOP` for outbound Block on a profile means the
   box is not as measured: stop and put it on #3896.

2. **Move the rules.**

       pwsh -NoProfile -File scripts/vps/Set-InboundRules.ps1 -Own -NoPause

   Expect `PROBE` lines (made, read back, taken away) first, then a `COPIED`
   and an `ACTIVE ..., from Group Policy` line per rule, `CHANGED the firewall
   ignores local rules`, `ACTIVE every required rule is taken from the policy
   store`, and `DONE <n> change(s) made.` A `STOP` at any point leaves everything
   after it undone; what it says goes on #3896 and the run stops here.

3. **Check.**

       pwsh -NoProfile -File scripts/vps/Set-InboundRules.ps1 -Own -Check -NoPause
       pwsh -NoProfile -File scripts/vps/Set-InboundRules.ps1 -Check -NoPause
       pwsh -NoProfile -File scripts/vps/Check-Site.ps1

   Expect `DONE read only, 0 thing(s) left`, exit 0; then `0 rule(s) outside
   the list, 0 required rule(s) missing or off`, exit 0; and the site
   answering. From One (a cloud thread reaches no raw port), the live and dev
   resources still answer from outside:

       curl.exe -sS -o NUL -w "%{http_code}`n" http://play.thornswood.net:3000/api/servers/thornswood/manifest.json
       curl.exe -sS -o NUL -w "%{http_code}`n" http://play.thornswood.net:7788/api/servers/thornswood/manifest.json

   Each prints 200. If the plain `-Check` names a rule outside the list that
   the firewall now ignores, write that on #3896: it says the active store
   still lists ignored local rules, which is a fact to record, not a port open.

4. **Edge off the box.**

       pwsh -NoProfile -File scripts/vps/Harden-VPS.ps1 -WhatIf -NoPause
       pwsh -NoProfile -File scripts/vps/Harden-VPS.ps1 -NoPause

   The dry run expects `WOULD Install{56EB18F8-...} set to 0 (was not set)`
   and `WOULD Microsoft Edge <version> uninstalled with its own setup`, every
   other line ALREADY (two more WOULD lines if #3213's note has not run yet).
   The real run expects the same as `CHANGED`, with Edge's setup exit code,
   and step 5's PASS lines. sshd_config is already as it wants, so sshd is
   not restarted. If Edge's setup refuses the uninstall, the run says
   `KEPT Microsoft Edge ... is still installed` with the exit code and where
   Edge's log is, and goes on: Edge stays unused and blocked from coming
   back (Patrick, 27 Oct, q-3896-edge-uninstall-refused, A). Put the KEPT
   line and its exit code on #3896.

5. **Parity.**

       pwsh -NoProfile -File scripts/vps/Check-ProdParity.ps1

   Expect each profile's `local rules` row ignored, `Microsoft Edge` not
   installed (or, after a KEPT line in step 4, installed with the updater
   told never to install it, which is not a review row), and no inbound rule row outside the list.

Put what each step printed on #3896. Close #3896 once steps 3 and 5 are clean.

## Risks

- None for anybody on: the game, resources, web and ssh rules are copied and
  read back as taken from the policy before local rules are turned off, and a
  connection already open stays open.
- A rule a script made before this pull request, outside the list, stops
  working once local rules are off. The list is the box's whole set, and step
  1's `IGNORED` lines name every one before it happens.
- The way back for A, on the box:

      Set-NetFirewallProfile -PolicyStore localhost -All -AllowLocalFirewallRules NotConfigured; gpupdate /target:computer /force

  The local rules were never touched, so they apply again at once.
- The way back for B: remove the `Install{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}`
  value under `HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate`, then install
  Edge from microsoft.com/edge/business/download.

## Release notes (draft)

none (box only)

## News post (draft)

none
