# 3317 A faction's book follows its Leader role

- **Issue / PR:** #3317, the pull request this note came in with.
- **Where:** the site on the box (Deploy-Docs), then the dev server (Deploy-DevGamemode). Main takes the gamemode at the next main release, when Patrick says so.
- **Needs first:** nothing. The 16 Leader roles are in Discord since the #3354 run (22 Oct, Cloud Desk, #3317 comment of 1:57 PM).
- **Staff notice:** none. Staff do nothing differently. They no longer hand a faction's book on, because giving the Leader role in Discord moves it, and docs/systems/factions.md says so.

## Run, in this order, from the repository root at main after the merge

1. **The site: /api/allowed sends each faction's Leader role and who holds it (factionLeaderProfiles), and stops reading Faction Owner.**

       pwsh scripts/deploy/Deploy-Docs.ps1

   It should end with the site answering on its port. Until step 2 runs, the dev server's gamemode still asks for factionOwnerProfiles, which the site no longer sends, so nobody on dev can found a faction book for those few minutes. Books that already exist open as before.

2. **The dev server: the faction books follow the Leader role.** In pwsh, from the repository root:

```powershell
$note = @'
Faction books belong to the faction's Leader
- Each faction has one book in J, owned by whoever holds its Leader role in Discord.
- When the Leader role goes to somebody else, the book goes with it the next time they open J.
'@
./scripts/deploy/Deploy-DevGamemode.ps1 -Note $note
```

   It should print that the new gamemode loaded, and post the note to the dev updates channel.

## Check afterwards

- The dev server's door has the Leader roles, a few minutes after step 2 (it reads the site every five minutes):

      pwsh scripts/ops/Set-Door.ps1 -Root C:\Thornswood-Server-Dev -NoPause

  Under "faction leaders" it lists each Leader role held by somebody who has linked their account, with their profiles.
- `pwsh scripts/deploy/Setup-Discord.ps1 -OnBox -Audit` no longer needs the Faction Owner role for anything. If the audit still lists "role Faction Owner is not in the plan", it is the hand-made role and nothing reads it now. Its removal waits on Patrick's yes for -Prune.

## Risks

- Between steps 1 and 2 (a few minutes), nobody on dev can found a faction book.
- The live server keeps main's gamemode, which also asks for factionOwnerProfiles. From step 1 until the next main release, nobody on main can found a faction book. Books that already exist are unchanged.
- A faction book founded before this has no Leader role on it, and keeps the account rule it had. Staff can disband it, and its faction's Leader can found the faction's book.

## Release notes (draft, for the main release that carries it)

Faction books belong to the faction's Leader
- Each faction has one book in J, owned by whoever holds its Leader role in Discord.
- When the Leader role goes to somebody else, the book goes with it the next time they open J.

## News post (draft)

none
