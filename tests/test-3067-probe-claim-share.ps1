<#
  test-3067-probe-claim-share.ps1 (a measurement for #3067, not a harness to keep)

  One thread gives a finished file its name with MoveFileExW, the way
  [ThornswoodArtifactName]::Claim does; another opens that name the moment it
  is there, the way the run that lost the name reads the winner's zip. Counts,
  for each way of opening, how often the open was refused with a sharing
  violation while the name was already there.
#>
$ErrorActionPreference = 'Stop'
Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.IO;
using System.Threading;
using System.Runtime.InteropServices;

public static class Probe3067 {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool MoveFileExW(string from, string to, int flags);

    // Returns { iterations with a sharing violation, total violations, opens that succeeded }.
    public static long[] Run(string dir, int iterations, FileShare share, int flags, int size) {
        byte[] data = new byte[size];
        new Random(1).NextBytes(data);
        long hitIterations = 0, violations = 0, opened = 0;
        for (int i = 0; i < iterations; i++) {
            string src = Path.Combine(dir, ".building-" + i + ".zip");
            string dst = Path.Combine(dir, "named-" + i + ".zip");
            File.WriteAllBytes(src, data);
            long v = 0; bool ok = false;
            ManualResetEventSlim go = new ManualResetEventSlim(false);
            Thread reader = new Thread(() => {
                go.Wait();
                DateTime until = DateTime.UtcNow.AddSeconds(5);
                while (DateTime.UtcNow < until) {
                    try {
                        using (FileStream fs = new FileStream(dst, FileMode.Open, FileAccess.Read, share)) { fs.ReadByte(); }
                        ok = true; return;
                    } catch (FileNotFoundException) {
                    } catch (IOException e) {
                        if ((e.HResult & 0xFFFF) == 32) { v++; continue; }
                        throw;
                    }
                }
            });
            reader.Start();
            go.Set();
            Thread.SpinWait(200);
            if (!MoveFileExW(src, dst, flags)) throw new IOException("MoveFileExW failed: " + Marshal.GetLastWin32Error());
            reader.Join();
            if (v > 0) { hitIterations++; violations += v; }
            if (ok) opened++;
            File.Delete(dst);
        }
        return new long[] { hitIterations, violations, opened };
    }
}
'@

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts-3067-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$fail = 0
try {
    $n = 3000
    $cases = @(
        @{ Name = 'FileShare.Read (Get-FileHash, ZipFile.ExtractToDirectory), MOVEFILE_WRITE_THROUGH'; Share = [IO.FileShare]::Read; Flags = 8 },
        @{ Name = 'FileShare.ReadWrite|Delete, MOVEFILE_WRITE_THROUGH'; Share = ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete); Flags = 8 },
        @{ Name = 'FileShare.Read, no flags'; Share = [IO.FileShare]::Read; Flags = 0 },
        @{ Name = 'FileShare.Read|Delete, MOVEFILE_WRITE_THROUGH'; Share = ([IO.FileShare]::Read -bor [IO.FileShare]::Delete); Flags = 8 }
    )
    foreach ($size in 4096, 262144) {
        foreach ($c in $cases) {
            $d = Join-Path $tmp ([Guid]::NewGuid().ToString('N').Substring(0, 8))
            New-Item -ItemType Directory -Force -Path $d | Out-Null
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $r = [Probe3067]::Run($d, $n, $c.Share, $c.Flags, $size)
            Write-Host ("MEASURE  size {0,6}  {1}: {2} of {3} names refused a reader at least once ({4} refusals in all), {5} opened, {6} ms" -f $size, $c.Name, $r[0], $n, $r[1], $r[2], $sw.ElapsedMilliseconds)
            if ($r[2] -ne $n) { $fail++ }
        }
    }
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ''
Write-Host ("{0} passed, {1} failed" -f 1, $fail)
if ($fail) { exit 1 }
exit 0
