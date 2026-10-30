<#
  test-4115-collection-revision-link.ps1

  Every collection button opens the revision the server was built against,
  and a copy ahead of the server is told it has nothing to install (#4115).

  WHY THIS EXISTS. On 30 October Nexus was on collection revision 5 and both
  feeds named revision 2. Every button to the collection opened the feed's
  collectionUrl, the collection's own page with no revision in it, so Nexus
  showed revision 5 and Vortex installed it. Following the "your mods need
  updating" card, or installing fresh, took a copy straight past the server,
  and Play shut again on the ahead card, under INSTALL THE MODS FIRST and a
  tooltip saying to open the collection, which cannot help. The update log
  said "The collection is not installed yet" for all three cases.

  What it checks:
    - Checks.CollectionRevisionUrl makes .../collections/<slug>/revisions/<N>
      from the configured address and the feed's revision, and leaves the
      address as it is with no revision or no collection in it (compiled and
      run with the build's compiler on Windows; SKIP elsewhere);
    - no button, card or box in the launcher opens cfg.CollectionUrl as it
      stands: each goes through CollectionLink;
    - the ahead state has its own Play label and tooltip, saying nothing
      needs installing, and no install button on the bar or the Diagnostics
      card, and a press that slips in opens nothing;
    - the stale and not-installed labels and the button name the revision;
    - the update log and Play's own refusal say which case holds updates;
    - READ ME FIRST says to install the revision the launcher opens.

  Prints PASS or FAIL per check and exits 1 when any check fails.
#>
param([string]$Scratch)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Launcher-Csc.ps1')
$repo = Split-Path -Parent $PSScriptRoot
$app = Join-Path $repo 'launcher\app'
function Src([string]$name) { [IO.File]::ReadAllText((Join-Path $app $name)).Replace("`r", '') }

$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$ok) {
    if ($ok) { $script:pass++; Write-Host ('PASS  ' + $what) }
    else { $script:fail++; Write-Host ('FAIL  ' + $what) }
}
function Method([string]$text, [string]$signature) {
    $start = $text.IndexOf($signature)
    if ($start -lt 0) { return '' }
    $at = $text.IndexOf('{', $start); $depth = 1; $end = $at + 1
    while ($depth -gt 0 -and $end -lt $text.Length) {
        if ($text[$end] -eq '{') { $depth++ }
        if ($text[$end] -eq '}') { $depth-- }
        $end++
    }
    return $text.Substring($start, $end - $start)
}

$checks = Src 'Checks.cs'
$shell = Src 'Shell.cs'
$packs = Src 'ShellPacks.cs'
$play = Src 'ShellPlay.cs'
$update = Src 'ShellUpdate.cs'
$all = $shell + $packs + $play + $update

# ---- where the buttons go ---------------------------------------------------
$urlMethod = Method $checks 'public static string CollectionRevisionUrl(Config cfg, int revision)'
Yes 'Checks.CollectionRevisionUrl exists' ($urlMethod.Length -gt 0)
Yes 'it builds the revision page from the slug' ($urlMethod.Contains('"/revisions/" + revision') -and $urlMethod.Contains('CollectionSlug(cfg)'))
$link = Method $shell 'static string CollectionLink()'
Yes 'Shell.CollectionLink opens the feed''s revision' ($link.Contains('Checks.CollectionRevisionUrl(cfg, Updater.FeedCollectionRevision)'))
Yes 'nothing opens the bare collection address any more' (-not ([regex]::IsMatch($all, 'ProcessStartInfo\(cfg\.CollectionUrl\)')))
Yes 'the bar''s button, the missing-mods box and the cards open CollectionLink' (
    ([regex]::Matches($shell, 'new ProcessStartInfo\(CollectionLink\(\)\)')).Count -eq 1 -and
    ([regex]::Matches($play, 'new ProcessStartInfo\(CollectionLink\(\)\)')).Count -eq 1 -and
    $packs.Contains('string url = CollectionLink();'))
$buttonText = Method $shell 'static string CollectionButtonText()'
Yes 'the button names the revision it opens' ($buttonText.Contains('"Open revision " + wants'))

# ---- ahead ------------------------------------------------------------------
$bar = Method $shell 'static void ShowCollectionBar(int revision = -1)'
Yes 'the ahead card says nothing needs installing' ($bar.Contains('nothing needs installing'))
Yes 'the ahead card has no install button' ($bar.Contains('btnInstallNow.Visibility = problem == "ahead" ? Visibility.Collapsed : Visibility.Visible;'))
$click = $shell.Substring($shell.IndexOf('btnInstallNow.Click += delegate'), 900)
Yes 'a press on the bar''s button while ahead opens nothing' ($click.Contains('if (collectionBarUp && CollectionProblem() == "ahead") return;'))
$draw = Method $shell 'static bool DrawStatus()'
$aheadAt = $draw.IndexOf('CollectionProblem(collectionRevision) == "ahead"')
$installAt = $draw.IndexOf('"INSTALL THE MODS FIRST"')
Yes 'Play has its own label for ahead, ahead of the install label' ($aheadAt -gt 0 -and $installAt -gt $aheadAt -and $draw.Contains('btnPlay.Content = "WAITING FOR THE SERVER";'))
Yes 'its tooltip says nothing needs installing' ($draw.Substring([Math]::Max(0, $aheadAt), 700).Contains('Nothing needs installing.'))
Yes 'a copy behind reads UPDATE THE MODS FIRST' ($draw.Contains('== "stale" ? "UPDATE THE MODS FIRST" : "INSTALL THE MODS FIRST"'))
Yes 'Play is still enabled by the same test' ($draw.Contains('btnPlay.IsEnabled = all && !playing && !updatePending && !collectionBarUp && !ownGameBusy && !working && feedNotice.Hold == null;'))
$status = Method $packs 'static UIElement CollectionStatusCard()'
Yes 'the Diagnostics ahead card has no button' ($status.Contains('installing; Play opens once the server is rebuilt on your revision.", false);'))
Yes 'CollectionCard leaves the button out when asked' ((Method $packs 'static UIElement CollectionCard(string title, string body, bool button = true)').Contains('if (button)'))

# ---- why updates wait -------------------------------------------------------
$wait = Method $shell 'static string[] CollectionWait()'
Yes 'CollectionWait names behind, ahead and not installed' ($wait.Contains('problem == "stale"') -and $wait.Contains('problem == "ahead"') -and $wait.Contains('"The collection is not installed yet."'))
Yes 'the update log no longer says not installed for every case' (-not $update.Contains('Log("The collection is not installed yet'))
Yes 'all three update log lines ask CollectionWait' (([regex]::Matches($update, '= CollectionWait\(\);')).Count -eq 3)
Yes 'Play''s own refusal asks it too' ($play.Contains('string[] wait = CollectionWait();') -and -not $play.Contains('Log("The collection is not installed yet. Open it'))

# ---- what the installer tells people ---------------------------------------
$rmf = [IO.File]::ReadAllText((Join-Path $repo 'installer\READ ME FIRST.txt')) -replace '\s+', ' '
Yes 'READ ME FIRST says to install the revision the launcher opens' ($rmf.Contains('opens the revision the server was built against') -and $rmf.Contains('not a newer one Nexus may show first'))

# ---- the real method, compiled ----------------------------------------------
if (-not $OnWindows) {
    Write-Host 'SKIP  Checks.CollectionRevisionUrl compiled and run: the build''s compiler (the Build Tools'' csc, against .NET Framework 4.8.1) is only on Windows; its source was read above'
} else {
    $slug = Method $checks 'public static string CollectionSlug(Config cfg)'
    $fixture = @'
using System;
namespace Thornswood {
 public class Config { public string CollectionUrl; }
 public static class CollectionLinkFixture {
  __METHODS__
  static string At(string url, int revision) { return CollectionRevisionUrl(new Config { CollectionUrl = url }, revision); }
  public static string Run() {
   string c = "https://www.nexusmods.com/games/skyrimspecialedition/collections/7essxf";
   string[,] want = {
    { At(c, 2), c + "/revisions/2" },
    { At(c + "/", 5), c + "/revisions/5" },
    { At(c + "/revisions/5", 2), c + "/revisions/2" },
    { At(c + "?tab=mods", 3), c + "/revisions/3" },
    { At(c, 0), c },
    { At(c, -1), c },
    { At("https://example/not-a-collection", 2), "https://example/not-a-collection" },
    { At(null, 2), "" },
    { CollectionRevisionUrl(null, 2), "" },
   };
   for (int i = 0; i < want.GetLength(0); i++) if (want[i, 0] != want[i, 1]) return "case " + i + ": " + want[i, 0];
   return "";
  }
 }
}
'@
    $asm = Add-LauncherType -Source ($fixture.Replace('__METHODS__', $slug + "`n" + $urlMethod))
    $said = [string]$asm.GetType('Thornswood.CollectionLinkFixture').GetMethod('Run').Invoke($null, @())
    Yes ('the real CollectionRevisionUrl pins the revision, replaces one already there, and leaves no revision or no collection as it is' + $(if ($said) { ' (' + $said + ')' } else { '' })) ($said -eq '')
}

Write-Host ''
Write-Host ($script:pass.ToString() + ' passed, ' + $script:fail + ' failed')
if ($script:fail) { exit 1 }
exit 0
