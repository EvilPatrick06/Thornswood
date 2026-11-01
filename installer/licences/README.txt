Thornswood installer licence texts
==================================

These five files are staged into every installer beside SOURCE CODE.txt
(Package-Thornswood.ps1), copied into the install folder (Setup-Thornswood.ps1),
and removed on uninstall (Uninstall.cs). Issue #421.

  GPL-3.0.txt
    Byte for byte skyrim-platform/LICENSE at fork commit 1a2e5995, and at
    5c54e8b9 before it (the file did not change between them)
    (https://github.com/ThornswoodRP/skymp). Same text as skymp5-client/LICENSE
    at that commit. Covers the GPL client runtime files.

  AGPL-3.0.txt
    Byte for byte skymp5-server/LICENSE at the same commit. Covers
    MpClientPlugin.dll and the server engine.

  Concentus-LICENSE.txt
    Byte for byte LICENSE in the Concentus 2.2.2 package from nuget.org, the
    Opus BSD licence, quoted in THIRD-PARTY.md under "Concentus licence".
    Covers the Opus codec compiled into the launcher for voice (#4823).

  SharpSRTP-LICENSE.txt
    Byte for byte LICENSE in https://github.com/jimm98y/SharpSRTP at commit
    ede1d045, the commit SharpSRTP 0.5.8's nuspec names (MIT), quoted in
    THIRD-PARTY.md under "SharpSRTP licence". Covers the DTLS-SRTP code
    compiled into the launcher for voice (#4823).

  BouncyCastle-LICENSE.txt
    Byte for byte LICENSE.md in the BouncyCastle.Cryptography 2.7.0 package
    from nuget.org (MIT), quoted in THIRD-PARTY.md under "BouncyCastle
    licence". Covers the cryptography SharpSRTP is built on, compiled into
    the launcher (#4823).

When a voice library's version moves in launcher/app/Thornswood.csproj,
refresh its text here from the new package in the same pull request.

When the recorded fork commit moves, refresh GPL-3.0.txt and AGPL-3.0.txt from
that commit's LICENSE files in the same pull request that moves
records/client-build.json and records/server-build.json.
