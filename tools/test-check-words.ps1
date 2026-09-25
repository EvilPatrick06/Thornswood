<#
  test-check-words.ps1

  The writing rules in CLAUDE.md are checked, and the check itself works.

  WHY THIS EXISTS. Entry 237 on the To Do List: "The repo's own writing rules
  are written down and nothing enforces them." MEASURED 24 SEPTEMBER, before
  tools\Check-Words.ps1 existed: eleven hits in the files people read. Five
  em dashes in README.md and one in SETUP.md, and the word the rules ban in
  README.md, the launcher's help, the rules page, and the Known Issues and
  Help pages the site serves in public.

  And one trap measured while writing the check. The first draft spelled the
  em dash as a regex escape; the tool that wrote the file turned the escape
  into the character itself, and Windows PowerShell 5.1, which reads a script
  with no byte order mark as ANSI, then found none of the six em dashes that
  were there, while PowerShell 7 found all of them. So this runs the check
  under both, on the same seeded files, and asks for the same answer.

  What it proves:
    - the repository as it stands passes, which it did not before the fixes;
    - every seeded break is reported at its own file and line, and nothing
      that is allowed is (multiplayer, playtest, getPlayer, an en dash);
    - the check exits 1 on a hit and 0 when clean;
    - it writes nothing, because a Check-*.ps1 is read only;
    - its own source is plain ASCII, so no editor can change what it matches.

  Read only apart from files under its own temp folder.
#>
[CmdletBinding()]
param([string]$CheckPath)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $CheckPath) { $CheckPath = Join-Path $Here 'Check-Words.ps1' }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}

Yes 'tools\Check-Words.ps1 exists' (Test-Path -LiteralPath $CheckPath)
if (-not (Test-Path -LiteralPath $CheckPath)) { Done }

$bytes = [System.IO.File]::ReadAllBytes($CheckPath)
$high = @($bytes | Where-Object { $_ -gt 127 }).Count
Yes ("the check's own source is plain ASCII, so its encoding cannot change what it matches ({0} byte(s) above 127)" -f $high) ($high -eq 0)

# Run the check in a fresh process, the way the build step and a person run
# it, and hand back its exit code, its hits as file:line, and its output.
function Invoke-Check([string]$exe, [string]$root) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $CheckPath)
    if ($root) { $a += @('-Root', $root) }
    $out = @(& $exe @a 2>&1 | ForEach-Object { "$_" })
    $code = $LASTEXITCODE
    $hits = @($out | ForEach-Object {
        $m = [regex]::Match($_, '^::error file=([^,]+),line=(\d+)::')
        if ($m.Success) { $m.Groups[1].Value + ':' + $m.Groups[2].Value }
    } | Sort-Object)
    return @{ Code = $code; Hits = $hits; Out = $out }
}

$self = (Get-Process -Id $PID).Path

# ---- the repository itself ------------------------------------------------
$r = Invoke-Check $self $null
foreach ($h in $r.Hits) { Write-Host ("      " + $h) }
Yes ('the repository keeps the writing rules: no hits, exit 0 (exit ' + $r.Code + ', ' + $r.Hits.Count + ' hit(s))') ($r.Code -eq 0 -and $r.Hits.Count -eq 0)

# ---- a seeded copy of every path the check reads ----------------------------
#
# Built from code points, never typed, for the same reason the check is.
$em = [string][char]0x2014
$en = [string][char]0x2013
$utf8 = New-Object System.Text.UTF8Encoding($false)
$utf8bom = New-Object System.Text.UTF8Encoding($true)

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('ts-check-words-' + [guid]::NewGuid().ToString('N'))
function Put([string]$rel, [string[]]$lines, $enc) {
    $full = Join-Path $tmp $rel
    $dir = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if (-not $enc) { $enc = $utf8 }
    [System.IO.File]::WriteAllText($full, (($lines -join "`r`n") + "`r`n"), $enc)
}

try {
    Put 'README.md' @(
        '# Seeded',
        ('Co-op for five' + $em + 'people.'),
        'Every Player gets a horse.',
        "The players' horses are shared.",
        'A multiplayer engine, a playtest, getPlayer() and PlayerCharacter.',
        ('Pages 1' + $en + '5 and a well-known name, both fine.'),
        'Ask gavin about it.'
    )
    Put 'SECURITY.md' @('Fine.', 'An entity &mdash; here.', 'A number &#8212; here.', 'A hex one &#x2014; here.', 'Fine again.')
    Put 'tools/app/Help.cs' @('new HelpItem("x", "fine"),', 'new HelpItem("y", "a single-player game"),')
    # With a byte order mark, which the check has to read through.
    Put 'tools/ui.xaml' @('<TextBlock x:Name="PlayerList" Text="the multiplayer client"/>', ('<TextBlock Text="one' + $em + 'two"/>')) $utf8bom
    Put 'tools/discord/content.py' @('WELCOME = """', 'Nothing wrong here.', '"""')
    Put 'tools/docs-app/data/site/a.md' @('Fine.', ('Not' + $em + 'fine.'))
    Put 'tools/docs-app/data/site/b.md' @('Fine, with a hyphen - and nothing else.')
    Put 'tools/docs-app/data/known.md' @('| A | B |', '| a player save | why |')
    Put 'tools/docs-app/data/help.md' @('Fine.')
    Put 'tools/docs-app/public/home.html' @('<html>', '<body>', '<p>one &mdash; two</p>', '</body>', '</html>')

    $want = @(
        'README.md:2', 'README.md:3', 'README.md:4', 'README.md:7',
        'SECURITY.md:2', 'SECURITY.md:3', 'SECURITY.md:4',
        'tools/app/Help.cs:2',
        'tools/ui.xaml:2',
        'tools/docs-app/data/site/a.md:2',
        'tools/docs-app/data/known.md:2',
        'tools/docs-app/public/home.html:3'
    ) | Sort-Object

    $before = @{}
    foreach ($f in (Get-ChildItem -Path $tmp -Recurse -File)) { $before[$f.FullName] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash }

    $s = Invoke-Check $self $tmp
    $missing = @($want | Where-Object { $s.Hits -notcontains $_ })
    $extra = @($s.Hits | Where-Object { $want -notcontains $_ })
    foreach ($m in $missing) { Write-Host ("      not reported: " + $m) }
    foreach ($x in $extra) { Write-Host ("      reported but allowed: " + $x) }
    Yes ('every seeded break is reported at its own file and line (' + $want.Count + ' wanted, ' + $s.Hits.Count + ' reported)') ($missing.Count -eq 0)
    Yes 'nothing allowed is reported: multiplayer, playtest, getPlayer, PlayerCharacter, an en dash, a hyphen' ($extra.Count -eq 0)
    Yes ('a hit exits 1 (exit ' + $s.Code + ')') ($s.Code -eq 1)
    Yes 'a file with a byte order mark is read through it' ($s.Hits -contains 'tools/ui.xaml:2')
    Yes 'a page under the site glob is named by its own path' ($s.Hits -contains 'tools/docs-app/data/site/a.md:2')

    $after = @{}
    foreach ($f in (Get-ChildItem -Path $tmp -Recurse -File)) { $after[$f.FullName] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash }
    $same = ($before.Count -eq $after.Count)
    foreach ($k in $before.Keys) { if ($after[$k] -ne $before[$k]) { $same = $false } }
    Yes 'the check wrote nothing: the same files, byte for byte' $same

    # The other PowerShell. Windows PowerShell 5.1 is the one that reads a file
    # with no byte order mark as ANSI, which is where an em dash typed into the
    # check would have gone missing.
    $other = $null
    if ($PSVersionTable.PSEdition -eq 'Core') { $c = Get-Command powershell.exe -ErrorAction SilentlyContinue; if ($c) { $other = $c.Source } }
    else { $c = Get-Command pwsh -ErrorAction SilentlyContinue; if ($c) { $other = $c.Source } }
    if ($other) {
        $o = Invoke-Check $other $tmp
        Yes ('the other PowerShell (' + (Split-Path -Leaf $other) + ') reports exactly the same hits and exit code') (($o.Code -eq $s.Code) -and (($o.Hits -join ' ') -eq ($s.Hits -join ' ')))
    } else {
        Write-Host 'SKIP  no second PowerShell on this machine to compare with'
    }

    # Clean the seeded breaks away and the same files pass.
    Put 'README.md' @('# Seeded', 'A multiplayer engine, a playtest, getPlayer() and PlayerCharacter.')
    Put 'SECURITY.md' @('Fine.')
    Put 'tools/app/Help.cs' @('new HelpItem("x", "fine"),')
    Put 'tools/ui.xaml' @('<TextBlock x:Name="PlayerList" Text="the multiplayer client"/>') $utf8bom
    Put 'tools/docs-app/data/site/a.md' @('Fine.')
    Put 'tools/docs-app/data/known.md' @('| A | B |', '| an ordinary Skyrim save | why |')
    Put 'tools/docs-app/public/home.html' @('<p>one, two</p>')
    $c2 = Invoke-Check $self $tmp
    Yes ('clean files exit 0 with no hits (exit ' + $c2.Code + ', ' + $c2.Hits.Count + ' hit(s))') ($c2.Code -eq 0 -and $c2.Hits.Count -eq 0)

    # A listed file that is gone is said out loud, not silently dropped.
    Remove-Item -LiteralPath (Join-Path $tmp 'SECURITY.md') -Force
    $g = Invoke-Check $self $tmp
    $warned = @($g.Out | Where-Object { $_ -like '::warning::SECURITY.md is not there*' }).Count -gt 0
    Yes ('a listed file that is missing is a warning and not a failure (exit ' + $g.Code + ')') ($warned -and $g.Code -eq 0)
}
finally {
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

Done
