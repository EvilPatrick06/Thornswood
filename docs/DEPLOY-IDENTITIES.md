# Restricted deployment identities for the VPS (issue #2182)

Status: AUDIT AND DESIGN ONLY. Nothing on the box was changed to write this:
no key was added, removed or rotated, no access was disabled, no account or
task was created, and nothing was tried against production. Every fact in
section 1 was read on the box over ssh, read-only, on 11 Oct 2026. Section 6
sets doing nothing beside each change (16 Oct). Decisions Patrick made are in
section 7.

## 1. What access looks like now (evidence)

How the scripts get in. Every script that reaches the box goes through
`scripts\vps\Remote.ps1` (`Invoke-ThornswoodRemote`) or plain `ssh`/`scp`,
34 scripts under `scripts\` in all, as `Administrator` with a key
(`docs\OWNERSHIP.md`, "VPS access"; `Setup-SshKey.ps1`; `Add-VpsKey.ps1`).
Runbooks do the same by hand (`docs\IT-IS-DOWN.md`, `docs\RESTORING.md`,
`docs\MOVING-THE-SERVER.md`).

| What | Read on the box |
| --- | --- |
| Session | `win-mp817amcsj9\administrator`, member of BUILTIN\Administrators, High Mandatory Level. Every ssh session is a full elevated admin |
| sshd | `PasswordAuthentication no`, `KbdInteractiveAuthentication no`; `Match Group administrators` reads `C:\ProgramData\ssh\administrators_authorized_keys` |
| Admin keys | 5 ed25519 lines. Comments: `thornswood` (three lines), `claude-session-2026-09-16`, `zayde-thornswood`. None carries `from=`, `command=` or `restrict` |
| Admin key file ACL | SYSTEM and Administrators full control only (correct for OpenSSH) |
| Per-user keys | none (`C:\Users\*\.ssh\authorized_keys` absent) |
| Which keys are used | Last 400 OpenSSH events: every accepted login is Administrator, one key, one source address. The other four keys showed no login in that window |
| Firewall for 22 | `OpenSSH-Server-In-TCP` and two more inbound rules on 22, RemoteAddress `Any` |
| Local admins | `Administrator`, `cloudbase-init` (the provider's first-boot agent account, enabled) |
| Other accounts | `thornswood-runner`, `-runner2`, `-runner3`, `-runner4`: Users plus their GitHub runner groups, not admins; run the four `actions.runner.*` services |
| Services | `sshd` LocalSystem; `ThornswoodBot` as `NT SERVICE\ThornswoodBot` |
| Tasks | Thornswood Server, Dev Server, Voice, Dev Voice, Web (#2578) and Backup (#2612): LOCAL SERVICE, Limited, each with a SID of its own. Load, Watch, Maint Update, Dev Crash Capture: SYSTEM, Highest. Thornswood Docs: LOCAL SERVICE, Limited. The one-shot sshd restart and rollback tasks of vps-harden.ps1 and vps-ssh-scope.ps1 stay SYSTEM: they need administrator and must outlive the session they cut (#2612) |

So: one identity, full admin, reachable from anywhere on port 22 with any of
five keys, used for everything from a site file copy to a firewall change.
The runtime side is already partly least privilege (the site under LOCAL
SERVICE, the bot under its own virtual account, the runners non-admin, the
folder locks from `Lock-VpsFolders.ps1`).

## 2. What the scripts actually need

| Operation | Scripts | Needs admin? |
| --- | --- | --- |
| Copy a build to a stage folder, check hashes, swap, put back | Deploy-Docs, Deploy-Server, Deploy-DevGamemode, Install-Voice, Install-Bot (files), Publish-Server, `Swap.ps1` | No, if the identity has Modify on those service folders |
| Stop and start one named Thornswood task | the swap blocks, Request-Restart, runbooks | No, if each task's security descriptor grants the identity start and stop |
| Write the feed store and history | Feed-Store, Publish-Update, Publish-Discord `-Record` | No, Modify on `C:\Thornswood-Docs\feed*` |
| Read logs, status, ACLs | Check-*, Watch, IT-IS-DOWN | No |
| Register or change a task that runs as SYSTEM | Install-*, Install-Backup, Install-Runner | Yes |
| Install a service, change a virtual account, set folder ACLs | Install-Bot, Install-Runner, Lock-VpsFolders | Yes |
| Firewall, sshd, Windows Update, hardening | Harden-VPS, Maint Update | Yes |
| Add or remove an ssh key | Add-VpsKey, Setup-SshKey | Yes |

Most day to day traffic (every Ship, deploy and feed write) is in the first
three rows. The admin rows are install-time and rare. This table was first
read off the script names and what they do. Section 2a checks it against the
commands each script actually sends, and where the two differ, 2a is right.

## 2a. Checked against the code (12 Oct 2026)

`records\remote-commands.json` lists every call under `scripts\` that reaches
the box: 227 calls in 52 files (section 1 said 34 scripts; the extra files
are the shared helpers, `Artifact.ps1`, `Swap.ps1`, `ServerContent.ps1`,
`DeployedBuild.ps1`, `Send-Script.ps1`, `Send-Secret.ps1`, `Vps.ps1`, plus ops
and one-off scripts the first count left out). Each row gives the script, the
function it sits in, what it sends, and its class: a gate verb, `admin`, or
`transport` (31 rows, helpers that only carry what their caller hands them).
By class: 91 admin, 59 read-status, 25 stage, 9 feed-send, 8 swap,
3 task-start-stop, 1 putback. `tests\test-remote-command-map.ps1` parses
every script and fails when a remote call has no row, or a row has no call.
Nothing on the box was read or changed for this. Counted again on 16 Oct
2026: 238 calls in 55 files, 98 admin, 62 read-status, 31 transport,
26 stage, 9 feed-send, 8 swap, 3 task-start-stop, 1 putback.

Where the evidence differs from section 2:

| Section 2 said | The code does | So |
| --- | --- | --- |
| Swap and put back need no admin | `Swap.ps1` StopOurs kills the server by pid with `Stop-Process`, and the Deploy-Docs swap (StopIt) does the same to `node.exe`, besides stopping the task. The game servers run as SYSTEM | Task start and stop rights are not enough. The gate's swap and putback verbs must stop the process themselves, elevated, or the swap blocks change first |
| Artifact store writes need Modify only | `Send-ThornswoodArtifact` and the put back record restore (`Restore-SwapRecord`, `Restore-ThornswoodServerRecord`) run `Get-ThornswoodLockedFolderScript`, which sets the store's ACL, on every call | Admin today. The ACL belongs at install time (Lock-VpsFolders), not in every deploy |
| Deploy-Docs is a file deploy | Every run also opens or removes the site firewall rule, sets the task's account, and can write the site password into `config.json` | Admin for those three calls. The file stage, check and swap rows are deploy verbs |
| Install-Bot files need no admin | The bot swap goes through `Bot-Service.ps1`: `sc.exe`, `Stop-Service`, `Stop-Process` and `Set-Acl`. The rest installs Python, pip packages and the service | Admin. Only the stage upload and its hash check are deploy verbs |
| Install-Voice files need no admin | The main run registers the task and the firewall rule and stops the process | Admin, apart from the stage, its check and the task restart |
| Publish-Server is a file deploy | It copies the zip and four libraries to `C:\` and runs `Install-ThornswoodServer.ps1`, which registers the SYSTEM task | Admin (first install). Day to day server deploys are Deploy-Server |
| Watch is a read | Watch-Services and Watch-Load write their scripts into locked folders and register or delete their tasks | Admin for those calls; their status reads stay read-status |
| Feed writes are Feed-Store, Publish-Update and Publish-Discord | Feed writes also come from Remirror-Site-Feed, Publish-News (`news.json`) and Publish-Installer (site `files`) | All feed-send; the feed verb must cover those folders too |
| Request-Restart stops and starts a task | It only drops a request json in the server data folder; the gamemode warns everyone on the server, sends them off and deletes it | stage (a file write), no task rights needed |
| (not listed) | Restart-Server uses `Restart-Service`; Go.ps1 copies `voice-server.js` straight into the live voice folder and kills the voice process; Wipe-Saves, Reset-Character, Set-Door and Clean-Everything delete or rewrite game data and stop processes; Backup-Server and Fetch-Backups read every secret | Admin, outside every gate verb |
| (not listed) | Every secret write (Rotate-*, Set-DiscordLogin, Install-Bot and Install-Runner tokens, the site password) | Admin. No gate verb carries a secret |

What this means for section 3: the first three rows of section 2 hold only
for Deploy-Server, Deploy-DevGamemode and the stage half of Deploy-Docs,
Install-Voice and Install-Bot, and only once the process kill and the store
ACL move out of the deploy path (or into the gate, run elevated). Patrick has
not decided the deploy identity (section 7.4), so nothing here changes that.

## 3. Proposed identities

1. `thornswood-deploy`, a local user, not in Administrators. Its own key in
   `C:\Users\thornswood-deploy\.ssh\authorized_keys` with
   `restrict,command="powershell -NoProfile -File C:\Thornswood-Gate\Gate.ps1"`.
   The gate reads `SSH_ORIGINAL_COMMAND` and runs only a fixed list of verbs
   (stage, swap, put back, feed send, start and stop of named Thornswood
   tasks, read status). Stage uploads go to a staging folder it owns. Modify
   on the service folders and feed folders, start and stop on the named
   tasks. This covers rows 1 to 4.
2. `Administrator` stays, as break glass and for install-time work only.
   Its keys get `from="<addresses>"` once section 7 settles the addresses,
   and the keys nobody claims are removed (decision, not done here).
3. The runtime identities stay as they are (SYSTEM tasks, LOCAL SERVICE
   site, ThornswoodBot, runners). Moving the SYSTEM tasks to virtual
   accounts is a separate change, under "Later".

Scripts change by taking `-As deploy|admin` in `Remote.ps1`, defaulting to
deploy once the gate exists, and failing with a clear sentence when a deploy
verb is refused rather than retrying as admin.

## 4. Key lifecycle

- One key per person per machine, comment `<person>-<machine>-<date>`, so a
  line can be traced and removed without touching anyone else's.
- Added with `Add-VpsKey.ps1` (it gains `-Role deploy|admin`).
- Reviewed quarterly against `docs\OWNERSHIP.md`; a key with no login in 90
  days (OpenSSH log) is proposed for removal.
- Removal on leaving or loss: delete the line, nothing else changes. No
  shared private key exists, so nothing has to be reissued to others.

## 5. Migration and rollback

1. In the repo: list every remote command each script sends and map it to a
   gate verb or to admin. No box change. Done: section 2a,
   `records\remote-commands.json` and `tests\test-remote-command-map.ps1`.
2. Create `thornswood-deploy`, the gate, the ACLs and task rights. Admin
   access untouched. Rollback: delete the user and the gate folder.
3. Dev only: point the dev deploy scripts at deploy. Run a dev Ship and a dev
   `-PutBack`. Rollback: `-As admin`.
4. Live: the same for live deploys after a clean week on dev. Rollback:
   `-As admin`.
5. Restrict Administrator keys (`from=`, unclaimed keys removed) and, if
   decided, the firewall scope for 22. Rollback: put the saved
   `administrators_authorized_keys` back from the provider console. The
   provider's console login is the recovery path if every key fails, and must
   be confirmed working BEFORE this step.

Owner: the Installer lane builds steps 1 and the repo side of 2 to 4; Claude
runs every box step; Patrick owns keys and step 5.

## 6. Doing nothing, set beside each change

Decided by Patrick on 15 Oct 2026 (#2168, A): this doc sets what staying as
we are costs and risks beside each change's own cost, migration and
rollback. Everything below was read from the repository, GitHub and the
public site on 16 Oct 2026, unless it names another date. The box facts are
section 1's, read on 11 Oct; nothing on the box was read or changed for this
section.

### 6.1 Who holds Administrator ssh today

- Five key lines (section 1). Three carry the comment `thornswood`, which
  `Setup-SshKey.ps1` gives every key it makes. One's key (fingerprint
  `SHA256:lJZoYUi5QcfocYYXKXG0wCSqdCVzQsDsYVE4m/RmyfA`, read 12 Oct) is one
  of them; which machines hold the other two is not written down anywhere.
  `claude-session-2026-09-16` and `zayde-thornswood` are decided for removal
  (7.1) and are still on the box: the removal waits on Patrick's console
  login check (vault note `claude-queue\2182-deploy-identities.md`, last
  entry 12 Oct).
- `Setup-SshKey.ps1` makes every key with an empty passphrase, on purpose,
  so scripts run without a prompt. The private key file alone is the login.
- No line carries `from=`, and the inbound rules on 22 take any address
  (section 1).
- What uses the key from One: every Ship and deploy; `Fetch-Backups.ps1`
  every night, which pulls backups that hold every secret (an admin row in
  the map); and `Watch-Outside.ps1` every five minutes, which logs in only
  when it has an alert to hand to the watchdog's outbox.

### 6.2 What a stolen key can do, now and after each change

The columns are cumulative: each one assumes the changes to its left are
done too. "Deploy identity" is section 3. "Own accounts" is the "Later" item
at the end of this doc: the game servers, voice, web and backup tasks moved
off SYSTEM onto accounts of their own.

| A stolen key can | Today | After 7.1 and 7.2 (two keys gone, 22 limited) | After the deploy identity (a stolen deploy key) | After own accounts too |
| --- | --- | --- | --- | --- |
| Log in | Any of five keys, from any address | Three keys, from the listed addresses only | The deploy key, from the listed addresses | Same |
| Run code as SYSTEM on the box | Yes | Yes | Yes, in one deploy: stage and swap a `gamemode.js` into a server folder. Both game server tasks run as SYSTEM at Highest (`Install-ThornswoodServer.ps1` registers the live one with `-UserId 'SYSTEM'`, and `vps-dev-instance.ps1` gives the dev one the live task's principal), and `gamemode.js` loads Node's `fs` and `http` | No. A gamemode runs as its own server's account, with its own folders |
| Read the site's secrets (`C:\Thornswood-Docs\config.json`) | Yes | Yes | Yes, through SYSTEM above, or by swapping the site's `server.js`, which runs as LOCAL SERVICE and reads that file | Yes, through a site swap. The site needs those secrets to run |
| Read every other secret, the backups and the backup passphrase | Yes | Yes | Yes, through SYSTEM above | No |
| Change accounts, keys, the firewall or sshd | Yes | Yes | Through SYSTEM above only | No |
| Read the four runners' `.credentials` and take their jobs, release builds included (docs\RUNNER-ISOLATION.md F4) | Yes | Yes | Through SYSTEM above only | No |
| Write the feed, and through it the packs and the client runtime every launcher installs | Yes | Yes | Yes: feed-send is a deploy verb | Yes. Only #2163's signed manifest (docs\SIGNED-RELEASES.md, phases C and D) closes this |
| Put a launcher exe on testers' machines | No. A launcher installs only a launcher signed by ThornswoodRelease (`Signature.cs`), and nothing on the box can sign | No | No | No |

### 6.3 Each change against doing nothing

**7.1 and 7.2, the two keys and port 22** (decided 11 Oct; waits on
Patrick's console login check, not on work).
- Doing nothing: two keys with no login in the sampled log stay valid admin
  logins, and every key works from any address. Cost: none.
- The change costs about ten commands, already written in the vault note.
  `Set-SshScope.ps1` is built and tested (`tests\test-ssh-scope.ps1`, 56
  checks). Nothing in the repository has to move.
- Rollback: the saved `administrators_authorized_keys` copied back (vault
  note), and `Set-SshScope.ps1 -From Any`. A port 22 change whose new login
  fails is put back by the box itself within ten minutes.
- Risk of the change: a machine whose address changes loses ssh until the
  list is changed. If that is One, every Ship, deploy, backup fetch and
  Watch-Outside login fails until someone in the list, or Patrick at the
  console, runs `Set-SshScope.ps1` again.

**7.4, the deploy identity** (undecided).
- Doing nothing: no work. A stolen key stays a stolen box.
- The change costs, measured from `records\remote-commands.json` on 16 Oct
  (238 calls in 55 files, 98 of them admin): before any deploy can run as
  deploy, the store ACL that `Artifact.ps1` sets on every send (three calls)
  and that `Swap.ps1`'s record restore sets (one call) moves to install
  time; the process stop in the swap blocks moves into a gate verb that runs
  elevated; and the three admin calls on every `Deploy-Docs.ps1` run (the
  firewall rule, the task's account, the site password) leave the deploy
  path. Then `Remote.ps1 -As`, the gate itself, `Add-VpsKey.ps1 -Role`, the
  account, the folder rights and task rights on the box, and a week on dev
  (section 5). Nobody has put days on it; the issue says large.
- What it buys, measured: while the game servers run as SYSTEM, very little
  against someone who means it. The swap verb every deploy needs is a way to
  run code as SYSTEM (6.2). It does stop a deploy script from changing
  accounts, keys or the firewall by mistake, and a stolen deploy key needs a
  deploy to get further, which leaves a `.prev` folder and a record in
  `C:\Thornswood-Deploys`.
- Migration and rollback: section 5 (`-As admin`; delete the account and the
  gate folder).

**Own accounts for the SYSTEM tasks** ("Later"; on the board as #2578
since 16 Oct).
- Doing nothing: any code the game servers, voice and web tasks load runs
  as SYSTEM, so a gamemode fault that writes where it is told, or anyone who
  can deploy, reaches the whole box.
- The change: each install script registers its task under an account of
  its own with rights on its own folders, as the site and the bot already
  run. Its cost has not been measured. It touches at least
  `Install-ThornswoodServer.ps1`, `vps-dev-instance.ps1`,
  `Install-Voice.ps1`, `Setup-Domain.ps1` and `Lock-VpsFolders.ps1`.
- Migration: one service at a time, dev first. Rollback: run that service's
  install script as it is today, which registers the task as SYSTEM again.

### 6.4 What the comparison concludes

- 7.1 and 7.2 are the cheapest and largest step: two fewer keys, and a
  stolen key that works only from known addresses. They wait on Patrick's
  console check and his address list, not on work.
- The deploy identity on its own, before own accounts, costs large work and
  buys little against a deliberate attacker. Doing nothing on it is the
  better choice until the SYSTEM tasks have their own accounts. This
  replaces Claude's 12 Oct recommendation on #2182 (B, after items 2 and 3).
- The feed's path to testers' machines is the same in every column. #2163's
  signed manifest is the step that changes it.
- Administrator ssh is never removed entirely: 98 calls would only work at
  the console, and a broken gate would leave only the console.

### 6.5 Not measured from here

- Which machines hold the other two `thornswood` keys, and whether
  `zayde-thornswood` is Djinn's: Patrick.
- Whether One's address is fixed: Patrick's internet provider, or what
  https://api.ipify.org shows on One over a week.
- Logins beyond the 400 events read on 11 Oct: the main session, reading the
  OpenSSH log on the box (agents are refused box reads).
- Days of work for the deploy identity and for own accounts: whoever takes
  own accounts first.
- `Watch-Outside.ps1` reaches the box with ssh through a variable (`& $ssh`)
  in two places, and `records\remote-commands.json` has no row for either:
  the map test finds only commands named `ssh` or `scp`. Recorded on #2182.

## 7. Decisions (Patrick, 11 Oct 2026)

1. Keys. Who owns the three keys commented `thornswood` is unknown; they stay
   for now. The `claude-session-2026-09-16` and `zayde-thornswood` keys are
   to be removed. Claude removes them, and only after the provider's hosting
   console login is confirmed working.
2. Port 22. Yes, restrict the inbound rules on 22 to known addresses. Same
   condition: only after the console login check. The way it is done:
   `scripts\vps\Set-SshScope.ps1 -From <addresses>`, which proves key login,
   refuses a list that leaves out the machine running it, arms a ten minute
   put back, and cancels it only once a new key login gets in
   (`tests\test-ssh-scope.ps1`). Which addresses go in the list is still to
   be decided (#2182).
3. `cloudbase-init`. Undecided. Left as it is (enabled local admin); revisit
   later.
4. Deploy identity and gate. Undecided. The design in section 3 stays ready,
   but `thornswood-deploy` and the gate are not created.

Order on the box (Claude only, from the vault note): confirm the console
login, save `administrators_authorized_keys`, remove the two keys, then
narrow port 22. No lane makes any of these changes.

## Later, not in this issue

Moving the SYSTEM tasks (game servers, voice, web, backup) to per-service
virtual accounts with only the folders they need, the way the site and bot
already run. Its own issue since 16 Oct, #2578, because section 6 found the
deploy identity buys little until it is done. Done for the game servers,
voice and web by #2578 and for the backup by #2612.
