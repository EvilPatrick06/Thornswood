# 2554 notices and jobs get a title and a body, and a job a reward

- **Lane:** Claude (agent, slug board-posts)
- **Issue / PR:** #2554, #2565 (NOT MERGED when this note was written, 15 Oct; head 9de372f7). It is built on #2555 (`claude/board-fix`) and has it merged in.
- **Channel:** dev
- **Staff status updates:** #staff-updates (1549254991082946570)
- **Needs first:** **#2555 merged and its dev run (`2516-board-anchors.md`) done.** This runs after it. Then #2565 merged on a green `Launcher builds`. Nothing else: no content plugin, no engine change.

## Run
From the shared clone `C:\Thornswood-Repo` at origin/main with #2565 in it (`git fetch origin; git checkout --detach origin/main`).

**Order matters: voice first.** The page now sends a post of up to about 1,350 characters on one line. The voice service on dev cuts every line at 400 until it has this change, so a post sent before the voice install arrives with its body cut, and the server cannot tell. So:

1. Dev voice (keeps the box's settings, stages, swaps, waits for `/health`; everybody's voice and chat socket drop for a few seconds and reconnect by themselves):

        .\scripts\deploy\Install-Voice.ps1 -Root C:\Thornswood-Voice-Dev -Port 7789 -TaskName 'Thornswood Dev Voice' -NoPause

2. Then the gamemode and a dev Ship (the board page `game/ui/thornswood-board.js` and J's page `game/ui/thornswood-journal.js` ship in the client):

        $notes = @"
        Notices and jobs have a title and a body
        - Make a post, at the bottom of a notice board, asks for a title, what it says, and whether it is a notice or a job.
        - A job now carries a reward. You pay it when you post the job, it is held, and when the job is done you press Pay the reward and it goes to whoever took it.
        - The board lists each post's title, who put it up and when. Read opens it.
        "@
        .\scripts\deploy\Deploy-DevGamemode.ps1 -Note $notes
        .\scripts\release\Ship.ps1 -Channel dev -Notes $notes -NoPause

Live voice gets the same install (`.\scripts\deploy\Install-Voice.ps1 -NoPause`) only on Patrick's word, and it must be done **before** this reaches main, for the same reason.

## Check afterwards
- `curl.exe -s https://thornswood.net/voice-dev/health` answers with a build ending `-roster-once-1-long-command-1`, and the same `chatRange`, `bind` and `most` as before.
- Dev server log after the gamemode deploy: no `command threw` lines naming `post` or `jobDone`.
- In game on dev, at Whiterun's board: Make a post, Job, a title, a few lines of body with a blank line in it, reward 5. The chat says `That cost 35 gold: 30 for the board, and the 5 reward, held until you say the job is done`, and the form closes. The row shows the title and `Job, 5 gold reward, <name>, <time>`. Read shows the body with its line breaks. A second character takes it; the first presses Pay the reward; the second's pack goes up by 5. Put the result on #2554.
- Posts put up on dev before this were one line with no title. They are not converted (Patrick, 15 Oct: no carry-over). They show with an empty title; their poster or a guard of the hold takes them down.

## Risks and how to put it back
- Run out of order (gamemode before voice), a long post arrives cut at 400. Install voice first; if it was missed, take the cut post down and post again.
- `Deploy-DevGamemode.ps1 -PutBack` puts the last gamemode back; `Ship.ps1 -Channel dev` with the previous release puts the pages back; `Install-Voice.ps1 -Root C:\Thornswood-Voice-Dev -Port 7789 -TaskName 'Thornswood Dev Voice' -PutBack -NoPause` puts the old voice files back. The voice change alone is harmless without the rest: it only lets command lines be longer.
- Rewards held for jobs posted under this build stay on the ledger if the gamemode is put back; the old code does not know a job holds gold, so it would not pay them out. In alpha on dev that is acceptable; say so on #2554 if a put back happens.

## Release notes (draft)
Notices and jobs have a title and a body
- Make a post, at the bottom of a notice board, asks for a title, what it says, and whether it is a notice or a job.
- A job now carries a reward. You pay it when you post the job, it is held, and when the job is done you press Pay the reward and it goes to whoever took it.
- The board lists each post's title, who put it up and when. Read opens it.

## News post (draft)
Notice boards got a proper post. Press Make a post at the bottom of any town's board, give it a title and write as much as you need, up to a few paragraphs. Jobs now come with a reward that you put up when you post. It is held safely until you say the job is done, and then it goes to whoever did it. Take your job down before anyone takes it and the reward comes straight back.

## Test task (draft, for closing the issue once the fix is on main)
Test task: Board posts with titles and rewards
Server: Main
1. Go to a town's notice board with at least 40 gold and press E on it.
2. Press Make a post at the bottom. Pick Job, write a title, write two short paragraphs, and set the reward to 5.
3. Press Post it.
4. Ask a friend to press Read on your job and then Take.
5. Press Pay the reward on your job.
What should happen: Posting takes 35 gold from you. The board lists your job by its title with "Job, 5 gold reward", your name and the time. Read shows both paragraphs. When you press Pay the reward, your friend gets 5 gold and the job leaves the board.

## Ran
- Dev release 20261016-010446-dev at 1:04 AM 16 Oct (Claude), from ops-batch at 7a02caa0, after Publish-Server dev (engine 3bdf3d3c, 10:45 PM 15 Oct), dev voice (-long-command-1) and Deploy-DevGamemode -LoadOrder (103 plugins, 10:48 PM). Dev voice and the gamemode ran first, in that order. Left: live voice (`Install-Voice.ps1 -NoPause`) before this reaches main, on Patrick's word.
