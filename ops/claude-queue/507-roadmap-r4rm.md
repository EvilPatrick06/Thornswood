# 507 Roadmap row r4rm: deploy the property row to the live board

- **Lane:** Anvil (Installer), 17 Oct. Site lane is Herald's; this follows Herald's notes on the PR
- **Issue / PR:** #507, PR #2676 squash-merged as 9907f3b030e72590d6b81b8f406432a78be7fd38
- **Channel:** live site (thornswood.net). Dev site too if it serves the roadmap from its own board.json
- **Needs first:** nothing else. Run from the shared clone on main at or after `9907f3b0`, in PowerShell 7
- **Who runs it:** Claude. Lanes do not run Deploy-Docs

## What changed

Only the roadmap row `r4rm` ("Property you actually own") in `site\data\board.json`. Patrick chose A on #507 (17 Oct): the free claim at the door stands, so the row no longer says "Buy it, furnish it". It stays `done: false` until the playtest.

New text of the row's second cell:

    Claim a building for free at its door and the deed in your pack says it is yours. Lock it, have a smith cut keys, and carry its master key. The hold's steward can set rent and evict, and a claim nobody goes into for 14 days lapses

The rest of #2676 (a test harness, two workflow lines and a docs page) needs no deploy.

## Run

1. On One, in the shared clone, `git pull` to main at or after `9907f3b0`.
2. Deploy the one board:

       .\scripts\deploy\Deploy-Docs.ps1 -Board roadmap

   A plain `-Site` deploy does not replace the live `board.json`, so the row would not change. Do not use `-Boards` or `-SeedDocs`: those flatten every board typed on the site.
3. Check: open https://thornswood.net/roadmap and confirm the property row reads as above. On the box, `Select-String -Path C:\Thornswood-Docs\data\board.json -SimpleMatch -Pattern "Claim a building for free at its door" | Measure-Object | % Count` should print 1.

## Order and risk

- Order: any time after `9907f3b0` is on main. No game, launcher or engine step goes with it, and it does not wait on 1.2.4.
- Risk: low. `-Board roadmap` replaces only the roadmap board inside the live `board.json`, writes a `.bak` first, and moves the board's revision on so an open hub page reloads instead of saving over it. Anything typed into the roadmap board on the site since the last deploy is replaced by the repo's copy (it stays in the `.bak`). Other boards are untouched.
- Undo: put the `board.json` `.bak` that Deploy-Docs wrote back in place on the box. (`-PutBack` puts the last app back, not a board, so it is not the undo here.)

## Draft release note

The roadmap now describes property as it works: claim a building for free at its door and carry the deed, lock it, have a smith cut keys, carry the master key, and know the hold's steward can set rent or evict. A claim nobody goes into for 14 days lapses.

