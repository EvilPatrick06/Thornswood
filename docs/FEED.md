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
  `version.json` through it too. A main Ship's reset of dev receives the dev
  store, writes main's feed and baseline into it and sends both, so the site's
  dev feed is reset at once rather than at the next remirror.
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
    "forkCommit": "b6721bb0"
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
| `maxOnline` | number | `Publish-Update.ps1:1348-1352` | `Shell.cs:4551` | Saved when above 0. Written as a number because a quoted `"25"` reads as 0 (`Publish-Update.ps1:1344-1347`). |
| `collectionUrl` | string | `Set-Collection.ps1:98-101` only; Ship carries it forward untouched | `Shell.cs:4549` | Saved. Where the Collection button sends people. |
| `collectionRevision` | number | `Publish-Update.ps1:1371-1379`, read off the shipping machine's Vortex | `Shell.cs:4564`, then `Shell.cs:4814-4860` | Not saved. 0 or missing: the launcher says nothing about the collection being behind or ahead. Wrong: tells people to reinstall a collection that is fine. |
| `updateRepo` | string `owner/name` | Nobody since #907: `Publish-Update.ps1` takes it out of the feed | `Feed-Rules.ps1` only (a feed that still names one keeps its GitHub pack urls legal until its next Ship) | Launchers from #907 on ignore it. Older ones save it and ask that repository, via the GitHub Contents API, when the site does not answer; once it is deleted that answers 404 and they ask the site again. |
| `updateFeedUrl` | string, https | `Publish-Update.ps1` from `UpdateFeedUrl` (defaults to the site live/dev URL by channel) | `Shell.cs`, `Updater.FeedUrl` | Saved, quietly. The one `version.json` fetch since #907. Publish the new URL under the old feed first, then move. Since #937 only an https address on thornswood.net is used; anything else in `config.json`, empty included, is the built-in live or dev address, so editing the file cannot switch the update check off. |
| `voicePort` | string | from `VoicePort` | `Shell.cs:4569-4572` | Saved, quietly. Used when `voiceUrl` is empty. |
| `voiceUrl` | string or absent | `Publish-Update.ps1:1328-1342`; `-dev` appended on the dev channel | `Shell.cs:4581-4585` | Saved, quietly. The one field that can be cleared: `""` sends launchers back to the raw port, absent changes nothing (`Config.cs:511-526`). |
| `discordAppId`, `siteUrl`, `presenceImage` | string | from config, `Publish-Update.ps1:1316-1321` | `Shell.cs:4579-4586` | Saved, quietly. The Discord presence card and its buttons. |
| `message` | string | Nobody: set by hand in the feed (received, edited and sent with `Feed-Store.ps1`; `FeedNotice.cs:15-20`) | `FeedNotice.From` (`FeedNotice.cs:53-82`) | A bar above Play until a feed without it arrives. Never holds Play on its own. |
| `maintenance` | string (read as on only for `true`, `1`, `yes`, `on`) | By hand | `FeedNotice.cs:61-68,91-96` | On: Play held, button says CLOSED FOR MAINTENANCE. Absent in the current feeds. |
| `minLauncher` | string, dotted numbers | `Publish-Update.ps1` on every publish, as the feed's `launcherVersion` (#937) | `FeedNotice.cs:58-77`; the site's `/api/play/pass` | A launcher below it holds Play, and the site refuses it a join pass, so the game server ends its session. The site also refuses a launcher above `launcherVersion`, a number never published. A value that is not digits and dots is ignored by the launcher, so a typo cannot lock everybody out (`FeedNotice.cs:98-120`); the site reads such a value as `launcherVersion`. Updating needs no pass. |
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
| `url` | string | A thornswood.net host asset under `/feed/assets/<sha256>` or `/feed-dev/assets/<sha256>`, **or**, on a feed that still names `updateRepo`, a GitHub release asset in it (`Feed-Rules.ps1`). Since #897 a new pack is written as the site address. A GitHub one (a pack published before 28 Sep) is the browser download address, `https://github.com/<owner>/<name>/releases/download/<tag>/<file>`, since #445, or the older `api.github.com` asset id address; both stop answering when Thornswood-Releases is deleted (#907). Empty: the launcher skips it and writes it off as applied. A url that answers 404 fails the whole update and Play stays off. |
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
- **Signature.** A downloaded launcher exe must carry a signer whose Subject
  contains `ExpectedSigner` (`Gavin Knotts`, `Updater.CheckSigner`), checked
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
  `ExpectedSigner` (CONTRIBUTING.md, `records\signing\README.md`), or that
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
- **After a main Ship** (not a hotfix), Ship receives the dev store, copies the
  main feed over the dev feed, keeping dev's `serverPort`, `voicePort` and
  `voiceUrl`, copies the main baseline over the dev one, and sends both back
  (Ship.ps1, "dev follows main"), so the site's dev feed is reset at once. Dev
  launchers then take main's launcher and packs.
- **Before editing**, every script that edits a feed receives it from the VPS
  store, and each send replaces it there only if it has not changed since
  (`Feed-Store.ps1`, #907). A refused send leaves the release marked NOT
  SHIPPED and resumable.

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
- **Both feeds' client runtime is behind the record.** Main and dev both
  name fork commit `258fac47` (read 28 Sep, after the main Ship);
  `records\client-build.json` is on `fde333f1` since #919, which stops the
  game's browser starting an mDNS responder. The next dev Ship carries it.
- **Main has no Skyrim pin fields.** The dev feed's `expectedExeBytes`,
  `newerExeBytes` and `depots` match `records\skyrim-pin.json`; main was last
  published before #874 added them, so main launchers use their compiled
  values until the next main Ship.
- **Main's live launcher is unsigned** (1.1.101 predates signing); the next
  main Ship is the first signed one. See "Checks on every download" for what
  the signer check does and does not prove (#912).
