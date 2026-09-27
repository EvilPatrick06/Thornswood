# Privacy

What Thornswood keeps about you, why, and how to have it deleted.

Thornswood is a free fan project run by two people. It is not a company. This
page is written plainly rather than legally, and it is meant to be the whole
truth rather than the minimum.

## The short version

- Signing in with Discord tells us your Discord id, your name there and which
  roles you have. Nothing else from your Discord account.
- Playing sends the server your character, where it is and what it does, and
  what you type in chat.
- Voice is carried between people and is not recorded.
- Ask for deletion in the Discord and it is done.
- There is no advertising tag and no analytics on this site.

## What is stored, and why

**Your Discord id, name and roles.** Sign-in is Discord and nothing else, so
this is how the server knows who you are and whether you are allowed in. It is
the only identity Thornswood has: there are no passwords here and no email
addresses.

**When you played.** Each session records who, when it started and when it
ended, so a closed playtest has a record of what was tested and by whom
instead of somebody's memory.

**Your character.** Name, appearance, what you carry, where you are standing,
what you have built and claimed, and the ranks you have earned. That is the
character, and without it there is nothing to log back into.

**What you say in chat.** Kept so that a report of something that happened has
something behind it other than one person's word. If you would not want a
moderator to read it, do not type it in a shared channel.

**The launcher's own log.** Sent to the site when a session ends. It is about
the game: which mods are installed, what failed to start, which version you
are on. It is how somebody who cannot play gets helped without a conversation.

## What is not stored

- No email address, no password, no payment details. Patreon holds the
  payment side and Thornswood never sees a card.
- No voice recording. Voice is passed between the people in the room and
  nothing keeps a copy.
- No advertising or analytics tag on this site. There was a Google Ads tag
  until 23 September 2026 and it was removed.

## What leaves this site anyway

Honesty about the things a page does by existing:

- **Discord** is where sign-in happens, so signing in tells Discord that you
  signed in here.
- **GitHub** hosts the launcher updates, so your launcher asks GitHub for them.

Opening a page on this site loads nothing from anybody else. The fonts came
from Google and a markdown renderer from cdnjs until 24 September 2026, and
both are served from here now.

## How long it is kept

- **Sign-in records**, which are the only thing here holding your address, are
  deleted after 30 days. That is enforced by the site rather than promised:
  old rows go whenever the log is written or read.
- **Session records and chat** are kept for 365 days, then dropped. The site
  prunes session logs after that window (a session marked kept is never
  pruned). Chat on the voice service ages the same way. Both numbers come from
  the code rather than a promise on this page; if they change, this line
  changes with them.

- **Your character** is kept until you ask for it to be deleted, or until a
  wipe, which is announced first.
- **Launcher logs** are kept while they are useful for fixing something.

## Deleting it

Ask in the Discord, or open a ticket there with **I need help**. Say which
account and what you want removed. It is done by a person, and you will be told
when it is.

What deletion means here: your Discord link, your session records, your chat
and your character. What cannot be undone is something you said that somebody
else has already quoted in a report, because that now belongs to the report.

## Who can see it

The two people who run Thornswood, and moderators for the parts moderation
needs. Nothing is sold, shared or handed to anybody else, and there is nobody
to hand it to.

## Children

Thornswood is eighteen and over. If you are under eighteen, do not sign up, and
if you already have, say so and the account will be removed.

## Changes

This page is in the repository with the rest of the site, so every change to it
has a date and an author in the history. If something material changes it will
be said in the Discord rather than quietly edited.

## Cookies

These cookies make the site and the age gate work. They are not advertising and they are not analytics.

- **tw**. Signed member cookie after Discord sign-in. HttpOnly. Set by the site when you sign in; cleared when you sign out.
- **twa**. Signed admin cookie for people who run the hub. HttpOnly. Same idea as tw, for staff only.
- **tw-age-18**. Records that this browser confirmed eighteen or older on the age gate. Also kept in localStorage on the same browser. Not HttpOnly. Clearing it means the gate asks again.

There is no advertising cookie and no analytics cookie on this site. A longer list of what is stored about play (Discord id, character, chat, launcher logs) is in the sections above.

## Asking about any of this

The Discord, which is linked on every page. For a security problem rather than
a privacy one, see `SECURITY.md` in the repository.
