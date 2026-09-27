# records\signing

The code signing setup, in the repository since 25 September. Until then it
was `C:\tools` on Patrick's machine, which nothing backed up and no other
machine had.

- `metadata.json`: which Azure Artifact Signing account, region and
  certificate profile `signtool` signs with. Tracked in git: it names the
  account and holds no key or password. The profile is `ThornswoodRelease`
  (it read "FILL THIS IN AFTER THE PROFILE EXISTS" until 27 September, while
  the machine that signs read its own copy at `C:\tools\metadata.json`).
- `client\`: Microsoft's signing client, `Azure.CodeSigning.Dlib.dll` and what
  comes with it, from the `Microsoft.Trusted.Signing.Client` package on NuGet.
  Ignored by git: it is Microsoft's, and it can be fetched again.

`tools\signing.json` says whether a machine signs, and with what. It stays out
of git because it is one machine's setup. Its `dlib` and `metadata` can name
these files relative to the repository folder:

```json
{
  "method": "artifactsigning",
  "dlib": "records\\signing\\client\\Azure.CodeSigning.Dlib.dll",
  "metadata": "records\\signing\\metadata.json"
}
```

SIGNING IS ON since 27 September (issue #390, closed). It was switched off on
purpose until then (Patrick, 22 September: "the code signing stuff isnt
finnished thats why its switched off"). The launcher and the setup program are
signed on every Ship from a machine whose `tools\signing.json` is enabled.

EVERY RELEASE HAS TO BE SIGNED NOW. `ExpectedSigner` in
`launcher\app\Updater.cs` is set, so a launcher from dev 1.1.101.17 on
refuses an update that is not signed by this certificate. A machine with no
`tools\signing.json`, or one that is disabled, still builds and Ships and
only prints "not signing": its launcher would be refused by everybody on a
signed one. So only a machine that signs Ships, dev included, until Ship
itself refuses an unsigned launcher.

The certificate is issued to a person, and Windows shows that person's name
as the verified publisher. The live main launcher, 1.1.101, was built before
signing and is unsigned; the next main Ship is the first signed one.
