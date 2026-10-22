<#
  test-2519-setup-discord-onbox.ps1

  Setup-Discord.ps1 -OnBox builds the Discord on the VPS with the token the
  running bot already holds, and asks for nothing.

  WHY THIS EXISTS. Issues #2519 and #2341. Setup-Discord.ps1 asked for the bot
  token at a hidden prompt (Read-Host -AsSecureString), even for -Check, so
  the Gamemasters layout and the #welcome-travelers Attach Files overwrite,
  both merged, waited on a person who holds the token to sit at a prompt; the
  Releases desk on One runs with nobody at one, and stopped there on 22 Oct
  2026. The token is already on the box, in C:\Thornswood-Bot\bot.env.json,
  where the bot reads it. -OnBox runs the build there with it.

  What it checks, with Vps.ps1 and Send-Script.ps1 replaced by stand-ins that
  write down the script instead of sending it, in a throwaway git repository:
    1. -OnBox -Check asks for no token, sends one script and passes;
    2. the script carries Build-Discord.py, content.py and staff-channel.txt
       byte for byte as the commit holds them, sets DISCORD_CHECK and the
       site's open switch, and sets no -Posts or -Prune it was not given;
    3. it reads the token from bot.env.json on the box, never carries one,
       and clears it and removes its folder in a finally;
    4. the script itself, run with a stand-in Python and the box's paths
       pointed at a temp folder, under Windows PowerShell where there is one,
       because the box runs 5.1: the files are there when the build runs,
       the token is in its environment, and the folder is gone afterwards;
       a bot.env.json with no token stops it before the build;
    5. an uncommitted change to one of the three files stops the run before
       anything is sent.

  It never reaches the VPS or Discord. Files under its own temp folder only.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here

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

$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue)
$git = (Get-Command git -ErrorAction SilentlyContinue)
Yes 'pwsh and git are on this machine' ($null -ne $pwsh -and $null -ne $git)
if (-not $pwsh -or -not $git) { Done }

$work = Join-Path ([IO.Path]::GetTempPath()) ('ts-setup-onbox-' + [Guid]::NewGuid().ToString('N'))
try {
    $tree = Join-Path $work 'repo'
    $dep = Join-Path $tree 'scripts\deploy'; $vps = Join-Path $tree 'scripts\vps'; $bot = Join-Path $tree 'bot'
    New-Item -ItemType Directory -Force -Path $dep, $vps, $bot | Out-Null
    Copy-Item -LiteralPath (Join-Path $Repo 'scripts\deploy\Setup-Discord.ps1') -Destination $dep
    foreach ($f in 'Build-Discord.py', 'content.py', 'staff-channel.txt') { Copy-Item -LiteralPath (Join-Path $Repo ('bot\' + $f)) -Destination $bot }
    $sent = Join-Path $work 'sent.ps1'
    [IO.File]::WriteAllText((Join-Path $vps 'Vps.ps1'), "function Get-ThornswoodVpsUser { 'Administrator' }`nfunction Get-ThornswoodVpsAddress { '192.0.2.1' }`n")
    [IO.File]::WriteAllText((Join-Path $vps 'Send-Script.ps1'), @"
function Invoke-ThornswoodRemote {
    param([string]`$Target, [string[]]`$SshArgs, [string]`$Script)
    [IO.File]::WriteAllText('$($sent.Replace("'", "''"))', `$Script)
    `$global:LASTEXITCODE = 0
    return @('far side said: done', ('target ' + `$Target), ('ssh ' + (`$SshArgs -join ' ')))
}
"@)
    $null = & git -C $tree init -q 2>&1
    $null = & git -C $tree -c user.email=t@t -c user.name=t add -A 2>&1
    $null = & git -C $tree -c user.email=t@t -c user.name=t commit -q -m t 2>&1
    Yes 'the throwaway repository has a commit' ($LASTEXITCODE -eq 0)

    # The caller defines Invoke-RestMethod, so the site's open switch is read
    # from this and never from thornswood.net.
    $runner = Join-Path $work 'run.ps1'
    [IO.File]::WriteAllText($runner, @"
param([string]`$Pass)
function Invoke-RestMethod { [pscustomobject]@{ open = `$false } }
`$s = @{}; foreach (`$p in (`$Pass -split ',')) { if (`$p) { `$s[`$p] = `$true } }
& '$((Join-Path $dep 'Setup-Discord.ps1').Replace("'", "''"))' -OnBox @s
exit `$LASTEXITCODE
"@)
    function Run-Setup([string[]]$pass) {
        Remove-Item -LiteralPath $sent -Force -ErrorAction SilentlyContinue
        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $out = & $pwsh.Source -NoProfile -NonInteractive -File $runner -Pass ($pass -join ',') 2>&1 | Out-String; $code = $LASTEXITCODE }
        finally { $ErrorActionPreference = $old }
        $text = ''
        if (Test-Path -LiteralPath $sent) { $text = [IO.File]::ReadAllText($sent) }
        return [pscustomobject]@{ Code = $code; Out = $out; Sent = $text }
    }

    # ---- 1. it runs, and asks for nothing ------------------------------------
    $r = Run-Setup @('Check')
    Yes ("-OnBox -Check passes with nobody at a prompt (exit {0})" -f $r.Code) ($r.Code -eq 0 -and $r.Out -notmatch 'Bot token')
    Yes '  sends one script, to the box, with host keys checked and no prompt' ($r.Sent.Length -gt 0 -and $r.Out -match 'target Administrator@192\.0\.2\.1' -and $r.Out -match 'BatchMode=yes' -and $r.Out -match 'StrictHostKeyChecking=yes')
    Yes '  says the commit it built from, and prints what the far side said' ($r.Out -match 'from commit [0-9a-f]{12}' -and $r.Out -match 'far side said: done')

    # ---- 2. what goes up -----------------------------------------------------
    $s = $r.Sent
    $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($s, [ref]$null, [ref]$errs)
    Yes 'the script it sends parses' (@($errs).Count -eq 0)
    foreach ($f in 'Build-Discord.py', 'content.py', 'staff-channel.txt') {
        $m = [regex]::Match($s, "(?m)^\s*'" + [regex]::Escape($f) + "' = '([A-Za-z0-9+/=]+)'")
        $same = $m.Success -and ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $bot $f))) -eq $m.Groups[1].Value)
        Yes "  it carries $f byte for byte" $same
    }
    Yes '  it sets DISCORD_CHECK and the open switch (alpha, 0)' ($s -match "(?m)^\s*\`$env:DISCORD_CHECK = '1'" -and $s -match "(?m)^\s*\`$env:THORNSWOOD_OPEN = '0'")
    Yes '  and no -Posts or -Prune it was not given' ($s -notmatch 'DISCORD_POSTS' -and $s -notmatch 'DISCORD_PRUNE')
    $r2 = Run-Setup @('Posts', 'Prune')
    Yes '  -Posts and -Prune go through when given, and -Check then does not' ($r2.Code -eq 0 -and $r2.Sent -match "DISCORD_POSTS = '1'" -and $r2.Sent -match "DISCORD_PRUNE = '1'" -and $r2.Sent -notmatch 'DISCORD_CHECK')

    # ---- 3. the token --------------------------------------------------------
    Yes 'it reads the token from bot.env.json on the box' ($s -match [regex]::Escape("'C:\Thornswood-Bot'") -and $s -match [regex]::Escape("'bot.env.json'") -and $s -match 'DISCORD_TOKEN = \[string\]\$cfg\.DISCORD_TOKEN')
    Yes '  with the bot''s own libraries' ($s -match [regex]::Escape("`$env:PYTHONPATH = Join-Path `$botRoot 'py-libs'"))
    $fin = [regex]::Match($s, '(?s)\} finally \{(.*?)\n\}').Groups[1].Value
    Yes '  and clears it and removes its folder in a finally' ($fin -match '\$env:DISCORD_TOKEN = \$null' -and $fin -match 'Remove-Item -LiteralPath \$dir -Recurse -Force')

    # ---- 4. the script itself, with a stand-in Python ------------------------
    $box = Join-Path $work 'box'; $win = Join-Path $work 'win'
    New-Item -ItemType Directory -Force -Path $box, $win | Out-Null
    $standIn = @'
function python {
    param($f)
    'RAN ' + (Split-Path -Leaf $f)
    'TOKEN ' + $env:DISCORD_TOKEN
    'CHECK ' + $env:DISCORD_CHECK
    'FILES ' + ((Get-ChildItem -LiteralPath (Split-Path $f) | Sort-Object Name | ForEach-Object { $_.Name }) -join ',')
    'DIR ' + (Split-Path $f)
    $global:LASTEXITCODE = 0
}

'@
    $local = $standIn + $s.Replace("'C:\Thornswood-Bot'", "'" + $box.Replace("'", "''") + "'").Replace('$env:WINDIR', "'" + $win.Replace("'", "''") + "'")
    $farPath = Join-Path $work 'far.ps1'
    [IO.File]::WriteAllText($farPath, $local)
    # The box runs Windows PowerShell 5.1, so the script runs under it wherever
    # it is here (the Windows runners); elsewhere under pwsh.
    $farPs = (Get-Command powershell.exe -ErrorAction SilentlyContinue)
    if (-not $farPs) { $farPs = $pwsh }
    Write-Host ('      the box''s script runs under ' + $farPs.Source)
    function Run-Far {
        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $o = & $farPs.Source -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $farPath 2>&1 | Out-String; $c = $LASTEXITCODE }
        finally { $ErrorActionPreference = $old }
        return [pscustomobject]@{ Code = $c; Out = $o }
    }
    [IO.File]::WriteAllText((Join-Path $box 'bot.env.json'), '{"DISCORD_TOKEN":"stand-in-token","PING_URL":"x"}')
    $f = Run-Far
    Yes ("run on the box, the build runs and passes (exit {0})" -f $f.Code) ($f.Code -eq 0 -and $f.Out -match 'RAN Build-Discord\.py')
    Yes '  with the three files beside it' ($f.Out -match 'FILES Build-Discord\.py,content\.py,staff-channel\.txt')
    Yes '  with the bot''s token in its environment, and -Check' ($f.Out -match 'TOKEN stand-in-token' -and $f.Out -match 'CHECK 1')
    Yes '  and its folder is gone afterwards' (@(Get-ChildItem -LiteralPath $win -Recurse -Directory -Filter 'thornswood-discord-*').Count -eq 0)

    [IO.File]::WriteAllText((Join-Path $box 'bot.env.json'), '{"PING_URL":"x"}')
    $f = Run-Far
    Yes ("a bot.env.json with no token stops it before the build (exit {0})" -f $f.Code) ($f.Code -eq 3 -and $f.Out -match 'NO TOKEN' -and $f.Out -notmatch 'RAN ')
    Yes '  and leaves no folder either' (@(Get-ChildItem -LiteralPath $win -Recurse -Directory -Filter 'thornswood-discord-*').Count -eq 0)

    # ---- 5. an uncommitted change stops it -----------------------------------
    Add-Content -LiteralPath (Join-Path $bot 'content.py') -Value '# changed'
    $r = Run-Setup @('Check')
    Yes ("an uncommitted change to content.py stops the run (exit {0})" -f $r.Code) ($r.Code -ne 0 -and $r.Out -match 'Commit these first' -and $r.Out -match 'content\.py')
    Yes '  before anything is sent' ($r.Sent.Length -eq 0)
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Done
