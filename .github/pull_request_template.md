## What changed

<!-- One fix per pull request. Say what a person will notice, not the branch name. -->

## Which parts it touches, and what runs after the merge

<!-- Tick every part this pull request changes. CONTRIBUTING.md, "After a pull
request is merged", has the command for each. They all run in the same sitting. -->

- [ ] The launcher, the game plugins or anything in a pack: a dev Ship
- [ ] The gamemode (`tools\gamemode.js`): Deploy-DevGamemode, or Deploy-Gamemode then Deploy-Server
- [ ] The site's app or `tools\docs-app\public`: Deploy-Docs
- [ ] The public pages (`tools\docs-app\data\site`): Deploy-Docs -Site
- [ ] The bot (`tools\discord`): Install-Bot -CodeOnly
- [ ] The voice service (`tools\voice`): Install-Voice
- [ ] Only scripts that run on the machine that ships: nothing more
- [ ] Docs only

## Checked

<!-- What you ran and what it printed: the test harnesses you touched, a dev Ship,
what you saw in game. "Not run" is an answer; leave nothing blank. -->

## Before asking for a read

- [ ] It changes one thing. A branch that changes eight things is eight reviews.
- [ ] If it edits Shell.cs, Checks.cs, Keep.cs, Hold.cs, Updater.cs or Publish-Update.ps1, there is a line in #dev about it.
- [ ] If it changes anything in CONTRIBUTING.md's settled design, the team agreed it in #dev first.
- [ ] Anything it found or left unfinished is on the To Do List.
