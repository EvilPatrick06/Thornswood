# Active Issues

Every open bug and where it stands. Reference only, nothing here needs doing by a tester.

**SHIPPED** published, not yet confirmed by anyone. **BUILT** fixed, not yet published. **OPEN** not started. **UNCONFIRMED** fixed a while ago, never verified either way.

Anything confirmed working moves to Archive.

## Shipped

| Issue | Cause |
|---|---|
| World had no NPCs | Server refused all ten playable races via a hardcoded list |
| Looting armour stripped worn gear | Server rejected any two items sharing a body slot and unequipped both |
| Mod spells removed from hand | Server rejected spells it had not granted |
| Every door and chest unlocked | Client unlocked every reference the server tracked |
| Enemy health mirrored your own | Hosted NPC health was reported using your character's values |
| Enchantment damage did nothing | Client dropped enchantment hits before reporting them |
| Keyboard locked on load | Browser focus flag raised with no path left to lower it |
| Guards attacked on sight after death | Resisted arrest flag never cleared without a save load |
| Voice indicator stuck on LISTENING ONLY | Indicator asked the game browser, which no longer owns the mic |
| Whisper and yell did not switch | Mode change sent on a socket that had been closed |
| No warning before restarts | Not implemented |

## Built

| Issue | Cause |
|---|---|
| Launcher would not reopen after closing | Hidden voice window kept the process alive holding the instance lock |
| No field of view setting | Not implemented |

## Open

| Issue | Notes |
|---|---|
| Alt tabbed keyboard input reaches the game | Typing in another window moves your character |
| Typing in Docs enters game chat | Same cause as above |
| Chains and cage doors do not activate | Reported still broken after the handle fix |
| Bard instruments render badly | Not investigated |
| Emote wheel | Not investigated |

## Unconfirmed

| Issue | Notes |
|---|---|
| Dwemer security bars will not move with E | May be fixed by the activator change that fixed handles |
| Character creation freezes after login | Focus arbiter fix shipped, never verified |
| Compass does not black out undiscovered locations | Config shipped, never verified |
