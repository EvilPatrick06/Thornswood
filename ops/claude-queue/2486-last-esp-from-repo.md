# 2486 Thornswood-Last.esp goes out from the repo, not the collection

- **Lane:** Wyrd (Vortex/collection)
- **Issue / PR:** #2486 (closed, Needs playtest), #2537 and #2569 merged; dev server and dev release 20261016-010446-dev already carry Last.esp from the repo
- **Channel:** dev, then Vortex (collection revision)
- **Staff status updates:** #staff-updates (1549254991082946570)
- **Left:** only the Vortex collection revision that drops Thornswood-Last.esp, then the same on live. The dev deploy and dev Ship below are already done.

## Run
From the shared clone at the merge commit of #2537:
    .\scripts\deploy\Deploy-DevGamemode.ps1 -LoadOrder -Note "Thornswood-Last.esp now comes from the repo"
    then a dev Ship (.\scripts\release\Ship.ps1 for dev, as usual)
Then in Vortex: a collection revision that drops Thornswood-Last.esp from the collection, so it is not sourced twice. If that revision changes any other plugin, refresh records\collection-plugins.json with scripts\mods\New-CollectionPluginRecord.ps1 (it now leaves both our plugins out).

## Check afterwards
- Deploy-DevGamemode lists Thornswood-Last.esp under "will go up" (sha256 old -> new) the first time, and nothing on a second run.
- The dev Ship prints "the dev server already holds this release's Thornswood-Last.esp (... bytes, the same sha256)" when the pack changes it, and refuses with the Deploy-DevGamemode command if the server does not hold it (#2308 rule, now for both plugins).
- The dev pack carries Data\Thornswood-Last.esp; a dev client that updates gets the same sha256 as game\content\Thornswood-Last.esp.
- The dev server manifest (data\api\servers\thornswood\manifest.json) serves thornswood-last.esp.

## Risks and how to put it back
- A dev client whose Vortex still deploys the collection copy gets ours laid over it by the pack (same as Content.esp since 3 Oct). Load order is unchanged.
- Revert #2537 and run Deploy-DevGamemode -LoadOrder again to go back to the collection copy.

## Release notes (draft)
none (no change people would notice; it only changes how the late plugin is delivered)

## News post (draft)
none

## Test task (draft)
none
## Ran
- Dev release 20261016-010446-dev at 1:04 AM 16 Oct (Claude), from ops-batch at 7a02caa0, after Publish-Server dev (engine 3bdf3d3c, 10:45 PM 15 Oct), dev voice (-long-command-1) and Deploy-DevGamemode -LoadOrder (103 plugins, 10:48 PM). The dev server and the dev pack carry Thornswood-Last.esp from the repo. Left: the Vortex collection revision that drops it from the collection.
