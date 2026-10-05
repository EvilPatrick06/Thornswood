# Light plugin form ids stored under a light order that moved

Issue #1715, measured on 5 October 2026. Every light plugin form id the live
and the dev world have stored, which plugin and record each one was stored
for, and whether it still names that record. What moves them once is
`scripts\oneoff\Move-LightFormIds.ps1`.

## Why an id can drift

A light plugin's forms have ids `0xFE000000 | (light index << 12) | local id`.
The light index is the plugin's place among the light plugins the game loads:
the Skyrim.ccc ones in Data first (`_ResourcePack.esl` is light index 0), then
the plugin list's. Until the engine loads light plugins, the server leaves them
out of its load order (`scripts\deploy\Deploy-Gamemode.ps1`), so nothing held
the light order to one answer: each machine had whatever Vortex and LOOT gave
it. The server stores the id the client sends (a character's head parts, in
`appearanceDump.headpartIds`), so a stored light id names the right record only
while the light order is the one it was stored under.

## The light orders the game used

From the 133 session logs the 5 October measurement read (24 September to
5 October), each with the light list the game wrote to
`thornswood-plugins-light.txt` in that session. Ten different light orders:

| Light list | Light plugins | `_ResourcePack.esl` | KhisartinBeards.esp | HammerHair.esp |
| --- | --- | --- | --- | --- |
| 1591C2319952 | 43 | 0 | 0x22 | 0x1E |
| 205F8519A84C | 53 | 0 | 0x27 | 0x1B |
| 545C0B26371C | 54 | 0 | 0x29 | 0x24 |
| 77D42F5BD5AA | 42 | not loaded | 0x21 | 0x1D |
| 7CDDE011B954 | 43 | 0 | 0x20 | 0x1C |
| 885E9FAF4F2F | 43 | 0 | 0x1E | 0x19 |
| 9E6D5DE3A1ED | 52 | 0 | 0x26 | 0x21 |
| A63BDF188CA4 | 54 | 0 | 0x29 | 0x25 |
| B6C5A7A5DF34 | 42 | not loaded | 0x1F | 0x1B |
| E6B27D27E717 | 41 | not loaded | 0x1E | 0x1A |

The light list is named by the first twelve hex digits of its hash, as the
measurement keyed it. Different machines used different lists on the same
day. The main sessions of 5 October that name a character used
A63BDF188CA4, and so did a dev session at 12:01; the last dev session that
day, at 12:17, used 205F8519A84C. On 24 to 26 September the dev sessions
used B6C5A7A5DF34, 7CDDE011B954, 77D42F5BD5AA and 1591C2319952.

## Every stored light id

A scan of every change form in both world folders (`world\changeForms` under
the live and the dev server root) for numbers in the light range. The
measurement kept seven of its matches as form ids, every one a head part in a
character's appearance; the scan's other matches were not at an id field.

| World | Record | Field | Stored id | Light index | Local id | Stored for | Record type |
| --- | --- | --- | --- | --- | --- | --- | --- |
| live | `a.json` | headpartIds[7] | 0xFE029827 | 0x29 | 0x827 | KhisartinBeards.esp | HDPT |
| live | `a.json` | headpartIds[8] | 0xFE029838 | 0x29 | 0x838 | KhisartinBeards.esp | HDPT |
| dev | `6.json` | headpartIds[5] | 0xFE01CBD6 | 0x1C | 0xBD6 | HammerHair.esp | HDPT |
| dev | `6.json` | headpartIds[6] | 0xFE01CBD8 | 0x1C | 0xBD8 | HammerHair.esp | HDPT |
| dev | `6.json` | headpartIds[7] | 0xFE01CBD7 | 0x1C | 0xBD7 | HammerHair.esp | HDPT |
| dev | `7.json` | headpartIds[7] | 0xFE020827 | 0x20 | 0x827 | KhisartinBeards.esp | HDPT |
| dev | `7.json` | headpartIds[8] | 0xFE020838 | 0x20 | 0x838 | KhisartinBeards.esp | HDPT |

How each was tied to its plugin: a measured light list puts that plugin at
that light index, and that plugin has a head part record (HDPT) at that local
id (read from the plugins' own records). It is the only one that fits. Live's
`a.json` belongs to profile 1035774629, whose sessions on 5 October were main
sessions on A63BDF188CA4, where KhisartinBeards.esp is 0x29 (issue #1930).
Dev's `6.json` (written 24 September, 22:42) has three ids at 0x1C with local
ids 0xBD6 to 0xBD8: only 7CDDE011B954 puts HammerHair.esp at 0x1C, and
HammerHair.esp has head parts at all three. Dev's `7.json` (written
25 September, 10:50; profile 787062656 by issue #1930) has two at 0x20 with
local ids 0x827 and 0x838: only 7CDDE011B954 puts KhisartinBeards.esp at
0x20, and it has head parts at both. HammerHair.esp has a head part at
0x827 too, but it is at 0x20 in no measured list and has none at 0x838.

## Which have drifted

Against the light order each server's clients use now:

- **Live: 2 stored, 0 drifted.** Both are KhisartinBeards.esp at 0x29, its
  index in the main sessions of 5 October.
- **Dev: 5 stored, 5 drifted.** HammerHair.esp is 0x1B and KhisartinBeards.esp
  0x27 in the last dev light order, so the three HammerHair.esp ids at 0x1C
  and the two KhisartinBeards.esp ids at 0x20 name other plugins' forms. The
  measurement of 5 October read light index 0x20 there as
  RaceMenuMorphsHIMBO.esp, whose only record is a quest, so 0xFE020827 names
  nothing at all.
- Live's two would drift the same way on a server whose light order is dev's:
  KhisartinBeards.esp is 0x29 on one and 0x27 on the other.

The plugins involved: KhisartinBeards.esp and HammerHair.esp. 487 playable
head parts come from light plugins (HammerHair.esp 416, KhisartinBeards.esp
60, AwBaldandShavedHair.esp 11, issue #1930), so every character that picks
one stores an id that moves with the light order.

## What stops it, and what puts the stored ones right

- With an engine that loads light plugins (`"lightPlugins": true` in
  `records\server-build.json`), Deploy-Gamemode lists them, the server's light
  order is kept from deploy to deploy the way its full order is
  (`scripts\deploy\ServerOrder.ps1`), the manifest publishes it as `light`,
  and the launcher holds every machine's list to it (Scan names the first
  light plugin out of place, Fix puts the list into the server's whole order,
  and Publish-Update ships the pack's list that way).
- The first deploy that lists light plugins takes the light order from the
  build's plugin list, the way the game takes it. For main that is the order
  the live ids were stored under, so they stay right. For dev it is not the
  order of 24 and 25 September, so its five ids are moved once with
  `scripts\oneoff\Move-LightFormIds.ps1`, on a copy of the dev world taken
  with the server stopped:
  - `-Plan`: order `dev0924` is the light list 7CDDE011B954, for `6.json`
    (the three HammerHair.esp ids) and `7.json` (the two KhisartinBeards.esp
    ids); order `live1005` is A63BDF188CA4, for live's `a.json`.
  - `-To`: the server's own manifest after that deploy, which has the light
    list.
  - A dry run first, then `-Write`, which keeps each record it changes as it
    was. Every id it moves is listed with its plugin and local id.
- The synthetic save that builds a returning character at the main menu
  cannot name a light plugin's form at all on main's native (issue #1930);
  that is the engine's to fix and is apart from this.
