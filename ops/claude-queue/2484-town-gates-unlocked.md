# 2484: Town gates load unlocked from Thornswood-Last.esp (Wyrd)

Status: HOLD. Not ready until the #2484 PR is merged. It touches game\ (the Last plugin and the front plugin), so it waits for the 1.2.4 freeze to lift. Branch wyrd/2484-gates-unlocked, commit 5e49bac4.

## What changed
- Thornswood-Last.esp now overrides the Whiterun main gate (1b1f1:Skyrim.esm) and Riften's two outer leaves (42284, 42286) without their lock and script, so they load unlocked. New sha256 and size are in game/data/last-plugin.json.
- The front plugin's 30-second gate unlock timer (openTheGates) is gone.

## Steps for Claude, after merge
1. Thornswood-Last.esp ships in packs and from both game servers (#2486). Cut a dev release so clients get the new Last plugin, and deploy the dev server from the same main so its plugin matches.
2. On dev: walk in through Whiterun's main gate and Riften's main gate with no lock prompt. Claim a gate with the mold flow and check it still locks, then unclaim and check it opens.
3. Then live, the same way.
4. Post a Test task: comment on #2484 and close it.