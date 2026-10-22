# 2267 /needs says the needs bars as a line of text

**Dev ran 12 Oct 2026: Deploy-DevGamemode a818d143 at 2:13 AM, dev Ship 20261012-021714-dev at 2:17 AM. Left: main.**

- **Lane:** Claude (overnight run, survival-property)
- **Issue / PR:** #2267, #2342 (merged as bdc7787d59935a61d98317cb04530a27350f7e4a)
- **Channel:** dev (main waits on Patrick's word)
- **Staff status updates:** #staff-updates (1549254991082946570)
- **Needs first:** nothing. If #2246's note (2246-rest-places.md) is queued too, both are gamemode changes and can share one Deploy-DevGamemode and one dev Ship.

## Run
From the shared clone, current with origin/main (at or after bdc7787d):

    .\scripts\deploy\Deploy-DevGamemode.ps1
    .\scripts\release\Ship.ps1 -Channel dev "Type /needs to see your needs as text
    - With the needs bars hidden in Settings, typing /needs in the chat says your hunger, thirst, rest and warmth as one line.
    - The help in the game, the launcher's Help and the Settings line under the needs bars say so."

The gamemode deploy is the server half (the /needs answer and the /help list). The dev Ship carries the help panel's Living text (game/ui/thornswood-help.js) and the launcher's lines (Help.cs, Keys.cs, ui.xaml, Thornswood.ini comment). The command works with the gamemode alone; the Ship only brings the help text.

## Check afterwards
On dev, with a character in the world:
- Type `/needs`: one line, "Hunger N% (band), Thirst N% (band), Rest N% (band), Temp <word> N, warming/cooling toward N. ... The Body page on K says what sets each one." `/need` says the same.
- Sit down and type it again: it ends with "You are resting, sitting." (or the place).
- `/help` names /needs in its "Typed in the chat:" list.
- After the Ship: F7, Living, names /needs; launcher Settings, the line under "Show the needs bars on screen" names it.
- In the creation hall, `/needs` says the needs start once you arrive in your town.

## Risks and how to put it back
- Gamemode restart on dev only. It reads and changes no meter.
- Put back: `.\scripts\deploy\Deploy-DevGamemode.ps1 -PutBack` for the gamemode; revert the merge for the help text.

## Release notes (draft)
Type /needs to see your needs as text
- With the needs bars hidden in Settings, typing /needs in the chat says your hunger, thirst, rest and warmth as one line.

## News post (draft)
none

## Test task (draft, for closing the issue once the fix is on main)
Test task: Type /needs to see your needs as text
1. In the launcher, open Settings and untick "Show the needs bars on screen", then play.
2. Once you are in your town, type /needs in the chat and press Enter.
3. Sit down on a chair and type /needs again.
4. Type /need as well.
What should happen: each time one line says your Hunger, Thirst and Rest as a per cent with how you are doing, and your Temp as a word and number, matching the Body page on K. Sitting adds that you are resting. /need says the same as /needs.
