# Test These

Work down in order. Mark PASS, FAIL or SKIP under each one, put what happened in the box, and your name beside it.

If it fails, write what you saw in plain words. Do not work out why. Drop any file the test names into the Drive folder.

Build 1.0.193 and up. The version is at the bottom of the launcher.

Logs, all wiped at every game start so copy them before launching again:

```
C:\Thornswood\Game\Data\Platform\thornswood-front.log
C:\Thornswood\Game\Data\Platform\thornswood-voice.log
C:\Thornswood\Game\Data\Platform\thornswood-loadorder.txt
C:\Thornswood\Profile\launcher.log
```

## TEST 1. Launcher opens and closes

1. Open the launcher.
2. Close it with the X.
3. Open it again.
4. If it does not open, press Ctrl Shift Escape and look for Thornswood in the list.

Pass if it opens the second time. If not, note whether Thornswood was still in Task Manager.

## TEST 2. Log in with no red error

1. Press Play.
2. Watch the whole way through loading. Do not skip.
3. Reach your character.

Pass if there is no red text at any point. If there is, press tilde for the console, scroll up, and screenshot every line naming a mod that does not match. All of them, not just the first.

Grab `thornswood-loadorder.txt` either way.

## TEST 3. People in the world

1. Go to Whiterun and walk through the market.
2. Leave through the main gate.
3. Walk the road for two minutes.

Pass if you see townsfolk, wildlife, bandits or animals. Named quest characters and guards are deliberately absent, so do not count those.

## TEST 4. Armour stays on

1. Put on a full set of armour, every slot.
2. Equip a different chest piece.
3. Equip a helmet.
4. Equip a shield.
5. Equip a cloak if you have one.
6. Open your inventory and check everything is still worn.

Pass if each piece went on and nothing came off by itself. If it fails, note which two items you were wearing, whether everything came off or some of it, and whether you could put it back on.

Grab `thornswood-front.log`.

## TEST 5. Spells stay equipped

1. Read a spell tome. Prefer Odin, Apocalypse or Triumvirate over vanilla.
2. Equip the spell.
3. Cast it.
4. Wait ten seconds and check it is still in your hand.

If it fails, name the spell and the mod.

## TEST 6. Locks

1. Travel somewhere you have never been. A bandit camp or dungeon.
2. Find a chest or door that should be locked.
3. Try to open it, then pick it.

Pass if it was locked and lockpicking worked. Anywhere visited before this week may be permanently unlocked, so only a new location tests this.

## TEST 7. Enemy health and damage

1. Find a bandit or wolf on your own.
2. Hit it once and watch the health bar.
3. Keep going until it dies.
4. Note if the bar ever jumped back up.
5. Note if the bar moved when your own health moved.
6. Then get someone else to fight the same enemy with you.
7. Check you both see it take damage and both see it die.

## TEST 8. Enchanted weapons

1. Equip an enchanted weapon, any element.
2. Hit an enemy.
3. Watch for the effect and the extra damage.

## TEST 9. Keyboard on load in

1. Load into the world.
2. Straight away try to walk forward.
3. Open your inventory.
4. Open the map.

If the keyboard is dead, in this order: press Escape once and try to move, and write down whether that fixed it. If not, alt tab out and back, and write down whether that did. Escape is the fix that shipped, so which one worked is the answer.

Grab `thornswood-front.log`.

## TEST 10. Guards after death

1. Steal in front of a guard, or attack someone, to get a bounty.
2. When the guard approaches, resist arrest.
3. Let them kill you.
4. Respawn.
5. Walk up to a guard in the same hold.

Pass if the guard talks to you and offers the fine or jail. You keep the bounty, that is intended.

## TEST 11. Voice

Needs two people.

1. Get in world with someone standing near you.
2. Look at the microphone icon at the bottom of the screen.
3. Hold V. The icon should turn green while held.
4. Talk. Ask if they heard you.
5. Let go of V. Talk again. Ask if they can STILL hear you.
6. Press B. The word should change between WHISPER, LOCAL and YELL.
7. Set whisper and walk away until they stop hearing you.
8. Set yell and do the same. Yell should carry much further.

Step 5 matters most. If they hear you with the key released, say so straight away.

Grab `thornswood-voice.log` and `launcher.log`.

## TEST 12. Restart warning

1. Ask Gavin to send a test restart while you are playing.
2. Watch the chat.

Pass if a message says what is happening and how long, then more as it counts down.

## TEST 13. Field of view

1. In the launcher open Display. The Field of view box should read 65.
2. Press Apply without changing it. Start the game. Nothing should look different.
3. Quit. Set it to 90. Press Apply. Start the game.

Pass if at 90 the view is noticeably wider.

## TEST 14. Chains and cage doors

Press E on a pull chain, a lever, and a cage gate.

## TEST 15. Dwemer bars

In any Dwemer ruin, press E on the control for the sliding bars over a doorway.

## TEST 16. Compass

Look at the compass near an undiscovered location. It should show a blacked out marker rather than nothing.

## TEST 17. New character

Make a fresh character and wait two minutes after logging in. It used to freeze a few seconds in and need Task Manager.

## Do not report these

Typing in another window still moves your character. Bard instruments look wrong. Mod settings menus reset every session. NPCs stand still when nobody is near them. You cannot save.
