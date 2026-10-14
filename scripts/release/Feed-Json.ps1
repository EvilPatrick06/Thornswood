<#
  Feed-Json.ps1

  The one way a channel's version.json is written (#1050).

      . (Join-Path $PSScriptRoot 'Feed-Json.ps1')

  Feed-Store.ps1 dot-sources it, so every script that receives and sends the
  feed has it. It is a file of its own so a harness that stands a stub in for
  Feed-Store.ps1 (to send nothing) still writes the feed the real way.

  Compact: no indentation and no line breaks. ConvertTo-Json without
  -Compress indents each level, which was about 960 of main's 7,789 bytes on
  12 Oct and meant nothing to the launcher, the site or any script, all of
  which parse it. -Depth 8 is the deepest any writer used, so no nested list is
  ever cut to its type name.

  No byte order mark: the launcher's reader stops on one and reports an
  unexpected character, which takes out the update check for everybody at
  once, including their route to a fix, and node refuses it too.

      ConvertTo-FeedJson $doc            the text
      Write-FeedVersionFile $path $doc   the file

  tests\test-1050-feed-compact.ps1 holds every writer to it and parses what it
  writes with the launcher's own VersionDoc.Parse.

  Keep it ASCII and Windows PowerShell 5.1.
#>

function ConvertTo-FeedJson($Doc) {
    return ($Doc | ConvertTo-Json -Depth 8 -Compress)
}

function Write-FeedVersionFile([string]$Path, $Doc) {
    if (-not $Path) { throw 'Write-FeedVersionFile needs the path of version.json.' }
    if ($null -eq $Doc) { throw "Write-FeedVersionFile was given no feed for $Path; nothing was written." }
    [IO.File]::WriteAllText($Path, (ConvertTo-FeedJson $Doc), (New-Object Text.UTF8Encoding($false)))
}
