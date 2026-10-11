<#
  Artifact.ps1

  What a deploy sends, built from a commit rather than copied off a working
  tree, and what the box keeps to say which commit each part runs. Issue #459.
  Dot-sourced by Deploy-Docs.ps1 (site), Install-Voice.ps1 (voice),
  Install-Bot.ps1 (bot), Deploy-DevGamemode.ps1 and Deploy-Server.ps1
  (gamemode), and by Publish-Server.ps1 for the refusal below.

  THE ARTIFACT. New-ThornswoodArtifact reads the named paths out of the
  repository's HEAD commit (git's own bytes, so line endings and file dates on
  this machine do not come into it) and writes them into one zip:

      <component>-<commit, 12>-<sha256 of the zip, 16>.zip
      e.g. site-655846b6a1c2-3f09c2d1e8a7b654.zip

  The zip is stored (no compression), its entries in ordinal order, every date
  2000-01-01, written by the few lines of C# below rather than by .NET's
  ZipArchive, whose headers and deflate output differ between Windows
  PowerShell 5.1 and PowerShell 7. So the same commit gives the same bytes on
  any machine, and the name alone says which commit it is. Beside it,
  <same name>.json is the record: component, commit, sha256, size, and every
  file with its own size and sha256. The record has no clock in it either.

  A DEPLOY SENDS A COMMIT OR NOTHING. A file with uncommitted changes, staged
  or not, deleted, or untracked, under the named paths or among the other
  repository files a deploy sends (-AlsoSends), refuses the deploy before it
  talks to the box, naming every such file (Assert-ThornswoodCommitted).
  There is no switch past it: commit the change, or put it back, and run the
  deploy again. Patrick, 29 Sep, issue #1121. Until then (#1090) such a
  deploy went through and its record said "edited". Ignored files are never
  sent and do not count.

  SITE AND VOICE, BEFORE ANYTHING IS SENT. Deploy-Docs.ps1 and
  Install-Voice.ps1 call Assert-ThornswoodSourceIntegrity on the artifact
  they just built. It checks the zip's hash and every file in the expanded
  tree against the commit's own blobs. If any of that differs, it throws
  and those scripts do not send. Issue #1335.

  The zip is expanded next to itself, laid out like the repository, and the
  deploy scripts send from that folder instead of from the working tree, so
  what goes up is exactly what the zip holds.

  ON THE BOX, C:\Thornswood-Deploys:
    <component>\<name>.zip and <name>.json   every artifact sent, kept
                                              (Send-ThornswoodArtifact)
    current\<part>.json                       what each part runs now, one per
                                              folder a part runs from, e.g.
                                              thornswood-server-dev.json
    history.log                               one line per deploy
  and a copy of the part's record beside what it runs, as
  thornswood-deploy.json (Set-ThornswoodArtifactCurrent). Those are read over
  HTTP: the site's /api/deploys lists every part for staff signed into the
  hub (#1359), the voice service's /health carries its own, and a game
  server serves its own from its data folder, so
  http://<box>:3000/thornswood-deploy.json for live and :7788 for dev.

  Nothing here stops, starts or swaps anything. Building needs git; sending
  needs ssh and scp and the person's key on the box, nothing else, so any
  machine that can reach the box can do it.
#>

# ssh and scp run through Invoke-ThornswoodNative (issue #941).
. (Join-Path $PSScriptRoot '..\vps\Vps.ps1')

. (Join-Path $PSScriptRoot '..\vps\Send-Script.ps1')
. (Join-Path $PSScriptRoot '..\vps\Lock-Folder.ps1')

$script:ThornswoodDeployStore = 'C:/Thornswood-Deploys'

function Initialize-ThornswoodArtifactType {
  if ('ThornswoodArtifactZip' -as [type]) { return }
  Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.Text;

public static class ThornswoodArtifactZip {
    static uint[] table;

    static uint[] Table() {
        if (table != null) return table;
        uint[] t = new uint[256];
        for (uint n = 0; n < 256; n++) {
            uint c = n;
            for (int k = 0; k < 8; k++) c = ((c & 1) != 0) ? (0xEDB88320u ^ (c >> 1)) : (c >> 1);
            t[n] = c;
        }
        table = t;
        return t;
    }

    public static uint Crc32(byte[] data) {
        uint[] t = Table();
        uint c = 0xFFFFFFFFu;
        for (int i = 0; i < data.Length; i++) c = t[(c ^ data[i]) & 0xFF] ^ (c >> 8);
        return c ^ 0xFFFFFFFFu;
    }

    static string ReadLine(Stream s) {
        StringBuilder sb = new StringBuilder();
        while (true) {
            int b = s.ReadByte();
            if (b < 0) throw new EndOfStreamException("git cat-file ended early");
            if (b == 10) return sb.ToString();
            sb.Append((char)b);
        }
    }

    // The exact bytes of each blob, from one git cat-file --batch.
    public static byte[][] ReadBlobs(string git, string repo, string[] ids) {
        ProcessStartInfo psi = new ProcessStartInfo(git, "cat-file --batch");
        psi.WorkingDirectory = repo;
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.RedirectStandardInput = true;
        psi.RedirectStandardOutput = true;
        psi.RedirectStandardError = true;
        Process p = Process.Start(psi);
        p.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e) { };
        p.BeginErrorReadLine();
        Stream input = p.StandardInput.BaseStream;
        Stream output = p.StandardOutput.BaseStream;
        byte[][] res = new byte[ids.Length][];
        try {
            // .NET Framework puts a byte order mark in front of the first
            // thing written to a child's standard input, which git reads as
            // part of the first object name. One empty line first takes it,
            // on either runtime, and its "missing" answer is read and dropped.
            input.WriteByte(10);
            input.Flush();
            string first = ReadLine(output);
            if (!first.EndsWith("missing")) throw new InvalidOperationException("git cat-file answered: " + first);
            for (int i = 0; i < ids.Length; i++) {
                byte[] q = Encoding.ASCII.GetBytes(ids[i] + "\n");
                input.Write(q, 0, q.Length);
                input.Flush();
                string header = ReadLine(output);
                string[] parts = header.Split(' ');
                if (parts.Length != 3 || parts[1] != "blob") throw new InvalidOperationException("git cat-file answered: " + header);
                int size = int.Parse(parts[2]);
                byte[] buf = new byte[size];
                int got = 0;
                while (got < size) {
                    int n = output.Read(buf, got, size - got);
                    if (n <= 0) throw new EndOfStreamException("git cat-file ended inside " + ids[i]);
                    got += n;
                }
                output.ReadByte();
                res[i] = buf;
            }
        } finally {
            try { input.Close(); } catch { }
            p.WaitForExit();
        }
        return res;
    }

    // A stored zip whose bytes depend on nothing but the names and contents.
    public static void WriteStored(string path, string[] names, byte[][] datas) {
        if (names.Length != datas.Length) throw new ArgumentException("names and contents differ in count");
        if (names.Length > 65535) throw new InvalidOperationException("too many files for one zip");
        ushort time = 0;
        ushort date = (ushort)(((2000 - 1980) << 9) | (1 << 5) | 1);
        ushort flags = 0x0800;
        uint[] crcs = new uint[names.Length];
        uint[] offsets = new uint[names.Length];
        byte[][] nameBytes = new byte[names.Length][];
        using (FileStream fs = new FileStream(path, FileMode.Create, FileAccess.Write)) {
            BinaryWriter w = new BinaryWriter(fs);
            for (int i = 0; i < names.Length; i++) {
                if (fs.Position > uint.MaxValue - (long)datas[i].Length - 1024) throw new InvalidOperationException("the zip would pass 4 GB");
                nameBytes[i] = new UTF8Encoding(false).GetBytes(names[i]);
                crcs[i] = Crc32(datas[i]);
                offsets[i] = (uint)fs.Position;
                w.Write((uint)0x04034b50); w.Write((ushort)10); w.Write(flags); w.Write((ushort)0);
                w.Write(time); w.Write(date); w.Write(crcs[i]);
                w.Write((uint)datas[i].Length); w.Write((uint)datas[i].Length);
                w.Write((ushort)nameBytes[i].Length); w.Write((ushort)0);
                w.Write(nameBytes[i]); w.Write(datas[i]);
            }
            uint cdStart = (uint)fs.Position;
            for (int i = 0; i < names.Length; i++) {
                w.Write((uint)0x02014b50); w.Write((ushort)20); w.Write((ushort)10); w.Write(flags); w.Write((ushort)0);
                w.Write(time); w.Write(date); w.Write(crcs[i]);
                w.Write((uint)datas[i].Length); w.Write((uint)datas[i].Length);
                w.Write((ushort)nameBytes[i].Length); w.Write((ushort)0); w.Write((ushort)0);
                w.Write((ushort)0); w.Write((ushort)0); w.Write((uint)0); w.Write(offsets[i]);
                w.Write(nameBytes[i]);
            }
            uint cdEnd = (uint)fs.Position;
            w.Write((uint)0x06054b50); w.Write((ushort)0); w.Write((ushort)0);
            w.Write((ushort)names.Length); w.Write((ushort)names.Length);
            w.Write(cdEnd - cdStart); w.Write(cdStart); w.Write((ushort)0);
            w.Flush();
        }
    }
}
'@
}

function Get-ThornswoodSha256Hex([byte[]]$Bytes) {
  $h = [Security.Cryptography.SHA256]::Create()
  try { return (-join ($h.ComputeHash($Bytes) | ForEach-Object { $_.ToString('x2') })) } finally { $h.Dispose() }
}

# Runs git in the repository and hands back its lines. git writes progress and
# warnings on stderr, and the deploy scripts run with Stop, so stderr is left
# out here and a failure is read from the exit code instead.
function Invoke-ThornswoodArtifactGit([string]$RepoDir, [string[]]$GitArgs) {
  $eap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $out = @(& git -C $RepoDir -c core.quotepath=off @GitArgs 2>$null)
    $code = $LASTEXITCODE
  } finally { $ErrorActionPreference = $eap }
  if ($code -ne 0) { throw ('git ' + ($GitArgs -join ' ') + ' failed in ' + $RepoDir + ' (exit ' + $code + ')') }
  return @($out | ForEach-Object { [string]$_ })
}

<#
  Every file under -Paths (repository paths, files or folders, forward
  slashes) that is not exactly what the commit holds: changed, staged,
  deleted, renamed or untracked, as git status says it. Ignored files are not
  listed. Each is a Path and, in plain words, How.
#>
function Get-ThornswoodUncommitted([string]$RepoDir, [string[]]$Paths) {
  $Paths = @($Paths | Where-Object { $_ } | ForEach-Object { ([string]$_).Replace('\', '/').Trim('/') })
  if (-not $Paths.Count) { return @() }
  $found = @()
  foreach ($line in (Invoke-ThornswoodArtifactGit $RepoDir (@('status', '--porcelain', '--untracked-files=all', '--') + $Paths))) {
    if ($line.Length -lt 4) { continue }
    $xy = $line.Substring(0, 2)
    $p = $line.Substring(3)
    if ($p -match ' -> ') { $p = ($p -split ' -> ')[-1] }
    $how = 'changed and not committed'
    if ($xy -eq '??') { $how = 'new and not committed' }
    elseif ($xy.Contains('D')) { $how = 'deleted and not committed' }
    $found += [pscustomobject]@{ Path = $p; How = $how }
  }
  return @($found | Sort-Object Path)
}

<#
  Refuses, by throwing, when any file under -Paths is not what the commit
  holds, naming each one. Every deploy that sends files out of this
  repository calls it before it talks to the box: New-ThornswoodArtifact does,
  and Publish-Server.ps1 does for the files it sends. No switch turns it off.
#>
function Assert-ThornswoodCommitted {
  param(
    [Parameter(Mandatory = $true)][string]$RepoDir,
    [string[]]$Paths = @(),
    [string]$What = 'this deploy'
  )
  $dirty = @(Get-ThornswoodUncommitted $RepoDir $Paths)
  if (-not $dirty.Count) { return }
  $nl = [Environment]::NewLine
  $list = @($dirty | ForEach-Object { '    ' + $_.Path + '  (' + $_.How + ')' }) -join $nl
  throw ('Refused: ' + $What + ' would send ' + $dirty.Count + ' file(s) that are not committed, so nothing was sent and the box was not touched:' + $nl +
         $list + $nl +
         'Commit them, or put them back, then run it again. A deploy only ever sends a commit.')
}

<#
  Builds the artifact and expands it. -Paths are repository paths, files or
  folders, with forward slashes. -AlsoSends are the other repository files
  the deploy sends that are not in the zip (a plugin, a record, a script);
  they are only checked. Any of either that is not committed refuses the
  build (Assert-ThornswoodCommitted). -OutDir defaults to
  out\deploys\<component>.
#>
function New-ThornswoodArtifact {
  param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-z][a-z0-9-]*$')][string]$Component,
    [Parameter(Mandatory = $true)][string]$RepoDir,
    [string[]]$Paths = @(),
    [string[]]$AlsoSends = @(),
    [string]$OutDir = ''
  )
  Initialize-ThornswoodArtifactType
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $RepoDir = (Resolve-Path -LiteralPath $RepoDir).ProviderPath.TrimEnd('\')
  Assert-ThornswoodCommitted -RepoDir $RepoDir -Paths (@($Paths) + @($AlsoSends)) -What ('the ' + $Component + ' deploy')
  if (-not $OutDir) {
    $where = Join-Path $PSScriptRoot '..\release\Where.ps1'
    $OutDir = Join-Path (Join-Path (& $where Out) 'deploys') $Component
  }
  if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }
  $OutDir = (Resolve-Path -LiteralPath $OutDir).ProviderPath

  $commit = (Invoke-ThornswoodArtifactGit $RepoDir @('rev-parse', '--verify', 'HEAD^{commit}') | Select-Object -First 1).Trim()
  if ($commit -notmatch '^[0-9a-f]{40}$') { throw "Could not read the commit in $RepoDir, so there is nothing to build an artifact from." }
  $git = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source

  $Paths = @($Paths | Where-Object { $_ } | ForEach-Object { ([string]$_).Replace('\', '/').Trim('/') })
  $blobs = @{}
  if ($Paths.Count) {
    foreach ($line in (Invoke-ThornswoodArtifactGit $RepoDir (@('ls-tree', '-r', '--full-tree', $commit, '--') + $Paths))) {
      $m = [regex]::Match($line, '^(\d{6}) (\w+) ([0-9a-f]{40})\t(.+)$')
      if (-not $m.Success) { throw "git ls-tree said something this does not read: $line" }
      if ($m.Groups[2].Value -ne 'blob') { continue }
      $p = $m.Groups[4].Value
      if ($p.StartsWith('"')) { throw "A path git had to quote cannot go into an artifact: $p" }
      $blobs[$p] = $m.Groups[3].Value
    }
    foreach ($want in $Paths) {
      $hit = @($blobs.Keys | Where-Object { $_ -eq $want -or $_.StartsWith($want + '/') })
      if (-not $hit.Count) { throw "The commit $($commit.Substring(0, 12)) has nothing at $want, so the $Component artifact would be missing it." }
    }
  }

  [string[]]$names = @($blobs.Keys)
  if (-not $names.Count) { throw "The $Component artifact would be empty." }
  [Array]::Sort($names, [StringComparer]::Ordinal)
  [string[]]$ids = @($names | ForEach-Object { $blobs[$_] })
  $datas = [ThornswoodArtifactZip]::ReadBlobs($git, $RepoDir, $ids)

  $building = Join-Path $OutDir ('.building-' + [Guid]::NewGuid().ToString('N') + '.zip')
  [ThornswoodArtifactZip]::WriteStored($building, $names, $datas)
  $sha = (Get-FileHash -LiteralPath $building -Algorithm SHA256).Hash.ToLowerInvariant()
  $short = $commit.Substring(0, 12)
  $name = $Component + '-' + $short + '-' + $sha.Substring(0, 16) + '.zip'
  $zip = Join-Path $OutDir $name
  if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $building -Force }
  else { Move-Item -LiteralPath $building -Destination $zip }

  $contents = @()
  for ($i = 0; $i -lt $names.Count; $i++) {
    $contents += [ordered]@{ path = $names[$i]; size = $datas[$i].Length; sha256 = (Get-ThornswoodSha256Hex $datas[$i]) }
  }
  $record = [ordered]@{
    component = $Component
    name      = $name
    commit    = $commit
    sha256    = $sha
    size      = (Get-Item -LiteralPath $zip).Length
    files     = $contents
  }
  $recordPath = [IO.Path]::ChangeExtension($zip, '.json')
  [IO.File]::WriteAllText($recordPath, (ConvertTo-Json -InputObject $record -Depth 5), (New-Object Text.UTF8Encoding($false)))

  # Laid out like the repository, so a script that sent <repo>\site\server.js
  # sends <folder>\site\server.js.
  $folder = Join-Path $OutDir ([IO.Path]::GetFileNameWithoutExtension($name))
  if (Test-Path -LiteralPath $folder) { Remove-Item -LiteralPath $folder -Recurse -Force }
  [IO.Compression.ZipFile]::ExtractToDirectory($zip, $folder)

  return [pscustomobject]@{
    Component  = $Component
    Name       = $name
    Zip        = $zip
    RecordPath = $recordPath
    Record     = $record
    Folder     = $folder
    Commit     = $commit
    Short      = $short
    Sha256     = $sha
    Size       = $record.size
  }
}

function Assert-ThornswoodSourceIntegrity {
  param(
    [Parameter(Mandatory = $true)]$Artifact,
    [Parameter(Mandatory = $true)][string]$RepoDir
  )
  # Deploy-Docs (site) and Install-Voice (voice) call this after the artifact
  # is built and before anything is sent. The tree that would go up has to be
  # the commit's own bytes: the zip's hash, every expanded file's hash, and
  # the blobs git has for that commit. A miss throws, and the caller must not
  # send. This does not replace the hash compare those scripts already make
  # of the files once they are on the box.
  if (-not $Artifact -or -not $Artifact.Folder -or -not $Artifact.Zip -or -not $Artifact.Record) {
    throw 'Refused: there is no site or voice artifact to check, so nothing was sent and the box was not touched.'
  }
  $component = [string]$Artifact.Component
  if (-not $component) { $component = 'deploy' }
  $RepoDir = (Resolve-Path -LiteralPath $RepoDir).ProviderPath.TrimEnd('\')
  $commit = (Invoke-ThornswoodArtifactGit $RepoDir @('rev-parse', '--verify', 'HEAD^{commit}') | Select-Object -First 1).Trim()
  if ($commit -notmatch '^[0-9a-f]{40}$' -or $commit -ne [string]$Artifact.Commit) {
    $built = [string]$Artifact.Commit
    throw "Refused: the $component artifact is not HEAD ($commit), it was built from $built, so nothing was sent and the box was not touched."
  }
  if (-not (Test-Path -LiteralPath $Artifact.Zip)) {
    throw "Refused: the $component artifact zip is missing, so nothing was sent and the box was not touched."
  }
  $zipHash = (Get-FileHash -LiteralPath $Artifact.Zip -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($zipHash -ne ([string]$Artifact.Sha256).ToLowerInvariant()) {
    throw "Refused: the $component artifact zip is not the bytes built from $($commit.Substring(0, 12)), so nothing was sent and the box was not touched."
  }
  if (-not (Test-Path -LiteralPath $Artifact.Folder)) {
    throw "Refused: the $component artifact tree is missing, so nothing was sent and the box was not touched."
  }

  $reasons = [ordered]@{}
  $want = @{}
  foreach ($f in @($Artifact.Record.files)) {
    $path = $null; $sha = $null; $sizeText = $null
    if ($f -is [System.Collections.IDictionary]) {
      $path = [string]$f['path']; $sha = [string]$f['sha256']; $sizeText = [string]$f['size']
    } else {
      $path = [string]$f.path; $sha = [string]$f.sha256; $sizeText = [string]$f.size
    }
    if (-not $path) { $path = '(no path)' }
    $path = $path.Replace('\', '/').Trim('/')
    if ($sha) { $sha = $sha.ToLowerInvariant() }
    $size = 0L
    $sizeOk = $false
    try { $size = [int64]$sizeText; if ($size -ge 0) { $sizeOk = $true } } catch { $sizeOk = $false }
    if ($want.ContainsKey($path)) {
      $reasons[$path] = 'listed twice in the artifact record'
      continue
    }
    if ($sha -notmatch '^[0-9a-f]{64}$' -or -not $sizeOk) {
      $reasons[$path] = 'the artifact record has no usable size and sha256'
      $want[$path] = @{ sha256 = ''; size = -1L }
      continue
    }
    $want[$path] = @{ sha256 = $sha; size = $size }
  }
  if (-not $want.Count) {
    throw "Refused: the $component artifact lists no files, so nothing was sent and the box was not touched."
  }

  $root = (Get-Item -LiteralPath $Artifact.Folder).FullName.TrimEnd('\')
  $onDisk = @{}
  foreach ($file in @(Get-ChildItem -LiteralPath $root -Recurse -File -Force)) {
    if ($file.FullName.Length -le $root.Length -or ($file.FullName[$root.Length] -ne [char]92 -and $file.FullName[$root.Length] -ne '/')) {
      throw "Refused: could not name a file under the $component artifact tree, so nothing was sent and the box was not touched."
    }
    $rel = $file.FullName.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
    if ($onDisk.ContainsKey($rel)) { $reasons[$rel] = 'two files in the tree land on one path' }
    $onDisk[$rel] = $file.FullName
  }
  foreach ($path in @($want.Keys)) {
    if (-not $onDisk.ContainsKey($path)) { $reasons[$path] = 'missing from the tree that would be sent' }
  }
  foreach ($path in @($onDisk.Keys)) {
    if (-not $want.ContainsKey($path) -and -not $reasons.Contains($path)) {
      $reasons[$path] = 'in the tree that would be sent, but not in the commit artifact'
    }
  }

  $diskSha = @{}
  foreach ($path in @($want.Keys)) {
    if (-not $onDisk.ContainsKey($path)) { continue }
    if ($reasons.Contains($path)) { continue }
    $bytes = [IO.File]::ReadAllBytes($onDisk[$path])
    $hex = Get-ThornswoodSha256Hex $bytes
    $diskSha[$path] = $hex
    if ($bytes.LongLength -ne $want[$path].size -or $hex -ne $want[$path].sha256) {
      $reasons[$path] = 'bytes are not the recorded source'
    }
  }

  Initialize-ThornswoodArtifactType
  $git = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
  $blobIds = @{}
  $pathArgs = @($want.Keys)
  foreach ($line in @(Invoke-ThornswoodArtifactGit $RepoDir (@('ls-tree', '-r', '--full-tree', $commit, '--') + $pathArgs))) {
    if (-not $line) { continue }
    $m = [regex]::Match($line, '^(\d{6}) (\w+) ([0-9a-f]{40})\t(.+)$')
    if (-not $m.Success) { throw "Refused: git ls-tree said something this does not read ($line), so nothing was sent and the box was not touched." }
    if ($m.Groups[2].Value -ne 'blob') { continue }
    $p = $m.Groups[4].Value
    if ($p.StartsWith('"')) { throw "Refused: a path git had to quote cannot be checked ($p), so nothing was sent and the box was not touched." }
    $blobIds[$p] = $m.Groups[3].Value
  }
  $idNames = New-Object System.Collections.Generic.List[string]
  $ids = New-Object System.Collections.Generic.List[string]
  foreach ($path in @($want.Keys)) {
    if (-not $blobIds.ContainsKey($path)) {
      if (-not $reasons.Contains($path)) { $reasons[$path] = 'not in commit ' + $commit.Substring(0, 12) }
      continue
    }
    if (-not $want[$path].sha256) { continue }
    [void]$idNames.Add($path)
    [void]$ids.Add($blobIds[$path])
  }
  if ($ids.Count) {
    $datas = [ThornswoodArtifactZip]::ReadBlobs($git, $RepoDir, $ids.ToArray())
    for ($i = 0; $i -lt $idNames.Count; $i++) {
      $path = $idNames[$i]
      $hex = Get-ThornswoodSha256Hex $datas[$i]
      $recordSha = $want[$path].sha256
      $diskOk = $diskSha.ContainsKey($path) -and $diskSha[$path] -eq $hex
      if ($hex -ne $recordSha -or -not $diskOk) {
        if (-not $reasons.Contains($path)) { $reasons[$path] = "not the commit's bytes" }
      }
    }
  }

  if ($reasons.Count) {
    $nl = [Environment]::NewLine
    $list = @($reasons.Keys | Sort-Object | ForEach-Object { '    ' + $_ + '  (' + $reasons[$_] + ')' }) -join $nl
    throw ("Refused: the $component deploy would send " + $reasons.Count + " file(s) that are not the source at " + $commit.Substring(0, 12) + ", so nothing was sent and the box was not touched:" + $nl + $list)
  }
}

# One line for a deploy to print.
function Format-ThornswoodArtifact($Artifact) {
  return ('{0}, commit {1}, {2} file(s), {3:N0} bytes' -f $Artifact.Name, $Artifact.Short, @($Artifact.Record.files).Count, $Artifact.Size)
}

# The name the box files a part under: the folder it runs from, so the live and
# dev copies of one component never share a record. C:/Thornswood-Server-Dev is
# thornswood-server-dev.
function Get-ThornswoodArtifactPart([string]$Root) {
  $leaf = ($Root.Replace('\', '/').TrimEnd('/') -split '/')[-1]
  if ($leaf -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw "Cannot name a part after the folder $Root." }
  return $leaf.ToLowerInvariant()
}

function Invoke-ThornswoodArtifactRemote([string]$Target, [string[]]$SshArgs, [string]$Script) {
  # Host key checking on whatever the caller passed (#450): only the box whose
  # key known_hosts holds, checked against vps.json, is ever talked to.
  # Send-Script.ps1 adds it and refuses a weaker one.
  $eap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    # cmd.exe on the box stops at 8,191 characters (tests\test-remote-length.ps1).
    # These scripts are short; one that is not goes up as a file of its own
    # name and is run from there (Send-Script.ps1, issue #1070).
    $out = @(Invoke-ThornswoodRemote -Target $Target -SshArgs @($SshArgs | Where-Object { $_ }) -Script $Script | Where-Object { $_ -is [string] } | ForEach-Object { $_.Trim() })
  } finally { $ErrorActionPreference = $eap }
  return $out
}

function Send-ThornswoodArtifactFile([string]$Local, [string]$Target, [string[]]$SshArgs, [string]$Far) {
  # Host key checking on whatever the caller passed (#450): only the box whose
  # key known_hosts holds, checked against vps.json, is ever talked to.
  $strict = @('-o', 'StrictHostKeyChecking=yes') + @($SshArgs | Where-Object { $_ })
  $eap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    Invoke-ThornswoodNative { & scp @strict $Local ($Target + ':' + $Far) } 2>&1 | Out-Null
    $code = $LASTEXITCODE
  } finally { $ErrorActionPreference = $eap }
  if ($code -ne 0) { throw ('scp failed sending ' + (Split-Path -Leaf $Local) + ' to ' + $Far) }
}

<#
  Puts the zip and its record in the box's store, before anything is swapped.
  A zip the store already holds with the same hash is not sent again, so
  deploying the same commit twice moves nothing. Throws when the box does not
  end up holding exactly these bytes.
#>
function Send-ThornswoodArtifact {
  param(
    [Parameter(Mandatory = $true)]$Artifact,
    [Parameter(Mandatory = $true)][string]$Target,
    [string[]]$SshArgs = @(),
    [string]$Store = $script:ThornswoodDeployStore
  )
  $store = $Store.Replace('\', '/').TrimEnd('/')
  $dir = $store + '/' + $Artifact.Component
  $zipWin = ($dir + '/' + $Artifact.Name).Replace('/', '\')
  $ask = @"
$(Get-ThornswoodLockedFolderScript $store.Replace('/', '\'))
New-Item -ItemType Directory -Force -Path '$($dir.Replace('/', '\'))', '$($store.Replace('/', '\'))\current' | Out-Null
if (Test-Path -LiteralPath '$zipWin') { 'HAS ' + (Get-FileHash -LiteralPath '$zipWin' -Algorithm SHA256).Hash.ToLowerInvariant() } else { 'HAS none' }
"@
  $have = @(Invoke-ThornswoodArtifactRemote $Target $SshArgs $ask | Where-Object { $_ -like 'HAS *' }) | Select-Object -Last 1
  if ($have -eq ('HAS ' + $Artifact.Sha256)) {
    Write-Host ('  ' + $Artifact.Name + ' is already in the store on the box') -ForegroundColor DarkGray
  } else {
    Send-ThornswoodArtifactFile $Artifact.Zip $Target $SshArgs ($dir + '/' + $Artifact.Name)
    $have = @(Invoke-ThornswoodArtifactRemote $Target $SshArgs $ask | Where-Object { $_ -like 'HAS *' }) | Select-Object -Last 1
    if ($have -ne ('HAS ' + $Artifact.Sha256)) { throw ('The box does not hold ' + $Artifact.Name + ' as it was built (' + $have + '). Nothing was swapped.') }
    Write-Host ('  ' + $Artifact.Name + ' sent to the store on the box, ' + $Artifact.Sha256.Substring(0, 16) + ' checked there') -ForegroundColor DarkGray
  }
  Send-ThornswoodArtifactFile $Artifact.RecordPath $Target $SshArgs ($dir + '/' + [IO.Path]::GetFileName($Artifact.RecordPath))
}

# What the box keeps for a part: the artifact's record without its file list,
# plus where it runs, when, and from which machine.
function New-ThornswoodDeployRecord($Artifact, [string]$Root) {
  return [ordered]@{
    part        = (Get-ThornswoodArtifactPart $Root)
    component   = $Artifact.Component
    name        = $Artifact.Name
    commit      = $Artifact.Commit
    sha256      = $Artifact.Sha256
    size        = $Artifact.Size
    files       = @($Artifact.Record.files).Count
    root        = $Root.Replace('\', '/')
    deployedUtc = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
    from        = [string]$env:COMPUTERNAME
  }
}

<#
  Records that a part now runs this artifact: current\<part>.json in the store,
  the same record beside what it runs (-Beside, default <Root>/thornswood-
  deploy.json), and a line in history.log. Called once the new files are in
  place, never before.
#>
function Set-ThornswoodArtifactCurrent {
  param(
    [Parameter(Mandatory = $true)]$Artifact,
    [Parameter(Mandatory = $true)][string]$Target,
    [string[]]$SshArgs = @(),
    [Parameter(Mandatory = $true)][string]$Root,
    [string]$Beside = '',
    [string]$Store = $script:ThornswoodDeployStore
  )
  $rec = New-ThornswoodDeployRecord $Artifact $Root
  if (-not $Beside) { $Beside = $Root.Replace('\', '/').TrimEnd('/') + '/thornswood-deploy.json' }
  $store = $Store.Replace('\', '/').TrimEnd('/')
  $local = Join-Path (Split-Path -Parent $Artifact.Zip) ($rec.part + '.deploy.json')
  [IO.File]::WriteAllText($local, (ConvertTo-Json -InputObject $rec -Depth 4), (New-Object Text.UTF8Encoding($false)))
  $far = $store + '/current/' + $rec.part + '.json'
  Send-ThornswoodArtifactFile $local $Target $SshArgs $far
  $line = ($rec.deployedUtc + ' ' + $rec.part + ' ' + $rec.name + ' from ' + $rec.from).Replace("'", "''")
  $said = Invoke-ThornswoodArtifactRemote $Target $SshArgs @"
Copy-Item -LiteralPath '$($far.Replace('/', '\'))' -Destination '$($Beside.Replace('/', '\').Replace("'", "''"))' -Force
Add-Content -LiteralPath '$($store.Replace('/', '\'))\history.log' -Value '$line'
'RECORDED'
"@
  if ($said -notcontains 'RECORDED') {
    Write-Host ('  the record went to the store and not beside ' + $rec.part + ': ' + ($said -join ' ')) -ForegroundColor Yellow
  } else {
    Write-Host ('  the box records ' + $rec.part + ' as ' + $rec.name) -ForegroundColor DarkGray
  }
  return $rec
}
