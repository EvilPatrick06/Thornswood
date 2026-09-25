# Reporting something quietly

Thornswood is a small modded Skyrim server in closed playtest. It holds Discord
ids, the names people choose, what they said in chat, and a record of when they
played. That is enough to be worth reporting a hole in rather than posting one.

## Where to send it

**Use GitHub's private vulnerability reporting** on this repository: the
Security tab, then *Report a vulnerability*. It opens a thread only the
maintainers can read, and it is the preferred way because nothing about it is
public until we say so.

If that is not available to you, send it to the owner as a Discord direct
message rather than posting it in a channel. The Discord is linked from
[thornswood.net](https://thornswood.net).

Please do not open a public issue for a security problem, and please do not
post it in a Discord channel. Both are read by everybody, including whoever
would use it.

## What to include

Whatever you have. A sentence and a screenshot is a real report.

- What you did, in the order you did it.
- What happened that should not have.
- Which address or which part of the game, if you know.
- Whether you had to be signed in, in the Discord, or in the world.

You do not need a proof of concept and you should not need to take anything to
prove it. If you already have, say so and say what you have, so it can be
deleted.

## What happens next

- A reply within **72 hours**, saying whether it is understood and whether it
  is being worked on. This is a two person project, so that is a person
  answering rather than a process.
- A fix goes out on the dev build first and then to everybody, which is how
  every change here goes out.
- You will be told when it is fixed, and credited in the release note if you
  want to be. Say either way.

## What is in scope

- The site at thornswood.net, its login and its API.
- The voice service, its join tokens and its rooms.
- The game server: anything that lets somebody act as another person, take
  what is not theirs, or take the world down.
- The launcher and the update feed: anything that would put a file on somebody
  else's machine.

## What is not

- Anything about Skyrim itself, or about the mods in the collection. Those
  belong upstream.
- Somebody being rude in chat. That is moderation and goes to the staff in
  Discord.
- A missing hardening header on a page that holds nothing, unless you can show
  what it lets somebody do.

## Please do not

- Test against the live server with other people in it. Ask and you will be
  given the dev one.
- Read, change or delete anybody else's data to prove a point. Showing that you
  could is enough.
- Run anything that takes the server down for the people playing on it.

Reports made in good faith under those rules will not be answered with anything
other than thanks and a fix.
