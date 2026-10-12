# Signed releases and artifact provenance (issue #2163)

Status: DESIGN AND PILOT, with the release.yml move under way (#2163, #498).
release.yml builds on GitHub's hosted Windows runner with MSBuild and signs
the launcher there; Ship, Publish-Installer, the feed and every checksum
check stay as they are. Patrick's answers are at the end, under
"Decisions", and none is pending.

This does not claim reproducible builds. Byte-identical local and runner
builds are impossible with the Framework 4 csc (it stamps a build time and a
fresh MVID). MSBuild with `-p:Deterministic=true` gave two byte-identical
rebuilds on One (#498), but release.yml does not set it and nobody has
measured runner against local. Provenance here means "this signed file came from this commit,
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
- Until the release.yml move (#2163) lands and Patrick's Azure side is set
  up, the runner's exe is signed later on One, so the draft release holds
  unsigned bytes and a `SHA256SUMS` for them, and the published file has a
  different hash from the draft's. Decided (section 8): release.yml signs on
  GitHub's runner through a federated Azure identity, which ends this gap.
  A draft from the VPS fallback job is still unsigned and says so in its notes.
- Nothing ties source commit, engine pin, runner, records and artifact hashes
  together in one signed statement.

## 2. Artifact types and how each is signed

| Artifact | Format | Signature | Algorithm | Verified by |
| --- | --- | --- | --- | --- |
| Launcher `Thornswood.exe` | PE | Authenticode, embedded (today) | RSA certificate from Artifact Signing, SHA256 file digest, RFC 3161 SHA256 timestamp | Ship gate; installed launcher before swap (`Signature.cs`) |
| Installer / setup-stub | PE | Authenticode, embedded (today) | same | Ship gate; Windows SmartScreen for the people installing |
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
key (minisign, Sigstore keyless) was the alternative; Patrick kept the
catalog (section 8, decision 1).

The manifest also carries the provenance: source commit, engine/skymp pin,
tag, release id, runner name, the hashes of `client-build.json` and
`server-build.json`, and the sha256 of every asset. The pilot's
`records\signing\pilot-2163.json` is that shape for one test file.

## 3. Owners, custody, rotation, recovery, revocation

| Thing | Owner | Custody |
| --- | --- | --- |
| Signing account ThornswoodSigning and profile ThornswoodRelease | Patrick (makes accounts and gives the Certificate Profile Signer role, Developer-Guide.md "Your own signing sign in", #1740) | In Azure. No private key leaves Microsoft's HSM; certificates last three days and are reissued |
| Release signing in release.yml (decided, section 8) | Patrick sets up the Azure side (the federated credential and the Signer role on ThornswoodRelease); the owner of the release.yml move does the workflow | A federated (OIDC) identity in Azure that trusts only release.yml on `v*` tags of this repository. No secret, password or key is stored in GitHub or on any machine; GitHub mints a short token per run. Pull request jobs never get it |
| Right to sign by hand | Each person who ships, with their own account holding Certificate Profile Signer on ThornswoodRelease | Their own `az login` on the machine they ship from, for local and fallback signing only once release.yml signs. Nothing is copied between machines; `signing.json` holds paths only |
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
run `Setup-ShipMachine.ps1`. Compromised workflow or repository: Patrick
deletes the federated credential (or removes its role), which stops release
signing at once without touching anyone's own sign in. Lost or compromised Azure account of a signer:
Patrick removes the role and resets the account; no key is exposed because
none was held. Lost signing account or profile: a new profile means a new
durable identity, and installed launchers refuse it, so recovery is the
documented two-step identity add. That only works while the old profile can
still sign the bridging launcher. If the old profile is gone first, every
installed launcher must be updated by hand (new installer). This is the main
recovery risk and why "Decisions" covers a second identity (not for now).

Revocation. Microsoft can revoke a certificate; a timestamped signature made
before the revocation date stays valid, later ones fail WinVerifyTrust. To
withdraw one bad release without revoking: point the feed back at the last
good release (the feed store keeps `history\`), and once the manifest is
enforced, list the bad manifest's sha256 in a `revoked` array the launcher
refuses. Emergency stop of all signing: remove the signer role assignments,
the federated identity's included.

## 4. Verification points

1. Sign time (`Sign-Artifact.ps1`, in release.yml once signing moves there):
   reads the signature back, must be Valid; a failure fails the job and no
   draft gets the file.
2. Publish (`Assert-PublishSigned.ps1`): Authenticode Valid, Subject has
   ExpectedSigner, `Signature.cs` passes. Unchanged.
3. Ship download of the runner's draft: `SHA256SUMS` first (kept), then the
   Authenticode check of the already signed exe and stub, then in phase B the
   draft's manifest signature. Once release.yml signs, `SHA256SUMS` describes
   the signed files.
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
- Draft promotion. Today the draft's `SHA256SUMS` describes the UNSIGNED
  runner exe, and signing on One changes the bytes. With signing in
  release.yml (section 8) the runner builds and signs in one job, the draft
  carries the signed exe (the stub stays unsigned until Package signs the
  finished Setup, section 8) with a `SHA256SUMS` of the signed files,
  and the manifest is signed in the same job, so the draft's hashes and the
  published hashes are the same and "this runner built and signed Y from
  this commit" is one signed statement. Promoting a draft is a person's act
  and stays that way.
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

Not yet done: signing and verifying away from One. With section 8 decision 2
that proof is a signed draft from release.yml, not a second hand-run
machine; the vault note (`claude-queue\2163-signed-releases.md`) says so.

## 8. Decisions (Patrick)

Answered 11 Oct 2026 and settled 12 Oct 2026, 11:11 AM MT (Patrick's
decisions relayed by Smeagle; recorded on #2163). None is pending.

1. Key custody for non-PE artifacts: the default design, a Windows catalog
   signed by ThornswoodRelease (section 2). Decided 12 Oct; no separate key.
2. Where release signing happens: on GitHub's hosted Windows runner, in
   release.yml, through Azure Artifact Signing with a federated (OIDC)
   identity limited to release.yml on `v*` tags (the `release` environment).
   It replaces the earlier "VPS build machine" answer. The same change moves
   release.yml to the hosted runner and makes #498's MSBuild switch for the
   release build, one switchover, not two. The VPS stays the backup for every
   GitHub runner build: release.yml's fallback job runs there the way
   build.yml's does (BUILD_RUNNER = vps, a manual run asking for the box, or
   the hosted job failing), with the in-box csc and unsigned until the VPS
   has MSBuild and a signing path (#498), and Ship signs that draft on
   download as before (#921). The draft from the hosted job carries the
   signed launcher and a `SHA256SUMS` of the signed files. setup-stub.exe
   stays unsigned on purpose: Package signs the finished Setup after the
   OneFile attach, and a pre-signed stub cannot be signed again. Pull request
   jobs never get the identity. The Azure side (the app registration, its
   federated credential for the `release` environment, and the Certificate
   Profile Signer role on ThornswoodRelease) is Patrick's to set up.
3. Second durable identity: still not for now. The recovery risk in section
   3 stays accepted.
4. Signers holding Certificate Profile Signer on ThornswoodRelease: Patrick,
   Djinn and Four.
5. Main builds are always signed. Dev builds stay unsigned to save signing
   quota. Phase D runs only after Claude's signing pilot verifies on a clean
   machine (a signed draft from release.yml, checked with
   `Test-SignPilot.ps1 -Verify` style checks away from One), and its
   `minLauncher` is set to the first signed launcher.
