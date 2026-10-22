# 2387 jump and sprint timers removed

> HOLD: do not run any step here until Claude has posted that 1.2.4 is out and PR #2606 is squash-merged on green.

Issue: #2387. PR: #2606 (Fixes #2387), branch waystone/2387-npc-sprint.

## What changed

game/plugins/thornswood-front.js no longer has ownTheCharacter, holdNpcClear or holdSprintGate. Nothing puts IsNPC, bSprintOK or AI driven back on a timer any more. The jump and sprint probe stays and only reads. The cause they were chasing was another launcher's MpClientPlugin.dll, which the fork's own client replaced on 20 September (1.1.61.1).

## Claude steps after merge

1. Ship Dev as usual with the merged main. This is a game plugin only: no engine bump, no records, no collection revision.
2. Ship Main with the next release once Dev is fine.
3. No VPS or server step.

## What to watch

In Data/Platform/thornswood-front.log, jump and sprint presses should read "played" with "IsNPC no, bSprintOK yes". If a press ever reads "refused" with IsNPC yes or bSprintOK no, reopen #2387 and attach that log with the client logs from the same minute.
