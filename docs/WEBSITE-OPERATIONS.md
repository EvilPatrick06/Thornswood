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

The website has no advertising or analytics tags. Its cookies support
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
| `site/public/logo.png`, `favicon.ico`, `og.png` | Current branded files are tracked in the repository. | Djinn made them for Thornswood, under the contributor terms in `LICENSE` (Patrick, 15 Oct 2026, #2177). |
| `site/public/banner.jpg`, `banner.mp4`, `banner.webm` | Current homepage art and animation are tracked in the repository. | Djinn made them for Thornswood, under the contributor terms in `LICENSE` (Patrick, 15 Oct 2026, #2177). |
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
   It ends `DRY RUN: nothing was changed` and names the services a real run
   stops for a moment.
4. **The real run**, when nobody is on either game server (it refuses while
   anybody is, unless `-Now` is added, which drops them):
   ```powershell
   .\scripts\vps\Remote.ps1 -File .\scripts\vps\Delete-Person.ps1 -Arguments '-DiscordId <their id> -Delete -By <your name>'
   ```
   It stops the site, the game servers, voice and the bot only where their
   files hold something of the person's, removes it, starts each one again,
   and ends `DELETED, and written down in C:\Thornswood-Deletions\requests.jsonl`.
   `NOT FINISHED` names a file it could not change; run it again.
5. **What is not on the box**, by hand: remove their approved gallery
   pictures in the hub by name (the gallery keeps no account with an approved
   picture).
6. **Tell them** in the ticket that it is done, and what stays: staff's
   records about them (bans, PKs, notes, the staff logs), reports they made or
   that were made about them, a session staff marked kept, and what the game's
   registers still say about a house or a bounty their character held (#2351
   has the decision on those). Logs age out by their own rule, and the
   encrypted backups expire on their schedule; the record below is why a
   restore never brings the person back.
7. **Then delete their ticket threads** in the Discord, which is the last
   place on our side that holds what they wrote.

**The record.** `C:\Thornswood-Deletions\requests.jsonl` on the box, one line
for each completed request: the Discord id, the profile ids, when, who ran it
and how many records each store lost. Nothing else about the person. The
folder is SYSTEM's and Administrators' only. The nightly backup takes it as
`deletions\requests.jsonl`, so it leaves the box with every backup and comes
back with any of them. A request made after the last backup is only on the
box until the next nightly run.

**After a restore**, before anything starts, `Delete-Person.ps1 -Reapply`
removes everybody in the record again. `Restore-Box.ps1` does it as its last
step; [RESTORING.md](RESTORING.md) has the commands for every other restore.

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
