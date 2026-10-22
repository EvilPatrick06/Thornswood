# Nexus and Vortex jobs taken off Patrick's page (20 Oct 2026, 12:41 PM, his word)

The release desk does these once the #2914 scripts work. Steps as they were on the page:

**State, 20 Oct 2:50 PM (Claude):** todo-nexus-line DONE (#2829 closed: both pages 1:48/1:49 PM, 1.0.1 README). todo-421 steps 1 to 5 DONE: Client Runtime 1.0.1 is file 823485, 152,002,702 bytes, md5 74ef6a9f5cf0a5ba7dbab9c00cb67491. Step 6: revision 3 of 7essxf is a DRAFT (id 813334); the Dev check needs Vortex on One to install it, asked as questions/q-421-rev3-vortex on Patrick's page. Then `New-NexusRevision.ps1 -Publish 3`, then step 7 (THIRD-PARTY.md Client Runtime section and the ___systemPolyfill.js tests) in one PR, then close #421. USSEP (#1262) becomes revision 4: renumber docs/COLLECTION-REVISION-3.md, its test and 1262-collection-revision-3.md when 3 is published.

## todo-421-client-runtime-upload
```json
{
  "asked": "2026-10-20T15:20:00Z",
  "id": "todo-421-client-runtime-upload",
  "issue": 421,
  "steps": [
    "Open the Thornswood Client Runtime mod's files in Vortex's staging folder (Thornswood Client Runtime 192762), the copy that becomes the new upload.",
    "Delete [[copy:Data\\Platform\\Distribution\\___systemPolyfill.js]] (your call on 28 Sep: nothing in the client loads it) and [[copy:Data\\Docs\\Thornswood Client Runtime\\licences\\SkyrimPlatform-LICENSE.txt]], which was only there for it.",
    "Replace [[copy:Data\\Docs\\Thornswood Client Runtime\\README.txt]] with [[file:C:\\Thornswood-Repo\\temp\\421\\nexus-client-runtime\\README.txt]] (3,107 bytes, sha256 296515e0). It names no ___systemPolyfill.js, links the source page, and has the d3dcompiler_47.dll terms paragraph from option A of the question beside this. If you pick B there, also delete d3dcompiler_47.dll from RuntimeDependencies and the d3dcompiler lines from the README (the line under Microsoft Direct3D HLSL Compiler in the list and the paragraph starting 'd3dcompiler_47.dll is Microsoft's').",
    "Replace [[copy:Data\\Docs\\Thornswood Client Runtime\\licences\\ICU-LICENSE.txt]] with [[file:C:\\Thornswood-Repo\\temp\\421\\nexus-client-runtime\\licences\\ICU-LICENSE.txt]] (25,505 bytes, sha256 af3e84c4), ICU 71's own text, the one that matches icudtl.dat.",
    "Zip it the way 1.0.0 was zipped, changing nothing else (SkyrimPlatformImpl.dll and SkyrimPlatformCEF.exe.hidden stay out), and upload it on Nexus as version 1.0.1 of [[link:mod 192762|https://www.nexusmods.com/skyrimspecialedition/mods/192762]], as the main file.",
    "Make a new collection revision that points at the new file, and publish it.",
    "Tell Claude the new file id, its size and md5, so THIRD-PARTY.md's Client Runtime section and the tests that name ___systemPolyfill.js are brought up to date."
  ],
  "title": "Upload the next Thornswood Client Runtime to Nexus (the README and ICU 71 licence fixes)"
}

```

## todo-nexus-line
```json
{
  "asked": "2026-10-19T19:00:01Z",
  "id": "todo-nexus-line",
  "issue": 2829,
  "steps": [
    "At the next collection revision, add this line near the top of the description of both mods on Nexus Mods, [[link:Thornswood Content|https://www.nexusmods.com/skyrimspecialedition/mods/192001]] and the [[link:Thornswood Client Runtime|https://www.nexusmods.com/skyrimspecialedition/mods/192762]]: [[copy:THIS MOD IS NOT MADE, GUARANTEED OR SUPPORTED BY ZENIMAX OR ITS AFFILIATES.]]",
    "The Client Runtime's README (Data\\Docs\\Thornswood Client Runtime) carries it from its next upload."
  ],
  "title": "Paste the Nexus notice line at the next collection revision"
}

```

