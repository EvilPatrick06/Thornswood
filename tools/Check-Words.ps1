<#
  Check-Words.ps1

  The Words section of CONTRIBUTING.md, checked instead of hoped for: no em dashes
  anywhere written for people, never the word player, and the owner is
  Patrick. Entry 237 on the To Do List: "it is the only way a rule about
  writing survives two people and a deadline."

  MEASURED 24 September, before the fixes that came with it: eleven hits over
  the files below. Five em dashes in README.md (37, 55, 69, 72, 78) and one in
  SETUP.md:46. The word at README.md:3, tools/app/Help.cs:207, the rules page
  at 295, and the Known Issues and Help pages (known.md:49, help.md:121),
  which the site serves to anybody without a sign in. The old owner name had
  none. Since then main deleted SETUP.md (#265) and rewrote README.md for
  the people who work on the repository, so SETUP.md is off the list below
  and SECURITY.md, the page GitHub shows anybody reporting a hole, is on it.

  What it reads is the files that are text for people from end to end: the
  README and the security page, the launcher's help and window, the bot's
  channel posts, the public site pages, and the two data pages the site
  serves in public (PUBLIC_DOCS in tools/docs-app/server.js). Not lore\,
  where in-world writing is not operational text. Not the code files either
  (the gamemode, the overlays, the rest of the launcher): a word check there
  fires on identifiers and engine names like player.moveto, and those are
  not text for people.

  The em dash is built from its code point, [char]0x2014, plus its HTML
  entities, and never pasted in, so this file's own encoding cannot decide
  whether the check works. Measured while writing it: the first draft spelled
  it as a regex escape, the tool that wrote the file turned that escape into
  the character itself, and Windows PowerShell 5.1, reading this file as
  ANSI, then found none of the six em dashes that were there. So the pattern
  has no escape to lose, and test-check-words.ps1 fails on any byte in this
  file that is not plain ASCII. Each file is read as UTF-8 on purpose: Windows
  PowerShell 5.1 reads a file with no byte order mark as ANSI, and would
  never see an em dash in one. En dashes and hyphens are allowed. The word has
  a boundary on each side, so multiplayer, playtest and getPlayer pass.

  Read only. Each hit prints as ::error file=,line= so GitHub marks the line
  on the pull request, and any hit exits 1. There is no fix mode, which is
  why a Claude may run it.
#>
[CmdletBinding()]
param([string]$Root)

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $Root) { $Root = Split-Path -Parent $Here }

$Paths = @(
    'README.md', 'SECURITY.md', 'tools/app/Help.cs', 'tools/ui.xaml', 'tools/discord/content.py',
    'tools/docs-app/data/site/*.md', 'tools/docs-app/data/known.md', 'tools/docs-app/data/help.md',
    'tools/docs-app/public/home.html'
)
$Rules = @(
    @{ Re = ([string][char]0x2014) + '|&mdash;|&#0*8212;|&#x0*2014;'; Say = 'an em dash. Use a comma, a colon or a full stop.' },
    @{ Re = '\bplayers?\b'; Say = 'the word player. Say customers, clients, people, testers or partners.' },
    @{ Re = '\bgavin\b'; Say = 'the old owner name. He is Patrick.' }
)

$hits = 0; $read = 0
foreach ($p in $Paths) {
    $files = @(Get-ChildItem -Path (Join-Path $Root $p) -File -ErrorAction SilentlyContinue)
    if (-not $files.Count) { Write-Host ("::warning::{0} is not there, so it was not checked" -f $p); continue }
    foreach ($f in $files) {
        $read++
        $rel = $p
        if ($p.Contains('*')) { $rel = $p.Substring(0, $p.LastIndexOf('/') + 1) + $f.Name }
        $lines = [System.IO.File]::ReadAllLines($f.FullName, [System.Text.Encoding]::UTF8)
        for ($i = 0; $i -lt $lines.Count; $i++) {
            foreach ($r in $Rules) {
                if ([regex]::IsMatch($lines[$i], $r.Re, 'IgnoreCase')) {
                    $hits++
                    Write-Host ("::error file={0},line={1}::{2}" -f $rel, ($i + 1), $r.Say)
                }
            }
        }
    }
}

if ($hits) {
    Write-Host ("{0} hit(s) in the {1} file(s) read. The rules are the Words section of CONTRIBUTING.md." -f $hits, $read)
    exit 1
}
Write-Host ("the writing rules hold in all {0} file(s) read" -f $read)
exit 0
