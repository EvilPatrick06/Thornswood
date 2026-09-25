# docs

Pages about how Thornswood works, for everybody on the team. The rules are
CONTRIBUTING.md at the root; the long form is DEVELOPING.md.

| Page | What it answers |
| --- | --- |
| [SYSTEM.md](SYSTEM.md) | What runs where, what talks to what, and which script puts each piece in place: every VPS service with its folder, port and task. |
| [FEED.md](FEED.md) | The update feed launchers read: every field of version.json, who writes it, who reads it, and what happens when it is wrong. |
| [GAMEMODE.md](GAMEMODE.md) | How tools/gamemode.js is laid out, where its data lives, how it is deployed and which tests cover it. |
| [GLOSSARY.md](GLOSSARY.md) | The words used everywhere here, Keep, Hold, pack, baseline, door and the rest, one line each. |
| [../engine/README.md](../engine/README.md) | Building the SkyMP fork: the submodule, the configure line, the build and the records. |
| [archive](archive) | Dated snapshots, history only. |

Every page cites file and line for what it says. When a page and the code
disagree, the code is right: fix the page in the same pull request.
