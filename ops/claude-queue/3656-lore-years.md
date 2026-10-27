# 3656 Lore years, and the unused signing variable (#3717)

Issues #3656 and #3717. Pull request: the one that adds this note ("Carry
out Patrick's page answers on the lore years, the unused launcher art and the
signing variable"). Patrick answered both on the report page on 27 Oct:
Eirik has held the crown twenty-three years; a playable Legion veteran served
in the war about fifty years ago; delete AZURE_SIGNING_SUBSCRIPTION_ID.

## Commands, from the repository root, once the pull request is merged

1. The World page, live site: `.\scripts\deploy\Deploy-Docs.ps1 -Site`.
   Check https://thornswood.net/world says "twenty-three years" and "served
   in the war about fifty years ago".
2. The #lore post, live Discord. bot\content.py changed, so first the bot's
   code: `.\scripts\deploy\Install-Bot.ps1 -CodeOnly`. Then
   `.\scripts\deploy\Setup-Discord.ps1 -OnBox -Posts -Only lore,factions`,
   which rewrites only the #lore and #factions posts from bot\content.py.
   Check #lore says "who's had it twenty-three years" and #factions says
   "none has in fifty years".
3. #3717, the repository variable (Thornswood only; the fork's own copy in its
   `thornswood-signing` environment stays):
   `gh api -X DELETE repos/EvilPatrick06/Thornswood/actions/variables/AZURE_SIGNING_SUBSCRIPTION_ID`.
   Check: `gh api repos/EvilPatrick06/Thornswood/actions/variables --jq '.variables[].name'`
   prints AZURE_SIGNING_CLIENT_ID, AZURE_SIGNING_TENANT_ID and BUILD_RUNNER,
   and no subscription id. Patrick picked this delete on the report page
   (q-3717-subscription-var, A, 27 Oct); it is covered by his standing rules.

## Risks

None of the three takes anything down. The site step reloads only the public
pages. Install-Bot -CodeOnly restarts the bot for a few seconds. The Discord
step edits two read only posts. The variable is read by no
workflow (tests\test-release-workflow.ps1 checks that), so signing does not
change.

## Afterwards

Close #3656 and #3717 with what ran. No test task: a Claude reads the page,
the post and the variables list.
