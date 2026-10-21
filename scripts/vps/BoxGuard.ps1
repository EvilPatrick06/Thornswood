<#
  BoxGuard.ps1

  What a box script asks before it changes anything: is this the box?
  Get-ThornswoodBoxRefusal answers '' on the box and, anywhere else, the
  reason the script refuses, for the script to say in its own way with what
  it did not do.

  WHY IT EXISTS (issue #3041). Five box scripts (Bootstrap-VPS,
  Clear-OldWorldCopies, Delete-Person, Lock-VpsFolders and
  Install-ThornswoodServer) refused a gaming PC by looking for one file,
  C:\Thornswood\Game\SkyrimSE.exe. The setup program installs on whichever
  drive a person picks, in whichever folder (its drive buttons and its folder
  picker, installer\setup\Bootstrap.cs), so a gaming PC with its launcher on
  D: had no file there and the guard let the script run on it. Three more
  (vps-harden, vps-time-wait and vps-ssh-scope) asked Windows what the
  machine is, and went ahead when Windows did not answer. Eight copies of one
  question, answered two ways, each changed by hand.

  THE RULE. The box is Windows Server; a gaming PC, and every developer's
  machine here, is a Windows workstation (Windows 10 or 11). Windows says
  which in Win32_OperatingSystem.ProductType: 1 a workstation, 2 a domain
  controller, 3 a server. So a box script goes ahead where it is 2 or 3 and
  refuses everywhere else, including where it cannot be read: a guard that
  waves a script through when it cannot tell is no guard. It looks for
  neither the game nor the launcher, because neither has one place to be,
  and a gaming PC with no launcher on it yet is a gaming PC all the same.
  The tests that run a box script on a developer's machine pass the
  script's own -AllowGamingPc, and nothing else does.

  ONE PLACE, CARRIED. A box script runs on the box with nothing beside it
  (Remote.ps1 -File sends its text; Publish-Server.ps1 and Restore-Box.ps1
  copy it up alone), so it cannot dot-source this file. Each carries an
  exact copy of the function between the lines
      # ---- BoxGuard.ps1 (copy) ----
      # ---- end BoxGuard.ps1 ----
  the way Install-ThornswoodServer.ps1 carries ServiceAccount.ps1. A change
  is made here and written into every copy with
      pwsh -NoProfile -File scripts\dev\Copy-BoxGuard.ps1
  and tests\test-3041-box-guard.ps1 fails while a copy differs, when a script
  asks for ProductType anywhere else, and when the rule answers wrong with
  Windows' answer stood in for.
#>

function Get-ThornswoodBoxRefusal {
    # scripts\vps\BoxGuard.ps1 says why this asks Windows rather than looking
    # for the game, and why it refuses when it cannot tell (#3041).
    try { $type = [int](Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).ProductType }
    catch { return ('Windows did not say whether this is a server (' + $_.Exception.Message + '), so it is not taken for the box') }
    if ($type -eq 2 -or $type -eq 3) { return '' }
    if ($type -eq 1) { return 'this is a Windows workstation, a gaming PC or a developer''s machine, not the box' }
    return ('Windows gives this machine product type ' + $type + ', which is not a server, so it is not taken for the box')
}
