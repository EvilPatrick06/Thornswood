# Sending a change

Thank you for wanting to help. Most changes here come from the Thornswood team,
and [Developer-Guide.md](Developer-Guide.md) is their long form. This page is
the short one, for anybody.

## Before you start

- **A problem or an idea** goes in an issue first, with one of the
  [forms](https://github.com/EvilPatrick06/Thornswood/issues/new/choose), so we
  can say whether a change for it is wanted before you spend time on one.
- **A security hole** never goes in an issue or a pull request.
  [SECURITY.md](SECURITY.md) says where to send it.
- Read [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Sending it

1. Fork the repository and make a branch from `main`.
2. Make one change. A pull request that changes eight things is eight reviews.
3. Fix the cause. If something breaks, find out why and change that, rather
   than adding something that hides it. Say in the pull request what the cause
   was and how you found it.
4. Run the tests your change can reach. They are in `tests/`, and each one says
   at its top what it checks (`node tests/test-<name>.js`, or
   `pwsh tests/test-<name>.ps1`). `pwsh scripts/dev/Check-Words.ps1` checks
   the writing in every file people read.
5. Open the pull request and fill in its first three parts. Leave the part
   for the Thornswood team as it is.

The team reads it, runs the build check on it, and says what is needed before
it can be merged.

## What we cannot take

- Other people's work without their leave: mods, meshes, textures, sounds,
  music, fonts or code. Say whose it is and where the leave is written.
  [THIRD-PARTY.md](THIRD-PARTY.md) lists what is here already.
- Bethesda's files, and anything from the Creation Club. Thornswood is Skyrim
  Special Edition only, and its files are never ours to share.
- Secrets of any kind: keys, tokens, passwords, addresses that are not public.

## The licence

[LICENSE](LICENSE) says what Thornswood's own work is under, and the terms for
what you contribute. Read it before you send a change.
