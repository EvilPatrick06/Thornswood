Thornswood installer licence texts
==================================

These three files are staged into every installer beside SOURCE CODE.txt
(Package-Thornswood.ps1), copied into the install folder (Setup-Thornswood.ps1),
and removed on uninstall (Uninstall.cs). Issue #421.

  GPL-3.0.txt
    Byte for byte skyrim-platform/LICENSE at fork commit b6721bb0
    (https://github.com/EvilPatrick06/skymp). Same text as skymp5-client/LICENSE
    at that commit. Covers the GPL client runtime files.

  AGPL-3.0.txt
    Byte for byte skymp5-server/LICENSE at the same commit. Covers
    MpClientPlugin.dll and the server engine.

  WebView2-LICENSE.txt
    The Microsoft.Web.WebView2 1.0.2903.40 LICENSE.txt text already quoted in
    THIRD-PARTY.md under "Microsoft WebView2 SDK licence". Covers the three
    WebView2 files the launcher embeds.

When the recorded fork commit moves, refresh GPL-3.0.txt and AGPL-3.0.txt from
that commit's LICENSE files in the same pull request that moves
records/client-build.json and records/server-build.json.
