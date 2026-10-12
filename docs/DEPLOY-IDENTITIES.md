# Restricted deployment identities for the VPS (issue #2182)

Status: AUDIT AND DESIGN ONLY. Nothing on the box was changed to write this:
no key was added, removed or rotated, no access was disabled, no account or
task was created, and nothing was tried against production. Every fact in
section 1 was read on the box over ssh, read-only, on 11 Oct 2026. Decisions
only Patrick can make are in section 7.

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
| Tasks | Thornswood Server, Dev Server, Voice, Dev Voice, Web, Backup, Load, Watch, Maint Update, Dev Crash Capture: SYSTEM, Highest. Thornswood Docs: LOCAL SERVICE, Limited |

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
three rows. The admin rows are install-time and rare. This table is read off
the script names and what they do; a per-call check of every remote command
each script sends is the first build step in section 5.

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

1. In the repo: list every remote command each of the 34 scripts sends and
   map it to a gate verb or to admin. No box change.
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

## 6. Doing nothing

Any of five admin keys, from any address, is full control of both game
servers, every secret in `C:\Thornswood-Docs\config.json` and the bot files,
the backups, and the feed every launcher trusts (docs\SIGNED-RELEASES.md:
whoever writes the feed can change both a pack and its hash). A leaked
developer laptop key is a full box compromise with no narrower blast radius.
The likelihood is low today (password login is off, keys are ed25519), the
impact is total, and four of the five keys showed no use in the sampled log.

## 7. Decisions needed (Patrick)

1. Whose are the three keys commented `thornswood`, and should the
   `claude-session-2026-09-16` and `zayde-thornswood` keys stay?
2. Restrict port 22 by address (home addresses can change; the provider
   console is the fallback), or rely on keys plus `from=` only?
3. `cloudbase-init` is an enabled local admin. Keep it (the provider may use
   it for password resets) or disable it after asking the provider?
4. Go ahead with the deploy identity and gate (section 3), dev first?

## Later, not in this issue

Moving the SYSTEM tasks (game servers, voice, web, backup) to per-service
virtual accounts with only the folders they need, the way the site and bot
already run.
