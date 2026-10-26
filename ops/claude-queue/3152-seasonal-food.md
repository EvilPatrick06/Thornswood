# 3152 Seasonal herbs, festival dishes and brews (content plugin and gamemode)

- **Lane:** Claude (26 Oct 2026)
- **Issue / PR:** #3152, PR #3491
- **Channel:** dev now; main with the next main Ship, when Patrick says so.
- **Needs first:** PR #3491 merged.

## Why

Each season has its own two herbs, and a festival dish and a brew made from
them. Thornswood-Content.esp gains 22 records (four feasts, their four fine
records, four brews, eight recipes, two effects), so the server and every
client need the same plugin. The gamemode refuses an out-of-season herb and
gives a feast its help.

## Run (dev, touches the dev server and the dev release)

From the repository root, on main at the merge commit of PR #3491. The server
takes the content plugin and its load order before clients get the matching
release.

```powershell
./scripts/deploy/Deploy-DevGamemode.ps1 -LoadOrder -LoadOrderRefuse on -ShipFollows
$note = @'
Seasonal food and drink
- Lavender, Jazbay grapes, Snowberries and Juniper each grow in two seasons; out of season the plant is bare and says when it grows.
- Each season has a festival dish and a festival brew made from its two herbs, at the oven or the cooking pot.
- A festival dish is a feast: it fills more than a meal, and its help is stronger and wears off sooner.
'@
./scripts/release/Ship.ps1 -Channel dev -Notes $note -NoPause
```

The deploy should end with the reload or restart line it prints for a load
order change, and the Ship with `SHIP EXIT 0`.

## Check afterwards

- The dev server's `Thornswood-Content.esp` and the dev release's are both
  sha256 `bea10873c87b2c8bc0dc759ae286effc980723b17c5d8b84b6b671b8fdde57a0`.
- The dev server.log has no `outOfSeason` or `feastHelpOf` error after the
  reload.

## Risks

- A client on the old release has no feast or brew records; the load order
  refuse setting sends them to update first, as with any content change.
- The season of a herb follows the season clock; with seven real days a
  season, two of the four herbs are always bare.

## Main

With the next main Ship, when Patrick says so. Then the `Test task for #3152:`
block in PR #3491 is posted on #3152 as a Main test task, and #3152 closes.

## Draft news

The seasons now reach the kitchen. Lavender, Jazbay grapes, Snowberries and
Juniper each grow in two seasons, and every season has a festival dish and a
festival brew made from its own pair: the First Planting Loaf and Mead in
spring, the Midyear Jazbay Tart and Wine in summer, the Harvest's End Roast
and Ale in autumn, and the Saturalia Spice Cake and Mulled Mead in winter.
