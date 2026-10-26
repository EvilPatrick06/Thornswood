# Website operational review

Reviewed 4 October 2026. Owner: Patrick. This follows the
[website audit](WEBSITE-AUDIT.md). Findings distinguish verified operation
from legal applicability and missing evidence. This is not a legal opinion
or a claim of complete accessibility compliance.

## Confirmed facts

Patrick confirmed that the operators are primarily based in Colorado,
United States. Adults in North and South America are the target audience;
UK and EU audiences are not knowingly targeted or served. Contact remains
the Discord and private support tickets. Do not publish a personal address
or invent a business identity, email, registration or LocalBusiness schema.

The website has no advertising tag. Its one analytics is Cloudflare Web
Analytics, which Cloudflare writes into each page on the way out and which
stores nothing in the browser; the content rules allow it and the privacy
page names it (Patrick, 22 Oct 2026, #3218). Its cookies support
authentication, sign-in security and the self-declared age notice. That
notice records a statement; it does not verify age. Public images and
recordings require moderation before publication. Existing rules prohibit
sexual content involving minors and graphic content in public channels.

## Legal applicability questions

| Area | Verified source and consequence | Next decision |
| --- | --- | --- |
| Colorado privacy | The [Colorado Attorney General](https://coag.gov/resources/colorado-privacy-act/) describes general CPA thresholds based on annual Colorado consumer data and sale-related processing. A free project or nonprofit is not automatically exempt. | Record whether the project conducts covered activity and meets a threshold. Concurrent game seats do not establish annual data volume. Keep requests private and collect only necessary data. |
| Colorado children | [SB24-041](https://leg.colorado.gov/bills/sb24-041) became law, effective 1 October 2025, adding protections for children's online data. | Review the enacted children's provisions separately from the general volume threshold when minors are known or reasonably implicated. Enforce the existing adult-only admission and moderation rules; do not rely solely on the browser declaration. |
| Colorado sexual-material proposal | [SB25-201](https://www.leg.colorado.gov/bills/SB25-201) is marked Lost. Its introduced proposed start date is not an enacted requirement. | Do not implement that proposal as current law. Evaluate actual content and applicable enacted laws for the locations served. |
| Colorado application age signals | [SB26-051](https://leg.colorado.gov/bills/SB26-051) became law, with an effective date of 1 July 2028. Its scope concerns covered application stores, operating systems and applications. | Review scope before distributing through a covered store. It is not evidence that this ordinary website currently needs that application's age-signal API. |
| US children's privacy | The [FTC COPPA guidance](https://www.ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions) addresses child-directed services and general-audience services with actual knowledge of collecting under-13 data. | Stop admitting a known minor, restrict access and refer existing records to the operators for safe deletion and necessary retention review. An eighteen-and-over label does not decide statutory scope. |
| South America | Brazil's [LGPD Article 3](https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2018/lei/l13709.htm) can apply to offering services to individuals in Brazil or collecting their data there, regardless of the operator's location. | Include Brazil in the audience-specific privacy review. Other countries in the intended North/South American audience need their own scope assessment; do not declare a US-only exemption. |
| UK/EU | [Ofcom age-assurance guidance](https://www.ofcom.org.uk/online-safety/protecting-children/age-assurance) distinguishes highly effective assurance from self-declaration for covered services. | No intentional targeting is a confirmed fact, not a complete jurisdiction test. Reassess if actual UK links, audiences or covered content arise, and assess EU privacy scope separately. |

These are bounded source checks, not a survey of every state or country.
Operator decisions on actual content, audience, thresholds and adult-service
requirements remain open. Do not add collection of identity documents,
birth dates, biometrics or location merely to close a checklist. Any new
verification provider needs its own necessity, retention and security review.

## Asset permission evidence

| Asset | Existing evidence | Status |
| --- | --- | --- |
| `site/public/logo.png`, `favicon.ico`, `og.png` | Current branded files are tracked in the repository. | Djinn made them for Thornswood, under the contributor terms in `LICENSING.md` (Patrick, 15 Oct 2026, #2177). |
| `site/public/banner.jpg`, `banner.mp4`, `banner.webm` | Current homepage art and animation are tracked in the repository. | Djinn made them for Thornswood, under the contributor terms in `LICENSING.md` (Patrick, 15 Oct 2026, #2177). |
| Cinzel and Spectral font files | `site/public/fonts.css` identifies the authors, upstream projects and SIL Open Font License 1.1. | Preserve the licence notices with the distributed files. |
| Community gallery media | Signed-in submissions, captions and moderation records; publication permissions described in Terms. | Staff must check permission and privacy before approving each submission. Submission alone is not proof of ownership of third-party material. |

The register is `records/asset-provenance.json` (#2177), held to the files by
`tests/test-asset-provenance.js` on every pull request; it records who made
each asset above, on what terms, and, for anything still unconfirmed, who can
answer.

For each brand asset, keep creator/source, permission or licence, permitted
uses, attribution requirements, approval date and the file hash together.
Store private permission correspondence in the private staff records, not
in this repository or public credits. Repository history is not a licence.
AI generation, if confirmed, does not settle rights in third-party material
used as references. Replace or withhold an asset if its required permission
cannot be established. Do not label it cleared merely because it is online.

## Recovery and privacy operations

Nightly encrypted backups now include every upload, including large
recordings. Encryption, authentication and decryption use bounded buffers
while preserving the existing archive format. Missing/empty keys fail before
creating an archive. Tampering fails before plaintext is created. Stream
failures close all handles and remove owned temporary files; a publication
collision preserves the earlier backup. Temporary backup copies have a
restricted Windows ACL. See [RESTORING.md](RESTORING.md).

The existing watch, outside-watch, nightly backup and off-box fetch tasks
provide the operational checks. Watch free space as media grows: removing
the omission policy does not remove storage costs. A successful backup task
is not proof of recovery; periodically run the existing encrypted check and
rehearse recovery into a restricted disposable destination.

Completed deletion requests are kept in a restricted record with only the
identity and action needed to reapply them (Deletion requests, below).
Before restoring an older backup, those deletions are applied again before
service reopens. Do not restore deleted gallery content into public use. Old
encrypted recovery copies expire under the documented retention schedule
rather than being silently advertised as immediately rewritten. Verify the
local key copy exists without printing it.

## Deletion requests

The privacy page promises that somebody who asks in the Discord has their
Discord link, session records, chat and character deleted, by a person, and
is told when it is done. `scripts\vps\Delete-Person.ps1` is the one action
that does it across every store on the box (issue #2351, decided by Patrick
on 12 October 2026). Any staff member with VPS access runs it, from their own
clone, in PowerShell 7.

1. **The request comes from the account itself**, in a private ticket that
   account opened (**I need help** in the Discord). Never act on a request
   about somebody else's account. Do not ask for a government identity
   document.
2. **Their Discord id**: on the hub's Linked accounts page, or in Discord
   with Developer Mode on, right click the person and Copy User ID. It is 17
   to 20 digits.
3. **The dry run** changes nothing and prints, for every store, how many of
   their records are there, which a real run removes and which it keeps:
   ```powershell
   .\scripts\vps\Remote.ps1 -File .\scripts\vps\Delete-Person.ps1 -Arguments '-DiscordId <their id>'
   ```
   It ends `DRY RUN: nothing was changed` and names the services that take
   the rest out of their own files as each next starts. Its `release` lines
   count what the game's registers say about their characters (a house, a
   farm, an office, a post on a board, a place on a roll or in a book, a
   dungeon chest's record): the game server lets go of those itself as it
   starts (below). A `waiting` line names a service that still has a request
   for them from an earlier real run.
4. **A faction or business book they own** is disbanded when the game
   server lets go of their character, with its members' place in it. If the
   dry run counts one (`faction and business books they own`) and the group
   wants to keep it, a staff member hands it to another member in the game
   first (Hand it on, on the book's tab, which only staff see), then runs the dry run
   again.
5. **The real run**, at any time; it stops nothing and drops nobody (issue
   #2758, Patrick, 18 October 2026: "it should not restart everytime we want
   to delete a person it should just fully apply the rest upon a server
   restart"):
   ```powershell
   .\scripts\vps\Remote.ps1 -File .\scripts\vps\Delete-Person.ps1 -Arguments '-DiscordId <their id> -Delete -By <your name>'
   ```
   It removes their records at once from every copy nothing runs from (the
   folders a restore, a wipe, an install or a reset set aside), writes the
   request into each service that holds something of theirs, and ends
   `RECORDED, and written down in C:\Thornswood-Deletions\requests.jsonl`
   with the services it asked. `NOT FINISHED` names a file it could not
   change; run it again. Each service takes the request out of its own
   files the next time it starts, before anything of theirs is open, and
   says so in its own log with counts and never a name or a number:
   - **the site** (`site.log`, `deletion requests:`) removes their link, rules
     answer, sign-ins, sessions with their logs and alerts, roster rows,
     tickets and gallery pictures;
   - **each game server**: `server-log.js`, which its task starts it under,
     deletes their characters' saves and takes them off the card, mod menu,
     take count and last-left files before the engine starts (`server.log`,
     `deletions:`); then the gamemode lets go of every entry the game's
     registers hold through that register's own rule (issue #2351, Patrick's
     option A of 16 October): their house and farm are free, an office their
     character held ends, their posts come down with their words off, a job
     they had taken goes back on the board, they leave every roll and book,
     the bed nights end, and the drop box and the ledgers keep every coin and
     every line with their name off it (`thornswood.log`, `release:`, ending
     `every part is done, and the list is gone`). A save the server had not
     finished when it last stopped, holding one of their characters, is
     replayed by the engine first, so their saves go at the start after;
   - **voice** (`voice.log`, `deletions:`) takes their chat lines out of every
     day, except the ones inside a session staff kept;
   - **the bot** (`bot.log`, `deletion requests:`) forgets their join number
     and open ticket.

   Nothing restarts on a schedule: a service starts again at a deploy or an
   install of its own, after a crash and after a reboot. In October 2026 that
   was about a day for the game servers and the site, and up to a week for
   voice and the bot. Until then that service's copy still holds their
   records. To see what still waits, run the dry run again: each `waiting`
   line is a service that has not started since. When the person should not
   wait, restart that service in a quiet hour (`Request-Restart` for a game
   server, or its own deploy).
6. **What the run cannot find**, by hand: a gallery picture of theirs
   approved before 16 October 2026, removed in the hub by name. Until then the
   site kept no account with a picture once it was approved, so nothing ties
   those to them; the run finds every one sent since.
7. **Tell them** in the ticket once the dry run shows nothing `waiting`, that
   it is done, and what stays: staff's
   records about them (bans, PKs, notes, the staff logs), reports they made or
   that were made about them, and a session staff marked kept. In the game,
   what somebody else wrote naming their character (a letter addressed to
   them, a thing left in a drop box for them) is that person's and stays,
   and gold that was held for them on a hold's ledger stays with the hold.
   Logs age out by their own rule, and the encrypted backups expire on their
   schedule; the record below is why a restore never brings the person back.
8. **Then delete their ticket threads** in the Discord, which is the last
   place on our side that holds what they wrote.

**The record.** `C:\Thornswood-Deletions\requests.jsonl` on the box, one line
for each request, written when it is made: the Discord id, the profile ids,
when, who ran it, how many records each store held and which services it
asked. Nothing else about the person. The
folder is SYSTEM's and Administrators' only, with read for the nightly
backup's own task (#2833). The nightly backup takes it as
`deletions\requests.jsonl`, so it leaves the box with every backup and comes
back with any of them. A request made after the last backup is only on the
box until the next nightly run.

**After a restore**, before anything starts, `Delete-Person.ps1 -Reapply`
removes everybody in the record again from every copy nothing runs from, and
asks every service again, so each takes them out of its restored files as it
starts. `Restore-Box.ps1` does it as its last step;
[RESTORING.md](RESTORING.md) has the commands for every other restore,
putting back a folder an install or a wipe set aside among them.

**The guild traders' ledger** (`private\merchant-ledger.json`) keys a supply
wait, a commission promise and a trade still waiting on a character by that
character's form id and profile.
The dry run counts those as `release`, and the game server lets
go of them as its merchant purses are read (#2652): the waits and the
promises go, so the gold a promise held back is the trader's to spend again,
and a waiting trade is cleared, the trader keeping what it already held. The
traders' purses and shelves name nobody and stay, like a hold's ledger.

**What the game does not let go of yet.** A crop they sowed stays in the
ground with their number as the one who sowed it, which nobody holds any
more; whoever brings it in empties it, and a wipe takes it.

## Accessibility scope

Browser checks inspect public routes, mobile layout, contrast, keyboard
navigation and the report/gallery flows. They do not certify every browser,
assistive technology, signed-in staff screen or uploaded document. Keep an
accessible private support path and record reproducible reports rather than
claiming universal conformance. A full screen-reader and staff-workflow audit
remains a separate acceptance task.

On 4 October, all 16 public routes passed at mobile width 390 and the
default desktop viewport: one main heading, image alt attributes and no
horizontal overflow. The browser reported no console warnings or errors.
The measured desktop text/background pairs included 1,834 elements with no
contrast failure; 246 elements with image, translucent or unresolved
backgrounds were excluded from that calculation and need visual assessment.
Keyboard report navigation skips the spam trap and reaches the labelled
fields and checkboxes. The skip link now targets a focusable main landmark
without adding it to the ordinary tab sequence.
