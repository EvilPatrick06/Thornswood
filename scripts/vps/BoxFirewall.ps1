<#
  BoxFirewall.ps1

  Where the box keeps its firewall rules, and how a change to them takes
  effect (#3896).

  WHY. Until #3896 every rule on the box was a local rule, and the firewall
  took every local rule any installer made. Edge's setup adds an inbound
  "Microsoft Edge (mDNS-In)" rule with every new version, and the WebView2
  Runtime's setup (which the Visual Studio C++ workload requires, so it stays)
  adds one per version and never removes the old ones. Chromium's installer
  adds that rule with no policy or check in the way (install_worker.cc,
  firewall_manager_win.cc), and any other installer can do the same. Patrick,
  27 Oct 2026, on the report page: A, the box's own policy holds every rule
  and local rules are ignored, plus B, Edge off the box.

  THE RULE. Every Thornswood firewall rule lives in the box's local Group
  Policy store, which PowerShell calls -PolicyStore localhost, and the
  firewall is told to ignore local rules (AllowLocalFirewallRules False in
  that store, set by Set-InboundRules.ps1 -Own). So:
    - a script that makes, changes, turns on or off, or takes away a rule
      names -PolicyStore localhost, and after its last change runs
      Sync-ThornswoodFirewall, which refreshes Group Policy so the firewall
      takes what the store now holds;
    - a script that reads what the firewall does reads -PolicyStore
      ActiveStore, and one that reads what the box's policy holds reads
      -PolicyStore localhost. A read with no store reads the local store,
      which the firewall ignores.
  tests\test-3896-firewall-policy.ps1 fails on a firewall command in
  scripts\ that names no store, on a script that changes the store and never
  refreshes, and on a copy of Sync-ThornswoodFirewall that differs from this.

  ONE PLACE, CARRIED. A box script runs on the box with nothing beside it, so
  each one that changes a rule carries an exact copy of the function between
  the lines
      # ---- BoxFirewall.ps1 (copy) ----
      # ---- end BoxFirewall.ps1 ----
  the way they carry BoxGuard.ps1, and a script that builds its box code on
  this machine puts Get-ThornswoodFirewallScript's text into it. A change is
  made here and written into every copy with
      pwsh -NoProfile -File scripts\dev\Copy-BoxGuard.ps1 -Source BoxFirewall
#>

function Sync-ThornswoodFirewall {
    # scripts\vps\BoxFirewall.ps1 (#3896): the firewall takes the box's policy
    # store when Group Policy is refreshed, so every change to the store ends here.
    $was = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $said = @(& gpupdate.exe /target:computer /force 2>&1 | ForEach-Object { [string]$_ } | Where-Object { $_.Trim() })
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $was
    if ($rc -ne 0) { throw ('gpupdate did not refresh the box''s policy, so the firewall has not taken the change (exit ' + $rc + '): ' + ($said -join ' ')) }
}

# The function above as text, for box code built on this machine.
function Get-ThornswoodFirewallScript {
    return ('function Sync-ThornswoodFirewall {' + (Get-Item 'function:Sync-ThornswoodFirewall').ScriptBlock.ToString() + "}`r`n")
}
