<#
  Note-Rules.ps1

  What release notes may say. Ship.ps1 dot-sources this and refuses notes that
  break it, before anything is built. tests\test-note-rules.ps1 drives the same
  function, so the rule and its test cannot disagree.

  WHY IT EXISTS. Release notes are read by customers in three places: the
  launcher's News tab, the site's News page and Discord. CONTRIBUTING.md says
  plain words, never "player", no em dashes, and never pull request numbers or
  branch names in them. Ship checked only that there was a title and a detail
  line (25 September), so on 26 and 27 September these went out anyway:

    "This is what players actually got from demoting 1.1.92.1 through 1.1.95.4"
    "Place no longer throws walked is not defined (fireWalked / PR #239)"
    "Server load order is kept after Fix PutInServerOrder"
    "Autoplay uses WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS instead of
     EnvironmentOptions that faulted CreateAsync on One"
    "Bar covers whole run; every stop says why.#617 #618"

  and "Launcher 1.1.101" twice in one list.

  WHAT IT REFUSES, in the title, the body and every detail line:
    - the word player or players
    - an em dash
    - an issue or pull request number (#123), "PR", "pull request"
    - a code file name (.cs .ps1 .js .dll .json .exe .xaml .py and the like);
      a mod's .esp name is allowed, people see those in Vortex, and so is a
      .swf, which SkyUI's own error box names
    - our own shop words: demoting, worktree, cherry-pick, squash, CI
    - an environment variable (WORDS_LIKE_THIS)
    - a code identifier: camelCase, or three or more joined capitalised words
      (PutInServerOrder, EnvironmentOptions); a short list of ordinary names
      (SkyUI, SkyMP, GitHub, YouTube, WebView) is allowed
    - the same line twice
  Each problem comes back as one line saying what and where, so the person
  shipping can rewrite it rather than guess.
#>

$NoteAllowedNames = @('SkyUI', 'SkyMP', 'SkyrimPlatform', 'GitHub', 'YouTube', 'TikTok', 'VirusTotal',
                      'WebView', 'NirnLab', 'SunHelm', 'RaceMenu', 'MaxOnline', 'PayPal', 'JContainers')

function Get-NoteProblems([string]$Notes) {
    $problems = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    $lines = @($Notes -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $n = 0
    foreach ($raw in $lines) {
        $n++
        $line = ($raw -replace '^\s*-\s*', '').Trim()
        $where = if ($n -eq 1) { 'the title' } else { "line $n" }
        $short = if ($line.Length -gt 60) { $line.Substring(0, 57) + '...' } else { $line }

        $key = $line.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { $problems.Add("$where repeats an earlier line: '$short'"); continue }
        $seen[$key] = $true

        if ($line -match '(?i)\bplayers?\b') { $problems.Add("$where says player; the people in the world are customers, testers or people: '$short'") }
        if ($line.Contains([string][char]0x2014)) { $problems.Add("$where has an em dash; use a comma or a full stop: '$short'") }
        if ($line -match '#\d+' -or $line -match '\bPR\b' -or $line -match '(?i)\bpull request') { $problems.Add("$where names an issue or pull request; say what changed for the person instead: '$short'") }
        if ($line -match '(?i)\b[\w-]+\.(cs|ps1|psm1|js|ts|dll|json|exe|xaml|py|bat|cmd|pdb|txt|log)\b') { $problems.Add("$where names a code file: '$short'") }
        if ($line -match '(?i)\b(demot(e|ed|ing)|worktrees?|cherry-?pick(ed)?|squash(ed)?)\b' -or $line -cmatch '\bCI\b') { $problems.Add("$where uses a word from how we work, not from the game (" + $Matches[0] + "): '$short'") }
        if ($line -match '\b[A-Z][A-Z0-9]*_[A-Z0-9_]+\b') { $problems.Add("$where names a setting or variable (" + $Matches[0] + "): '$short'") }
        foreach ($m in [regex]::Matches($line, '\b[A-Za-z][A-Za-z0-9]*\b')) {
            $w = $m.Value
            if ($NoteAllowedNames -contains $w) { continue }
            $camel = $w -cmatch '^[a-z]+[A-Z][A-Za-z0-9]*$'
            $humps = ([regex]::Matches($w, '[A-Z][a-z]+')).Count
            $pascal = $w -cmatch '^[A-Z][a-z]+([A-Z][a-z0-9]+){2,}$' -and $humps -ge 3
            if ($camel -or $pascal) { $problems.Add("$where names something in the code ($w): '$short'"); break }
        }
    }
    return $problems.ToArray()
}
