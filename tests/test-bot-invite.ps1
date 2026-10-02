<#
  test-bot-invite.ps1

  The bot's invite asks for what it runs on, not Administrator.

  Issue #455, "The bot is invited with Administrator and keeps it". With
  Administrator the blast radius of the bot token, or of a backup zip that
  holds it, is the whole server. The build needs Administrator, because it
  makes the Owner and Dev roles and those carry it, but the running bot does
  not. So bot\Build-Discord.py has two sets: Administrator for a build, and
  RUN_BITS for the rest of the time. A build that finishes with nothing failed
  ends on the invite link with that set and a line saying to untick
  Administrator, and `Build-Discord.py --invite <application id>` prints the
  same without a token, without discord.py and without connecting.

  This checks, in order:

    1. the builder parses, without running it;
    2. the dry path prints an invite whose permissions are one integer, not 8,
       with scope bot and the id it was given;
    3. that integer, decoded against the bit numbers on Discord's permissions
       page (written out below, not taken from the builder or discord.py), is
       exactly the intended list, and Administrator is not in it;
    4. the builder's own names for those bits are the page's names;
    5. the untick Administrator line follows the link;
    6. the dry path never imports discord.py and needs no token: a stand-in
       discord package that fails on import is put first on the path;
    7. with no id it says how to get one and prints no link;
    8. Setup-Discord.ps1 parses and says the same about the two sets.

  The end of a real build is checked in bot\test-bot-overwrites.py, which
  drives the builder against a stand-in server and needs discord.py.

  Never connects to anything. Writes only under its own temp folder.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
$Builder = Join-Path $Repo 'bot\Build-Discord.py'
$Setup = Join-Path $Repo 'scripts\deploy\Setup-Discord.ps1'

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

# Discord's permission bits, by number, off
# https://docs.discord.com/developers/topics/permissions
$Documented = @{
    0 = 'CREATE_INSTANT_INVITE'; 1 = 'KICK_MEMBERS'; 2 = 'BAN_MEMBERS'
    3 = 'ADMINISTRATOR'; 4 = 'MANAGE_CHANNELS'; 5 = 'MANAGE_GUILD'
    6 = 'ADD_REACTIONS'; 7 = 'VIEW_AUDIT_LOG'; 8 = 'PRIORITY_SPEAKER'
    9 = 'STREAM'; 10 = 'VIEW_CHANNEL'; 11 = 'SEND_MESSAGES'
    12 = 'SEND_TTS_MESSAGES'; 13 = 'MANAGE_MESSAGES'; 14 = 'EMBED_LINKS'
    15 = 'ATTACH_FILES'; 16 = 'READ_MESSAGE_HISTORY'; 17 = 'MENTION_EVERYONE'
    18 = 'USE_EXTERNAL_EMOJIS'; 19 = 'VIEW_GUILD_INSIGHTS'; 20 = 'CONNECT'
    21 = 'SPEAK'; 22 = 'MUTE_MEMBERS'; 23 = 'DEAFEN_MEMBERS'
    24 = 'MOVE_MEMBERS'; 25 = 'USE_VAD'; 26 = 'CHANGE_NICKNAME'
    27 = 'MANAGE_NICKNAMES'; 28 = 'MANAGE_ROLES'; 29 = 'MANAGE_WEBHOOKS'
    30 = 'MANAGE_GUILD_EXPRESSIONS'; 31 = 'USE_APPLICATION_COMMANDS'
    32 = 'REQUEST_TO_SPEAK'; 33 = 'MANAGE_EVENTS'; 34 = 'MANAGE_THREADS'
    35 = 'CREATE_PUBLIC_THREADS'; 36 = 'CREATE_PRIVATE_THREADS'
    37 = 'USE_EXTERNAL_STICKERS'; 38 = 'SEND_MESSAGES_IN_THREADS'
    51 = 'PIN_MESSAGES'
}

# What the running bot is meant to hold, by the page's names. bot.py's calls
# are what put each one here; the builder's comment above RUN_BITS says which.
$Intended = @('MANAGE_CHANNELS', 'VIEW_CHANNEL', 'SEND_MESSAGES', 'ATTACH_FILES',
              'READ_MESSAGE_HISTORY', 'MANAGE_ROLES', 'MANAGE_THREADS',
              'CREATE_PUBLIC_THREADS', 'CREATE_PRIVATE_THREADS',
              'SEND_MESSAGES_IN_THREADS')

$py = (Get-Command python -EA SilentlyContinue).Source
if (-not $py) { $py = (Get-Command py -EA SilentlyContinue).Source }
if (-not $py) {
    Write-Host 'SKIP  no Python on this machine, so the builder cannot be run'
    Done
}

$Tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts-bot-invite-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Tmp -Force | Out-Null

# Runs python with no token in the environment and a discord package that
# stops the process if anything imports it.
$Fake = Join-Path $Tmp 'fake'
New-Item -ItemType Directory -Path (Join-Path $Fake 'discord') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $Fake 'discord\__init__.py') -Encoding ascii `
    -Value "raise SystemExit('the dry path imported discord.py')"
function Run-Py([string[]]$argv) {
    $saved = @{}
    foreach ($n in @('DISCORD_TOKEN', 'DISCORD_CLIENT_ID', 'PYTHONPATH')) {
        $saved[$n] = [Environment]::GetEnvironmentVariable($n)
    }
    try {
        $env:DISCORD_TOKEN = $null
        $env:DISCORD_CLIENT_ID = $null
        $env:PYTHONPATH = $Fake
        $out = & $py @argv 2>&1 | Out-String
        return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
    } finally {
        foreach ($n in $saved.Keys) { [Environment]::SetEnvironmentVariable($n, $saved[$n]) }
    }
}

try {
    # ---- 1. the builder parses, without running it -------------------------
    $r = Run-Py @('-c', "import ast,sys; ast.parse(open(sys.argv[1], encoding='utf-8').read()); print('the builder parses')", $Builder)
    Yes 'Build-Discord.py parses' ($r.Code -eq 0 -and $r.Out -match 'the builder parses')

    # ---- 2. the dry path prints one integer, not 8 ---------------------------
    $id = '123456789012345678'
    $r = Run-Py @($Builder, '--invite', $id)
    Yes 'the dry path exits 0' ($r.Code -eq 0)
    $m = [regex]::Match($r.Out, 'https://discord\.com/oauth2/authorize\?client_id=(\d+)&scope=bot&permissions=(\d+)')
    Yes 'it prints an invite link with scope bot' $m.Success
    if (-not $m.Success) { Write-Host $r.Out; Done }
    Yes '  for the application it was given' ($m.Groups[1].Value -eq $id)
    $n = [UInt64]$m.Groups[2].Value
    Yes ('  and its permissions are {0}, not 8' -f $n) ($n -ne 8)
    Yes '  and there is exactly one link' ([regex]::Matches($r.Out, 'oauth2/authorize').Count -eq 1)

    # ---- 3. the integer decodes to exactly the intended list -------------
    $got = @()
    $unknown = @()
    for ($b = 0; $b -lt 64; $b++) {
        if (($n -band ([UInt64]1 -shl $b)) -ne 0) {
            if ($Documented.ContainsKey($b)) { $got += $Documented[$b] } else { $unknown += $b }
        }
    }
    Yes ('  every bit in it is on the permissions page' + $(if ($unknown) { ' (not: ' + ($unknown -join ', ') + ')' } else { '' })) ($unknown.Count -eq 0)
    Yes ('  it decodes to ' + ($got -join ', ')) ((@($got | Sort-Object) -join ',') -eq (@($Intended | Sort-Object) -join ','))
    Yes '  Administrator is not in it' ($got -notcontains 'ADMINISTRATOR')
    $sum = [UInt64]0
    foreach ($b in $Documented.Keys) { if ($Intended -contains $Documented[$b]) { $sum += ([UInt64]1 -shl $b) } }
    # CREATE_PUBLIC_THREADS joined the set on 2 October, for the Live smoke
    # session thread under #test-tasks (bot.py, the live smoke section). It
    # took the number from 361045789712 to this one. PIN_MESSAGES and
    # MANAGE_MESSAGES deliberately stayed out: the checklist pin is tried and
    # shrugged off when Discord refuses it.
    Yes ('  and it is the sum of those bits, {0}' -f $sum) ($n -eq $sum -and $n -eq [UInt64]395405528080)

    # ---- 4. the builder's names are the page's names ------------------------
    $src = Get-Content -LiteralPath $Builder -Raw
    $rows = [regex]::Matches($src, "\('([A-Za-z ]+)',\s+(\d+)\),")
    $pairs = @($rows | ForEach-Object { [pscustomobject]@{ Name = $_.Groups[1].Value; Bit = [int]$_.Groups[2].Value } })
    Yes ('RUN_BITS in the builder names {0} bits' -f $pairs.Count) ($pairs.Count -eq $Intended.Count)
    $named = $true
    foreach ($p in $pairs) {
        $want = $Documented[$p.Bit]
        $have = ($p.Name.ToUpper() -replace ' ', '_') -replace '^MANAGE_SERVER$', 'MANAGE_GUILD'
        if ($have -ne $want) { $named = $false; Write-Host ("      bit {0} is {1} on the page, the builder calls it {2}" -f $p.Bit, $want, $p.Name) }
    }
    Yes '  and each one is called what the page calls that bit' $named
    Yes '  and the dry path lists them by those names' (@($pairs | Where-Object { $r.Out -notmatch [regex]::Escape($_.Name) }).Count -eq 0)

    # ---- 5. the untick line follows the link --------------------------------
    $at = $r.Out.IndexOf('untick Administrator')
    Yes 'it tells the person to untick Administrator on the bot''s role' ($at -ge 0)
    Yes '  after the link, not before it' ($at -gt $m.Index)
    Yes '  now the build is done' ($r.Out -match 'untick Administrator on the bot''s role now the build is done')

    # ---- 6. no discord.py, no token -----------------------------------------
    Yes 'the dry path never imported discord.py' ($r.Out -notmatch 'imported discord')
    Yes '  and never asked for a token' ($r.Out -notmatch 'No token')

    # ---- 7. no id -----------------------------------------------------------
    $r = Run-Py @($Builder, '--invite')
    Yes 'with no id it exits non-zero' ($r.Code -ne 0)
    Yes '  and says where the id is, and prints no link' ($r.Out -match 'General Information' -and $r.Out -notmatch 'oauth2/authorize')
    $r = Run-Py @($Builder, '--invite', 'not-an-id')
    Yes 'with something that is not an id it prints no link either' ($r.Code -ne 0 -and $r.Out -notmatch 'oauth2/authorize')

    # ---- 8. Setup-Discord.ps1 says the same ---------------------------------
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Setup, [ref]$tokens, [ref]$errors)
    Yes 'Setup-Discord.ps1 parses' (@($errors).Count -eq 0)
    $s = Get-Content -LiteralPath $Setup -Raw
    Yes '  and says Administrator is for the build only' ($s -match 'Administrator is for the build')
    Yes '  and says how to print the smaller invite' ($s -match '--invite')
    Yes 'the builder''s own setup steps say the same' ($src -match 'Administrator is for\s+the build only' -and $src -match 'TWO PERMISSION SETS')
} finally {
    Remove-Item -LiteralPath $Tmp -Recurse -Force -EA SilentlyContinue
}

Done
