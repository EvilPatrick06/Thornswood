# Status

What is true now. Rewritten in place by whoever changes it; history is in git.

Last rewritten 22 Oct 2026, 9:10 AM (Patrick's time), when status moved here
from the vault's `wiki/status.md`. That file's last text is still in the vault,
on One. The Desk folds what is still true from it into this page the next time
it runs on One.

## The Desk

- One went offline at 8:39 AM on 22 Oct, so the Desk's session there is down.
- The Desk is moving to the cloud (#3229). Box access (Setup-CloudSsh) and
  Ship signing (the fork's signing workflow) work from the cloud. What a cloud
  session may run without asking still waits on Patrick's standing rules
  reaching its settings.

## Waiting for the Desk

- Merges, each once `Launcher builds (VPS fallback)` is green on its head:
  #3300, then #3303, then #3305. #3299 is red on a missing privacy entry in
  site/public/page-versions.json.
- After those: `Install-Bot.ps1 -CodeOnly`, then the bot's `--forum-check`, then
  `--apply`.
- Box checks: #2351 (Restore-Backup -CheckOnly, Delete-Person -Reapply against
  a scratch target), #2191 (voice /health).
- Checks that need a game client on One: #1032, #1031, #1269, #2434.
