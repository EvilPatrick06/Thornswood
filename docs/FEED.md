# The update feed

Every Thornswood launcher decides what to download from one file:
`version.json`. It is served from **thornswood.net** (`/feed/version.json`
live, `/feed-dev/version.json` for dev), and since #907 from nowhere else:
the GitHub repository `EvilPatrick06/Thornswood-Releases`, once the feed, its
fallback and the home of the release baseline, is retired. This page is every
field in it, who writes each one, who reads it, and what goes wrong when it is
wrong.

## Where it is and how a launcher reads it

### Host cutover (#649) - live URL shape

Confirmed with Website. Code signing is on since 27 Sep; what it checks and
what it does not is under "Checks on every download".

| What | URL |
| --- | --- |
| Live `version.json` | `https://thornswood.net/feed/version.json` |
| Dev `version.json` | `https://thornswood.net/feed-dev/version.json` |
| Live assets | `https://thornswood.net/feed/assets/<sha256>` |
| Dev assets | `https://thornswood.net/feed-dev/assets/<sha256>` |

- **The request.** The launcher reads `config.json` `UpdateFeedUrl` (a direct
  https GET of `version.json`). Defaults in `Config.AfterLoad`: main -> live
  URL above; `Channel` or `UpdateBranch` `dev` -> dev URL (`Config.cs`,
  `Updater.Check`). Host allowlist includes `thornswood.net`.
- **Conditional, since #445.** `Updater.FromSite` keeps the last document it
  read with the `ETag` the site sent, sends `If-None-Match` on the next check,
  and reads a 304 as that same document. The site answers the tag it issued
  with 304 and no body (`site/server.js`, the `/feed/version.json` route). The
  launcher asks every thirty seconds while the game runs, and the document is
  about ninety kilobytes, so that is roughly ten megabytes an hour per launcher
  saved without slowing the check down. The tag and the document are held in
  memory, never in `config.json`: a tag without the document it belongs to
  would ask, be told nothing had changed, and have nothing to read.
  `Cache-Control` stays `no-cache`, which means ask every time, so a release is
  still seen inside the server's five minute window.
- **No fallback since #907.** Until then a site feed that did not answer sent
  the check, at most once every five minutes, to the GitHub Contents API on
  `UpdateRepo` (Thornswood-Releases). That is gone from the launcher: a miss is
  what the caller gets, which reads as no answer rather than as no update, so
  the in play countdown clock is left where it is and the next check, thirty
  seconds on, asks the site again. `UpdateRepo` and `UpdateToken` stay in
  `config.json` only so an old one still loads.
- **Launchers in the field.** Every launcher from the #649 cutover on (26 Sep)
  reads the site first, so deleting the repository changes nothing for it: its
  old fallback asks a repository that answers 404 while the site is down, and
  the site answering is all it needs. A launcher last run before 26 Sep reads
  only GitHub, so once the repository is deleted it finds no feed and has to be
  reinstalled from the site; `site\data\known.md` says so to the person.

### Downloads come from the site (#897)

Asked for by Patrick on 28 Sep: "let's get it so we don't need the repo and we
use the website".

- **Where the bytes are.** On the VPS, `C:\Thornswood-Docs\feed\assets\<sha256>`
  and `C:\Thornswood-Docs\feed-dev\assets\<sha256>`, served by `site\server.js`
  at the asset urls in the table above, with Range resume and immutable
  caching. Each channel has its own folder and holds its own copy: a file both
  feeds name is stored twice, once in each. The route answers only a name of
  64 lowercase hex characters; there is no listing of the folder, and a
  `.part` left by a dropped send is never served.
- **What is up there, 28 Sep.** The one-off copy below was run that day: it
  sent 2 assets to `feed` (6.7 MB) and 25 to `feed-dev` (339.6 MB), each
  checked against the feed's sha256 first, and wrote no `version.json`. After
  it, every asset both live feeds name answers at its site url with the size
  GitHub recorded for it (77 of 77 on main, 94 of 94 on dev). On disk: `feed`
  79 files, 371 MB; `feed-dev` 100 files, 564 MB; 75 files (354 MB) are in
  both. Ten files no feed names any more (old launchers and client runtimes,
  35 MB) and two old `version.json` copies in `feed-dev` are left for a person
  to clear.
- **How a release gets there.** `Publish-Update.ps1` sends every pack, the
  launcher and the client runtime with `Remirror-Site-Feed.ps1 -Send` (scp to
  `<sha256>.part`, then renamed) BEFORE `version.json` is written, and names
  them by their site url. An asset that does not land stops the publish with
  the feed untouched. The `-AssetHost github` path it kept for rolling back
  went with the repository (#907).
- **The urls already on a feed** move over with `Move-FeedUrlsToSite`
  (`Feed-Rules.ps1`): each GitHub url whose bytes the site answers for (a HEAD
  on the asset url, and its size when the feed gives one) is rewritten, and any
  other stays. Every Ship does it for its own channel;
  `Repair-Manifest.ps1 -MoveToSite` does it without a release and sends the
  feed.
- **The old bytes** went up once with `scripts\oneoff\Copy-ReleaseAssets-ToSite.ps1`,
  which read both live feeds, downloaded each missing asset, checked it against
  the feed's sha256 and sent it. It never wrote a feed. It reads GitHub, so it
  does nothing once the repository is gone.
- **Launchers in the field** need nothing new: `thornswood.net` has been on the
  host allow list since before 25 Sep, and a download is checked for https, the
  host and the sha256, plus the signer for a launcher exe (see "Checks on every
  download").

### The feed store on the VPS (#907)

Patrick, 28 Sep: "I just want the repo deleted in general if we won't be using
it anymore". Until then every script that edits a feed pulled, committed and
pushed a clone of Thornswood-Releases beside the repository, and the baseline
Ship diffs against (`published.json`) was committed there too. Both live on
the VPS now, beside the feed the site already serves:

| On the VPS | What | Served |
| --- | --- | --- |
| `C:\Thornswood-Docs\feed\version.json` | the live feed | yes, `/feed/version.json` |
| `C:\Thornswood-Docs\feed\published.json` | the live baseline | no |
| `C:\Thornswood-Docs\feed\launchers.txt` | every launcher version the channel has published, oldest first | no |
| `C:\Thornswood-Docs\feed\releases.txt` | every release the feed has named, oldest first, one tab separated line each: id, channel, launcher, packs, baseline, commit, tag (#444, `Get-FeedStoreReleases`) | no |
| `C:\Thornswood-Docs\feed\history\<utc stamp>-<name>` | each of those files as it was before it was replaced | no |
| `C:\Thornswood-Docs\feed\assets\<sha256>` | the downloads | yes |

and the same under `feed-dev` for dev. `site\server.js` answers only
`/feed[-dev]/version.json` and `/feed[-dev]/assets/<64 hex>`, so nothing else
in those folders can be fetched: `tests\test-feed-store.ps1` asks a copy of
the site for `published.json`, `launchers.txt`, `history\`, a `.part` and
`read.json` under both and gets 404 for each. Deploy-Docs denies the site
process write to both folders (#923), so only a publisher over ssh writes them.

- **The one piece of code.** `scripts\release\Feed-Store.ps1`. `Receive-FeedStore`
  fetches the files into this machine's working folder for the channel,
  `%LOCALAPPDATA%\Thornswood\feed\main` or `\dev` (not a git repository), checks
  each against the sha256 the VPS gave for it, writes `read.json` with those
  sha256s, and keeps the last twenty of each in `backup\`. `Send-FeedStore`
  sends a file back to `<name>.part` and, in one step on the VPS, checks that
  every file this folder read still has the sha256 it had, copies the one it
  replaces into `history\`, and renames the `.part` over it (`File.Replace`, so
  the site never answers 404 in between). If anything moved up there it
  replaces nothing and throws: that is two publishers at once, the push git
  used to refuse.
- **Who uses it.** Ship and Publish-Update receive both files at the start
  (a run that sends nothing, Ship `-DryRun`, uses what it last received),
  ask again before editing the feed (a feed edited meanwhile is received again
  and the release goes on top; a baseline moved meanwhile stops the release
  with nothing written), send `version.json`, then the baseline. Repair-Manifest,
  Set-Server, Set-Collection, Publish-Server's news entry and Publish-Pack
  receive, edit and send the feed the same way. Remirror-Site-Feed sends
  `version.json` through it too. Main and Dev publish to their own stores.
  A Main Ship never replaces the Dev feed or baseline.
- **The dev number.** Ship climbs a dev build's fourth part past every
  version in `feed-dev\launchers.txt`, which every send of the dev feed adds
  to, and past main's feed as the site serves it. Until #907 it read the same
  out of the dev branch's git history.
- **The move.** `scripts\oneoff\Move-FeedStore-ToVps.ps1` copied the last
  baseline each clone held, and every launcher version its history named, to
  the VPS, read both back byte for byte, and saved the whole repository as a
  git bundle under `%LOCALAPPDATA%\Thornswood\feed`. #907 has the steps.
- **When a baseline is lost.** Put the last good one back from `history\` on
  the VPS or from any shipping machine's `feed\<channel>\backup\`, or run
  `Publish-Update.ps1 -Baseline` after the launcher has brought the game up to
  date.
- **Announce a move.** The feed field `updateFeedUrl`: publish the new URL
  under the old feed first, then move. Shell saves it quietly into
  `config.json`.
- **What the log says.** One line per feed address, written once and again if
  it changes: `Update checks read <url>.` (`Shell.OnVersionDoc`). A check that
  could not be made at all while the game runs writes one line a session with
  what came back (`Shell.CheckUpdatesInPlay`).
- **Parsing.** `VersionDoc.Parse` with the .NET `DataContractJsonSerializer`.
  A byte order mark is skipped. A value of the wrong JSON type can make the
  serializer throw, and then the whole document is unread and every launcher
  reports no answer from the update source and shuts Play. Unknown fields are
  ignored.
- **The remirror.** `scripts\deploy\Remirror-Site-Feed.ps1`, which
  `scripts\release\Publish-PostShip.ps1` runs at the end of every release for
  the channel that shipped, checks every asset the feed names is on the site,
  sends any that are missing, and sends `version.json` last, through the store,
  so the feed never names bytes the site does not hold. After a Ship it finds
  `version.json` already there. `-Check` says what it would send and sends
  nothing. Handed an old clone with `-FeedDir`, it replaces whatever the site
  has, as it always did, and says so.

## A real entry, trimmed

From the live feed as it stood on 26 Sep, then in `EvilPatrick06/Thornswood-Releases` (main, commit a22e4ef).
`packs` holds 69 entries and `news` 40; one of each is shown, trimmed. Nothing
here is a secret: the hashes are public and `discordAppId` is a public
application id (`Config.cs:160-164`).

```json
{
  "launcherVersion": "1.1.95",
  "launcherUrl": "https://api.github.com/repos/EvilPatrick06/Thornswood-Releases/releases/assets/591560398",
  "launcherSha256": "8dc36e32eb3dde35691e7a68e46195c6354968c3ea01585d03eb53289dca3070",
  "serverAddress": "192.135.112.23",
  "serverPort": "7777",
  "message": "",
  "packs": [
    {
      "id": "20260915-0030",
      "url": "https://api.github.com/repos/EvilPatrick06/Thornswood-Releases/releases/assets/565069058",
      "sha256": "5bf7ff5c7009e24a8c21e599bb732ba11402035a7a4199d91cdf3180360cf1b3",
      "notes": "Connect your Discord from the launcher"
    }
  ],
  "news": [
    {
      "date": "9-26-2026 10:09 PM",
      "title": "What arrived with launcher 1.1.95",
      "body": "The last main note only said demoting was promoted. This is what players actually got ...",
      "details": ["A sealed scroll opens Thornswood: click to open, Continue to characters; ...", "5 files to download, 48.4 MB"],
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
    "url": "https://api.github.com/repos/EvilPatrick06/Thornswood-Releases/releases/assets/591302878",
    "sha256": "efc8debfc3cd480183ab5d229b241e198f06f942b99a50baa50b172891b35726",
    "bytes": 6356315,
    "forkCommit": "5c54e8b9"
  }
}
```

Those `api.github.com/.../releases/assets/<id>` addresses are what the
publisher wrote before #445, and a release published since #445 wrote the
browser download address on the GitHub side. Both stop working when
Thornswood-Releases is deleted, which is why every one is moved to the site
first (#897, #907). A release published since #897 writes the site address.

The dev feed (branch `dev`, commit 12f71c8) has the same shape with
`serverPort` `"7787"`, `voicePort` `"7789"`, `voiceUrl`
`"https://thornswood.net/voice-dev"`, `launcherVersion` `"1.1.95.11"`,
`collectionUrl` ending `7essxf` where main's then ended `ombo2a` (both end
`7essxf` since), pack ids ending `-dev`, and a non-empty `mainVersion`.

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
| `launcherUrl` | string, https | `Publish-Update.ps1`: since #897 the site address `/feed[-dev]/assets/<sha256>` | `Updater.SelfUpdate` (`Updater.cs:945-948`) | Empty: no launcher update is offered (`Shell.cs:4610-4611`). Must pass the host list below. |
| `launcherSha256` | string, 64 hex | `Publish-Update.ps1:1253` | `Updater.Download` (`Updater.cs:436-448`) | Empty: download refused. Mismatch: file deleted, update fails. |
| `serverAddress` | string | `Publish-Update.ps1:1316-1321` from config `ServerAddress`; `Set-Server.ps1:97`; `Set-Vps.ps1` | `Shell.cs:4548` | Saved. A change stops Ship unless `-MoveServer` (`Publish-Update.ps1:1289-1303`); the dev channel skips that check. Wrong: everybody connects to the wrong box. |
| `serverPort` | string | as above, `ServerPort` | `Shell.cs:4550` | Saved. Must be a string; the launcher field is a string. |
| `maxOnline` | number | `Publish-Update.ps1`, from `records\most-online.json` by way of `scripts\deploy\MaxOnline.ps1` (#481) | `ShellUpdate.cs:120` | Saved when above 0. Written as a number because a quoted `"25"` reads as 0. The Play page prefers the number the running server announces as `max` in its `online.json` (`Online.cs`). |
| `collectionUrl` | string | `Set-Collection.ps1:98-101` only; Ship carries it forward untouched | `Shell.cs:4549` | Saved. Where the Collection button sends people. |
| `collectionRevision` | number | `Publish-Update.ps1:1371-1379`, read off the shipping machine's Vortex | `Shell.cs:4564`, then `Shell.cs:4814-4860` | Not saved. 0 or missing: the launcher says nothing about the collection being behind or ahead. Wrong: tells people to reinstall a collection that is fine. |
| `updateRepo` | string `owner/name` | Nobody since #907: `Publish-Update.ps1` takes it out of the feed | `Feed-Rules.ps1` only (a feed that still names one keeps its GitHub pack urls legal until its next Ship) | Launchers from #907 on ignore it. Older ones save it and ask that repository, via the GitHub Contents API, when the site does not answer; once it is deleted that answers 404 and they ask the site again. |
| `updateFeedUrl` | string, https | `Publish-Update.ps1` from `UpdateFeedUrl` (defaults to the site live/dev URL by channel) | `Shell.cs`, `Updater.FeedUrl` | Saved, quietly. The one `version.json` fetch since #907. Publish the new URL under the old feed first, then move. Since #937 only an https address on thornswood.net is used; anything else in `config.json`, empty included, is the built-in live or dev address, so editing the file cannot switch the update check off. |
| `voicePort` | string | from `VoicePort` | `Shell.cs:4569-4572` | Saved, quietly. Was the raw port's number for an empty `voiceUrl`; since #1304 the launcher never connects to the raw port, and this only goes into `Thornswood.ini` for the game. |
| `voiceUrl` | string or absent | `Publish-Update.ps1:1328-1342`; `-dev` appended on the dev channel | `Shell.cs:4581-4585` | Saved, quietly. The one field that can be cleared: `""` used to send launchers back to the raw port, and since #1304 gives them the built-in `https://thornswood.net/voice` (`/voice-dev` on the dev build, `Config.Voice`, `Config.VoiceBase`); anything not https is treated the same. Absent changes nothing (`Config.cs:511-526`). |
| `discordAppId`, `siteUrl`, `presenceImage` | string | from config, `Publish-Update.ps1:1316-1321` | `Shell.cs:4579-4586` | Saved, quietly. The Discord presence card and its buttons. |
| `message` | string | Nobody: set by hand in the feed (received, edited and sent with `Feed-Store.ps1`; `FeedNotice.cs:15-20`) | `FeedNotice.From` (`FeedNotice.cs:53-82`) | A bar above Play until a feed without it arrives. Never holds Play on its own. |
| `maintenance` | string (read as on only for `true`, `1`, `yes`, `on`) | By hand | `FeedNotice.cs:61-68,91-96` | On: Play held, button says CLOSED FOR MAINTENANCE. Absent in the current feeds. |
| `minLauncher` | string, dotted numbers | `Publish-Update.ps1` on every publish, as the feed's `launcherVersion` (#937) | `FeedNotice.cs:58-77`; the site's `/api/play/pass` | A launcher below it holds Play, and the site refuses it a join pass, so the game server ends its session. The site also refuses a launcher above `launcherVersion`, a number never published. A value that is not digits and dots is ignored by the launcher, so a typo cannot lock everybody out (`FeedNotice.cs:98-120`); the site reads such a value as `launcherVersion`. Updating needs no pass. |
| `packs` | array | `Publish-Update.ps1:1210-1233` appends; `Repair-Manifest.ps1` removes | `Updater.Pending` (`Updater.cs:360-368`) | See below. |
| `optional` | array | `Publish-Pack.ps1:197-213` | Add-ons on the Diagnostics page (`ShellPacks.cs DrawAddons`, #1170); the Mods page's Add-ons tab, which nothing opens | Absent in both feeds today; `scripts/release/optional-packs.txt` lists none. |
| `clientRuntime` | object | `Publish-Update.ps1:1236-1245`, only when the fork commit changed | `ClientRuntime.Heal` (`ClientRuntime.cs:261-269`) | Null or no `url`: a missing client file cannot be repaired from it. Same host and sha256 checks as a pack. |
| `baseline` | object `{ id, sha256, url, entries }` | `Publish-Update.ps1` on every release that sends to the site (the release manifest block, #441); taken out by a `-NoUpload` run | The launcher from #1050 on, which syncs the install to it (`Updater.SyncRecord`, `launcher\app\Sync.cs`; see "Syncing to the release record"). The next `Publish-Update.ps1`, through `Resolve-ReleaseBaseline` (`Release-Baseline.ps1`) | The release record: what that release left installed, every file of ours as `<bytes>:<sha256>`, at `/feed[-dev]/assets/<sha256>`, the same bytes as the store's `published.json`. The next release is diffed against it; a missing or stale store copy is replaced by it, checked by sha256. The launcher reads it apart from the rest of the feed (`RecordRef.FromFeed`), so a `baseline` of any other shape costs that one field and never the whole feed. |
| `releases` | array, newest first, at most 30, of `{ id, sha256, url, entries, lastPack, to? }` | `Publish-Update.ps1` on every release that names a `baseline` (the release list block, #442); `Rollback-Feed.ps1` adds the one a rollback makes, with `to` naming the release it went back to | No launcher. `Rollback-Feed.ps1` (`Get-FeedReleases`, `Release-Baseline.ps1`) | The record each release published, the same shape as `baseline`, plus `lastPack`, the last pack on the feed once that release was out, whose plugin list is the one it shipped. What a channel can be put back to; a release older than the newest thirty cannot be. The first release after this change starts the list with the `baseline` the feed already named. |
| `release` | object `{ id, channel, launcherVersion, packs, baseline, commit, branch, uncommitted, tag }` | `Publish-Update.ps1` on every release (the release record block, #444) | No launcher. Ship, which tags `commit` as `tag` once the feed is out (`Add-ReleaseTag`, `Release-Name.ps1`); the store's `releases.txt` | The release's one name is `id`, the id its packs and its `baseline` carry (`20260928-1630`, dev `20260928-2324-dev`). The rest is what else it is known by: the launcher the feed offers with it (the same across Ships that keep their launcher, #921), the packs it added, its baseline id (empty on a `-NoUpload` run), the commit it was built from and how many tracked files differed from it, and the tag `release/main/<id>` or `release/dev/<id>` (empty when it was not built from a git checkout). `Get-ReleaseDisagreements` says whether they agree, with each other and with `releases`, whose newest entry is the same id ending on its last pack. After a main Ship the dev feed carries main's, `channel` main. `Rollback-Feed.ps1` does not rewrite it yet, so after a rollback it still names the last Ship until the next. |
| `news` | array, newest first, at most 40 | `Publish-Update.ps1:1507-1536`; `Publish-Server.ps1:415-520` | News tab (`Shell.cs:2965-3160`); `Publish-News.ps1` copies it to the site | Cosmetic. |
| `mainVersion` | string | `Publish-Update.ps1:1554-1599`: the main feed's `launcherVersion` on a dev ship, `""` on a main ship | Dev News tab header (`Shell.cs:2992-3002`) | Cosmetic. Stale today, see the end. |
| `serverPassword` | string | Nobody. `Publish-Update.ps1:1405-1408` deletes it on every ship | Declared at `Config.cs:497`, read by nothing since 1.0.197 | Must never come back: the feed is public. |

### A pack entry

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | `yyyyMMdd-HHmm`, `-dev` added on the dev channel, `-<part>` added when a release is split to stay under GitHub's 2 GiB asset limit (`Publish-Update.ps1:762,768-804`). Compared case-insensitively with `applied.txt`. An empty id is never offered. |
| `url` | string | A thornswood.net host asset under `/feed/assets/<sha256>` or `/feed-dev/assets/<sha256>`, **or**, on a feed that still names `updateRepo`, a GitHub release asset in it (`Feed-Rules.ps1`). Since #897 a new pack is written as the site address. A GitHub one (a pack published before 28 Sep) is the browser download address, `https://github.com/<owner>/<name>/releases/download/<tag>/<file>`, since #445, or the older `api.github.com` asset id address; both stop answering when Thornswood-Releases is deleted (#907). Empty: the launcher skips it and writes it off as applied. A url that answers 404 fails the whole update and Play stays off. |
| `sha256` | string, 64 hex | Mandatory; checked after download (`Updater.cs:436-448`). |
| `notes` | string | The whole Ship note, first line first. The update card shows it (`Shell.cs:4669-4670`). |
| `name`, `bytes` | string, number | Optional packs only: Add-ons on the Diagnostics page shows them (`Config.cs:354-360`). Publish-Pack also writes `notes` as a file count. |

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
2. From #1050 on: when the feed names a `baseline` this install has not synced
   to (`Profile\release.txt`), that release is the one pending update, and no
   pack is replayed (`Updater.Pending`, `Sync.cs RecordDue`). See "Syncing to
   the release record". Otherwise, and in every launcher before #1050:
   pending packs are every `packs` entry whose `id` is not a line in
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

A machine that loses `applied.txt` asks for every pack on the feed again. A
launcher from #1050 on does not: it syncs to the record, which needs no
history.

## Syncing to the release record (#1050)

Patrick, 29 Sep: the launcher fetches each file straight from the site by its
fingerprint, syncing the install to the release record, instead of replaying
the chain of packs.

- **What the record is.** The `baseline` the feed names (#1011): one JSON
  object, itself an asset named by its sha256. Every key is a path under the
  game folder with the value `<bytes>:<sha256>` of a file of ours, plus:
  `:golden:plugins.txt` and `:golden:loadorder.txt` (the reference plugin list
  exactly as the pack carries it, into `Profile\Default`); `:gone:<path>` =
  `removed` for a file of ours a release stopped shipping, or `always` for
  Ship-Rules' delete list; and `:record:files` = `1`, written only once every
  file above is on the site beside the record. The `:profile:`, `:order:` and
  `:src:` keys are Publish-Update's own and no launcher reads them.
  `Release-Baseline.ps1` has the list.
- **What the launcher does** (`launcher\app\Sync.cs`). `Updater.Pending`
  offers one update standing for the release when the feed names a record this
  install has not synced to. Installing it reads the record (checked against
  its sha256), compares every file of ours in the install with it, by size and
  then sha256, and downloads only the ones that differ, from the folder the
  record is in: its own url with its sha256 swapped for the file's
  (`/feed[-dev]/assets/<sha256>`). The record's address is checked once
  (https, the host list, stored under its own sha256), so no file can come
  from anywhere else. Each download is checked against its sha256 (and size)
  before anything is written into the game; then they are put in place (a
  linked file is unshared first, as a pack does), the plugin list is settled,
  every `:gone:` path is taken out (a `removed` one is left alone when Vortex
  deploys that path now, the rule `RemovePack` keeps), the kept copies follow,
  every pack on the feed is marked applied, and `Profile\release.txt` records
  the release. A record without `:record:files` (every release before #1050)
  is written down as `packs <sha256>` and the packs go in as before.
- **Interrupted.** Downloads land in `Profile\Sync\<sha256>`: a cut off one is
  carried on from where it stopped with a Range request (thrown away and
  fetched whole once more if the joined file does not check out), a finished
  one is not fetched again, and a sync that stopped after its downloads
  finishes from them with the site out of reach. `release.txt` moves only once
  every step is done, and `Profile\Sync` is cleared then.
- **What it never touches.** The launcher exe: it updates only through
  `SelfUpdate`, with every check Signature.cs makes (WinVerifyTrust, the
  Artifact Signing root, the ThornswoodRelease durable identity,
  `ExpectedSigner`). The six client runtime files: they stay with the
  launcher, which puts back any that are not the build it records
  (`ClientRuntime.Heal`). Anything outside the game folder and
  `Profile\Default`.
- **A file changed by hand** is not a new release, so it is not offered on
  every check; the next release's sync, or `Updater.Resync`, finds it by its
  sha256 and puts only it right.
- **How every file gets on the site** (`Publish-Update.ps1`, the record files
  block). Before `version.json` is touched: the plugin list the pack carried
  goes in as `:golden:` (a release with no pack keeps the last one's); the
  `:gone:` list carries forward from the last record, adds what this release
  removed, and on the first record of a channel starts from every `delete.txt`
  the packs on the feed carry (read off each pack's zip directory with a Range
  request, not the whole pack); every file of ours is sent with
  `Remirror-Site-Feed.ps1 -Send`, which skips what is already up and sends the
  rest as one zip that the VPS unpacks, checking each file's bytes against its
  name; `-Have` then lists the folder and every sha256 the record names must be
  there, or the release stops with the feed untouched. The first record on a
  channel also runs Check-Secrets over the files no pack carries. Only then
  does the record get `:record:files`.
- **How big that is on the site.** Measured on the dev record of 29 Sep: 2,515
  files of ours, 463.5 MB, 449.0 MB once the files with the same bytes are
  counted once, stored as they are (not zipped). Each channel has its own
  folder, so the first release after this on each sends about that much; after
  that a release adds only the files it changed, the same bytes a pack carries
  unzipped. About 180 MB of that record is the Creation Kit and a backup of
  SkyrimSE.exe, which are not ours and should not be in a release at all
  (filed separately). Nothing deletes an old asset: a file every record in
  `releases` has stopped naming can be cleared by hand.

## When the packs can go

Updating is the one place backwards compatibility matters, so the packs stay on
the feed, and Publish-Update keeps appending them, for every launcher before
#1050. They can go from a channel from the first Ship after both of these hold:

1. the channel's `minLauncher` is at or above the first launcher that syncs to
   the record, the first one built from a commit with `launcher\app\Sync.cs`:
   on main, 1.1.103 if the next Bump-Version comes after this merges; on dev,
   the first dev number Ship gives after this merges (the dev
   feed is on 1.1.102.7 on 29 Sep, so 1.1.102.8 or above; read it off the dev
   feed the day it goes out). Publish-Update sets `minLauncher` to the feed's
   `launcherVersion` on every publish (#937), so this holds from the Ship that
   first publishes such a launcher;
2. the record the feed names carries `:record:files`, and its `:gone:` list was
   started from the packs (that Ship printed "read what N pack(s) took out").

From then an installed launcher of any age still updates: it finds no pack,
is offered the launcher, takes it through the signed self-update (unchanged),
and the new launcher syncs the install to the record, taking out every file of
ours a release removed since, from `:gone:`. Nothing an old launcher needs in
order to update comes from `packs`.

What changes then: `packs` becomes `[]` rather than being left out, the shape
every launcher ever published has read; Publish-Update stops
appending; and `Rollback-Feed.ps1` stops building a pack, because a record
whose files are up is the whole rollback. After it, version.json is:

```json
{
  "launcherVersion": "1.1.103", "minLauncher": "1.1.103",
  "launcherUrl": "https://thornswood.net/feed/assets/<sha256>", "launcherSha256": "<sha256>",
  "launcherInputs": "<sha256>",
  "serverAddress": "192.135.112.23", "serverPort": "7777", "voicePort": "7778",
  "voiceUrl": "https://thornswood.net/voice", "updateFeedUrl": "https://thornswood.net/feed/version.json",
  "collectionUrl": "...", "collectionRevision": 1, "maxOnline": 25,
  "discordAppId": "...", "siteUrl": "https://thornswood.net", "presenceImage": "...",
  "expectedExeBytes": "...", "newerExeBytes": "...", "depots": [ ... ],
  "clientRuntime": { "url": "...", "sha256": "...", "bytes": 6356315, "forkCommit": "..." },
  "packs": [],
  "baseline": { "id": "20261001-1200", "sha256": "<sha256>", "url": "https://thornswood.net/feed/assets/<sha256>", "entries": 2583 },
  "release": { ... }, "releases": [ ... ], "news": [ ... ]
}
```

Measured on the main feed of 29 Sep (80,452 bytes): `packs` is 43,126 of it,
`news` 27,862, and `releases` would be about 7,800 once it holds thirty. So
dropping the packs takes it to about 37 KB; the few hundred bytes #1050 asks
for also needs the news in a file of its own that the News tab reads and the
releases list kept only in the VPS store, where Rollback-Feed is its only
reader. That is the rest of #1050.

## Checks on every download

- **Host allow list.** https only, and the host must be `github.com`,
  `objects.githubusercontent.com`, `release-assets.githubusercontent.com`,
  `api.github.com` or `thornswood.net`, or under one of them
  (`Updater.cs:389-411`). The update token, if any, goes only to
  `api.github.com` (`Updater.cs:46-52`).
- **sha256.** Required for packs, the launcher and the client runtime; an empty
  one refuses the download (`Updater.cs:428-451`).
- **Signature.** A downloaded launcher exe must carry a signer whose Subject
  contains `ExpectedSigner`, the name on the signing certificate
  (`Updater.CheckSigner`; the profile is ThornswoodRelease), checked
  before the swap, in every launcher from dev 1.1.101.17 on. Main's live
  1.1.101 predates it and is itself unsigned; dev 1.1.101.34 is signed and
  timestamped. Up to #912 the check read only the embedded certificate's
  Subject, so a self-made certificate with that name passed. Since #912
  (`launcher\app\Signature.cs`) Windows verifies the signature and its chain
  first (WinVerifyTrust: a changed or self-signed file fails), and the chain
  must end at Microsoft Identity Verification Root Certificate Authority 2020,
  come from a "Microsoft ID Verified CS" authority, be timestamped, and carry
  Thornswood's Artifact Signing durable identity value
  (`1.3.6.1.4.1.311.97.203948530.216998690.847558466.123546472`), which stays
  the same across the three day certificate renewals. Launchers already
  installed still run the old Subject check, which a real signed launcher
  passes.
  Packs and the client runtime are zips and are not signed: the host and the
  sha256 are their only checks.
- **Quota.** Nothing a launcher fetches spends the sixty anonymous
  `api.github.com` requests an hour any more (#445): the feed is on
  thornswood.net, and since #897 so is every new download. The GitHub urls
  still on a feed are browser download addresses (redirected to the asset
  CDN, no quota) or older `api.github.com` asset id addresses; the next Ship on
  each channel, or `Repair-Manifest.ps1 -MoveToSite`, moves them all to the
  site.
- **Publish side.** `Feed-Rules.ps1` refuses a new pack whose url is not a
  thornswood.net feed asset under `/feed/assets/<sha256>` or
  `/feed-dev/assets/<sha256>`; a GitHub release asset passes only on a feed
  that still names that repository as `updateRepo`, and since #907 a publish
  takes `updateRepo` out. Since #897 every new pack, launcher and client
  runtime is sent to the site and named there. `Check-Secrets.ps1` scans every zip
  and exe before upload. Nothing is written to the feed if any asset failed to
  upload, and `version.json` is written without a byte order mark.
- **Signing.** On since 27 Sep: `Ship.ps1` and `Publish-Installer.ps1` refuse
  a launcher or setup program that is not Authenticode Valid under
  `ExpectedSigner` (Developer-Guide.md, `records\signing\README.md`), or that
  the launcher's own `Signature.cs` check refuses (#912).
- **Optional packs go to the site too.** `Publish-Pack.ps1` sends each zip to
  `/feed/assets/<sha256>` with `Remirror-Site-Feed.ps1 -Send` before
  `version.json` is touched, names it there, and sends the feed to the VPS
  store with `Remirror-Site-Feed.ps1`. The GitHub release path went with
  Thornswood-Releases (#907). It publishes nothing today
  (`optional-packs.txt` lists none).

## Main and dev

- **main** is written by a main Ship from Patrick's machine, or by a hotfix
  Ship. It is also what `Set-Server.ps1`, `Set-Collection.ps1` and
  `Publish-Pack.ps1` edit.
- **dev** is written by `Ship.ps1 -Channel dev` from any branch on any
  developer's machine; the last dev Ship wins. Its launcher version is main's
  published number plus a fourth part, `.1`, `.2` (`Ship.ps1:487-552`).
- **After a main Ship**, the Dev feed, baseline, release identity and history
  stay unchanged. Dev advances through its own Ship and keeps its own server
  and voice addresses. Publish the same source to both channels when both
  should carry it; their release records remain independent.
- **Before editing**, every script that edits a feed receives it from the VPS
  store, and each send replaces it there only if it has not changed since
  (`Feed-Store.ps1`, #907). A refused send leaves the release marked NOT
  SHIPPED and resumable.
- **Each release has one name and a tag** (#444): its id, recorded in the
  feed's `release` with everything else it is known by, and in the store's
  `releases.txt`. Once the publisher has sent the feed, Ship tags the commit it
  was built from `release/main/<id>` or `release/dev/<id>` (annotated with the
  launcher, packs, baseline and feed) and pushes the tag; never on a dry run,
  and a tag that did not go on is a line on Ship's last screen with the command
  that finishes it. `git tag -l 'release/dev/*'` lists dev's, `git show
  release/main/<id>` says what one shipped. The `v<version>` tags are not
  these: a person pushes one so CI builds a main launcher (`release.yml`).

## Putting a channel back (#442)

A launcher never takes a pack back off: a required pack id stays in
`applied.txt`, and `IsNewer` only goes up (`Updater.cs`). Until #442 the only
way back from a bad release was to ship another one by hand with a higher
launcher version and a pack that put the files back, which is what 1.1.77 did
for 1.1.76 on 21 September.

Now it is one command, and it goes the same way as every other update:

```
.\scripts\release\Rollback-Feed.ps1 -Channel dev -List      what the feed can go back to
.\scripts\release\Rollback-Feed.ps1 -Channel dev -Back 1    back to the release before this one
.\scripts\release\Rollback-Feed.ps1 -Channel dev -To <id>   back, or forward again, to that one
```

- **What it builds.** The records of two releases (`baseline` now and the one
  asked for in `releases`) are compared file by file, and the difference goes
  out as ONE ordinary pack on the end of `packs`: every file whose bytes differ
  at the older release's bytes, every file added since in `delete.txt`, and
  the plugin list out of the pack that release ended on (`lastPack`). The
  feed's `baseline` then names the record of what that pack leaves installed,
  sent to the site like any other, and the store's `published.json` is the
  same bytes, so the next Ship is diffed against the rolled back state.
- **Why every installed launcher follows.** Nothing in the launcher changed:
  the rollback is a pack like any other, at `/feed[-dev]/assets/<sha256>`,
  with its sha256 on the feed. A launcher that took every release applies it
  and lands on the older files; one several releases behind applies those and
  then this, and lands on the same files; a fresh install seeded with every
  pack id applies only this. `tests\test-feed-rollback.ps1` proves all three
  with the launcher's own `Updater` compiled, back, further back and forward.
- **Launchers that sync to the record** (#1050) follow the new record rather
  than the pack: it names what the release asked for installed, lists what the
  later releases added under `:gone:`, and says `:record:files` once every file
  it names is in the channel's folder on the site (the rollback sends any that
  are not, from what it staged or from the folder of either record). When one
  cannot be had it goes out without `:record:files` and those launchers take
  the pack like the rest. `tests\test-record-sync.ps1` proves both kinds land
  on the same files, back and forward.
- **Where the bytes come from.** The site's copy of each file beside its record
  (#1050), then the packs already on the site, found by size and sha256 and
  checked again as they are read. A file only the installer ever carried is
  restored from `/feed[-dev]/assets/<sha256>` the same way, so a rollback past
  the release that first changed it needs no `-FilesFrom` (#1051). When that
  asset is missing (a record from before #1050, or one scrubbed off the site),
  the rollback stops, names the file, and sends nothing; `-FilesFrom <folder>`
  points at a folder holding such files at their game paths, and only a file
  of the right size and sha256 is taken.
- **What does not go back.** The launcher, `launcherVersion`, `minLauncher`
  and `clientRuntime`, and the six client runtime files: a launcher never
  moves to a lower number, signed launchers refuse an update not signed by us,
  the site refuses a join pass above `launcherVersion`, and the launcher
  carries the record of which client belongs beside it and puts back any
  other. A bad launcher is fixed forward by a Ship. The server is not in the
  feed either: if the release being undone changed the gamemode or the
  plugins the server loads, the server goes back too. And if that release
  changed how the launcher and the game's own plugins talk to each other,
  putting the files back without the launcher is not enough; ship a fix
  instead.
- **How far back.** To any release in `releases`, which starts with the first
  Ship after #442 on each channel and holds the newest thirty. A release that
  named no record (every one before #441, and a `-NoUpload` run) is not one.
- **Safety.** `-DryRun` builds the pack and sends nothing. The pack is checked
  by `Check-Secrets.ps1` like a Ship's, the note by `Note-Rules.ps1`, and the
  pack and its record are on the site before `version.json` names them. The
  feed and the baseline go back through `Feed-Store.ps1` in one send, which
  replaces nothing if another Ship or feed edit went out meanwhile.

Optional packs are the one thing a person can remove themselves
(`Updater.RemovePack`).

## What looks wrong in the feeds today

Re-checked on 28 Sep against both live feeds on thornswood.net and the records
in this repository (#897). The three problems this section once listed (dead
private packs, main and dev launcher versions apart, `Updater.cs` behind the
feed) are still cleared: main holds 75 packs and dev 92, none under the private
source repository; main's `launcherVersion` is `1.1.101`, the same as `Version`
in `Updater.cs` and as the dev feed's `mainVersion`; dev is on `1.1.101.34`.
Both feeds carry `collectionUrl` ending `7essxf` and `collectionRevision` 1.
The stale-main-clone hazard in `Publish-Update.ps1` is gone with the clones
(#907): a dev publish reads main's feed from the site every time.

What differs, none of it broken:

- **Download urls on GitHub**, on 28 Sep every one (main 77, dev 94), though
  the site holds every one; each channel's next Ship moves them (see
  "Downloads come from the site"). Thornswood-Releases is deleted only once
  neither feed names one (#907).
- **Both feeds' client runtime is behind the record.** Main names fork
  commit `a922b480` and dev `10841f40` (read 29 Sep); `records\client-build.json`
  is on `1a2e5995` since #1200 (the pin and both build records one commit, a
  refused craft put right at once), on top of `b4543a86` from #898, which lets
  the game hear the key up of a key
  it holds while a panel has the keyboard, on top of `10841f40` (#1016, J
  kept from the game's journal) and `267ac311` (#919, no mDNS responder in
  the game's browser). The next dev Ship carries it.
- **Main has no Skyrim pin fields.** The dev feed's `expectedExeBytes`,
  `newerExeBytes` and `depots` match `records\skyrim-pin.json`; main was last
  published before #874 added them, so main launchers use their compiled
  values until the next main Ship.
- **Main's live launcher is unsigned** (1.1.101 predates signing); the next
  main Ship is the first signed one. See "Checks on every download" for what
  the signer check does and does not prove (#912).
