# Records

What a release is checked against, kept apart from the scripts that write and
read it (issue #440, phase 8):

- `client-build.json`: the six SkyMP client files built from the fork, by
  hash, and the fork commit they came from. `scripts\release\New-ClientBuildRecord.ps1`
  writes it; Build-Launcher puts it inside the launcher, and Sync-Client and
  Ship refuse a client that is not this build.
- `server-build.json`: the server binary the same way.
  `scripts\release\New-ServerBuildRecord.ps1` writes it and Deploy-Server
  refuses any other binary.
- `steam-build.json`: the public Steam build of Skyrim last looked at and
  accepted. `scripts\dev\Check-Outside.ps1` goes red when Steam moves past it,
  which is the day to try the downgrade on one machine.
- `signing\`: the code signing setup, with its own README. It is switched off
  until it is finished.

Change a record only by running the script that writes it, in the same pull
request as the build or the fork commit it describes.
