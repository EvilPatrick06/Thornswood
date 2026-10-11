# Signed releases and artifact provenance (issue #2163)

Status: DESIGN AND PILOT. Nothing in the live release path changes with this
document. release.yml, Ship, Publish-Installer, the feed and every checksum
check stay exactly as they are. Open questions only Patrick can decide are
at the end, under "Decisions needed".

This does not claim reproducible builds. release.yml itself says
byte-identical local and runner builds are impossible with the Framework 4
csc (it stamps a build time and a fresh MVID), and nobody has measured
otherwise. Provenance here means "this signed file came from this commit,
this runner and these records", recorded and signed, not "anyone can rebuild
the same bytes".

## 1. Where things stand today (measured 11 Oct 2026)

| Layer | What it is | Where |
| --- | --- | --- |
| Authenticode signing | Azure Artifact Signing, account ThornswoodSigning, profile ThornswoodRelease, `signtool /fd SHA256 /tr http://timestamp.acs.microsoft.com /td SHA256` | `scripts\release\Sign-Artifact.ps1`, `records\signing\` |
| What is signed | Launcher `Thornswood.exe`, the installer (`Setup`, signed after the OneFile attach), and setup-stub on the paths that sign it | `Build-Launcher.ps1`, `Package-Thornswood.ps1` |
| Publish gate | Ship and Publish-Installer refuse an unsigned or wrongly signed file | `scripts\release\Assert-PublishSigned.ps1` |
| Launcher check | WinVerifyTrust, chain to Microsoft Identity Verification Root CA 2020 (`F40042E2...BFA2`), a "Microsoft ID Verified CS" issuer, a timestamp, the ThornswoodRelease durable identity `1.3.6.1.4.1.311.97.203948530.216998690.847558466.123546472`, Subject contains `ExpectedSigner` | `launcher\app\Signature.cs`, `Updater.cs` |
| Checksums | release.yml writes `SHA256SUMS` for Thornswood.exe and setup-stub.exe onto a DRAFT release; Ship downloads and refuses on mismatch. The feed names every pack, the launcher and the client runtime by sha256 and serves them at `/feed[-dev]/assets/<sha256>`; the launcher refuses an empty or mismatched hash | `.github/workflows/release.yml`, `docs\FEED.md`, `Updater.cs` |
| Build records | `records\client-build.json` and `server-build.json` name every built file by hash and the fork commit; the feed's `release` object names id, channel, commit, branch, tag; `releases.txt` on the VPS keeps the history | `records\README.md`, `docs\FEED.md` |

What is NOT covered today, which is what this issue is about:

- Packs, the client runtime, `version.json` and the build records are zips
  and JSON. Authenticode cannot sign them. They are protected only by the
  sha256 the feed names, and the feed is protected only by https and by who
  can write `C:\Thornswood-Docs\feed` over ssh. Whoever can write the feed
  can change both a pack and its hash.
- release.yml does not sign. The runner's exe is signed later on One, so the
  draft release on GitHub holds unsigned bytes and a `SHA256SUMS` for them,
  and the published file has a different hash from the draft's.
- Nothing ties source commit, engine pin, runner, records and artifact hashes
  together in one signed statement.

## 2. Artifact types and how each is signed

| Artifact | Format | Signature | Algorithm | Verified by |
| --- | --- | --- | --- | --- |
| Launcher `Thornswood.exe` | PE | Authenticode, embedded (today) | RSA certificate from Artifact Signing, SHA256 file digest, RFC 3161 SHA256 timestamp | Ship gate; installed launcher before swap (`Signature.cs`) |
| Installer / setup-stub | PE | Authenticode, embedded (today) | same | Ship gate; Windows SmartScreen; players |
| Client runtime, packs, baseline, optional packs | zip | Covered by the signed release manifest (below), by sha256 | SHA256 entries in a signed manifest | Launcher (phase C), Ship gate |
| Feed `version.json` | JSON | Covered by the signed release manifest: the manifest names the feed's own sha256 for that release | same | Launcher (phase C), `Check-ShipReady` |
| Build records `client-build.json`, `server-build.json` | JSON | Covered by the signed release manifest | same | Ship gate, box deploy |
| Release manifest `release-<id>.cat` (new) | Windows catalog (PKCS#7) | Authenticode via the SAME Artifact Signing profile (`signtool sign` signs `.cat` files) | as above | `Signature.cs` on the catalog, then each listed sha256 |

Why a catalog. It reuses the one signing identity the launcher already pins,
the one tool chain (`Sign-Artifact.ps1`) and the one custody arrangement. No
second key exists to lose, leak or rotate. A catalog is signed exactly like
an exe and checked by the same `Signature.cs`, and it carries a list of
hashes. A plain JSON manifest signed as a detached PKCS#7 by the same profile
is the fallback if catalogs prove awkward to build on the runner. A separate
key (minisign, Sigstore keyless) is listed as an alternative under
"Decisions needed", not proposed.

The manifest also carries the provenance: source commit, engine/skymp pin,
tag, release id, runner name, the hashes of `client-build.json` and
`server-build.json`, and the sha256 of every asset. The pilot's
`records\signing\pilot-2163.json` is that shape for one test file.

## 3. Owners, custody, rotation, recovery, revocation

| Thing | Owner | Custody |
| --- | --- | --- |
| Signing account ThornswoodSigning and profile ThornswoodRelease | Patrick (makes accounts and gives the Certificate Profile Signer role, Developer-Guide.md "Your own signing sign in", #1740) | In Azure. No private key leaves Microsoft's HSM; certificates last three days and are reissued |
| Right to sign | Each person who ships, with their own account holding Certificate Profile Signer on ThornswoodRelease | Their own `az login` on the machine they ship from. Nothing is copied between machines; `signing.json` holds paths only |
| Durable identity pinned by launchers | Launcher lane | `Signature.Identities` in `launcher\app\Signature.cs` |
| `SHA256SUMS`, feed hashes, records | Release lane (Ship) | Git (records), GitHub draft releases, VPS feed store |

Rotation. Certificate rotation is automatic (three days) and needs nothing
because the launcher pins the root and the durable identity, not a
thumbprint. A NEW profile or new identity validation is a rotation that does
need work, already written in `records\signing\README.md`: add the new
durable identity to `Signature.Identities`, Ship that launcher signed with
the OLD profile, and only then sign with the new one. Rotating a person's
signing right is removing their role assignment.

Recovery. Lost machine: nothing to recover, sign in on another machine and
run `Setup-ShipMachine.ps1`. Lost or compromised Azure account of a signer:
Patrick removes the role and resets the account; no key is exposed because
none was held. Lost signing account or profile: a new profile means a new
durable identity, and installed launchers refuse it, so recovery is the
documented two-step identity add. That only works while the old profile can
still sign the bridging launcher. If the old profile is gone first, every
installed launcher must be updated by hand (new installer). This is the main
recovery risk and why "Decisions needed" asks about a second identity.

Revocation. Microsoft can revoke a certificate; a timestamped signature made
before the revocation date stays valid, later ones fail WinVerifyTrust. To
withdraw one bad release without revoking: point the feed back at the last
good release (the feed store keeps `history\`), and once the manifest is
enforced, list the bad manifest's sha256 in a `revoked` array the launcher
refuses. Emergency stop of all signing: remove the signer role assignments.

## 4. Verification points

1. Sign time (`Sign-Artifact.ps1`): reads the signature back, must be Valid.
2. Publish (`Assert-PublishSigned.ps1`): Authenticode Valid, Subject has
   ExpectedSigner, `Signature.cs` passes. Unchanged.
3. Ship download of the runner's draft: `SHA256SUMS` first (unchanged), then
   in phase B the draft's manifest signature.
4. Launcher self update: sha256 from the feed, then `Signature.cs` (today).
5. Launcher pack and runtime download: sha256 from the feed (today), plus the
   manifest signature and listing (phase C).
6. Independent check by anyone: `Test-SignPilot.ps1 -Verify` style, no sign in.

## 5. Migration and enforcement

Checksums are never removed. Every phase adds a check in front of or beside
the sha256 and keeps the sha256 check.

- Phase A, pilot (this change): a TEST exe signed and verified on One with
  the real profile, an offline harness, this document. No live change.
- Phase B, produce: Ship writes and signs the manifest and uploads it to the
  feed store beside `version.json`; Ship's own gate verifies it. Launchers
  ignore it. Rollback: stop writing it.
- Phase C, warn: a launcher that understands the manifest verifies it and
  reports a failure to the log and the site, but still installs on a good
  sha256. Measure for at least one main and several dev releases.
- Phase D, enforce: a new `minManifestLauncher` (or the next `minLauncher`)
  makes the launcher refuse a release with no manifest, a bad signature, or
  an asset not listed. From here an unsigned artifact is never silently
  accepted. Rollback: the feed can name the previous release (already
  signed), and enforcement is a launcher build, so rolling it back is
  shipping the previous launcher behaviour behind the same flag, not turning
  checks off in the feed.

## 6. Tags, drafts, replacement and failed signatures

- Tag movement. release.yml builds whatever the tag points at, and a tag can
  be moved and re-run (`workflow_dispatch`). Making the tag resolve to the
  intended commit is #2202 (Wyrd lane), not this design. What this design
  adds is only that the manifest records the commit sha the draft was built
  from, so whatever check #2202 settles on has a signed value to compare.
- Draft promotion. The draft's `SHA256SUMS` describes the UNSIGNED runner
  exe; signing on One changes the bytes. Ship already checks the download
  against `SHA256SUMS` before signing; the manifest then records both the
  draft sha256 (unsigned) and the published sha256 (signed), so the chain
  "runner built X, One signed X into Y" is in one signed statement. Promoting
  a draft is a person's act and stays that way.
- Replacement. release.yml deletes and re-uploads same-named assets in a
  draft. After promotion an asset must never be replaced in place: a new
  build is a new release id. The feed serves by sha256, so a replaced file
  is a different URL and old manifests do not list it.
- Failed signature. Refuse, never warn, at every point that refuses today:
  Sign-Artifact exits 1 and Ship publishes nothing. In phase C the launcher
  logs and keeps the old version; in phase D it refuses to install and keeps
  the old version running. The pilot proves a one byte change inside the
  hashed region fails both the checksum and the signature
  (`tests\test-sign-pilot.ps1`, `Test-SignPilot.ps1 -Verify`).

## 7. The pilot

`scripts\release\Test-SignPilot.ps1 -Sign -Verify -Out <folder>` builds a
throwaway console exe, signs it through `Sign-Artifact.ps1 -Required` (the
release path), writes `SHA256SUMS` and `provenance.json`, and verifies with
the Ship gate and `Signature.cs`. Run on One, 11 Oct 2026, from commit
e975a14c: signed by the ThornswoodRelease profile, Microsoft RSA timestamp,
all eight checks passed. Record: `records\signing\pilot-2163.json`.
`-Verify` needs no sign in and no signing setup, so it can be run anywhere.

Found while piloting: flipping a byte in the middle of a small signed exe
can land in the signature blob, which Authenticode does not hash, and still
verify. A tamper test has to change bytes in the hashed region (the pilot
uses the DOS stub text). Anyone writing tamper tests later should know that.

Not yet done: signing and verifying from a second, clean machine. One is the
machine that already ships. That run is queued in the vault
(`claude-queue\2163-signed-releases.md`).

## 8. Decisions needed (Patrick)

1. Key custody for non-PE artifacts: catalog signed by ThornswoodRelease
   (proposed, one identity), or a separate key such as minisign or Sigstore
   keyless (second custody to own).
2. Where release signing happens: keep signing on a person's machine after
   download (today), or give the VPS runner a federated Azure identity with
   the signer role so release.yml signs. The second puts signing rights on
   the shared runners, which also run pull request builds.
3. A second durable identity (a second profile or second validated
   identity) pinned in `Signature.Identities` now, so losing ThornswoodRelease
   does not strand every installed launcher.
4. Who besides Patrick holds Certificate Profile Signer.
5. When phase D enforcement starts, and on which `minLauncher`.
