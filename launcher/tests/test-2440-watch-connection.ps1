<#
  test-2440-watch-connection.ps1

      pwsh -NoProfile -File .\launcher\tests\test-2440-watch-connection.ps1

  The launcher's feed watch keeps its socket out of the two connections the
  rest of the launcher shares with thornswood.net.

  WHY THIS EXISTS. The .NET Framework lets a program keep two connections to
  a host at a time (ServicePointManager.DefaultConnectionLimit), and a request
  waits for a free one inside its own timeout. From #2440 on, an open launcher
  keeps one long-poll to the site's /feed/watch open all the time, fifty
  seconds a wait, and it sat in the same connection group as everything else,
  so the Play page's gallery list, its pictures (up to 5.7 MB each), the voice
  token and the news took turns on the one connection left. A picture held the
  rest back, and a request whose timeout ran out while it waited failed:
  Patrick's launcher.log on 30 Oct, 7:08 PM, says "Voice: could not get a join
  token (The operation has timed out)", and the gallery list read the same way
  leaves Play's card hidden. Patrick's report the same evening: the Play
  gallery goes blank or loads its pictures slowly, where it used to turn
  through them steadily. Updater.Tip now puts the watch in a connection group
  of its own (Updater.WatchGroup), which counts its connections apart.

  What it proves, against a server of its own on 127.0.0.1, given the limit a
  host that is not loopback gets:
    - on this machine two held requests in the shared group leave a third to
      time out, so the limit this guards against is really there
    - with the feed watch held open through Updater.Tip and one picture
      downloading, the gallery's own GetBytes still answers at once

  HOW. Compiles launcher\app\*.cs with the build's compiler and C# version
  (Launcher-Csc.ps1), as test-2636-feed-watch-quiet.ps1 does, and calls
  Updater.Tip and Gallery.GetBytes by reflection. Nothing under C:\Thornswood
  is read or written and nothing leaves 127.0.0.1.

  On the code before this, the watch shares the group, and the last check
  fails: the gallery's request times out.

  Runs under Windows PowerShell 5.1 and restarts itself there from pwsh,
  because the launcher runs on the .NET Framework.
#>
[CmdletBinding()]
param([string]$Src)

$ErrorActionPreference = 'Stop'
. (Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'tests') 'Launcher-Csc.ps1')   # the build's compiler and C# version (#498)
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Here = Split-Path -Parent (Split-Path -Parent $Here)
if (-not $Src) { $Src = Join-Path $Here 'launcher\app' }

. (Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'tests') 'Windows.ps1')
if (-not $OnWindows) { Write-Host 'NOT RUN  this runs the launcher''s code on the .NET Framework the launcher runs on, which only Windows has'; exit 0 }
if ($PSVersionTable.PSEdition -eq 'Core') {
    $winps = Get-WindowsPowerShell
    & $winps -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Src $Src
    exit $LASTEXITCODE
}

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts2440c-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Force -Path $tmp

# ---- a site of its own, on 127.0.0.1 ------------------------------------------
#
# /feed/watch and /hold are held for HoldMs and then answered (204 and a body
# of 200 bytes); /quick is answered at once. Every answer closes its socket.
# TsHold runs a request in the shared group on a thread of its own, standing in
# for a gallery picture that is still downloading; TsRun runs a launcher method
# the same way.
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Text;
using System.Threading;

public class TsSite2440
{
    TcpListener listener;
    public int Port;
    public volatile int HoldMs = 4000;

    public void Start()
    {
        listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        Port = ((IPEndPoint)listener.LocalEndpoint).Port;
        var t = new Thread(Loop);
        t.IsBackground = true;
        t.Start();
    }

    public void Stop() { listener.Stop(); }

    void Loop()
    {
        while (true)
        {
            TcpClient c;
            try { c = listener.AcceptTcpClient(); }
            catch (SocketException) { return; }
            catch (ObjectDisposedException) { return; }
            var t = new Thread(() => Serve(c));
            t.IsBackground = true;
            t.Start();
        }
    }

    void Serve(TcpClient c)
    {
        using (c)
        {
            try
            {
                var s = c.GetStream();
                var sb = new StringBuilder();
                int b;
                while ((b = s.ReadByte()) >= 0)
                {
                    sb.Append((char)b);
                    if (sb.Length >= 4 && sb.ToString(sb.Length - 4, 4) == "\r\n\r\n") break;
                }
                string first = sb.ToString().Split(new[] { "\r\n" }, StringSplitOptions.None)[0];
                string head;
                byte[] body = new byte[0];
                if (first.Contains("/feed/watch"))
                {
                    Thread.Sleep(HoldMs);
                    head = "HTTP/1.1 204 No Content\r\n";
                }
                else
                {
                    if (first.Contains("/hold")) Thread.Sleep(HoldMs);
                    body = new byte[200];
                    head = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\n";
                }
                head += "Content-Length: " + body.Length + "\r\nConnection: close\r\n\r\n";
                byte[] h = Encoding.ASCII.GetBytes(head);
                s.Write(h, 0, h.Length);
                if (body.Length > 0) s.Write(body, 0, body.Length);
                s.Flush();
            }
            catch (IOException) { }
        }
    }
}

public static class TsHold
{
    public static Thread Start(string url, int ms)
    {
        var t = new Thread(() =>
        {
            try
            {
                var r = (HttpWebRequest)WebRequest.Create(url);
                r.Timeout = ms;
                using (var a = r.GetResponse())
                using (var s = a.GetResponseStream())
                    s.CopyTo(Stream.Null);
            }
            catch (WebException) { }
        });
        t.IsBackground = true;
        t.Start();
        return t;
    }
}

public static class TsRun
{
    public static Thread Start(MethodInfo m, object[] args)
    {
        var t = new Thread(() =>
        {
            try { m.Invoke(null, args); }
            catch (TargetInvocationException) { }
        });
        t.IsBackground = true;
        t.Start();
        return t;
    }
}
'@

function Run {
    Yes 'the build''s compiler is here' (Test-Path -LiteralPath $LauncherCsc)
    if (-not (Test-Path -LiteralPath $LauncherCsc) -or $LauncherNeeded.Count -eq 0) { return }

    $refs = @(); $missing = @()
    foreach ($n in $LauncherNeeded) {
        $p = Find-LauncherRef $n
        if ($p) { $refs += $p } else { $missing += $n }
    }
    foreach ($n in $LauncherLib) {
        $p = $n
        if (Test-Path -LiteralPath $p) { $refs += $p } else { $missing += $n }
    }
    Yes ('every reference is on this machine' + $(if ($missing.Count) { ', missing ' + ($missing -join ', ') } else { '' })) ($missing.Count -eq 0)
    if ($missing.Count) { return }

    $cs = @(Get-ChildItem (Join-Path $Src '*.cs') -File)
    $dll = Join-Path $tmp 'Thornswood.dll'
    $cscArgs = @('/noconfig', '/nologo', '/target:library', '/platform:anycpu', "/langversion:$LauncherLangVersion", "/out:$dll")
    foreach ($r in $refs) { $cscArgs += "/reference:$r" }
    foreach ($f in $cs) { $cscArgs += $f.FullName }
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $said = & $LauncherCsc @cscArgs 2>&1
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $old
    $built = ($rc -eq 0) -and (Test-Path -LiteralPath $dll)
    Yes ('the launcher''s {0} source files compile at C# {1}' -f $cs.Count, $LauncherLangVersion) $built
    if (-not $built) {
        foreach ($l in @($said | Where-Object { "$_" -match 'error' } | Select-Object -First 20)) { Write-Host "      $l" }
        return
    }

    $asm = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($dll))
    $U = $asm.GetType('Thornswood.Updater')
    $G = $asm.GetType('Thornswood.Gallery')
    $C = $asm.GetType('Thornswood.Config')
    $flags = [Reflection.BindingFlags]'Static, Public, NonPublic'
    $tipM = $U.GetMethod('Tip', $flags)
    $getM = $G.GetMethod('GetBytes', $flags)
    Yes 'Updater.Tip and Gallery.GetBytes are in the build' ($null -ne $tipM -and $null -ne $getM)
    if ($null -eq $tipM -or $null -eq $getM) { return }
    $cfg = [Activator]::CreateInstance($C)

    $srv = New-Object TsSite2440
    $srv.HoldMs = 4000
    $srv.Start()
    try {
        $base = "http://127.0.0.1:$($srv.Port)"
        # A loopback address is given no limit at all unless one is set on its
        # ServicePoint (ServicePoint.LoopbackConnectionLimit, measured on
        # GitHub's Windows runner: three held requests went through at once).
        # thornswood.net is not loopback and gets DefaultConnectionLimit, so
        # this one is set to that, before any request, which every connection
        # group made under it then takes.
        $sp = [Net.ServicePointManager]::FindServicePoint([Uri]$base)
        $sp.ConnectionLimit = [Net.ServicePointManager]::DefaultConnectionLimit
        Yes ('the shared group allows {0} connections to a host here, as to thornswood.net' -f $sp.ConnectionLimit) (
            [Net.ServicePointManager]::DefaultConnectionLimit -eq 2 -and $sp.ConnectionLimit -eq 2)

        function Quick([string]$path) {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $got = $getM.Invoke($null, [object[]]@("$base$path", 2000))
            $sw.Stop()
            return @{ Got = $got; Seconds = $sw.Elapsed.TotalSeconds }
        }

        # ---- the limit is really there -----------------------------------------
        $a = [TsHold]::Start("$base/hold?a", 10000)
        $b = [TsHold]::Start("$base/hold?b", 10000)
        Start-Sleep -Milliseconds 500
        $q = Quick '/quick?control'
        Yes ('with two requests held in the shared group, a third waits and times out after {0:N1} s' -f $q.Seconds) ($null -eq $q.Got)
        [void]$a.Join(10000); [void]$b.Join(10000)

        # ---- the watch takes none of the shared two -----------------------------
        $w = [TsRun]::Start($tipM, [object[]]@($cfg, "$base/feed/watch", '', 10000))
        $p = [TsHold]::Start("$base/hold?picture", 10000)
        Start-Sleep -Milliseconds 500
        $q = Quick '/quick?gallery'
        Yes ('with the feed watch held and a picture downloading, the gallery''s request answers in {0:N1} s' -f $q.Seconds) (
            $null -ne $q.Got -and $q.Got.Length -eq 200 -and $q.Seconds -lt 1.5)
        [void]$w.Join(10000); [void]$p.Join(10000)
    }
    finally { $srv.Stop() }

    $upd = [IO.File]::ReadAllText((Join-Path $Src 'Updater.cs'))
    Yes 'Updater.Tip puts its request in the watch''s own group' ($upd -match 'q\.Group\s*=\s*WatchGroup;')
}

try { Run }
catch { $script:fail++; Write-Host "FAIL  the harness itself threw: $($_.Exception.Message)" }
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "$($script:pass) passed, $($script:fail) failed"
if ($script:fail) { exit 1 }
exit 0
