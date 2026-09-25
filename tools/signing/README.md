# tools\signing

The code signing setup, in the repository since 25 September. Until then it
was `C:\tools` on Patrick's machine, which nothing backed up and no other
machine had.

- `metadata.json`: which Azure Artifact Signing account, region and
  certificate profile `signtool` signs with. Tracked in git: it names the
  account and holds no key or password. `CertificateProfileName` still reads
  "FILL THIS IN AFTER THE PROFILE EXISTS" because the profile was never
  created, and `tools\Sign-Artifact.ps1` skips signing while it does.
- `client\`: Microsoft's signing client, `Azure.CodeSigning.Dlib.dll` and what
  comes with it, from the `Microsoft.Trusted.Signing.Client` package on NuGet.
  Ignored by git: it is Microsoft's, and it can be fetched again.

`tools\signing.json` says whether a machine signs, and with what. It stays out
of git because it is one machine's setup. Its `dlib` and `metadata` can name
these files relative to the repository folder:

```json
{
  "method": "artifactsigning",
  "dlib": "tools\\signing\\client\\Azure.CodeSigning.Dlib.dll",
  "metadata": "tools\\signing\\metadata.json"
}
```

Signing is switched off on purpose and not finished (Patrick, 22 September:
"the code signing stuff isnt finnished thats why its switched off"). What is
left is on the To Do List, "Nothing is code signed".
