# How to work on Thornswood

Thornswood is a co-op Skyrim roleplay server. The code for it is in a private GitHub repository. That repository holds the launcher, the website, the Discord bot, and the script the game server runs.

This guide is how you put that code on your computer, change it, check the change, and send it back so it can be merged.

You need Windows 10 or 11, a GitHub account that has been added to the repository, and Discord. The Dev role on Discord is what lets you open the staff pages on the website.

- Repository: https://github.com/EvilPatrick06/Thornswood
- Board (the list of work): https://github.com/users/EvilPatrick06/projects/1
- Public website: https://thornswood.net
- Staff website: https://thornswood.net/hub

The longer rules are two files inside the repository, `CONTRIBUTING.md` and `DEVELOPING.md`. Read them once the code is on your computer.

## What the words mean

**Git** is the program that remembers every change to the code. You run it in PowerShell.

**GitHub** is the website where that history is stored, along with issues and pull requests.

**The GitHub CLI** is a program called `gh`. It does GitHub jobs from PowerShell. The website has buttons for the same jobs.

**A repository** is the project. On GitHub it is one page. On your computer it is one folder.

**A clone** is that folder, downloaded to your computer.

**`main`** is the official branch. Merged work lands here. You do not commit on `main` directly.

**A branch** is your own line of changes, with a name. It starts as a copy of `main` and then holds your edits.

**A commit** is a saved checkpoint on your branch. It includes a sentence about why the change exists.

**A push** uploads your commits to GitHub.

**A pull request** is a GitHub page that shows your branch beside `main`. Merging it copies your work onto `main`.

**An issue** is one piece of work on the board: a bug, a change, or something still to decide.

**The VPS** is the remote computer that runs the live game, the dev game, the website, and the Discord bot. Your PC talks to it with a key.

**SSH** is that connection. A key has two halves. The public half is one line of text you can send to someone. The private half stays on your PC.

**The dev server** is a second copy of the game, used to try changes. The live server is the public one. Restarting the live server, and publishing a release, stay with Patrick.

## Install the programs

PowerShell is already on Windows. Open it from the Start menu.

These are the extra programs:

- **Git** downloads the repository and records commits.
- **GitHub CLI** (`gh`) talks to GitHub from PowerShell.
- **Node** runs the test files, and can run the website on your PC.
- **PowerShell 7** is the version these scripts expect. The icon says PowerShell 7. The older window is called Windows PowerShell.
- **OpenSSH Client** is what connects to the VPS.

Paste this and let each install finish. If Windows asks for an administrator, allow it.

```powershell
winget install --id Git.Git -e --accept-package-agreements --accept-source-agreements
winget install --id GitHub.cli -e --accept-package-agreements --accept-source-agreements
winget install --id OpenJS.NodeJS.LTS -e --accept-package-agreements --accept-source-agreements
winget install --id Microsoft.PowerShell -e --accept-package-agreements --accept-source-agreements
dism /Online /Add-Capability /CapabilityName:OpenSSH.Client~~~~0.0.1.0
```

Close the window. Open **PowerShell 7** from the Start menu. A new window is required because Windows only sees newly installed programs in a window opened afterwards.

```powershell
git --version
gh --version
node --version
ssh -V
```

Each line should print a version. If one says the program is not recognized, you are still in the old window.

## Sign the GitHub CLI into your account

`gh` has to know which GitHub user you are. This opens a browser.

```powershell
gh auth login
```

Choose GitHub.com, then HTTPS, then login with a browser. Approve it in the browser as the GitHub user that has access to the repository.

```powershell
gh auth status
```

That prints your username. It should say the account can see private repositories.

## Download the code

A clone is a full copy of the repository, history included. Put it in a folder of your own. `C:\Dev\Thornswood` is the example below. Any empty folder is fine.

```powershell
New-Item -ItemType Directory -Force -Path C:\Dev | Out-Null
cd C:\Dev
git clone https://github.com/EvilPatrick06/Thornswood.git
cd C:\Dev\Thornswood
git status
```

`git clone` downloads it. `cd` moves into the new folder. `git status` should say you are on branch `main` and that the working tree is clean, which means you have not changed any files yet.

If Git asks you to sign in, use the same GitHub account as `gh auth login`.

From here on, the commands assume your PowerShell is inside `C:\Dev\Thornswood`. If you used another folder, `cd` there first.

## Reach the VPS

The VPS is one Windows machine in a hosting centre. The website, both game servers, and the bot run on it. Scripts in `scripts\vps` connect to it over SSH.

You do not get the server password. Your PC creates a key. You send Patrick the public line. He puts that line on the server. After that, the scripts connect without asking.

```powershell
.\scripts\vps\Setup-SshKey.ps1 -KeyOnly
```

The script prints one line that starts with `ssh-ed25519`. Copy that whole line to Patrick in Discord. Leave the private key file where the script put it, under your user folder in `.ssh`. That file is the secret half.

When he says the key is on the server:

```powershell
.\scripts\vps\Setup-SshKey.ps1 -Test
```

The script reports whether the key works. If it says `Host key verification failed`, tell Patrick. The script is refusing the connection because this PC has not recorded the server's identity yet.

Two commands only read. They do not restart anything.

```powershell
.\scripts\vps\Check-Site.ps1
.\scripts\vps\Get-Logs.ps1
```

`Check-Site.ps1` asks the public website from outside, then asks a few health questions on the server. `Get-Logs.ps1` copies the recent website, bot, game server, and voice logs onto your PC and prints the folder it used. `-Lines 40000` copies a longer tail when the short one is not enough.

These scripts change the live service. Leave them unless Patrick has asked you to run that one:

| Script | What it does |
| --- | --- |
| `Restart-Server.ps1` | Restarts a service on the VPS |
| `Deploy-Server.ps1` | Updates the live game server |
| `Deploy-Gamemode.ps1` | Updates the script the live game server runs |
| `Install-Voice.ps1` | Updates the live voice service |
| `Ship.ps1` with no `-Channel dev` | Publishes a public launcher update |

## Find a piece of work

The board is a GitHub project with three columns.

- **Todo** is work nobody is doing.
- **In Progress** is work someone has taken, including work that is waiting on an answer.
- **Done** is finished.

Open https://github.com/users/EvilPatrick06/projects/1 and click a card. The card is an issue. The issue page has the description, the comments, and a sidebar. When you start the work, set yourself as the assignee in that sidebar, and say the issue number in #staff-general. Skip issues assigned to Djinn. Those are his.

PowerShell, from the repository folder:

```powershell
gh issue list
```

That prints open issues. `123` below stands for the issue number.

```powershell
gh issue view 123
gh issue view 123 --comments
```

The first prints the description. The second adds the comments.

```powershell
gh issue edit 123 --add-assignee "@me"
```

That assigns the issue to the account `gh` is logged in as. `@me` means that account.

To file something new:

```powershell
gh issue create --title "Short title" --body "What is wrong, where you saw it, and what is left."
```

On the website, the same action is the Issues tab, then New issue.

## Do the work on a branch

Each issue gets its own branch. The branch name is your name, a slash, and a few words about the job: `alex/fix-door-list`.

Get the latest `main`, then branch from it:

```powershell
git checkout main
git pull
git checkout -b alex/fix-door-list
```

`git checkout main` switches you onto `main`. `git pull` downloads new commits other people have merged. `git checkout -b` creates your branch and switches onto it. Replace the example name with yours.

Edit the files in this folder with any editor. When you want to see what changed:

```powershell
git status
git diff
```

`git status` lists the files. `git diff` shows the line changes.

Save a checkpoint. `git add` chooses which files go in it. `git commit` writes the checkpoint. The sentence after `-m` is the message other people will read. Say why, in one line.

```powershell
git add path\to\the-file
git commit -m "Fix the door list so a Dev role still gets in."
```

Upload the branch. The first push also tells GitHub to remember it as yours:

```powershell
git push -u origin HEAD
```

`origin` is GitHub. `HEAD` means the branch you are on. This does not change `main`.

If Git refuses the push because `main` moved while you were working, replay your commits on top of the new `main` and push again:

```powershell
git fetch origin
git rebase origin/main
git push
```

If the rebase stops and names a conflict, open the file it mentions, keep the text that should remain, then:

```powershell
git add path\to\the-file
git rebase --continue
```

Do not force the push. A force push rewrites history other people may already have.

## Check it on your computer

`tests\` holds small programs that exercise one area each. Run the one whose name matches what you changed. This example runs the local website test:

```powershell
node tests\test-site-local.js
```

A pass ends with no FAIL lines. A failure prints FAIL and a reason. Fix it on the same branch and run the test again before you open a pull request.

Pages, docs, and launcher help that a person will read:

```powershell
.\scripts\dev\Check-Words.ps1
```

That checks the writing rules in `CONTRIBUTING.md`. It prints the file and the line when something breaks a rule.

## Run the website on your PC

The live site stays on the VPS. You can run a private copy to see a page change.

Copy the `site` folder to somewhere outside the repository, such as `C:\Dev\thornswood-site`. Inside that copy, copy `config.example.json` and name the copy `config.json`. The example file has empty secrets, so this copy will not talk to Discord.

In that copied folder:

```powershell
$env:THORNSWOOD_DOCS_PORT = '3101'
$env:THORNSWOOD_DOCS_LOCAL = '1'
node server.js
```

`THORNSWOOD_DOCS_PORT` is the port number. `THORNSWOOD_DOCS_LOCAL` tells it to listen only on your PC. Open http://127.0.0.1:3101 in a browser. The game will show as down, because the file that says how many people are in the world exists only on the VPS. Ctrl+C in PowerShell stops the site.

Keep the live `config.json` off your PC. It holds the real Discord secrets.

## Open a pull request

Push the branch first. GitHub then shows a yellow bar on the repository page that says Compare and pull request.

The title is what changed. The description is how you tested it. If this finishes an issue, add a line `Closes #123`. GitHub closes that issue when the pull request merges. The pull request should target `main`.

The same step from PowerShell, while you are on your branch:

```powershell
gh pr create --title "Short title" --body @"
What changed.

How you tested it.

Closes #123
"@
```

GitHub starts a check called **Launcher builds**. It compiles the launcher and runs the shared checks. On the pull request page it is under Checks.

```powershell
gh pr checks
```

`pass` means that check succeeded. `pending` means it is still running. Wait and run the command again. A failed check means the branch needs another commit. Push the fix to the same branch. The check runs again by itself.

When Launcher builds is green, say so in #staff-general. Then merge. On the website the button is **Squash and merge**. Squash turns your branch's commits into one commit on `main`.

```powershell
gh pr merge --squash
```

GitHub deletes the branch after a squash merge. Update your PC:

```powershell
git checkout main
git pull
```

Tell Patrick, in #staff-general, what merged and what to try in game. Publishing the dev build uses a signing certificate on his account, so that step is his.

## The staff website

https://thornswood.net/hub is the staff area of the public site. Sign in with Discord. The Dev role is what gets you in. It is separate from the game. Opening the hub does not put you in Skyrim.

| Page | Address | What it is for |
| --- | --- | --- |
| Home | https://thornswood.net/hub | The front of the staff area |
| Gallery | https://thornswood.net/uploads | Pictures waiting for a yes or a no before they go on the public gallery |
| Linked accounts | https://thornswood.net/linked | Notes, bans, and PK flags on a Discord account |
| Sessions | https://thornswood.net/sessions | Who has connected, and when. Admin role |
| Inbox | https://thornswood.net/inbox | Help requests and reports sent from the game. Admin role |

Sessions and Inbox ask for an admin role, which is narrower than Dev. Gallery and Linked accounts accept Dev.

The PowerShell reads that match "is the site up" and "show me the logs" are `Check-Site.ps1` and `Get-Logs.ps1` from the VPS section above.
