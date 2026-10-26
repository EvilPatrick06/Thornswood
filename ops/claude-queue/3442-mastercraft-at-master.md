# 3442 Mastercraft: a smith's 120% repair waits for Master (dev gamemode, then a dev Ship)

- **Issue / PR:** #3442, the pull request this note came in with.
- **Channel:** dev.
- **Needs first:** nothing. The rule is in the gamemode; the repair panel's note is in the client (game/ui/thornswood-repair.js, packed by thornswood-front.js), so a dev Ship carries that one line. The gamemode works without the Ship: until it, the old panel note still says the half that makes a kit mends to 120%, while each row already shows the right number.
- **Staff notice:** no. Nothing staff do changes.

What it does: Patrick picked A on 26 Oct (report page). A Weapon Kit or an Armor Kit mends to 120% only for an Edgewright or a Platewright at Master in their own half. Below Master they mend to 100%, like anybody else. The Sewing Kit is unchanged: a Haberdasher of any rank mends to 120%, because it is not the Tailor's Master perk.

## Run, in this order, from the repository root at main after the merge

1. **The dev gamemode.**

       pwsh scripts/deploy/Deploy-DevGamemode.ps1

   It should report the dev server came back on the gamemode it sent.

2. **A dev Ship**, for the panel note. It can ride with the next dev Ship rather than one of its own.

       pwsh scripts/release/Ship.ps1 -Channel dev

## Check afterwards

- `node tests/test-1384-condition.js` on the merged tree: 138 passed, 0 failed.
- On dev, as a novice Edgewright with a Weapon Kit and a sword below 100%: the repair panel row says "Weapon Kit, to 100%". As a Master Edgewright the same row says "to 120%".
- Then put what ran on #3442 and move it to Done (`board: Done`): it closes with its main test task once a main Ship carries it.

## Risks and how to put it back

- A smith below Master who already mended a piece to 120% keeps it; nothing is taken back. Only new repairs change.
- Put back: `pwsh scripts/deploy/Deploy-DevGamemode.ps1 -PutBack`.

## Release notes (draft)

Mastercraft is the Master smith's
- A Weapon Kit or an Armor Kit mends a piece past new, to 120%, only for an Edgewright or a Platewright at Master. Below Master your own kit mends to 100%, like anybody else's.

## News post (draft)

Mastercraft means something again: only a Master Edgewright or Platewright mends a piece past new, to 120%. Below Master, your own kit brings it back to sound.

## Test task (draft, for closing the issue once it is on main)

Test task: Only a Master smith mends past new
Server: Main
1. Play a smith who is not yet Master, as an Edgewright or a Platewright.
2. Make or get the kit your half makes: a Weapon Kit for an Edgewright, an Armor Kit for a Platewright.
3. Wear down a weapon or a piece of armour in a fight, then open your inventory and press the key the bottom line names to open the repair panel.
4. Look at the row for that piece, then press Mend.
What should happen: The row says your kit brings the piece back to new, not past it, and after Mend the piece's name has no percentage on it. A smith at Master in the same half sees the row go past new, and the piece's name shows more than full condition after Mend.
