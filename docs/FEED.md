# The update feed

Every Thornswood launcher decides what to download from one file:
`version.json` in the public repository `EvilPatrick06/Thornswood-Releases`.
This page is every field in it, who writes each one, who reads it, and what
goes wrong when it is wrong. File and line references are to the source repo
on 25 September (main at 044b737) unless they say otherwise.

## Where it is and how a launcher reads it

- **One file per branch.** The `main` branch is the live feed. The `dev`
  branch is the dev build's feed. A launcher reads the branch in its
  `config.json` `UpdateBranch`, `main` when empty (`Config.cs:135,280`); the dev
  build is installed with `UpdateBranch` and `Channel` set to `dev`
  (`DevBuild.cs:100-101`).
- **The request.** `GET https://api.github.com/repos/<UpdateRepo>/contents/version.json?ref=<branch>`
  with `Accept: application/vnd.github.raw`, no token unless the config holds
  one (`Updater.cs:42-55,157-169`). With no token, GitHub allows sixty of these
  an hour per address; a 403 or 429 is reported as a rate limit, not a fault
  (`Updater.cs:195-209`). While the game is running the launcher checks every
  30 seconds (`Shell.cs:1517,1534`).
- **Parsing.** `VersionDoc.Parse` with the .NET `DataContractJsonSerializer`
  (`Config.cs:569-578`). A byte order mark is skipped. A value of the wrong JSON
  type can make the serializer throw, and then the whole document is unread and
  every launcher reports no answer from the update source and shuts Play
  (`Config.cs:537-543`). Unknown fields are ignored.
- **On disk.** Publishers keep a clone beside the source repo:
  `Thornswood-Releases` on `main`, and the worktree `Thornswood-Releases-dev` on
  `dev` (`Publish-Update.ps1:111-129`).

## A real entry, trimmed

From `/home/user/thornswood-releases/version.json` (main, commit 51d1968).
`packs` holds 229 entries and `news` 40; one of each is shown. Nothing here is
a secret: the hashes are public and `discordAppId` is a public application id
(`Config.cs:160-164`).

```json
{
  "launcherVersion": "1.1.94",
  "launcherUrl": "https://api.github.com/repos/EvilPatrick06/Thornswood-Releases/releases/assets/587122255",
  "launcherSha256": "8d5ffda17c740f340c431236fb15df74fd83abc5e5dd742db85a21bdda09f950",
  "serverAddress": "192.135.112.23",
  "serverPort": "7777",
  "message": "",
  "packs": [
    {
      "id": "20260924-1810",
      "url": "https://api.github.com/repos/EvilPatrick06/Thornswood-Releases/releases/assets/587122257",
      "sha256": "1a67e3c99b1d6a7c4fc06be90a96795afefde0a40a105bf512e90c2f6b84b2c8",
      "notes": "The Downgrade button works on its own again.\nIt finds Steam's window however your Steam draws it, ..."
    }
  ],
  "news": [
    {
      "date": "9-24-2026 6:10 PM",
      "title": "The Downgrade button works on its own again.",
      "body": "It finds Steam's window however your Steam draws it, ...",
      "details": ["Launcher 1.1.94", "21 files to download, 17.4 MB"],
      "channel": ""
    }
  ],
  "updateRepo": "EvilPatrick06/Thornswood-Releases",
  "voicePort": "7778",
  "collectionUrl": "https://www.nexusmods.com/games/skyrimspecialedition/collections/7essxf",
  "maxOnline": 25,
  "mainVersion": "",
  "voiceUrl": "https://thornswood.net/voice",
  "discordAppId": "1549251507361292418",
  "siteUrl": "https://thornswood.net",
  "presenceImage": "https://thornswood.net/presence.png",
  "collectionRevision": 5,
  "clientRuntime": {
    "url": "https://api.github.com/repos/EvilPatrick06/Thornswood-Releases/releases/assets/583111894",
    "sha256": "3fb5bb91f773e065b85be1ce190e341e5394e059673bfcda1a0268a524f1ce5c",
    "bytes": 6538349,
    "forkCommit": "3cbf2f87"
  }
}
```

The dev feed (branch `dev`, commit d00a6f7) has the same shape with
`serverPort` `"7787"`, `voicePort` `"7789"`, `voiceUrl`
`"https://thornswood.net/voice-dev"`, `launcherVersion` `"1.1.92.1"`, pack ids
ending `-dev`, and a non-empty `mainVersion`.

## Top-level fields

"Saved" means the launcher writes the value into its own `config.json`, so it
stays after the feed changes, and a later feed can only replace it with
another non-empty value (`Shell.cs:4548-4592`). Every saved field is
overwritten from the publishing machine's own `config.json` on each Ship
(`Publish-Update.ps1:1316-1321`), so a wrong value on that machine moves every
launcher.

| Field | Type | Written by | Read by | If wrong or missing |
| --- | --- | --- | --- | --- |
| `launcherVersion` | string, dotted numbers | `Publish-Update.ps1:1251`, from `Version` in `launcher/app/Updater.cs:13` or Ship's dev number | `Shell.cs:4610`, `Updater.IsNewer` (`Updater.cs:87-108`) | Offered only when higher, part by part. Equal or lower offers nothing. A number that does not parse is offered whenever it differs. Not saved. |
| `launcherUrl` | string, https | `Publish-Update.ps1:1252`, the release asset API address | `Updater.SelfUpdate` (`Updater.cs:945-948`) | Empty: no launcher update is offered (`Shell.cs:4610-4611`). Must pass the host list below. |
| `launcherSha256` | string, 64 hex | `Publish-Update.ps1:1253` | `Updater.Download` (`Updater.cs:436-448`) | Empty: download refused. Mismatch: file deleted, update fails. |
| `serverAddress` | string | `Publish-Update.ps1:1316-1321` from config `ServerAddress`; `Set-Server.ps1:97`; `Set-Vps.ps1` | `Shell.cs:4548` | Saved. A change stops Ship unless `-MoveServer` (`Publish-Update.ps1:1289-1303`); the dev channel skips that check. Wrong: everybody connects to the wrong box. |
| `serverPort` | string | as above, `ServerPort` | `Shell.cs:4550` | Saved. Must be a string; the launcher field is a string. |
| `maxOnline` | number | `Publish-Update.ps1:1348-1352` | `Shell.cs:4551` | Saved when above 0. Written as a number because a quoted `"25"` reads as 0 (`Publish-Update.ps1:1344-1347`). |
| `collectionUrl` | string | `Set-Collection.ps1:98-101` only; Ship carries it forward untouched | `Shell.cs:4549` | Saved. Where the Collection button sends people. |
| `collectionRevision` | number | `Publish-Update.ps1:1371-1379`, read off the shipping machine's Vortex | `Shell.cs:4564`, then `Shell.cs:4814-4860` | Not saved. 0 or missing: the launcher says nothing about the collection being behind or ahead. Wrong: tells people to reinstall a collection that is fine. |
| `updateRepo` | string `owner/name` | `Publish-Update.ps1:1316-1321` from `UpdateRepo` | `Shell.cs:4573-4576`, `Feed-Rules.ps1:43-49` | Saved, quietly. Wrong: every launcher asks the wrong repository next time and may never find its way back. This is how a rename is announced (`Config.cs:505-507`). |
| `voicePort` | string | from `VoicePort` | `Shell.cs:4569-4572` | Saved, quietly. Used when `voiceUrl` is empty. |
| `voiceUrl` | string or absent | `Publish-Update.ps1:1328-1342`; `-dev` appended on the dev channel | `Shell.cs:4581-4585` | Saved, quietly. The one field that can be cleared: `""` sends launchers back to the raw port, absent changes nothing (`Config.cs:511-526`). |
| `discordAppId`, `siteUrl`, `presenceImage` | string | from config, `Publish-Update.ps1:1316-1321` | `Shell.cs:4579-4586` | Saved, quietly. The Discord presence card and its buttons. |
| `message` | string | Nobody: set by hand in the releases repo (`FeedNotice.cs:15-20`) | `FeedNotice.From` (`FeedNotice.cs:53-82`) | A bar above Play until a feed without it arrives. Never holds Play on its own. |
| `maintenance` | string (read as on only for `true`, `1`, `yes`, `on`) | By hand | `FeedNotice.cs:61-68,91-96` | On: Play held, button says CLOSED FOR MAINTENANCE. Absent in the current feeds. |
| `minLauncher` | string, dotted numbers | By hand | `FeedNotice.cs:58-77` | A launcher below it holds Play. A value that is not digits and dots is ignored, so a typo cannot lock everybody out (`FeedNotice.cs:98-120`). Absent in the current feeds. |
| `packs` | array | `Publish-Update.ps1:1210-1233` appends; `Repair-Manifest.ps1` removes | `Updater.Pending` (`Updater.cs:360-368`) | See below. |
| `optional` | array | `Publish-Pack.ps1:197-213` | Add-ons tab (`Shell.cs:2310`) | Absent in both feeds today; `scripts/release/optional-packs.txt` lists none. |
| `clientRuntime` | object | `Publish-Update.ps1:1236-1245`, only when the fork commit changed | `ClientRuntime.Heal` (`ClientRuntime.cs:261-269`) | Null or no `url`: a missing client file cannot be repaired from it. Same host and sha256 checks as a pack. |
| `news` | array, newest first, at most 40 | `Publish-Update.ps1:1507-1536`; `Publish-Server.ps1:415-520` | News tab (`Shell.cs:2965-3160`); `Publish-News.ps1` copies it to the site | Cosmetic. |
| `mainVersion` | string | `Publish-Update.ps1:1554-1599`: the main feed's `launcherVersion` on a dev ship, `""` on a main ship | Dev News tab header (`Shell.cs:2992-3002`) | Cosmetic. Stale today, see the end. |
| `serverPassword` | string | Nobody. `Publish-Update.ps1:1405-1408` deletes it on every ship | Declared at `Config.cs:497`, read by nothing since 1.0.197 | Must never come back: the feed is public. |

### A pack entry

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | `yyyyMMdd-HHmm`, `-dev` added on the dev channel, `-<part>` added when a release is split to stay under GitHub's 2 GiB asset limit (`Publish-Update.ps1:762,768-804`). Compared case-insensitively with `applied.txt`. An empty id is never offered. |
| `url` | string | The asset's API address in the feed's own `updateRepo` (`Feed-Rules.ps1:8-14,55-64`). Empty: the launcher skips it and writes it off as applied (`Shell.cs:4925-4941`). A url that answers 404 fails the whole update and Play stays off (`Shell.cs:4969-4984`). |
| `sha256` | string, 64 hex | Mandatory; checked after download (`Updater.cs:436-448`). |
| `notes` | string | The whole Ship note, first line first. The update card shows it (`Shell.cs:4669-4670`). |
| `name`, `bytes` | string, number | Optional packs only: the Add-ons tab shows them (`Config.cs:354-360`). Publish-Pack also writes `notes` as a file count. |

There is no `size` or `files` field on a pack. The files a pack wrote are
recorded on each machine in `Profile\Packs\<id>.files`, not in the feed
(`Updater.cs:293-299,621-622`). `NewsItem.files` exists and the News tab
shows it (`Config.cs:385-387`, `Shell.cs:3122`), but no publisher writes it any
more (`Publish-Update.ps1:1492-1496`).

A pack is a zip with a `game/` tree (into the game folder), a `profile/` tree
(into `Profile\Default`, and a carried plugin list is put in place at once),
and an optional `delete.txt` of game paths to remove. Each tree is fenced to
its folder (`Updater.cs:465-633`).

### A news entry

`date` (`M-d-yyyy h:mm tt`; older shapes are converted when read,
`Config.cs:407-438`), `title`, `body`, `details` (the note's `- ` lines, then
lines worked out from the diff), `channel` (`"dev"` or `""`). A Ship with the
same title and body as the newest entry adds nothing (`Publish-Update.ps1:1517-1536`).

## How a launcher decides what is new

1. It reads the feed and saves the saved fields (`Shell.cs:4540-4592`).
2. Pending packs are every `packs` entry whose `id` is not a line in
   `Profile\applied.txt`, in feed order (`Updater.cs:219-225,360-368`). Order
   matters: part one before part two.
3. The launcher is offered when `launcherVersion` is higher and `launcherUrl`
   is set.
4. Packs go in first, one by one, each id appended to `applied.txt` once it is
   in (`Updater.cs:486-491,632`). Then the launcher replaces itself through a
   swap script that keeps `Thornswood.exe.old` and puts it back if the new one
   does not start (`Updater.cs:945-977`).
5. A fresh install gets an `applied.txt` listing every pack in the feed at
   build time, because the installer already contains them
   (`Package-Thornswood.ps1:731-742`). The dev build copies the main build's
   `applied.txt` when it is installed (`DevBuild.cs:92-96`).

A machine that loses `applied.txt` asks for every pack on the feed again.

## Checks on every download

- **Host allow list.** https only, and the host must be `github.com`,
  `objects.githubusercontent.com`, `release-assets.githubusercontent.com`,
  `api.github.com` or `thornswood.net`, or under one of them
  (`Updater.cs:389-411`). The update token, if any, goes only to
  `api.github.com` (`Updater.cs:46-52`).
- **sha256.** Required for packs, the launcher and the client runtime; an empty
  one refuses the download (`Updater.cs:428-451`).
- **Signature.** `ExpectedSigner` is empty, so the launcher exe's signature is
  not checked yet (`Updater.cs:881-901`).
- **Publish side.** `Feed-Rules.ps1` refuses a new pack whose url is not a
  release asset in `updateRepo` (`Publish-Update.ps1:1216-1220`).
  `Check-Secrets.ps1` scans every zip and exe before upload
  (`Publish-Update.ps1:1039-1047`). Nothing is written to the feed if any asset
  failed to upload (`Publish-Update.ps1:1139-1172`), and `version.json` is
  written without a byte order mark (`Publish-Update.ps1:1601-1605`).

## Main and dev

- **main** is written by a main Ship from Patrick's machine, or by a hotfix
  Ship. It is also what `Set-Server.ps1`, `Set-Collection.ps1` and
  `Publish-Pack.ps1` edit.
- **dev** is written by `Ship.ps1 -Channel dev` from any branch on any
  developer's machine; the last dev Ship wins. Its launcher version is main's
  published number plus a fourth part, `.1`, `.2` (`Ship.ps1:487-552`).
- **After a main Ship** (not a hotfix), Ship copies the main feed over the
  dev feed, keeping dev's `serverPort`, `voicePort` and `voiceUrl`, pushes it,
  and copies the main baseline over the dev one (`Ship.ps1:1099-1140`). Dev
  launchers then take main's launcher and packs.
- **Before editing**, Publish-Update and Repair-Manifest pull the feed they are
  about to change (`Publish-Update.ps1:1180-1192`, `Repair-Manifest.ps1:66-79`).
  A refused push leaves the release marked NOT SHIPPED and resumable.

## There is no rollback

Nothing takes a pack back off a machine that applied it, and a launcher never
moves to a lower number. `IsNewer` only goes up (`Updater.cs:77-108`), and a
required pack id stays in `applied.txt`. Removing a pack from `packs` only
stops machines that have not taken it yet. To undo a bad release, ship a new
one with a higher launcher version and a pack that puts the files back. That
is what happened on 21 September, when 1.1.76 was undone by 1.1.77
(`Ship.ps1:497-503`). Optional packs are the one thing a person can remove
(`Updater.cs:717-879`).

## What looks wrong in the feeds today

- **The live feed still lists 164 packs no launcher can download**, ids
  `20260910-2345` to `20260914-1917`, all under the private source repository.
  Read off the clone: 164 of 229 `packs` urls are
  `repos/EvilPatrick06/Thornswood/releases/assets/...`. The dev feed had them
  removed on 24 September (dev commit e42a112). `Repair-Manifest.ps1` has not
  been run on main. Any launcher whose `applied.txt` is lost or incomplete
  fails on the first one and Play stays off (`Feed-Rules.ps1:15-26`).
- **The dev feed's `mainVersion` is `"1.1.37"`; main is on 1.1.94**, and all
  40 dev news entries are marked `"dev"`, 30 of which main has. On a dev Ship,
  `Publish-Update.ps1:1557-1561` reads `Thornswood-Releases\version.json`
  from disk without pulling it, so a machine with an old main clone writes an
  old number and marks everything dev. The dev launcher's News tab says so to
  testers (`Shell.cs:2999-3001`).
- **`Updater.cs:13` on main says 1.1.92** while the live feed says 1.1.94,
  from the two hotfix branches. `Bump-Version.ps1:66-112` reads the live feed
  and climbs past it, so the next main number is safe as long as the releases
  clone is pulled first.
