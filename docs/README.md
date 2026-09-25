# docs

Pages about how Thornswood works, for everybody on the team. The rules are
CONTRIBUTING.md at the root; the long form is DEVELOPING.md.

| Page | What it answers |
| --- | --- |
| [SYSTEM.md](SYSTEM.md) | What runs where, what talks to what, and which script puts each piece in place: every VPS service with its folder, port and task. |
| [FEED.md](FEED.md) | The update feed launchers read: every field of version.json, who writes it, who reads it, and what happens when it is wrong. |
| [GAMEMODE.md](GAMEMODE.md) | How game/gamemode.js is laid out, where its data lives, how it is deployed and which tests cover it. |
| [GLOSSARY.md](GLOSSARY.md) | The words used everywhere here, Keep, Hold, pack, baseline, door and the rest, one line each. |
| [../engine/README.md](../engine/README.md) | Building the SkyMP fork: the submodule, the configure line, the build and the records. |
| [IT-IS-DOWN.md](IT-IS-DOWN.md) | What to do when the server, the site or voice is down. |
| [RESTORING.md](RESTORING.md) | Bringing the server, the site and the bot back from a backup. |
| [MOVING-THE-SERVER.md](MOVING-THE-SERVER.md) | Growing the VPS, or moving everything to a new box. |
| [OWNERSHIP.md](OWNERSHIP.md) | Who holds each credential, account and build, and who the second holder is. |
| [CLEAN-INSTALL-RUN.md](CLEAN-INSTALL-RUN.md) | The checklist for a stranger's first install, and what each step should show. |
| [COLLECTION-METHOD.md](COLLECTION-METHOD.md) | Why the mods come from a Nexus collection (half of the 15 September plan was reversed; it says which). |
| [JKS-SKYRIM.md](JKS-SKYRIM.md), [GOURMET-FISHING-PATCH.md](GOURMET-FISHING-PATCH.md) | Records of two mod decisions and the patch made for one. |
| [archive](archive) | Dated snapshots, history only. |

Every page cites file and line for what it says. When a page and the code
disagree, the code is right: fix the page in the same pull request.
