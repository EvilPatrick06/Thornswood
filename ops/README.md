# ops

What is true now about the servers and releases, and the runs the lanes leave
for the Desk. Patrick moved both here from the vault on 22 Oct 2026, so the Desk
can read and write them from any machine, the cloud included. The vault at
`C:\Thornswood Vault\Thornswood` stays for everything else.

| File | What it is |
| --- | --- |
| [status.md](status.md) | What is true now: what each server runs, what is mid-run, what waits and on what. Rewritten in place, never appended to. |
| `claude-queue/` | One note per change that needs a run (a Ship, a Deploy-*, Publish-*, Install-*, a live or dev server step, a Vortex step). The folder exists while a note is waiting. |

## A run note

A lane only commits, pushes and merges (Developer-Guide.md, the lanes
paragraph). When its change needs a run, it adds one note to
`ops/claude-queue/` in the same pull request as the change, so the note
reaches main with the change it runs and costs no build of its own. Name it
`<issue>-<what>.md`, for example `3078-containers-dev.md`. It holds:

1. The issue it belongs to, and the pull request.
2. The exact commands, in order, from the repository root, and which server
   each one touches (dev or live).
3. Its risks: what goes down, for how long, what to check afterwards.
4. Draft release notes, when people would notice the change.
5. A news post, when people would notice the change.

A note says nothing it would have to ask anybody about. A lane does not ask
anybody to approve a deploy; the note is the hand-off.

## What the Desk does with them

At the start of a session the Desk lists `ops/claude-queue/` on main and runs
each note: dev ones when they are ready, a main Ship or a live server run when
Patrick says so. Afterwards it puts what ran, when, what it printed and the
health check on the issue, rewrites [status.md](status.md), and deletes the
note. A note that cannot run keeps the reason written into it. The status
rewrite and the deleted notes go in one pull request for the batch, not one
each, since every pull request costs a build on the box.
