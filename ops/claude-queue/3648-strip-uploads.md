# 3648 Gallery pictures lose what they say about where and when they were made

- **Issue / PR:** #3648, the pull request this note came in with.
- **Where:** the live site (Deploy-Docs), then one run on the box against the site's uploads. No game server, no bot install.
- **Needs first:** nothing. The site change takes effect for every sender (browser, any launcher) the moment it is deployed, so it does not wait on a Ship. The launcher half (Gallery.Submit cleans before it sends) goes out with the next main Ship like any launcher change; nothing to run for it.
- **Staff notice:** no. Nothing staff do changes.

What it does:

- The site takes the Exif (GPS position, camera, time), XMP, IPTC, comments, a phone's second picture after the end, and a recording's position, tags and times out of every picture and recording as it lands in uploads/, without re-encoding anything, and keeps the orientation and colour profile. /shot/<name> then serves only that.
- The privacy page says so (Last changed stays 26 October 2026, with the new wording's hash in page-versions.json).
- `scripts/vps/Strip-Uploads.ps1` runs the deployed site's own code over what is already in uploads/ and counts the files that held a position. The live check on 26 Oct (on #3648) found none of the 7 approved pictures with any; waiting and held files were not checked, and this covers them.

## Run, in this order, from the repository root at main

1. **The site.**

       pwsh scripts/deploy/Deploy-Docs.ps1 -Site

   The site should answer at the end.

2. **Clean what is already in uploads/ on the live box.**

       pwsh scripts/vps/Remote.ps1 -File scripts/vps/Strip-Uploads.ps1

   It prints one line for each file it cleaned (name and block kinds only, never what a block said) and ends with `N files looked at, M had blocks taken out, G held a position, F could not be cleaned`. Exit 0 when F is 0. It refuses and changes nothing if step 1 has not put the new server.js there. A file it could not clean is left as it was and named: put the names on #3648 for staff to look at (delete it through the hub if it is a submission that cannot be shown safely).

## Check afterwards

- Put the last line of step 2 on #3648 (how many held a position).
- Run step 2 a second time: it should say `0 had blocks taken out`.
- https://thornswood.net/privacy, under Gallery submissions, says the site takes the position, time and camera out as the file arrives.
- Then delete this note. #3648 stays open, in Done, until the main Ship that carries the launcher half; that Ship's run closes it. No Test task: nobody would see a difference in the game or on the gallery.

## Risks

- None for the game. The site restarts for a moment, as every Deploy-Docs -Site does. Step 2 writes each changed file beside itself and renames it over, so the site keeps serving while it runs.
- Old nightly backups still hold the files as they were; they go when their keeping time on the privacy page is up. If one from before this is ever restored (Restore-Box.ps1), run step 2 again.

## Release notes (draft)

- Pictures and recordings sent to the gallery no longer carry the location, time or camera a phone or camera wrote into them.

## News post (draft)

none
