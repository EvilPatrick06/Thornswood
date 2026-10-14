# Thornswood To Do

Everything the Thornswood team needs to do, in the order to do it. One card
is one issue on [EvilPatrick06/Thornswood](https://github.com/EvilPatrick06/Thornswood/issues),
and this board is the only record of outstanding work: if it is not here, it
is not going to get done.

## Reading it

- **Order** is the do-order. Sort the view by Order and work down.
- **wave:** labels are the stage: 1 Today, 2 This week, then identity and
  safety, arriving in the world, what a stranger sees, release and
  operations, everything else, nice to have, and the world.
- **area:** labels say which part of the project it is.
- **needs:** labels say what it waits on: the live server, or Patrick.
- **anyone can start** marks work that needs nobody in particular.
- Each issue says where the problem lives, what is known, the steps as a
  checklist, the commands, when it is done, and the traps.

## Working on it

- Assign yourself when you start, and move the card to In Progress.
- Found something new? Open an issue with the Work to do template and give it
  the Order of where it belongs (52.5 between 52 and 53 is fine), not the end.
- Something that fits an existing issue goes on that issue as an edit or a
  comment, not a second issue.
- Write down what was measured and what is left, not just that you looked.
- A fix changes the cause. No band-aids: nothing that notices the damage and
  undoes it, and no retry that hopes a race comes out right. Until the cause
  is found, finding it is the work.
- A pull request that finishes an issue says `Closes #N`; merging it closes
  the issue and moves the card to Done.
- A fix people would notice says `Refs #N` instead, and its issue stays open
  until the fix is on main, where testers test. Then it is closed with a
  comment that starts `Test task:`, which the bot posts to #test-tasks.
  A test task with `Server: Dev` under its first line is a measurement
  someone on dev has to take: the bot posts it, open issue or closed, in the
  staff-only #dev-test-tasks.

The rules behind all of this are in
[Developer-Guide.md](https://github.com/EvilPatrick06/Thornswood/blob/main/Developer-Guide.md).
Every entry from before the board, finished ones included, is in
[docs/archive/todo-list-2026-09-25.md](https://github.com/EvilPatrick06/Thornswood/blob/main/docs/archive/todo-list-2026-09-25.md);
an "entry 243" in the code means entry 243 there.
