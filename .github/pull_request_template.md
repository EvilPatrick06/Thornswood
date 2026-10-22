## What changed

<!-- One fix per pull request. Say what a person will notice, not the branch name.
Then what caused it and how that was measured: the log line, the file, the steps.
Closes #N when it finishes an issue nobody would notice. A fix people would notice
says Refs #N and carries its test task, which moves the issue to Done on merge.
That issue stays open until a main Ship puts the fix on the main server, and that
Ship closes it with this test task; never close it at the merge, or testers are
sent to look for a fix main lacks:
Test task for #N: <title, at most 45 characters>
Server: Main
1. Plain steps, then what should happen. -->

## Which parts it touches, and what runs after the merge

<!-- Tick every part this pull request changes. Developer-Guide.md, "After a pull
request is merged", has the command for each. They all run in the same sitting. -->

- [ ] The launcher, the game plugins or anything in a pack: a dev Ship
- [ ] The gamemode (`game\gamemode.js`): Deploy-DevGamemode, or Deploy-Gamemode then Deploy-Server
- [ ] The site's app or `site\public`: Deploy-Docs
- [ ] The public pages (`site\data\site`): Deploy-Docs -Site
- [ ] The bot (`bot`): Install-Bot -CodeOnly
- [ ] The voice service (`voice`): Install-Voice
- [ ] Only scripts that run on the machine that ships: nothing more
- [ ] Docs only

## Checked

<!-- What you ran and what it printed: the test harnesses you touched, a dev Ship,
what you saw in game. "Not run" is an answer; leave nothing blank. -->

## Before asking for a read

- [ ] It changes one thing. A branch that changes eight things is eight reviews.
- [ ] It fixes the cause, and says what the cause was. No band-aids: nothing that notices the damage and undoes it, no retry that hopes a race comes out right, no layer over an earlier band-aid (Developer-Guide.md, "Fix the cause, no band-aids").
- [ ] If it edits Shell.cs, Checks.cs, Keep.cs, Hold.cs, Updater.cs or Publish-Update.ps1 in a way that blocks others' work, there is a line in #staff-updates about it (`scripts/ops/Say-Staff.ps1`). No line for opening or merging the pull request itself (Patrick, 22 Oct).
- [ ] If it changes anything in Developer-Guide.md's settled design, the team agreed it in #staff-updates first.
- [ ] Anything it found or left unfinished is on the board (GitHub Issues).
