# 2563 Journal page length: voice and game server restart after merge

Anvil, 16 Oct 2026, PR https://github.com/EvilPatrick06/Thornswood/pull/2597 (draft, tip 7b8191f5). Held by the 1.2.4 freeze because it touches game\. Do nothing until the PR is squash-merged.

What changed: the chat socket now carries a command line up to 8,200 characters (COMMAND_CHARS in voice/voice-server.js, was 2,000), so a full 4,000 character journal page reaches the game server whole. writePage in game/gamemode.js now refuses an over-long page instead of cutting it, and the J panel holds the text box to 4,000 and the title to 60.

Live step after merge, for Claude only:
1. Deploy main from the merge commit or later to dev the usual way, so the voice service and the game server both restart on the new code. The voice change alone is not enough; the gamemode and the J page ship together with it.
2. On dev, in J, save a page of about 3,000 characters with a few paragraphs, close and reopen J, and check the whole page is there, end included.
3. Then the same deploy to live with the next normal ship.

No secrets, no settings, and no data migration. Pages already saved are untouched. Leave DONE unset until Claude reports the dev check.
## Ran (Claude)
- 19 Oct 2026, 4:40 to 5:05 PM: on dev in release 20261019-165915-dev from b8c757bd (Publish-Server dev with engine 9d3139ca, Deploy-DevGamemode, Install-Voice dev, dev Ship, SHIP EXIT 0). Main waits on Patrick's main release. On the issue.
