# When a scanner calls the setup program malware

What to do when VirusTotal, Defender, SmartScreen or somebody's antivirus
flags `Thornswood-Setup-<date>.exe`. Nothing here is a fix for a real
detection: if a build is ever genuinely dirty, it comes off the site first and
is worked out afterwards. This page is for the ones that are wrong, which is
all of them so far.

## What was measured

27 September 2026, the live download, `Thornswood-Setup-20260927-0257.exe`,
SHA-256 `c1d2065f25291458d6748ff312efadf311202ae38c47971167a138e0120f258b`:

    https://www.virustotal.com/gui/file/c1d2065f25291458d6748ff312efadf311202ae38c47971167a138e0120f258b

5 of 71 engines flagged it, and every one of the five is a machine learning or
hash reputation verdict rather than a signature for a known family:

| Engine | What it said | What that is |
| --- | --- | --- |
| CrowdStrike Falcon | win/malicious_confidence_90% | a model's confidence score, no family named |
| APEX | Malicious | a model's verdict, no family named |
| McAfeeD | ti!\<hash\> | hash intelligence: the file is bad because other feeds say so |
| Trapmine | malicious.moderate.ml.score | a model's score |
| Kingsoft | a generic heuristic | a heuristic, no family named |

Windows reports the file as NotSigned. The version resource is filled in:
Title and Product are Thornswood Setup, Company is Thornswood, with a
copyright line, and Build-Launcher stamps FileVersion and ProductVersion from
the launcher's own version (`installer\setup\Bootstrap.cs:35-39`). VirusTotal
also tagged the file `detect-debug-environment` and
`packers: .NET executable`.

## Why an honest installer earns those verdicts

Five things about this program, all of them on purpose, are the same five a
dropper does.

- It is not signed. Authenticode is the one input every reputation system
  weighs heavily and the only one that carries across releases. Issue #390 is
  the lasting fix and it is deferred, so everything below is what can be done
  without it.
- It is a small .NET executable that downloads a much bigger payload and runs
  what is inside it (`installer\setup\Bootstrap.cs:693`, Download). That is
  the definition of a downloader. The one thing that makes ours different is
  that the payload is checked against the SHA-256 the site published before
  anything in it runs, and a file that does not match is deleted
  (`PayloadMatches` and `CheckPayload` in the same file).
- It ends other programs. StopSkyrim enumerates processes and used to call
  Kill on anything still alive (`installer\setup\Bootstrap.cs:930`). Killing
  a process with no consent is behaviour a model can see, so since this page
  was written it asks first: a Yes or No box naming what is still running,
  Kill only on Yes, and on No the install stops having changed nothing
  (`AskToClose`, same file). The enumeration itself stays, because a leftover
  Skyrim holds the game files open and the install genuinely cannot continue.
- Its resources have high entropy. The icon and the logo are compressed
  images sitting in `.rsrc`, which reads the same to an entropy check as a
  packed payload does.
- Its file name changes every release. `Thornswood-Setup-<date>.exe` is a new
  hash every build, so reputation never accumulates on the file. The product
  NAME is deliberately stable for the same reason, and must stay stable:
  Thornswood Setup, company Thornswood, from thornswood.net. Changing those
  strings throws away what little identity an unsigned build has.

`ti!<hash>` deserves its own line. McAfeeD is not looking at the file, it is
looking up a hash in a threat intelligence feed, and those feeds read
VirusTotal. So a detection there is downstream of the other four, and clearing
the model-based ones, plus community votes and a comment on the report, is
what eventually clears it. There is nothing in the binary to change for it.

## The checklist, once per flagged hash

Do this after a build is published and has been looked at on VirusTotal, not
before: the report has to exist first. Everything below needs the same three
facts, so write them once and paste them into each form.

    Thornswood Setup, the first-run installer for Thornswood, a private
    modded Skyrim multiplayer server at https://thornswood.net
    It downloads the Thornswood payload from thornswood.net, checks it
    against the SHA-256 the site published, unpacks it and runs the
    Setup.bat inside it. It is not code signed yet.
    File: Thornswood-Setup-<date>.exe
    SHA-256: <the hash of that exact file>
    Report: https://www.virustotal.com/gui/file/<sha256>

1. **VirusTotal, the report itself.** Get the hash the way the site gets it,
   in lower case: Publish-Installer prints it at the end of every publish
   (`scripts\release\Publish-Installer.ps1:238`), and the Downloads page shows
   it beside the size with the report link (`site\public\home.html:1315`).
   Open `https://www.virustotal.com/gui/file/<sha256>`, read which engines
   flagged it, and leave a community comment with the three facts above.
   `scripts\release\Publish-VirusTotal.ps1` posts that comment through the API
   when `VT_API_KEY` is set, so in practice this step is one command.
2. **Vote.** On the same report, a clean vote from the account that posted the
   comment. Votes and comments are what the smaller engines look at when
   somebody in their queue reads the case.
3. **Microsoft.** Defender and SmartScreen are the two that decide whether a
   stranger can install at all, so this one matters most. Submit the file as a
   suspected false positive at
   <https://www.microsoft.com/en-us/wdsi/filesubmission>, as a software
   developer, naming Thornswood Setup and thornswood.net and pointing at the
   Downloads page as the place it is published from. Microsoft's criteria for
   what it flags and why are at
   <https://learn.microsoft.com/en-us/windows/security/threat-protection/intelligence/criteria>.
   SmartScreen has no separate form; it follows Defender's verdict and the
   file's reputation.
4. **CrowdStrike.** Falcon false positives are raised through the CrowdStrike
   support portal, <https://supportportal.crowdstrike.com/>, which wants a
   Falcon subscription. Nobody here has one, so unless a tester who does
   raises it from their own console, the practical levers on Falcon are the
   VirusTotal comment, the votes, and signing when #390 lands. Say so plainly
   rather than pretending the ticket was filed.
5. **McAfee and Trellix.** The consumer McAfee and the Trellix products share
   the same intelligence. Their submission routes move about, so find the
   current one from their support site rather than trusting a link copied from
   here, and send the file with the three facts. Expect the `ti!<hash>`
   verdict to clear only after the report itself is clean, for the reason
   above.
6. **The small engines** (APEX, Trapmine, Kingsoft and whoever else is on the
   list that week). Each publishes a contact address on its own site, and the
   VirusTotal report links to the vendor page. One short message each, with
   the same three facts and the report link. They answer more often than the
   big ones do.
7. **Write down what was sent and when**, as a comment on issue #390, so the
   next person can see which vendors have already been asked and does not
   start again from nothing.

## Every release, not once

A new build is a new hash, and none of the work above carries over to it. So
after each `Package-Thornswood.ps1` and `Publish-Installer.ps1`:

- Take the hash Publish-Installer printed.
- Run `scripts\release\Publish-VirusTotal.ps1 -Path <the exe>` with `VT_API_KEY`
  set, which uploads the file if VirusTotal has never seen it and leaves the
  comment on the report either way. Without the key it says so and does
  nothing, so it is safe on any machine.
- Look at the report. If the count is zero, there is nothing else to do.
- If anything flagged it, work the checklist above for that hash.

What actually ends this is signing. Issue #390 moves reputation from a file
hash that changes every release to a certificate that does not, and until it
is done a low count on a fresh build is the best that can be expected. Keep
the identity strings stable, keep the ask before anything is ended, keep the
published SHA-256 and the report link on the Downloads page, and send the
false positive reports. That is the whole of what is available without it.
