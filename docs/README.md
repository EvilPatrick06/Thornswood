# docs

Pages about how Thornswood works, for everybody on the team. The rules are
Developer-Guide.md at the root; the long form is Developer-Guide.md.

| Page | What it answers |
| --- | --- |
| [WEBSITE-AUDIT.md](WEBSITE-AUDIT.md) | Public website discovery, accessibility, privacy and reliability checks, with verification and remaining operator risks. |
| [WEBSITE-OPERATIONS.md](WEBSITE-OPERATIONS.md) | Confirmed operator facts, legal applicability questions, public asset permission evidence and recovery procedures. |
| [SYSTEM.md](SYSTEM.md) | What runs where, what talks to what, and which script puts each piece in place: every VPS service with its folder, port and task. |
| [FEED.md](FEED.md) | The update feed launchers read: every field of version.json, who writes it, who reads it, and what happens when it is wrong. |
| [ICONS.md](ICONS.md) | Which icon file is which: Main launcher badge, Dev launcher monogram, site favicon. |
| [GAMEMODE.md](GAMEMODE.md) | How game/gamemode.js is laid out, where its data lives, how it is deployed and which tests cover it. |
| [GAMEMODE-COVERAGE.md](GAMEMODE-COVERAGE.md) | Which test drives each gamemode event handler, plugin, money function and chat word, and the gaps that were filled. |
| [SYSTEMS.md](SYSTEMS.md) | Thornswood systems. The summary of every system, and a link from each section to the full plan. |
| [systems/](systems/) | The finished plan for each system, one page each. Where the server is now is the last section of the page. The item lists are [systems/lists](systems/lists/README.md). |
| [GLOSSARY.md](GLOSSARY.md) | The words used everywhere here, Keep, Hold, pack, baseline, door and the rest, one line each. |
| [../engine/README.md](../engine/README.md) | Building the SkyMP fork: the submodule, the configure line, the build and the records. |
| [IT-IS-DOWN.md](IT-IS-DOWN.md) | What to do when the server, the site or voice is down. |
| [RESTORING.md](RESTORING.md) | Bringing the server, the site and the bot back from a backup. |
| [MOVING-THE-SERVER.md](MOVING-THE-SERVER.md) | Growing the VPS, or moving everything to a new box. |
| [OWNERSHIP.md](OWNERSHIP.md) | Who holds each credential, account and build, and who the second holder is. |
| [CLEAN-INSTALL-RUN.md](CLEAN-INSTALL-RUN.md) | The checklist for a stranger's first install, and what each step should show. |
| [COLLECTION-REVISION-2.md](COLLECTION-REVISION-2.md) | The Vortex pass for collection revision 2, step by step, and the exact plugin order a clean install must land in. |
| [COLLECTION-REVISION-3.md](COLLECTION-REVISION-3.md) | Collection revision 3 (#1262): the Unofficial Skyrim Special Edition Patch at 4.3.8a, its two rules and the 49-position order. Local side only until published. |
| [COLLECTION-REBUILD-7ESSXF.md](COLLECTION-REBUILD-7ESSXF.md) | Rebuilding onto the 7essxf Nexus collection and the steps on the ship PC. |
| [COLLECTION-METHOD.md](COLLECTION-METHOD.md) | Why the mods come from a Nexus collection (half of the 15 September plan was reversed; it says which). |
| [VIRUSTOTAL-FALSE-POSITIVE.md](VIRUSTOTAL-FALSE-POSITIVE.md) | Historical notes on scanner flags and vendor reports. Publish no longer uploads to VirusTotal; signing (#390) is the trust path. |
| [JKS-SKYRIM.md](JKS-SKYRIM.md), [GOURMET-FISHING-PATCH.md](GOURMET-FISHING-PATCH.md) | Records of two mod decisions and the patch made for one. |
| [LIGHT-ORDER-DRIFT.md](LIGHT-ORDER-DRIFT.md) | Every light plugin form id the live and the dev world stored, which plugin each was for, which have drifted with the light order, and the one-time move (#1715). |
| [NPC-POPULATION.md](NPC-POPULATION.md) | NPC population catalogue from the winning records in the load order. |
| [NPC-SERVER-ACTIVITY.md](NPC-SERVER-ACTIVITY.md) | Shared NPC activity on dev: who owns placed identities, movement, combat and return. |
| [npc-server-runtime.md](npc-server-runtime.md) | Dev NPC loading and first unattended activity. |
| [NPC-WORLD-PLAN.md](NPC-WORLD-PLAN.md) | NPC world work: town cut, habitat rules, rates and merchant quests. |
| [archive](archive) | Dated snapshots, history only. |

Every page cites file and line for what it says. When a page and the code
disagree, the code is right: fix the page in the same pull request.
