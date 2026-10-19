<#
  test-prior-acceptance.ps1

      powershell -NoProfile -File .\tests\test-prior-acceptance.ps1

  Installs made before the terms lock (issue #1009) have no
  Profile\accepted.json. Nothing else in the install records the terms, the
  privacy policy and the rules, so a later run cannot treat a missing file as
  a yes. The launcher (launcher\app\Acceptance.cs) asks the setup window's
  three questions when the record is missing or a page's hash has changed,
  and writes that same file. Declining writes nothing.

  This compiles the launcher's own class with the .NET Framework C# compiler
  and runs it against a scratch folder that stands in for an install made
  before the lock: a config.json, a Profile folder, and no accepted.json.
  No Skyrim, no C:\Thornswood, no window. The site is not asked.

  Under pwsh this starts itself again under Windows PowerShell, because that
  is the compiler Build-Launcher.ps1 uses.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here

if ($PSVersionTable.PSEdition -eq 'Core') {
    $wp = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $wp)) {
        Write-Host 'FAIL  Windows PowerShell is not on this machine, so the launcher''s own compiler cannot be asked'
        Write-Host ''
        Write-Host '0 passed, 1 failed'
        exit 1
    }
    & $wp -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
    exit $LASTEXITCODE
}

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 } else { exit 0 }
}

$accPath = Join-Path $Repo 'launcher\app\Acceptance.cs'
$bootPath = Join-Path $Repo 'installer\setup\Bootstrap.cs'
$shellPath = Join-Path $Repo 'launcher\app\Shell.cs'
$acc = [IO.File]::ReadAllText($accPath)
$boot = [IO.File]::ReadAllText($bootPath)
$shell = [IO.File]::ReadAllText($shellPath)

$tokens = $null; $errs = $null
[void][Management.Automation.Language.Parser]::ParseFile($PSCommandPath, [ref]$tokens, [ref]$errs)
Yes 'this harness parses' ($errs.Count -eq 0)

$csTokens = $null; $csErrs = $null
# The C# is not a PowerShell file. Parsed below by the C# compiler.

Yes 'Acceptance.cs is in the launcher source' (Test-Path -LiteralPath $accPath)
$said = $acc
Yes 'no em dash in Acceptance.cs' (-not ($said -match [char]0x2014))
Yes 'Acceptance.cs does not use the word the project does not use' (-not ($said -match '(?i)\bplayers?\b'))

$m = [regex]::Match($boot, 'static readonly string\[\] Pages = \{([^}]*)\};')
$windowPages = @([regex]::Matches($m.Groups[1].Value, '"(\w+)"') | ForEach-Object { $_.Groups[1].Value })
Yes 'the setup window still has three pages' ($windowPages.Count -eq 3)

$provider = New-Object Microsoft.CSharp.CSharpCodeProvider
$cp = New-Object System.CodeDom.Compiler.CompilerParameters
$cp.GenerateInMemory = $true
$cp.GenerateExecutable = $false
function Find-Ref([string]$name) {
    $roots = @(
        "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319",
        "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\WPF",
        "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319",
        "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\WPF",
        "${env:ProgramFiles(x86)}\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.6.1"
    )
    foreach ($d in $roots) {
        $cand = Join-Path $d $name
        if (Test-Path -LiteralPath $cand) { return $cand }
    }
    $hit = Get-ChildItem "$env:WINDIR\Microsoft.NET\assembly" -Filter $name -Recurse -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if ($hit) { return $hit }
    return $name
}
foreach ($r in @(
    'System.dll', 'System.Core.dll',
    'PresentationFramework.dll', 'PresentationCore.dll', 'WindowsBase.dll', 'System.Xaml.dll'
)) { [void]$cp.ReferencedAssemblies.Add((Find-Ref $r)) }
$built = $provider.CompileAssemblyFromSource($cp, $acc)
$errors = @($built.Errors | Where-Object { -not $_.IsWarning })
foreach ($e in $errors) { Write-Host ('      ' + $e.Line + '  ' + $e.ErrorNumber + '  ' + $e.ErrorText) }
Yes 'Acceptance.cs compiles with the .NET Framework C# compiler' ($errors.Count -eq 0)
if ($errors.Count) { Done }

$T = $built.CompiledAssembly.GetType('Thornswood.Acceptance')
Yes 'the class is Thornswood.Acceptance' ($null -ne $T)

$pages = @($T::Pages)
Yes 'the pages are the setup window''s, in its order' (($pages -join ',') -eq ($windowPages -join ','))
$words = @($T::Words)
$links = @($T::LinkWords)
Yes 'three boxes and three links' ($words.Count -eq 3 -and $links.Count -eq 3)
for ($i = 0; $i -lt $pages.Count; $i++) {
    $p = $pages[$i]
    $cap = $p.Substring(0, 1).ToUpper() + $p.Substring(1)
    $box = [regex]::Match($boot, 'x:Name=""Chk' + $cap + '""[\s\S]*?Text=""([^""]+)""').Groups[1].Value
    $lnk = [regex]::Match($boot, 'x:Name=""Lnk' + $cap + '""[\s\S]*?>([^<]+)</Hyperlink>').Groups[1].Value
    Yes "$p box is the setup window's words" ($box -eq $words[$i])
    Yes "$p link is the setup window's words" ($lnk -eq $links[$i])
}
Yes 'the file is accepted.json' ($T::FileName -eq 'accepted.json')
Yes 'the pages are on https://thornswood.net' ($T::Site -eq 'https://thornswood.net')

function Hex([char]$c) { return ([string]$c) * 64 }
$hTerms = Hex 'a'
$hPriv = Hex 'b'
$hRules = Hex 'c'
$hNew = Hex 'd'
$same = [string[]]@($hTerms, $hPriv, $hRules)
$changed = [string[]]@($hNew, $hPriv, $hRules)


$tmp = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-prior-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    # An install made before the lock: the launcher's config is there, Profile
    # exists, and there is no accepted.json.
    $root = Join-Path $tmp 'old-install'
    $prof = Join-Path $root 'Profile'
    New-Item -ItemType Directory -Force -Path $prof | Out-Null
    [IO.File]::WriteAllText((Join-Path $root 'config.json'), '{ "channel": "main" }')

    $script:asks = 0
    $no = [Func[bool]]{ $script:asks = $script:asks + 1; return $false }
    $kept = $T::Settle($prof, $same, $no)
    Yes 'a prior install with no record, declined, does not count as accepted' (-not $kept)
    Yes 'declining writes no accepted.json' (-not (Test-Path -LiteralPath (Join-Path $prof 'accepted.json')))
    Yes 'declining asked once' ($script:asks -eq 1)
    Yes 'declining leaves the rest of the install where it was' (Test-Path -LiteralPath (Join-Path $root 'config.json'))

    $script:asks = 0
    $yes = [Func[bool]]{ $script:asks = $script:asks + 1; return $true }
    $wrote = $T::Settle($prof, $same, $yes)
    $file = Join-Path $prof 'accepted.json'
    Yes 'ticking the three writes the record' ($wrote -and (Test-Path -LiteralPath $file))
    Yes 'and asked once' ($script:asks -eq 1)
    if (Test-Path -LiteralPath $file) {
        $raw = [IO.File]::ReadAllText($file)
        $bytes = [IO.File]::ReadAllBytes($file)
        $j = $raw | ConvertFrom-Json
        Yes 'accepted.json has no byte order mark' (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF))
        Yes 'it has accepted, pages and about' ((@($j.PSObject.Properties.Name) -join ',') -eq 'accepted,pages,about')
        Yes 'accepted is a UTC time' ($raw -match '"accepted":\s*"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ"')
        Yes 'pages are the three, in the setup window''s order' ((@($j.pages.PSObject.Properties.Name) -join ',') -eq ($pages -join ','))
        foreach ($p in $pages) {
            Yes "$p carries its address and the hash that was ticked" (
                $j.pages.$p.url -eq ("https://thornswood.net/$p") -and $j.pages.$p.sha256 -eq $same[$pages.IndexOf($p)])
        }
        Yes 'and nothing about the person or the machine' (-not ($raw -match [regex]::Escape($env:USERNAME)) -and -not ($raw -match [regex]::Escape($env:COMPUTERNAME)))
        Yes 'a later run with the same hashes does not ask again' (-not $T::NeedsAsk($raw, $same))
    }

    $script:asks = 0
    $again = [Func[bool]]{ $script:asks = $script:asks + 1; return $true }
    $quiet = $T::Settle($prof, $same, $again)
    Yes 'the same record is left in place without asking' ($quiet -and $script:asks -eq 0)

    $before = [IO.File]::ReadAllText($file)
    $script:asks = 0
    $upd = [Func[bool]]{ $script:asks = $script:asks + 1; return $true }
    $changedOk = $T::Settle($prof, $changed, $upd)
    $after = [IO.File]::ReadAllText($file)
    Yes 'a changed page hash asks again and rewrites the record' ($changedOk -and $script:asks -eq 1 -and $after -ne $before)
    Yes 'the new hash is the one just ticked' (($after | ConvertFrom-Json).pages.terms.sha256 -eq $hNew)

    # Empty hash: the site did not answer when it was written. A hash that can
    # be read now is a reason to ask. A site that does not answer now is not.
    $empty = $T::ToJson([datetime]'2026-09-01T00:00:00Z', [string[]]@('', '', ''))
    Yes 'an empty stored hash against a real page asks' ($T::NeedsAsk($empty, $same))
    Yes 'a real record against a site that does not answer does not ask' (-not $T::NeedsAsk($after, [string[]]@('', '', '')))
    Yes 'a complete record is not asked before the site has been read' (-not $T::NeedsAsk($after, $null))
    Yes 'no file at all is asked' ($T::NeedsAsk($null, $null))
    Yes 'a note with only a time, and no pages, is asked' ($T::NeedsAsk('{ "accepted": "2026-09-29T00:00:00Z" }', $null))

    # The setup window's own shape, and the by-hand script's ConvertTo-Json shape.
    $window = $T::ToJson([datetime]'2026-09-29T12:00:00Z', $same)
    Yes 'the launcher''s own record reads back' (-not $T::NeedsAsk($window, $same))
    $byHand = [ordered]@{
        accepted = '2026-09-29T00:00:00Z'
        pages = [ordered]@{
            terms = [ordered]@{ url = 'https://thornswood.net/terms'; sha256 = $hTerms }
            privacy = [ordered]@{ url = 'https://thornswood.net/privacy'; sha256 = $hPriv }
            rules = [ordered]@{ url = 'https://thornswood.net/rules'; sha256 = $hRules }
        }
        about = 'Answered yes in Setup-Thornswood.ps1, run by hand, before Install.'
    } | ConvertTo-Json -Depth 5
    Yes 'the by-hand record reads back as the same three pages' (-not $T::NeedsAsk($byHand, $same))

    # Only the page that changed (#2616, Patrick 16 Oct): asked again only
    # when a page changed, and only that page.
    $rec = $T::ToJson([datetime]'2026-10-16T00:00:00Z', $same)
    $none = $T::Changed($rec, $same)
    Yes 'nothing changed: no page is marked' (-not ($none -contains $true))
    $onlyPriv = $T::Changed($rec, [string[]]@($hTerms, $hNew, $hRules))
    Yes 'the privacy page changed: only privacy is marked' (
        $onlyPriv[0] -eq $false -and $onlyPriv[1] -eq $true -and $onlyPriv[2] -eq $false)
    $offline = $T::Changed($rec, [string[]]@('', '', ''))
    Yes 'a site that does not answer marks nothing' (-not ($offline -contains $true))
    $merged = $T::Merge($rec, [string[]]@($hNew, $hNew, $hNew), $onlyPriv)
    Yes 'the record keeps the unchanged pages'' stored hashes and takes the new one for the changed page' (
        $merged[0] -eq $hTerms -and $merged[1] -eq $hNew -and $merged[2] -eq $hRules)
    $sayOne = $T::Saying($onlyPriv)
    Yes 'the question names only the changed page' ($sayOne -match 'Privacy Policy has changed' -and -not ($sayOne -match 'Terms|Rules'))
    $sayTwo = $T::Saying([bool[]]@($true, $false, $true))
    Yes 'two changed pages are both named' ($sayTwo -match 'Terms and Conditions and the Rules have changed')
    Yes 'no record yet still asks all three' ($T::Saying($null) -match 'no note that the terms, the privacy policy and the rules')

    Yes 'a link off the site is not opened' (-not $T::OpenPage('https://example.com/terms'))
    Yes 'a link to some other page on the site is not opened' (-not $T::OpenPage('https://thornswood.net/other'))
    Yes 'an empty link is not opened' (-not $T::OpenPage(''))
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# Wiring, by reading. The window is not opened here.
$runAt = $shell.IndexOf('static void Run(')
$run = $shell.Substring($runAt)
$ensureAt = $run.IndexOf('Acceptance.Ensure(')
$loadAt = $run.IndexOf('Config.Load(')
Yes 'Run asks before it reads config' ($ensureAt -gt 0 -and $loadAt -gt $ensureAt)
Yes 'uninstall does not ask' ($run -match 'if \(!askedToUninstall && !termsOnFile && !Acceptance\.Ensure\(')
# A record already on disk is rechecked off the window thread, and only the
# changed pages are shown (#2616, Patrick 16 Oct).
Yes 'a record already on disk is rechecked off the window thread' (
    $run -match 'if \(!askedToUninstall && termsOnFile\)' -and $run.Contains('Acceptance.Recheck(') -and $run.Contains('Acceptance.Ask(which)'))
Yes 'declining a change closes the launcher' ($run.Contains('Application.Current.Shutdown()'))
Yes 'the recheck asks only when a page changed, and writes the merged record' (
    $acc.Contains('if (!Any(changed)) return true;') -and $acc.Contains('Merge(json, current, changed)'))
Yes 'the three questions are the only way Ensure writes' (
    $acc.Contains('if (!NeedsAsk(Read(profileDir), null)) return true;') -and
    $acc.Contains('return Settle(profileDir, FetchShas(), delegate { return Ask(null); });'))

Done
