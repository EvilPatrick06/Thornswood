# Developer Guide

This is the one guide for working on Thornswood. It covers a first day on Windows, how work moves, how a release goes out, and how a machine is set up to ship one. `CLAUDE.md` adds only what applies to a Claude. The outline has four parts: First day, Jobs, Rules, and The system. Read Quick start before your first change. Use the table when you already know the job and need the section.

- Repository: https://github.com/EvilPatrick06/Thornswood
- Board: https://github.com/users/EvilPatrick06/projects/1
- Site: https://thornswood.net
- Staff pages: https://thornswood.net/hub

## Find a section

| You are here to | Go to |
| --- | --- |
| Install the tools, clone, and open a pull request | [Quick start](#quick-start) |
| Learn Visual Studio Code, PowerShell, Git, and GitHub | [The four tools](#the-four-tools) |
| See which folder a file lives in | [Where the project lives](#where-the-project-lives) |
| Keep two branches on this PC | [Switch between branches on your PC](#switch-between-branches-on-your-pc) |
| Ship, post news, or deploy | [What any developer may do](#what-any-developer-may-do) |
| Follow a dev or main release in full | [How a release goes out](#how-a-release-goes-out) |
| Run the steps after a merge | [After a pull request is merged](#after-a-pull-request-is-merged) |
| Check wording before a page or a note | [Words](#words) |
| Read the branch and merge rules | [How work moves](#how-work-moves) |
| Prepare a PC that can ship | [Setting up a machine](#setting-up-a-machine) |
| Sign builds on a second PC | [Shipping from another machine](#shipping-from-another-machine) |
| See where a secret lives | [Secrets, by name and place, never by value](#secrets-by-name-and-place-never-by-value) |
| See what each part of Thornswood is | [The pieces](#the-pieces) |
| Find another document | [Where things are written down](#where-things-are-written-down) |

**First day**

- [Quick start](#quick-start)
- [Install the tools](#install-the-tools)
- [Install the OpenSSH client](#install-the-openssh-client)
- [Sign the GitHub CLI into your account](#sign-the-github-cli-into-your-account)
- [Clone the repository](#clone-the-repository)
- [The four tools](#the-four-tools)
- [Visual Studio Code](#visual-studio-code)
- [PowerShell](#powershell)
- [Where the project lives](#where-the-project-lives)
- [Git on your PC](#git-on-your-pc)
- [GitHub in the browser](#github-in-the-browser)
- [Reach the VPS](#reach-the-vps)
- [Your first branch](#your-first-branch)
- [Switch between branches on your PC](#switch-between-branches-on-your-pc)
- [Open the pull request from PowerShell](#open-the-pull-request-from-powershell)
- [When the pull request will not open](#when-the-pull-request-will-not-open)
- [Merge your own pull request](#merge-your-own-pull-request)

**Jobs**

- [What any developer may do](#what-any-developer-may-do)
- [How a release goes out](#how-a-release-goes-out)
- [After a pull request is merged](#after-a-pull-request-is-merged)

**Rules**

- [What this is](#what-this-is)
- [Words](#words)
- [Everything we need to do goes on the board](#everything-we-need-to-do-goes-on-the-board)
- [Settled design, not up for a quiet rewrite](#settled-design-not-up-for-a-quiet-rewrite)
- [How work moves](#how-work-moves)
- [How work moves, the long form](#how-work-moves-the-long-form)

**The system**

- [What Thornswood is](#what-thornswood-is)
- [The pieces](#the-pieces)
- [Setting up a machine](#setting-up-a-machine)
- [Shipping from another machine](#shipping-from-another-machine)
- [Secrets, by name and place, never by value](#secrets-by-name-and-place-never-by-value)
- [One Skyrim of its own](#one-skyrim-of-its-own)
- [Where things are written down](#where-things-are-written-down)

## First day

A new Windows PC, through a merged pull request. Follow Quick start in order.

### Quick start

For a new person on Windows, including a first day with Visual Studio Code, PowerShell, Git, and GitHub. Later sections are the full rules. Do these in order:

1. [Install the tools](#install-the-tools)
2. [Install the OpenSSH client](#install-the-openssh-client)
3. [Sign the GitHub CLI into your account](#sign-the-github-cli-into-your-account)
4. [Clone the repository](#clone-the-repository)
5. [The four tools](#the-four-tools), then [Visual Studio Code](#visual-studio-code), [PowerShell](#powershell), [Where the project lives](#where-the-project-lives), [Git on your PC](#git-on-your-pc), and [GitHub in the browser](#github-in-the-browser)
6. [Reach the VPS](#reach-the-vps)
7. [Your first branch](#your-first-branch)
8. [Switch between branches on your PC](#switch-between-branches-on-your-pc)
9. [Open the pull request from PowerShell](#open-the-pull-request-from-powershell)
10. [Merge your own pull request](#merge-your-own-pull-request)

[When the pull request will not open](#when-the-pull-request-will-not-open) is the page for the errors in that sequence.

Use your own GitHub account. Patrick adds that account as a collaborator on the private repository before a clone will work. Say so in Discord and wait for that. Use your own clone. The shared folder `C:\Users\you\Downloads\Thornswood-Repo` on the shipping machine is for the lanes that build from it. Your clone can live at `C:\Dev\Thornswood`, or any empty folder you own.

#### Install the tools

Open PowerShell. Paste this and let each install finish. If Windows asks for an administrator, allow it.

```powershell
winget install --id Git.Git -e --accept-package-agreements --accept-source-agreements
winget install --id GitHub.cli -e --accept-package-agreements --accept-source-agreements
winget install --id OpenJS.NodeJS.LTS -e --accept-package-agreements --accept-source-agreements
winget install --id Microsoft.PowerShell -e --accept-package-agreements --accept-source-agreements
winget install --id Microsoft.VisualStudioCode -e --accept-package-agreements --accept-source-agreements
```

Close that window and open **PowerShell 7** from the Start menu. A new window is required because Windows only sees newly installed programs in a window opened afterwards.

```powershell
git --version
gh --version
node --version
ssh -V
code --version
```

Each line should print a version. `code --version` prints a few lines, and the first is the version. If one says the program is not recognized, you are still in the old window.

#### Install the OpenSSH client

The VPS scripts need `ssh`. If `ssh -V` already printed a version, this step is done.

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
```

When that reports that the class is not registered, run the same install through DISM from an elevated PowerShell:

```powershell
dism /Online /Add-Capability /CapabilityName:OpenSSH.Client~~~~0.0.1.0
```

When DISM still fails, start Windows Update and run the DISM line again:

```powershell
Start-Service wuauserv
dism /Online /Add-Capability /CapabilityName:OpenSSH.Client~~~~0.0.1.0
```

`The operation completed successfully` means the client is installed. Check it:

```powershell
ssh -V
```

#### Sign the GitHub CLI into your account

```powershell
gh auth login
gh auth status
```

Choose GitHub.com, then HTTPS, then login with a browser, as the GitHub user that has access to the repository. `gh auth status` should name your account and say the token can see private repositories.

#### Clone the repository

```powershell
New-Item -ItemType Directory -Force -Path C:\Dev | Out-Null
cd C:\Dev
git clone https://github.com/EvilPatrick06/Thornswood.git
cd C:\Dev\Thornswood
git status
```

`git status` should say you are on `main` and the working tree is clean. If the clone asks for a login and then fails, you are not a collaborator yet. Stop and say so in Discord.

From here on, the commands assume PowerShell is inside your clone. If you used another folder, `cd` there first.

#### The four tools

Visual Studio Code is the window you work in. The folders sit on the left. The file you are reading sits in the middle. A terminal sits along the bottom.

PowerShell is that terminal. You type one line, press Enter, and Windows runs it. The line is a command. The text waiting for the next command is the prompt. It looks like `PS C:\Dev\Thornswood>`. The folder in the prompt is the folder the next command runs in.

Git is the history of this folder on your PC. A commit is one saved step in that history, with a message you write. A branch is a named line of commits. The folder shows one branch at a time.

GitHub is the website copy of that history, at https://github.com/EvilPatrick06/Thornswood. Your PC and GitHub each hold the repository. `main` on GitHub is the shared branch. A push uploads the branch you are on. Your commits join `main` when a pull request is merged. Until that merge, `main` on GitHub is the shared line, and your work is the branch you pushed.

| Word | What it means |
| --- | --- |
| Repository | This project folder plus the history Git keeps for it |
| Clone | The copy of the repository on your PC |
| Commit | One saved step, with a message, on the branch you are on |
| Branch | A named line of commits. The folder shows one at a time |
| `main` | The shared branch. A release is built from it |
| Push | Upload this branch's new commits to GitHub |
| Pull | Download new commits from GitHub onto the branch you are on |
| Pull request | The GitHub page that puts your branch's commits onto `main` when it is merged |
| `origin` | The name Git uses for the GitHub copy |

#### Visual Studio Code

Open the clone:

```powershell
cd C:\Dev\Thornswood
code .
```

`code .` opens the folder you are in. The window title shows Thornswood. If `code` is not recognized, close PowerShell, open PowerShell 7 again, `cd C:\Dev\Thornswood`, and run `code .` again.

The far left is a strip of icons. Hover each one and read the name.

**Explorer** lists the folders and files. Click a triangle to open a folder. Click a file to open it in the middle. A dot on the file's tab means the editor has changes that are still unsaved. `Ctrl+S` saves the file. Git sees the saved file.

The bar just above the editor shows the folders that lead to this file. Click a folder in that bar to open it.

`Ctrl+P` opens a file by name. Type `gamemode.js` and press Enter.

`Ctrl+Shift+F` searches the words inside files. Type a word from the task and press Enter. Click a result to open that line.

**Source Control** lists the same changed files `git status` will list. The message box at the top is the commit message. The rest of this guide does the commit from PowerShell, so the message and the branch stay visible in one place.

The branch name is in the status bar at the bottom left. Click it for a list of branches. The section Switch between branches on your PC is the safe way to change that name.

**Terminal.** Open it from the View menu, Terminal. A new terminal starts in the clone. If the dropdown beside the plus sign says a PowerShell whose version is 5, type `pwsh` and press Enter. Scripts in this repository run in PowerShell 7.

```powershell
$PSVersionTable.PSVersion
```

The major number is 7 or higher when you are in the right one.

#### PowerShell

You are always in one folder. Ask which:

```powershell
Get-Location
```

A clone opened as above prints `C:\Dev\Thornswood`.

List the names in that folder:

```powershell
Get-ChildItem
```

`ls` and `dir` are the same list. `Get-ChildItem scripts` lists what is inside `scripts` and stays where you are.

Move into a folder:

```powershell
Set-Location launcher
Get-Location
```

Move back to the repository folder:

```powershell
Set-Location ..
```

`cd launcher` and `cd ..` are the short forms. The rest of this guide uses `cd`. Press Tab while you type a folder name and PowerShell finishes it.

Run a script from the repository folder. The `.\` means "the file is in this folder":

```powershell
.\scripts\dev\Check-Words.ps1
```

The up arrow brings the previous command back so you can run it again. `Ctrl+C` stops a command that is still running. `Clear-Host` clears the text off the window. Your files stay as they were.

Open a file in Visual Studio Code from the terminal:

```powershell
code .\Developer-Guide.md
code .\game\gamemode.js
```

#### Where the project lives

Stay in `C:\Dev\Thornswood` for these. In Explorer, click the same path. Each big folder has its own `README.md`. Open that file when you go into the folder. The table in The pieces, later in this guide, is the long form of the same map.

| In Explorer | What it is | In PowerShell |
| --- | --- | --- |
| `README.md` | The short map of the repository | `code .\README.md` |
| `Developer-Guide.md` | This guide | `code .\Developer-Guide.md` |
| `launcher\app` | The launcher program, one `.cs` file per piece | `Get-ChildItem launcher\app\*.cs` |
| `launcher\ui.xaml` | The launcher window layout | `code .\launcher\ui.xaml` |
| `game\gamemode.js` | The server rules | `code .\game\gamemode.js` |
| `game\plugins` | Scripts that run in Skyrim | `Get-ChildItem game\plugins` |
| `game\ui` | Overlays in the game | `Get-ChildItem game\ui` |
| `site\data\site` | The public website pages | `Get-ChildItem site\data\site` |
| `site\server.js` | The website program | `code .\site\server.js` |
| `bot` | The Discord bot | `Get-ChildItem bot` |
| `voice` | Proximity voice | `code .\voice\voice-server.js` |
| `scripts\release` | Build and ship | `Get-ChildItem scripts\release` |
| `scripts\deploy` | Put a build on the server | `Get-ChildItem scripts\deploy` |
| `scripts\vps` | The server key and log reads | `Get-ChildItem scripts\vps` |
| `scripts\dev` | Checks you run on your PC | `Get-ChildItem scripts\dev` |
| `tests` | The test files | `Get-ChildItem tests` |
| `docs` | The system notes | `code .\docs\SYSTEM.md` |

`engine` is the SkyMP source. Leave it until a task tells you to build the server. `out` and `local` appear after a build. Git keeps them off GitHub.

Search for a file by name with `Ctrl+P`. From PowerShell, this walks the tree and can take a while:

```powershell
Get-ChildItem -Recurse -Filter gamemode.js
```

Search for a word inside one file:

```powershell
Select-String -Path .\game\gamemode.js -Pattern "door"
```

For the whole repository, `Ctrl+Shift+F` in Visual Studio Code is the search to use.

Do not edit Shell.cs, Checks.cs, Keep.cs, Hold.cs, Updater.cs or Publish-Update.ps1 without a line in #staff-general. Those files sit in `launcher\app` and `scripts\release`.

#### Git on your PC

`git status` is the command to run whenever you are unsure. It names the branch and lists files that differ from the last commit.

```powershell
git status
```

`nothing to commit, working tree clean` means the saved files match the branch. A list of files means those saved edits are in the folder and become part of the branch when you commit them.

See the line changes:

```powershell
git diff
```

See the latest commits on this branch:

```powershell
git log -5 --oneline
```

A commit has two steps. Name the files, then save the step with a message. Save in the editor first (`Ctrl+S`).

```powershell
git add path\to\file
git commit -m "Say what this step does, in one sentence."
```

That commit is on this PC, on the branch in the status bar. `git log -5 --oneline` shows it. GitHub learns it at the push, in Your first branch, below.

List the branches on this PC. The star is the one in the folder:

```powershell
git branch
```

#### GitHub in the browser

Sign in on the GitHub website as the account that was added to the repository. Open https://github.com/EvilPatrick06/Thornswood. The Code tab shows the files on the branch named in the dropdown. After a clone, that dropdown is `main`.

`gh` is the command-line window onto the same site:

```powershell
gh auth status
```

It should print your login. Your first branch, below, is the first push. After that push, refresh the Code tab, open the branch dropdown, and choose your branch. The files there are your branch. The `main` entry in that dropdown is still the shared line, without those commits.

The Pull requests tab lists open pull requests. `gh pr create` adds yours. Merging that page is what writes the commits onto `main`. The sections below are the commands for the push, the pull request, and the merge.

`git pull`, while you are on `main`, downloads commits other people have merged:

```powershell
git switch main
git pull
```

#### Reach the VPS

You do not get the server password. Your PC creates a key. You send the public line. Somebody who already has a key on the server adds yours. After that, the scripts connect without asking.

```powershell
.\scripts\vps\Setup-SshKey.ps1 -KeyOnly
```

The script prints one line that starts with `ssh-ed25519`. Copy that whole line into Discord. Leave the private key file where the script put it, under your user folder in `.ssh`. Send no file whose name ends in a private key, and no line that does not start with `ssh-ed25519`.

On a machine that already has a key, from the repository folder:

```powershell
.\scripts\vps\Add-VpsKey.ps1 -PublicKey 'ssh-ed25519 AAAA... comment'
```

When the key is on the server, on your machine:

```powershell
.\scripts\vps\Setup-SshKey.ps1 -Test
```

A good answer is that the key already works. `Host key verification failed` means this machine has not recorded the server yet. Run the same script without `-Test` only when the first run did not finish. Do not type the server password into a script.

Two reads that do not change the box:

```powershell
.\scripts\vps\Check-Site.ps1
.\scripts\vps\Get-Logs.ps1
```

`Check-Site.ps1` says whether the website answers. `Get-Logs.ps1` copies the tail of the site, bot, game server, and voice logs onto your machine and prints the folder. `-Lines 40000` pulls more.

#### Your first branch

One issue, one branch, one pull request. Start from a fresh `main`.

```powershell
git checkout main
git pull
git checkout -b yourname/short-name
```

`yourname` is your name in lowercase. `short-name` is the job, with hyphens. Example: `alex/fix-door-list`.

```powershell
git status
git diff
git add path\to\file
git commit -m "Fix the door list so a staff role still gets in."
git push -u origin HEAD
```

The first push sets the upstream. It puts this branch on GitHub under the same name. `main` on GitHub stays as it is. Your commits join `main` when the pull request is merged.

Run the test that covers your change before you open the pull request. A node test looks like this:

```powershell
node tests\test-site-local.js
```

Use the file in `tests\` whose name matches the area you touched. A passing run ends without an error. Pages, docs, and launcher help that a person will read:

```powershell
.\scripts\dev\Check-Words.ps1
```

#### Switch between branches on your PC

The folder shows one branch at a time. The files in Visual Studio Code are the branch named in the status bar at the bottom left. Every other local branch stays on this PC with its own commits. Switching replaces the files in the folder with the branch you pick. Switching back brings the first branch's files back.

Open the terminal from the Terminal menu, New Terminal. It starts in your clone. These commands are the same there and in PowerShell.

List the branches on this PC. A star marks the one in the folder:

```powershell
git branch
```

`git branch -vv` also shows the GitHub branch each one tracks, and whether yours is ahead of it or behind it.

Look at uncommitted work before you switch:

```powershell
git status
```

`nothing to commit, working tree clean` means the folder matches this branch. When `git status` lists files, those edits are in the folder and belong to a branch only after you commit them. Commit while the status bar still shows the branch they belong on:

```powershell
git add path\to\file
git commit -m "Save the door list work on this branch."
```

That commit stays on this branch. Then switch:

```powershell
git switch yourname/other-job
```

The folder now matches `yourname/other-job`. Come back the same way:

```powershell
git switch yourname/short-name
```

The door-list commit is in the folder again. `git switch -` returns to the branch you were on before this one.

Save editor tabs before you switch. A save writes the file into whichever branch is current. Commit that save on the branch named in the status bar, and the work stays with that branch.

Start a second job from a current `main`. The first branch keeps the commits you already made:

```powershell
git switch main
git pull
git switch -c yourname/second-job
```

`git switch -c` creates the branch and puts the folder on it. `git branch` lists both. Each commit stays on the branch where you made it.

To set the edits aside and look at another branch:

```powershell
git stash
git switch yourname/other-job
```

The folder is clean and shows the other branch. The stashed edits remain on this PC. Return to the branch you stashed from and put them back in the folder:

```powershell
git switch yourname/short-name
git stash pop
```

`git stash list` shows what is still set aside. Pop on the branch you stashed from, so the edits land on that job.

When the switch stops, those uncommitted edits touch a file that differs on the branch you asked for. You are still on the current branch, and the edits are still in the folder. Commit them, or stash them, then switch.

`git checkout yourname/other-job` moves you the same way `git switch` does. Later sections use `git checkout` for that move.

Push sends the branch you are standing on:

```powershell
git push -u origin HEAD
```

That branch appears on GitHub under its own name. `main` on GitHub does not gain those commits. They join `main` when the pull request is merged. Until then, the site, the dev build, and everyone else's `git pull` of `main` are still the shared line.

In Visual Studio Code, Source Control lists the same files as `git status`. Commit from that panel, or from the terminal, while the status bar shows the right branch. Click the branch name in the status bar to switch. Commit or stash first, so each job's files stay with its branch.

#### Open the pull request from PowerShell

`gh pr create` uses the branch you have checked out. Check that branch out first. A one-line body uses ordinary double quotes. PowerShell treats `@" ` as the start of a here-string, and a here-string needs a line break immediately after `@"`. Characters on that same line raise `No characters are allowed after a here-string header`.

A one-line body:

```powershell
gh pr create --title "Tools to 50" --body "Reduced tools from 100 to 50 on uses"
```

A body of several lines, saved first:

```powershell
$body = @"
What changed.

How you tested it.

Closes #123
"@
gh pr create --title "Short title" --body $body
```

The title says what changed. The body says how you tested it. If the work finishes an issue, put `Closes #123` in the body. The pull request targets `main`.

#### When the pull request will not open

**The push is not a fast-forward.** Your local branch is behind the same branch on GitHub. `gh pr create` tries to push first, and Git refuses to overwrite the remote. Bring the remote commits in, then create the pull request:

```powershell
git pull
gh pr create --title "Tools to 50" --body "Reduced tools from 100 to 50 on uses"
```

If `git pull` says there is no tracking information, name the remote and the branch. This example uses the branch from that session. Use the name `git status` prints for yours.

```powershell
git pull origin 1381-tools-to-50-uses---MP
```

To make later pulls work without the name:

```powershell
git branch --set-upstream-to=origin/1381-tools-to-50-uses---MP 1381-tools-to-50-uses---MP
git pull
```

**You rewrote the branch on purpose** (`git commit --amend` or `git rebase`) and you mean to replace the remote copy of that same branch:

```powershell
git push --force
gh pr create --title "Tools to 50" --body "Reduced tools from 100 to 50 on uses"
```

Force push replaces the remote branch. Use it on your own branch after you rewrote that branch. Main refuses a force push. If `main` moved while you were working, replay your commits on the new main instead:

```powershell
git fetch origin
git rebase origin/main
git push
```

**The pull stopped on a conflict.** Git will not commit while a file is unmerged. Open the file it names, often `game\gamemode.js`. Find the markers `<<<<<<<`, `=======`, and `>>>>>>>`. Keep the code you want and delete the marker lines. Save the file.

```powershell
git add game\gamemode.js
git commit -m "Resolve merge conflict in gamemode.js"
gh pr create --title "Tools to 50" --body "Reduced tools from 100 to 50 on uses"
```

If the stop was a rebase rather than a merge, the last step is `git rebase --continue` after the `git add`.

#### Merge your own pull request

Wait until the check named `Launcher builds` is green on the commit you are merging. It is on the pull request, under Checks. Pending means it is still running. A red check means the branch is not ready. Fix it on the same branch and push again.

```powershell
gh pr checks
```

When `Launcher builds` says pass, and you are confident in the change, merge it yourself. Say what you merged in #staff-general. On the website the button is **Squash and merge**.

```powershell
gh pr merge --squash
git checkout main
git pull
```

GitHub deletes the branch after a squash merge. A green check is required. It does not replace reading your own diff. Merge a pull request you understand. Leave one you do not.

## Jobs

Ship, post the news, deploy, and the steps after a merge.

### What any developer may do

Decided for the whole team: any developer may do every one of these. Confidence in the change, and a green `Launcher builds` check on the exact commit, are the gates for a merge. A release, a deploy, and a news post are the same people. Say what you are about to publish in #staff-general first. Dev and Main each have one shared feed and one shared server, and the last Ship on a channel wins.

The machine that runs `Ship.ps1` still has to sign the build. `records\signing\signing.json` has to be present and enabled, and the launcher tip has to be signed by the certificate the launcher already trusts. `.\scripts\release\Setup-ShipMachine.ps1` is how a machine gets there. Shipping from another machine, below, says which Azure sign-in can sign.

| Job | Command | Where it shows up |
| --- | --- | --- |
| Dev release | `.\scripts\release\Ship.ps1 -Channel dev` plus the note | Dev feed, dev launcher News tab, dev updates channel in Discord |
| Main release | `.\scripts\release\Bump-Version.ps1`, then after that pull request is merged, `.\scripts\release\Ship.ps1` plus the note | Live feed, launcher News tab, the site news page, Discord #news |
| Discord news | Ship posts it. To post the current feed again: `.\scripts\ops\Publish-Discord.ps1` or `.\scripts\ops\Publish-Discord.ps1 -Dev` | #news for main, the dev updates channel for dev |
| Game news | The same note. The launcher News tab reads the feed. The site news page is `.\scripts\ops\Publish-News.ps1`, which a main Ship already runs | Launcher News tab, and https://thornswood.net for main |
| Docs site | `.\scripts\deploy\Deploy-Docs.ps1` for the app. `.\scripts\deploy\Deploy-Docs.ps1 -Site` for the public pages | https://thornswood.net |
| Dev gamemode | `.\scripts\deploy\Deploy-DevGamemode.ps1` | Dev server only |
| Live gamemode | `.\scripts\deploy\Deploy-Gamemode.ps1`, then `.\scripts\deploy\Deploy-Server.ps1` | Live server |

A dev release can run from any branch on any developer's machine. A main release runs from `main` after `git pull`, with a clean tree that matches GitHub. Details, note rules, and the restart warning are in How a release goes out and After a pull request is merged.

`Set-DevNews.ps1 -Check` says whether the dev Discord webhook is set, and which channel it points at. It prints no secret.

```powershell
.\scripts\ops\Set-DevNews.ps1 -Check
.\scripts\ops\Publish-Discord.ps1 -DryRun
.\scripts\ops\Publish-Discord.ps1 -Dev -DryRun
.\scripts\ops\Publish-News.ps1 -OutFile news.json
```

`-DryRun` and `-OutFile` send nothing. A real post remembers what it already announced and refuses to repeat it. `-Force` is how a deleted post is made again.

The note is what people read. The first line is a title of three words or more, from the person's side. Then one line starting with `- ` for each thing they will notice. Ship refuses a title that is shorter, a note with no `- ` line, an issue number, a file name, a setting name, and the word the Words section bans.

```powershell
.\scripts\release\Ship.ps1 -Channel dev "The Downgrade button shows its progress and says why it stopped
- A bar under the Downgrade button shows how far the downgrade has got.
- When the downgrade stops, the line under the button says why and what to do next."
```

Everything still goes to the dev build first, including small changes. A main release is for a security fix, for something that leaves the game untestable, or for work the team has agreed goes live. Any developer who is confident may run that main release, then say so in #staff-general.

### How a release goes out

**Everything goes to the dev build first** (decided 23 Sep).
A main release is for a security fix, for something that leaves the game
untestable, or for work the team has agreed goes live. Any developer who
is confident may run it.

```
.\scripts\release\Ship.ps1 -Channel dev "what changed, in plain words"
```

That is the dev release: version 1.1.36.1, .2, .3, pack ids ending `-dev`, the
dev feed and the dev baseline (`feed-dev` in the VPS store), the dev ports,
and the dev server told. It runs from
any branch on any developer's machine. There is no installer for it, and it
posts to the dev updates channel in Discord and the dev launcher's News tab,
never #news. There is one dev feed and the last dev Ship wins, so say in #staff-general
when you take it. Main and Dev have independent feeds and baselines. A Main
Ship leaves Dev unchanged; advance Dev through its own Ship.

A main release, from your clone, on a machine that can sign:

```
cd C:\Users\<you>\Downloads\Thornswood-Repo
git checkout main
git pull
.\scripts\release\Bump-Version.ps1
```

The version moves first and on its own. `Bump-Version.ps1` changes `Version`
in `launcher\app\Updater.cs` (1.1.35 to 1.1.36), commits that one file, and
prints the rest. main refuses a push from everybody, so it prints the
commands that move that commit onto a branch, `patrick/launcher-1.1.36`,
push it and open the pull request, which is then merged (see How work
moves, the long form). Then, back on main:

```
git checkout main
git pull
.\scripts\release\Ship.ps1 "what changed, in plain words"
```

Ship writes nothing to this repository. It refuses a main release with
anything uncommitted, with a file under `scripts` or another folder a release
is built from that git does not know, with
a `-Version` other than the number already on main, or with main here behind
or ahead of `origin/main`, so what ships is what is on GitHub. It builds the
launcher, checks that the game folder holds the recorded client build
(`Sync-Client.ps1 -Check`) and that the behavior files and bodies in it were
built for this mod list (`scripts\mods\Build-Generated.ps1`, run before a Ship;
see One Skyrim of its own), then runs
`scripts\release\Publish-Update.ps1`, which
scans the game folder for loose files that are not Vortex's, not vanilla, not
runtime and not per machine, diffs them against this channel's baseline
(`published.json`, received from the VPS store at the start), zips the
difference as a pack, sends the pack, the launcher and the client runtime to
the site's `/feed[-dev]/assets/<sha256>` (since #897), rewrites `version.json`
and sends it and then the baseline back to the VPS store (since #907), which
is the moment the site serves the release.

The tip customers get is that `version.json`, and launchers poll the feed url in
it. So two things follow the tip, both run by
`scripts\release\Publish-PostShip.ps1`, which Ship calls for the remirror with
the channel it shipped, and then the release is announced as it always was:

1. **The host feed remirror**, the website lane's script, called as
   `& (Join-Path $Here '..\deploy\Remirror-Site-Feed.ps1') -Dev:$Dev`. It
   checks every asset the channel's feed names is on `https://thornswood.net/feed/`
   (or `/feed-dev/`) and finds `version.json` already there, because the
   publisher sent it. It has `-Check` for a dry run and `-Verify` to rehash
   what is up there, and optional `-FeedDir` and `-AssetDir` that nothing here
   passes: it works this machine's working copy out from the channel itself.
   That is the only feed a launcher polls since #907 (`docs\FEED.md`).
2. **The site news, the #news post and the server's countdown**, unchanged, the
   news main only as it always was. Those tell people to update, which is why
   the feed is mirrored before them.

VirusTotal is no longer part of publish (#802). Code signing covers trust
(#390). `Publish-VirusTotal.ps1` and `Add-VirusTotalComment.ps1` stay as
optional manual tools; `Publish-Installer.ps1` and Ship do not call them.

There is no third step for the launcher. A launcher updates itself from the feed
it polls, so the remirror is how a launcher update reaches anybody, and the
`Install-Launcher.ps1` that Ship runs in the middle of a release refreshes the
install on the shipping machine only (`C:\Thornswood` for main,
`C:\Thornswood-DevBuild` for dev).

The same block runs on a dev Ship, which is where it gets exercised: everything
goes to dev first, so the remirror is run several times a week rather than once
a fortnight. `Publish-PostShip.ps1` finds the remirror by name under `scripts\`
and calls it with the parameters it declares, so that lane does not have to
rename anything to fit, and a hook that is not on the branch yet is a line
saying which file it looked for rather than a failed release.

No switch turns either half off, asked for by the website and launcher lanes so
that every release exercises the block and the dev channel exercises it several
times a week. A `-DryRun` runs none of it, because a dry run publishes nothing to
follow.

Neither of them can fail a release. A script another lane has not landed is a
line naming it. A remirror that exits 1 has refused to publish a feed naming
bytes the site does not hold, which leaves the site one release behind rather
than pointing launchers at a 404, and the website lane asked for that to be a
line as well. So Ship names what did not happen on its last screen, with the
command for each, and still exits 0: a release that is on the feed, in #news and
on the server is out. Both halves ask before they act, so
`Publish-PostShip.ps1` can be run again by hand.

**A hotfix** is the one live release that does not come off main (decided by
Patrick on 24 Sep). A branch named `hotfix/...` starts from the commit the live
release was built from, carries only the fix and its `Bump-Version.ps1`
commit, is pushed, and Ship runs from a checkout of it. Every other check
above still applies, Ship refuses a hotfix branch that is not on GitHub, and
the dev feed is left alone. The fix also goes to main through its own pull
request, or the next main release loses it. Once live, the hotfix's commit
is tagged `live-<version>` and the branch deleted; the next hotfix starts
from that tag (`git checkout -b hotfix/<name> live-1.1.94` today).

Everything else, and which one each change needs, is the list under "After a
pull request is merged" below: `Deploy-Server.ps1` pushes a server
build, `Deploy-Gamemode.ps1` the gamemode (`Deploy-DevGamemode.ps1` for dev), `Deploy-Docs.ps1` the site, `Install-Bot.ps1` the bot,
`Request-Restart.ps1` an announcement. `Rotate-ServerPassword.ps1` changes a
password nothing checks any more; the secrets table below says why. Every
script closes the launcher and Skyrim itself when it needs to.

### After a pull request is merged

Merging on GitHub changes nothing anybody sees. You run the rest from the
repository folder. Any developer may.

1. `git checkout main`, then `git pull`. Ship.ps1 refuses a main release
   that is behind origin, so the pull comes first.
2. Then one command for each part the pull request touched:
   - The launcher (`launcher\app`, `launcher\ui.xaml`, the art and video that
     Build-Launcher.ps1 embeds), the game plugins (`game\plugins`), or
     anything else that goes out in a pack:
     `.\scripts\release\Ship.ps1 -Channel dev "what changed"`. The dev build is where
     it goes first, by the dev-first rule in How work moves. `.\scripts\release\Ship.ps1 "what changed"`
     with no channel is the live one, and that is for a security fix, for
     something that leaves the game untestable, or for work the team has
     agreed goes live. Any developer who is confident may run it.

     The note is the release post: #news, the launcher's News tab and the
     site all show it. Asked for by Patrick on 25 September, after a one-line
     dev note went out as a bare title: "what you gave for the news wasnt
     detailed enough". So a Ship command written for him carries the whole
     note. The first line is a title from the customer's side. Then one line
     starting with `- ` for each thing a person will notice, a plain sentence
     saying what it does for them and how to use it: the key, the button, the
     place. Never one line, and never branch names, pull request numbers or
     entry numbers. The dev post of 24 September 14:36 is the shape to copy.
     Ship refuses notes that break this (see "Every release note has a title
     and details" above), before it builds anything.
   - The gamemode behind that dev release: `.\scripts\deploy\Deploy-DevGamemode.ps1`.
     `Deploy-Gamemode.ps1` then `Deploy-Server.ps1` is the live pair.
   - The site's app or `site\public`: `.\scripts\deploy\Deploy-Docs.ps1`.
     The public pages (`site\data\site\*.md`) need
     `.\scripts\deploy\Deploy-Docs.ps1 -Site`.
   - The bot's code or join card art in `bot`:
     `.\scripts\deploy\Install-Bot.ps1 -CodeOnly`.
   - The bot's avatar (`bot\thornswood-bot-*.png`): no script
     sends it. It is uploaded by hand in the Discord developer portal.
   - `game\gamemode.js`: `.\scripts\deploy\Deploy-Gamemode.ps1`, then
     `.\scripts\deploy\Deploy-Server.ps1`.
   - The voice service (`voice\voice-server.js`, `voice\public`):
     `.\scripts\deploy\Install-Voice.ps1`.
   - Scripts that only change how a release is built (Ship.ps1, Publish-Update.ps1,
     the Deploy scripts): nothing more. The pull is the change. Any developer may run them.
   A pull request that touches several of these gets every one of them, in
   the same sitting, so nothing goes out half done.
3. Everybody else, once it is out, from the main folder: `git checkout main`, then
   `git pull`. If the branch had its own folder, `git worktree remove
   ..\<that folder>`. Then `git branch -D <name>/what-it-is`, after GitHub
   shows the pull request as merged; GitHub squashes the merge, so
   `git branch -d` refuses. A file the branch added that also sits untracked
   in the main folder stops the pull, so delete that copy first.

## Rules

Words, the board, settled design, and how a change moves.

### What this is

Thornswood: a modded co-op Skyrim roleplay server on SkyMP, in alpha and
open by application. This repo is the launcher (launcher\app, C# 5, WPF, built with the
.NET Framework 4 csc), the game plugins (game\plugins, Skyrim Platform
JavaScript), the site (site, node), the Discord bot (bot,
Python) and every script that ships or runs it. Owner: Patrick (EvilPatrick06).

Nothing here assumes you use Claude: this file is the rules for everybody, and a Claude
reads the same file. CLAUDE.md only adds what is about a Claude. A new developer
is added as a collaborator on the repository, and on CODEOWNERS beside the
shared files.

Patrick's Grok Bot lanes (Smeagle, Launcher, Installer, Website, GitHub,
Vortex) also work here, on the shipping machine, under his GitHub account.
Every rule in this file binds them the same as a person. They share notes
through an Obsidian vault at `C:\Thornswood Vault\Thornswood` on that machine
(`wiki/status.md` is what is true now); the vault is for coordinating, and
the board is still the one record of work. They mark what they are on with a
`claimed: <lane>` label and the board card moved to In Progress. Their
branches carry the lane's name (`launcher/`, `website/`, `github/` and so on).
On the shipping machine `C:\Users\you\Downloads\Thornswood-Repo` is shared
by all of them and sits detached at `origin/main`, because lanes build from
it: branch work goes in a worktree beside it, removed with its branch once
the pull request merges.

### Words

The people in the world are customers, clients, people, testers, partners.
Never "player". No em dashes anywhere written for people. Plain, direct
sentences, no filler, no placeholders. Secrets (server passwords, site keys,
Discord tokens, the news webhook, anything out of a config.json or .env on the
VPS) are named by location only; never printed, pasted, committed or logged.

What checks these, since 29 Sep (issue #460). Every pull request's build
(`Launcher builds`, step "Check the writing rules") runs
`scripts\dev\Check-Words.ps1` over every Markdown file outside `lore\` and
`docs\archive\`, the launcher's help and window, the bot's channel posts,
the public pages of the site and the voice service, and the installer's read
me. Each hit names the file, the line and the rule, and turns the build red:

| Rule | What it refuses |
| --- | --- |
| `em-dash` | an em dash, typed or as an HTML entity |
| `banned-word` | the word this section bans, any case; multiplayer and playtest pass |
| `old-owner` | the old owner name |
| `open-alpha` | calling the alpha a playtest that is closed; it is open by application |
| `placeholder` | a marker left for later, in capitals (to do, to be decided, fix me), or filler Latin |
| `names-person` | a person's name in README.md or the six component READMEs (launcher, site, voice, game\plugins, game\ui, installer\setup) |

A line that has to say it anyway (this section naming the word it bans, a
document quoting a note as it went out) goes in
`scripts\dev\Check-Words.allow.txt` with its reason; an allowance that no
longer matches anything is itself a hit. Release notes are not files, so
`scripts\release\Note-Rules.ps1` checks them when Ship or Rollback-Feed runs,
before anything is built. The same build step runs `tests\test-check-words.ps1`
and `tests\test-note-rules.ps1`, which plant a break of every rule and fail
if either check lets one through. Secrets are checked by
`scripts\dev\Check-Secrets.ps1` in the same build.

No machine checks these, so the person writing keeps them: plain, direct
sentences with no filler; the text inside code (the launcher's messages, the
game's chat lines, the bot's replies), because a word check there cannot
tell a message from a name in the code or one of Skyrim's own record names;
and names in the other documents, which record who decided something and
who holds what on purpose.

### Everything we need to do goes on the board

The one record of outstanding work is the Thornswood To Do board:
https://github.com/users/EvilPatrick06/projects/1

Each piece of work is an issue on this repository, and every issue is on the
board. Decided by Patrick on 25 Sep and approved in #staff-general: the list moved there
from a claude.ai page that nobody without Claude could open. The 169 open
entries became issues #368 to #536, each keeping its old number as its Order.
`docs/archive/todo-list-2026-09-25.md` holds every entry as it stood that day,
the finished ones included, so a comment in the code that says "entry 243 on
the To Do List" means entry 243 in that file.

Decided by Patrick on 17 Sep. Anything a session turns up goes on the board
before the session ends. A defect, a decision, a correction to something
already on there, or work started and not finished. Saying it in a chat or a
reply is not recording it: that is gone when the window closes and the next
person has no way to know it was ever found. What prompted this was a Google
Ads tag added to the site whose only trace was a paragraph on a neighbouring
entry, with no step telling anybody to deploy it.

How to use it:

- Order is the do-order. A new issue gets the Order of where it belongs, not
  the end; a number between two others (52.5) is fine.
- Work that fits an existing issue is an edit or a comment on it, not a
  second issue. Write down what was measured and what is left.
- Uncommitted changes sitting in the repo are outstanding work and belong on
  the board too.
- Labels: `wave:` is the stage, `area:` the part of the project, `needs:` who
  or what it waits on, and `anyone can start` marks what needs nobody in
  particular. Assign yourself when you start one.
- A pull request that finishes an issue says `Closes #N`, so merging closes
  it and the board moves it to Done. Say in the pull request, or in #staff-general,
  which issues moved.

### Settled design, not up for a quiet rewrite

- Decided by Patrick and Djinn on 17 Sep, after the three launchers kept
  getting into each other's files: Thornswood runs from its own game folder
  (`Thornswood\Game`), built by the launcher from what Vortex has deployed
  into the Steam copy, the big files as hard links so the collection is not
  stored twice, and copies of everything another launcher rewrites in place
  (settings, scripts, programs, the client folders, the master files and
  whatever else rewrites a copied file in place). Decided by Patrick on
  20 Sep: nothing here supports another server's install any more. The SkyMP
  client runtime is built from the fork and recorded in
  `records\client-build.json`; `Sync-Client.ps1` puts it in the game folder and
  Ship refuses a release whose client is not the recorded build. Nothing is
  taken from the Steam copy's `Data\Platform` or its SkyMP DLLs, because until
  that day another launcher's builds of all of them were what shipped.
  This is what ships now, corrected 18 Sep. The bullet used to say the Steam
  copy shipped until `djinn/own-game-folder` reached main. That branch is on
  main, `C:\Thornswood\Game` is built, and the launcher restarts into it:
  Profile\launcher.log records "runs from the new folder". A session reading
  the old wording would have believed the wrong layout was live, which is the
  one thing this section exists to prevent.
  Decided by Patrick on 24 Sep, for a tester whose Vortex deploys into
  another server's copy of Skyrim (`steamapps\common\Keizaal Online`), in
  his words "detcts and fixes this but doesnt have the servers bleed": when
  Vortex deploys anywhere but the Steam copy, `Thornswood\Game` is the Steam
  copy's game plus exactly the files Vortex's record in that folder lists,
  taken from Vortex's own mods folder, and nothing else of that folder is
  read. Scan names the folder, Fix and Settings point the launcher at it,
  and with no Steam copy on the machine it refuses (OwnGame.DeploysInto,
  Gather, tests\test-vortex-folder.ps1). Djinn to agree it in #staff-general.
  Decided by Patrick on 29 Sep (#1218, #1226): the Steam copy is the
  person's, to play vanilla at any build with their own mods, and Thornswood
  runs entirely from its own folder. With the own folder chosen in the setup
  window, first setup never writes into the Steam copy: the installer's
  payload and everything the launcher writes before the folder exists go to
  `Profile\Payload` (Paths.OwnFirst), and Make takes them in. Not chosen, the
  install uses the Steam copy as it always did, and once the folder is turned
  on and made the next start takes Thornswood's files back out of the Steam
  copy, once (OwnGame.CleanSteamCopy); an existing own folder gets the same
  from its next update. Steam's "Wait until I launch the game" is set only
  until the folder exists (tests\test-own-folder-first.ps1).
  Decided by Patrick on 29 Sep (#1232): `Thornswood\Game` takes only
  Skyrim's own files (from the Steam copy when it is on the pinned build, or
  the Downgrade's download), Vortex's deployed files by Vortex's own record,
  and Thornswood's own files. Skyrim's own is the pinned build's file list,
  `records\skyrim-files.json`, read out of the depot manifests the Downgrade
  uses, never a guess by folder. A mod put into the Steam copy by hand stays
  there, and a folder made before this loses such files at its next refresh,
  logged (OwnGameKinds.cs, tests\test-own-folder-alone.ps1).
  Decided by Patrick on 29 Sep (#1247): the behavior files and the BodySlide
  bodies a release carries are made in Thornswood's own folder, as a step on
  the shipping machine before a Ship (`scripts\mods\Build-Generated.ps1`,
  what it builds in `records\generated.json`), never in the Steam copy. The
  behavior files come from Pandora Behaviour Engine+, which the collection
  carries from revision 2, because Nemesis cannot generate from a command
  line. Ship stops while they are not built for the current mod list
  (tests\test-build-generated.ps1).
- Whichever folder the game runs from, the launcher looks after its own
  files: Keep puts its files back before Play and parks any plugin in
  `Data\Platform\Plugins` that is not ours; Hold keeps its files open read
  only while the game runs; the plugins idle unless the client points at our
  server and a fresh session note is there; Publish-Update packs what belongs
  and nothing else (Ship-Rules.ps1, by what is ours rather than by whose
  anything is). No wrapper scripts around the launcher, nothing moved by hand
  in Data\Platform, nothing touches Vortex's own files.
- The SkyMP client runtime is built from the fork, the `engine\skymp`
  submodule of this repository on `thornswood/engine-changes`, and recorded
  in `records\client-build.json` by `New-ClientBuildRecord.ps1`.
  `Sync-Client.ps1` puts the six recorded files in the game folder and
  refuses any that is not the recorded build; Ship refuses a release whose
  client is not. Every change Patch-Client.ps1 used to make by text is in the
  fork's source, and that script is gone.
  Decided by Patrick and Djinn on 25 Sep, so the second machine has
  everything and GitHub holds it: the fork, its build and the release output
  live in the repository folder, not in `C:\Thornswood-Dev`. The fork is the
  `engine\skymp` submodule, pinned to the commit the build records name; the
  output (packs, launcher, installer, server payload) is `out`, ignored by
  git; anything else that folder held and that never goes to GitHub is
  `local`, ignored too. Scripts ask `scripts\release\Where.ps1` where each of these is
  rather than naming a path. It no longer falls back to `C:\Thornswood-Dev`:
  no machine has that folder any more, and the fallback went on 28 Sep
  (issue #440), along with the forwarding copies in `tools\`. The files a
  machine kept in `tools\` moved on 29 Sep (signing.json to `records\signing`,
  the setup stub to `out`, the rest to `local`) and the folder is gone.
- Launcher code is C# 5 only: no string interpolation, no ?., no nameof,
  no expression bodied members, no out var.
- Every change goes out as one complete release: launcher, game files and
  server together, never a half.

Anything that changes one of these is a few lines in #staff-general first: the
problem, the approach, what it touches. Agreed in #staff-general by
the team before code; nobody settles it alone, and a Claude never does.

### How work moves

The short form of the rules. The same decisions, with the dates they were made, are in [How work moves, the long form](#how-work-moves-the-long-form).

#### Main, hotfixes, and merging

- main is what ships. Any developer may ship main from a machine that can sign, and Ship.ps1 refuses
  a main release that is not on main, is behind or ahead of origin, has
  anything uncommitted, has a file under `scripts` or another folder a release is built from that git does not know, or
  asks for a new number with `-Version`. A main Ship writes nothing to the
  repository: the version moves first through `Bump-Version.ps1` and its own
  pull request, and Ship builds only what is already on GitHub, so every other
  machine can `git pull` exactly what shipped. Corrected 24 Sep: this bullet
  used to say a main Ship committed and pushed the source after the release,
  which stopped being true on 22 Sep (f917dd8).
- The one live release that does not come off main is a hotfix, decided by
  Patrick on 24 Sep for a tester who could not get in while a day of dev work
  sat on main: "the only thing that should be going to main now is the fix
  for him". A branch named `hotfix/...` starts from the commit the live
  release was built from, carries only the fix and its `Bump-Version.ps1`
  commit, is pushed, and Ship runs from a checkout of it; every other gate
  above still applies, and Ship refuses a hotfix branch that is not on
  GitHub. A hotfix leaves the dev feed alone. The fix also goes to main
  through its own pull request, or the next main release loses it. 1.1.93 was
  the first, built from 55ac6ef. Any developer may ship a hotfix when they are confident in the fix and
  Launcher builds is green, the same as any live release. Once it is live, its commit is kept as a tag, `live-<version>`,
  and the branch is deleted, so no hotfix branch sits on GitHub: the next
  hotfix starts with `git checkout -b hotfix/<name> live-<version>` from the
  tag of the release that is live. 1.1.94 is `live-1.1.94` (25 Sep).
- Nobody pushes to main any more, Patrick included. Everything goes through a
  pull request. This replaces the 18 Sep decision that his own work went
  straight to main, which held while `enforce_admins` was off and stopped
  holding the moment it went on.
- What branch protection on main actually enforces, since 25 Sep:
  `enforce_admins` is **off**, there is no required check, required
  approving reviews is **0**, and the code owner review is **off**.
  Patrick, that day: "we don't need the required check/reviewer at all anymore for anyone as long as we give verbal agreement and the VPS check goes through". So the rule is ours, not a setting:
  anybody on the team merges their own pull request once `Launcher builds`
  (the build check, on the VPS) is green and they have said what it is in
  #staff-general. Nobody waits for Patrick. Force pushes are refused.
  Because nothing enforces it, it has to be kept by hand: on 25 Sep 35 pull
  requests were merged with their VPS build red and 18 with no build at all,
  and main went red with them. Wait for `Launcher builds` to say pass before
  merging, every time, including your own and including a Claude's. The last
  GitHub setting, "require branches to be up to date" with no check listed,
  was removed on 27 Sep at Patrick's word ("we use the VPS's build checker"),
  so GitHub requires nothing at all now.
  What changed on 23 Sep, since 22 Sep: the review requirement was one
  approving review, which Patrick could not give himself and had to override
  with `--admin` on every one of his own pull requests, and it is now zero.
  The code owner review on `.github/CODEOWNERS` is off. And `enforce_admins`,
  which had to stay off while `Ship.ps1` pushed its own version commit
  straight to main, went on, because Ship writes nothing to the repository now:
  `Bump-Version.ps1` moves the number first, as an ordinary commit on a
  branch, and Ship reads it.
  Check which it is rather than assuming, because this paragraph was wrong
  for a day before anybody looked:
  `gh api repos/EvilPatrick06/Thornswood/branches/main/protection`
#### Branch names

- Everybody's work goes on a branch named for whoever did it:
  `git checkout -b <name>/what-it-is` (your name, then a slash, and
  claude/ for a Claude's). Small commits, plain messages. Push the branch and
  open a pull request, standing on the branch, not on main:
  `git checkout <name>/what-it-is; git push -u origin <name>/what-it-is; gh pr create --fill`.
  It is merged into main from GitHub, never pushed over main.
  The branches opened before 17 Sep use a `gavin/` prefix; they are Djinn's
  and were left alone rather than renamed under open pull requests.
- One fix per commit, on a branch as much as anywhere: a commit that changes
  eight things cannot be reverted when one of them is wrong.
- `git pull` before starting anything. If a pull conflicts, resolve it on
  your branch (`git fetch`, `git rebase origin/main`), never on main. If a
  push is rejected, pull, do not force.
#### Dev first, notes, and open branches

- Decided by Patrick on 23 Sep: **everything goes to the dev build first.**
  His words: "start puttin these on the dev build and not the main build
  launcher unless it's a security issue or can make the game untestable,
  everything else even small changes go to the dev build launcher for
  pretesting". Size is not a reason to skip it. A main Ship is for a
  security fix or for something that leaves the game untestable, and he
  says which.
- The dev channel (`.\scripts\release\Ship.ps1 -Channel dev "what changed"`) may be
  run from any branch, from any developer's machine, to try work on the dev server.
  Say in #staff-general when you take it, because there is one dev feed and the last
  dev Ship wins. A main Ship leaves the Dev feed and baseline unchanged.
- Every release note has a title and details, dev included. Patrick, 25 Sep,
  after two dev posts went out as "The scroll glows" and "Dev build: ...":
  they must have details and be as good as the ones before them. The notes
  are what people read in the launcher, on the site and in Discord, so write
  them from the side of the person playing: a title that says what changed
  for them, then one "- " line for each thing they will notice, saying what
  it does and what to do if anything. Ship refuses a title under three words
  or notes with no "- " line. Since 27 Sep it also refuses notes that say
  what only we would understand (scripts\release\Note-Rules.ps1): the word
  the Words section bans, an em dash, an issue or pull request number, "PR", a code file or
  a setting name (WEBVIEW2_LIKE_THIS), a name out of the code (PutInServerOrder,
  camelCase), our own words for how we work (demoting, worktree, squash, CI),
  and the same line twice. On 26 and 27 Sep all of those went out to the
  launcher, the site and Discord. And "The load order moved, so start a new
  character" is added by Publish-Update only when the plugins that are on, or
  their order, really changed; it used to follow any byte of plugins.txt and
  told testers to start over three times in two days. The shape:

  ```
  .\scripts\release\Ship.ps1 -Channel dev "The Downgrade button shows its progress and says why it stopped
  - A bar under the Downgrade button shows how far the downgrade has got: each of the three downloads with its size, then the copy into your game.
  - When the downgrade stops for any reason, the line under the button says why and what to do next.
  - If Windows will not open Steam's links, the launcher asks Steam directly, so Steam's console still opens."
  ```
- One fix per pull request. A branch that changes eight things is eight
  reviews nobody has time for; split it.
- No stray branches and no stray pull requests. Decided by Patrick on
  25 Sep, after a count found 70 branches on GitHub, two of them holding
  work that had never been merged and was nearly deleted with the rest:
  "we need to make sure in the docs that we don't leave a bunch of stray
  branches and PRs and fix+merge them everytime or delete if old".
  - A branch is deleted once its pull request is merged. GitHub does that
    by itself (the repository setting "Automatically delete head branches", on since 25 Sep);
    delete it by hand if it was not.
  - Work goes into a pull request the day it is done, never left on a
    pushed branch without one. That is how the two above were lost track of.
  - At the start of a session, and before anything is shipped, look at what
    is open: `gh pr list --state open` and `git ls-remote --heads origin`.
    Everything there other than main, the current `hotfix/` branch and work
    somebody is doing today gets one of two things: fixed and merged, or,
    when it is old or no longer wanted, its pull request closed with a line
    saying why and its branch deleted. Somebody else's branch is theirs to
    decide on: ask them, and put it on the board if they cannot be asked.
    Check whether its work is already in main before deleting it; a
    squashed merge leaves the branch looking unmerged to git.
#### Signing, the build check, and the six shared files

- Code signing is on since 27 Sep (issue #390, closed): the launcher and the
  setup program are signed through Azure Artifact Signing
  (`records\signing\README.md`). `ExpectedSigner` in `launcher\app\Updater.cs`
  is set, so every launcher from dev 1.1.101.17 on refuses an update that is
  not signed by that certificate. **Only a machine that signs may Ship, dev
  included.** `Ship.ps1` and `Publish-Installer.ps1` refuse (non-zero exit) when
  `records\signing\signing.json` is missing or disabled, or when the launcher / Setup tip
  is not Authenticode Valid under `ExpectedSigner`. Local `Build-Launcher` /
  `Package -NoPublish` may still print "not signing" and leave an unsigned
  intermediate; that soft skip must not reach the site or the feed. The live main launcher,
  1.1.101, predates signing; the next main Ship is the first signed one.
- Every pull request gets the build check (.github/workflows/build.yml, about
  two minutes: the secret scan, every script and file parses, the writing
  rules and the two harnesses that prove the writing checks (see Words), the ownership page (`tests\test-ownership.js`, added by issue #752),
  seven more harnesses that are just as quick (the script index, the script
  paths, the architecture page and three launcher harnesses, issue #875, and
  the new-box runbook read against its scripts, issue #454),
  the launcher window, the count of
  silent catches in the launcher, and the launcher compiles with the .NET
  Framework csc). Red means the branch would stop Ship at the build step;
  fix that, and merge once it is green, you are confident in the change, and you have said so in
  #staff-general. Run the test harnesses your change touches yourself. All
  ~410 of them (tests/, bot, and voice), and a look for stray pull requests
  and branches run every night on the VPS (.github/workflows/nightly.yml,
  03:00 Mountain); a failure there opens an issue on the board, "Nightly
  checks failed", and whoever broke it fixes it next. It runs on the VPS, on a runner
  `.\scripts\deploy\Install-Runner.ps1` puts there (issue #437), because
  GitHub's own runners were blocked on billing from 25 Sep.
  `.\scripts\deploy\Install-Runner.ps1 -Status` says whether GitHub sees it.
- Do not edit Shell.cs, Checks.cs, Keep.cs, Hold.cs, Updater.cs or
  Publish-Update.ps1 without a line in #staff-general first; every machine touches those.

### How work moves, the long form

Several people, several machines, one repo. The short rules are above;
this is the long form.

- **main is what ships.** Any developer may ship main from a machine that can sign. `Ship.ps1`
  refuses a main release that is not on the `main` branch, is behind or
  ahead of `origin/main`, has anything uncommitted, or has a file under
  `scripts` or another folder a release is built from that git does not know. It commits and pushes nothing, so what
  shipped is already on GitHub and every other machine can `git pull` exactly
  that.
- **Every change goes through a pull request, Patrick's included.** Nobody
  pushes to main from any machine; GitHub refuses it. `git checkout -b
  <name>/what-it-is` (your name, then a slash; a Claude uses `claude/`; older
  branches use `gavin/`), small
  commits with plain messages, `git push -u origin <branch>`, then
  `gh pr create --fill` standing on the branch. Nothing is force pushed.
- **What GitHub enforces on main, and what it does not.** Since 25 Sep:
  `enforce_admins` is off; there is no required check; required approving
  reviews is 0; the code owner review is off. The build check,
  `Launcher builds` in `.github/workflows/build.yml`, runs on every pull
  request on the VPS runner, and the rule is ours rather than a setting:
  merge your own pull request once it is green, you are confident in the change, and you have said so in
  #staff-general. Nothing merges by itself: auto-merge is off on the repository, so
  somebody presses merge or runs `gh pr merge --squash`. Each of us merges
  our own. Somebody else on the team reading a pull request first is a habit,
  not a setting. `.github/CODEOWNERS` asks the rest of the team for a review when
  a pull request touches one of the shared files, and blocks nothing while
  the code owner review is off. The settings change without a commit, so
  read them rather than this paragraph:
  `gh api repos/EvilPatrick06/Thornswood/branches/main/protection`
- **One fix per pull request.** A branch that changes eight things is eight
  reviews at once; split it.
- **`git pull` before anything.** A conflicting pull is resolved on your
  branch (`git fetch`, `git rebase origin/main`), never on main. A rejected
  push means pull first; never `--force`.
- **The dev channel is for trying.** `.\scripts\release\Ship.ps1 -Channel dev "..."`
  runs from any branch on any machine and puts that build on the dev
  server. There is one dev feed and the last dev Ship wins, so say in #staff-general
  when you take it. A main Ship preserves the Dev feed and baseline.
- **Settled design is a proposal first.** Where the game runs from (its own
  folder, see One Skyrim of its own), Keep and Hold for Data\Platform, the
  client built from the fork and recorded, C# 5 only, one complete release at
  a time: changing any of these starts as a few lines in #staff-general, agreed by the
  team before code. Editing `Shell.cs`, `Checks.cs`, `Keep.cs`, `Hold.cs`,
  `Updater.cs` or `Publish-Update.ps1` gets a line in #staff-general too; every
  machine touches them.
- **The publisher receives the feed and the baseline from the VPS** at the
  start and asks again before `version.json` is edited: a feed somebody changed
  meanwhile is received again and the release goes on top of it, and a
  baseline another Ship moved stops the release with nothing written. Each send
  replaces the file on the VPS only if it is still the one received
  (`scripts\release\Feed-Store.ps1`), so a refused send means NOT SHIPPED; run
  Ship again.
- **The baseline is per channel on the VPS store.** Every shipping machine
  receives the same published.json, so a Dev Ship from a second machine packs
  the same difference. Pending unfinished-send notes stay per machine under
  LOCALAPPDATA.
- **Keep puts its kept copies back at every Play**, on every machine. Go.ps1,
  which Ship runs to put the plugins and overlays in, makes what it installs
  the kept copy, the way a pack does, so a Ship is never undone by the next
  Play. An edit copied into the game folder by hand is. Since 25 September
  nothing writes `Profile\developer.flag`, which used to let the machine that
  ships keep newer game files instead.
- **What never leaves a machine** in a pack or an installer is one list,
  `scripts\release\Ship-Rules.ps1`, read by `Publish-Update.ps1` and
  `Package-Thornswood.ps1` both: runtime folders, one machine's own files,
  other servers' files, and the SkyMP client's saved sign in
  (`Data\Platform\PluginsNoLoad`). The installer of 16 Sep carried that
  sign in file before the list was shared; the launcher removes that exact
  copy from every install (Leaks.cs), matched by content so nobody's own
  sign in is touched.

## The system

What the pieces are, how a machine is set up to ship, where a secret lives, and which other document to open.

### What Thornswood is

Thornswood is a modded co-op Skyrim roleplay server on SkyMP, the server
authoritative multiplayer for Skyrim Special Edition. It is Patrick's, in an
alpha that is open by application, becoming an RP server of its own,
less strict than the big ones, with working NPCs, its own launcher, its own
website and Discord, and a lore of its own (fifty years after the civil war,
the Stormcloaks won, a High King over the Jarls, the Thalmor expelled, the
Empire back under a trade treaty with one embassy). Characters live on the
server, not in save files. During the playtest they are throwaway.

The words we use, and the rule that every change ships as one complete
release, launcher, game files and server together, are in How work moves.

### The pieces

| Piece | Where | What it is |
| --- | --- | --- |
| Source repo | github.com/EvilPatrick06/Thornswood (private), clone at `C:\Users\<you>\Downloads\Thornswood-Repo` | Launcher source, plugins, site, bot, every script |
| Feed store | On the VPS beside the feed the site serves: `C:\Thornswood-Docs\feed\{version.json, published.json, launchers.txt, history\}` and the same under `feed-dev`. Each machine's working copy is `%LOCALAPPDATA%\Thornswood\feed\main` and `\dev` | `version.json` (the feed, served at `/feed[-dev]/version.json`), `published.json` (the pack baseline), every launcher version the channel published, and each replaced file, none of those three served. Ship receives and sends them through `scripts\release\Feed-Store.ps1` (#907). Until then they were the `Thornswood-Releases` GitHub repository and its two clones |
| Downloads | On the VPS, `C:\Thornswood-Docs\feed\assets` and `feed-dev\assets`, served at `https://thornswood.net/feed[-dev]/assets/<sha256>` | Every pack, launcher exe and client runtime a feed names, one file per sha256, one folder per channel (`docs\FEED.md` "Downloads come from the site") |
| Launcher | `launcher\app\*.cs` + `launcher\ui.xaml`, built by `scripts\release\Build-Launcher.ps1` with the .NET Framework 4 csc, C# 5 only | WPF app at `<drive>:\Thornswood\Launcher\Thornswood.exe` (C: on most machines); profile, config and packs under that folder. The scripts find the install on whichever fixed drive holds it; `-Root` overrides |
| Dev build | `<drive>:\Thornswood-DevBuild`, beside the main install, put there by the main launcher's Play page Server dropdown | Same exe, `config.json` says `Channel: dev`, `UpdateBranch: dev`, port 7787, voice 7789. Staff roles only (Owner, Dev, Gamemaster, Moderator, Loremaster) |
| Game | `<Root>\Game`, Thornswood's own folder, which the launcher builds from the Steam copy of Skyrim Special Edition and what Vortex deployed from the Nexus collection (see One Skyrim of its own) | The launcher will not Play from the Steam copy itself. Thornswood's own loose files live in `Data\Platform` (plugins in `Plugins\thornswood-*.js`, page in `UI\`) and `Data\SKSE\Plugins\Thornswood.ini` |
| Plugins | `game\plugins\thornswood-{front,emotes,mark,voice}.js`, UI in `game\ui` | Skyrim Platform JavaScript. Idle unless the client points at our server and the launcher left a fresh session note |
| Game server | VPS 192.135.112.23, `C:\Thornswood-Server`, UDP/TCP 7777, resources 3000, task `Thornswood Server` | skymp5-server with `gamemode.js`; the door reads its allowed list from the site |
| Dev game server | `C:\Thornswood-Server-Dev`, 7787, resources 7788, task `Thornswood Dev Server` | Same binaries, fresh world, door list is the staff roles only (`https://thornswood.net/dev`) |
| Voice | `C:\Thornswood-Voice` 7778 and `C:\Thornswood-Voice-Dev` 7789 | node, `voice\voice-server.js`; the launcher holds the microphone, the game plugin relays state through files in `Data\Platform` |
| Site | `site`, on the VPS at `C:\Thornswood-Docs`, node on 127.0.0.1:3001 behind Caddy, https://thornswood.net | Public pages from `data\site\*.md`, admin hub, Discord login, the door API, uploads, news |
| Bot | `bot`, on the VPS at `C:\Thornswood-Bot`, the Windows service `ThornswoodBot` under its own account, `NT SERVICE\ThornswoodBot` | discord.py: tickets, join cards, staff tools |
| Watchdog | `C:\Thornswood-Watch\watch.ps1`, every five minutes | Restarts any service that stops answering, three tries an hour, and tells the staff channel once when anything dies and once when it is back: the servers, voice, the site, the bot, the nightly backup, the build runner and the disk. Through the bot, or its own webhook when the bot is down |

The server's SkyMP fork is on GitHub (github.com/EvilPatrick06/skymp, branch
`thornswood/engine-changes`), so its source survives any one machine, and since
25 September it is the `engine\skymp` submodule of this repository, pinned to
the commit the build records name: `git submodule update --init engine/skymp`
fetches it into the repository folder. It is large and needs Visual Studio to
build, so a machine that only copies server binaries can leave it unfetched.
Its configured build tree and toolchain (`engine\skymp\build`) are on
Patrick's machine alone for now. The release output is `out` in the repository
folder, ignored by git. `scripts\release\Where.ps1` says where each of these is on the
machine it runs on.

What one machine keeps and git never sees has a home of its own since
29 September (issue #440, phase 10), when the last of it left `tools\` and that
folder went:

| File | Where | What it is | Read by |
| --- | --- | --- | --- |
| `signing.json` | `records\signing` | Whether this machine signs, and with what. No key in it | Sign-Artifact, Ship, Publish-Installer, Setup-ShipMachine |
| `setup-stub.exe`, `setup-stub.pdb` | `out` | The setup program, compiled by Build-Launcher | Package-Thornswood, Ship |
| `thornswood-front.zip` | `local` | The front build, made outside the repository | Go |
| `mod-audit.json` | `local` | What Audit-Mods found last time | Audit-Mods |
| `backup-key.txt` | `local` | A copy of the backup passphrase, a secret. Documents is where it really lives | Restore-Backup | Who holds each thing Thornswood cannot run without, and who the
second holder is, is `docs\OWNERSHIP.md`.

### Setting up a machine

Needs: Windows 10 or 11, Skyrim Special Edition on Steam (any Steam library,
any drive; the scripts find it through Steam) with the Thornswood collection
deployed through Vortex, the Thornswood launcher installed on any drive and
signed in, git, the GitHub CLI (`gh`) signed in to an account that is a
collaborator on the source repo, PowerShell 7, node, Python 3 with `discord.py`
and `Pillow` for the bot scripts, and an SSH key the VPS knows. There is no
releases clone any more: the feed and its baseline are on the VPS (#907).

```
cd C:\Users\<you>\Downloads
git clone https://github.com/EvilPatrick06/Thornswood.git Thornswood-Repo
gh auth login
gh auth status
```

Every change goes to the dev channel first, and the dev channel needs the dev
build on this machine too: in the main launcher, on the Play page, the Server
dropdown, Dev. It checks your Discord roles first, then puts it
at `<drive>:\Thornswood-DevBuild`, beside the main install. Then open it once and let it make its own game folder,
`<Root>-DevBuild\Game`: it offers at startup, and its own Settings, Maintenance
has "Make it". Ship refuses `-Channel dev` without the dev build, and with the
dev build but without that folder it builds the dev release out of the Steam
copy instead. `.\scripts\release\Check-ShipReady.ps1 -Channel dev` says whether both are
in place, without shipping anything.

Then in `Thornswood-Repo`:

```
.\scripts\vps\Setup-SshKey.ps1 -KeyOnly
```

which makes a key for the VPS, points ssh at it, and prints the public line.
Send that line to Patrick; he runs `.\scripts\vps\Add-VpsKey.ps1 -PublicKey '<the line>'`
from his machine and the VPS knows you. `.\scripts\vps\Setup-SshKey.ps1 -Test`
proves it. Until then the scripts that talk to the VPS (`Ship`, `Deploy-*`,
`Request-Restart`, `Install-Bot`, `Publish-Installer`, `Publish-News`) cannot
reach it, and Ship stops before it builds anything: the feed and its baseline
are received from the VPS (#907).

Every Ship, dev included, checks the SkyMP client against the record, so
this machine builds the engine once (Visual Studio 2022 Build Tools with
"Desktop development with C++", node and yarn; the script says what is
missing):

```
.\scripts\release\Build-Engine.ps1
```

`engine\README.md` has the rest. A machine that only Ships does not need
to build it: `.\scripts\release\Setup-ShipMachine.ps1` fetches the recorded
client from the site instead (Shipping from another machine, below). The
release webhooks are on the VPS (`scripts\ops\Discord-Hook.ps1`) and every
Ship reads them from there, so there is nothing to hand over.

The pack baseline lives on the VPS beside the feed, and every Ship receives it
first, so there is nothing to pull. If the VPS has none for a channel, Ship
stops with "No baseline yet". To rebuild a baseline by hand:

```
.\scripts\release\Publish-Update.ps1 -Baseline
```

which records what the game folder holds right now without shipping anything. Do it
straight after the launcher has brought the game up to date, so the baseline is the
current release and the first real Ship carries only what you changed.

`Publish-Discord.ps1` reads the #news webhook and the dev updates one from
the VPS through `Discord-Hook.ps1`, and a copy in `bot\news-webhook.txt` or
`bot\dev-webhook.txt` only when the VPS cannot be asked; without either, Ship
says so and carries on.

### Shipping from another machine

Issue #458: if One (Patrick's machine) dies, the release process has to
survive it. Measured on One on 29 September, this is everything a dev Ship
reads that is not in a fresh clone, where it is on One, and where a second
machine gets it or how it is rebuilt. Nothing in this list is copied from One
by hand, and no secret is written into the repository.

| What a Ship needs | On One | A second machine |
| --- | --- | --- |
| The source | the shared clone | `git clone https://github.com/EvilPatrick06/Thornswood.git` and `gh auth login` as a collaborator |
| The feed, its baseline, the launcher list and history | the VPS store, with a working copy in `%LOCALAPPDATA%\Thornswood\feed\<channel>` | Nothing to copy: every Ship receives them from the VPS first (`scripts\release\Feed-Store.ps1`, #907). The working copy is made on the first Ship |
| The release webhooks, dev and #news | the VPS, `C:\Thornswood-Bot\webhooks`; One has no local copy | Nothing to copy: Ship reads them over ssh (`scripts\ops\Discord-Hook.ps1`) |
| VPS access | One's own key, `.ssh\thornswood_ed25519` | Its own key: `.\scripts\vps\Setup-SshKey.ps1 -KeyOnly`, and somebody the VPS already knows runs `.\scripts\vps\Add-VpsKey.ps1 -PublicKey '<the line>'`. With no such machine left, the BisectHosting panel is the way in (`docs\IT-IS-DOWN.md`) |
| Signing: `records\signing\signing.json` | enabled, naming `C:\tools\metadata.json` and the client under `records\signing\client\client`, paths only One has. Never copy it | `.\scripts\release\Setup-ShipMachine.ps1` writes one from `records\signing\signing.template.json` (paths and "enabled": true, no key or password) |
| Signing: Microsoft's signing client | `records\signing\client`, ignored by git | The same script fetches `Microsoft.ArtifactSigning.Client` 1.0.128 from nuget.org and refuses it unless its sha256 is the pinned one, which is the package One has |
| Signing: the Azure sign in | `az login` on One, as Patrick | `az login` on the new machine, as Patrick. Only Patrick's Azure account has signing access (the Certificate Profile Signer role on the ThornswoodSigning account, profile ThornswoodRelease), so a second machine signs only while it is signed in as him (Patrick, 29 Sep). The script asks the signing service with that sign in and checks the profile answers with the identity the launcher pins. Signing in is the one step only Patrick can do |
| The client runtime `records\client-build.json` names | only in the dev game folder, `C:\Thornswood-DevBuild\Game`. The build copies in `Downloads\Thornswood-ClientBuild-<commit>` are older builds, and the shared clone's `engine\skymp\build` does not match the record | The script fetches the zip of the recorded commit from the site's feed (`clientRuntime` in `/feed-dev/version.json` or `/feed/version.json`), checks it against the feed's sha256 and every file against the record, and puts the six files in the build folder. A commit on neither feed is built: `.\scripts\release\Setup-ShipMachine.ps1 -Rebuild`, or `.\scripts\release\Build-Engine.ps1` |
| The game folder the Ship packs, `<root>-DevBuild\Game` | built by the dev launcher from what Vortex deployed | Skyrim Special Edition on Steam, Vortex with a profile named Thornswood and the Thornswood collection installed and deployed, the launcher from thornswood.net, then the dev build and its own game folder (Setting up a machine, above). A person does this; it needs a Nexus account, not Patrick's |
| The collection itself | Nexus collection `7essxf`, curated from Patrick's Nexus account in his Vortex | Any machine installs it. Only publishing a new revision needs his account (`docs\OWNERSHIP.md`) |
| Backups | the originals on the VPS, `C:\Thornswood-Backup`, and copies fetched to One's `Downloads\Thornswood-Backups`; the passphrase on the VPS and in One's Documents | Not needed to Ship. `.\scripts\vps\Fetch-Backups.ps1` brings them down to any machine the VPS knows |

The whole of it, on the second machine, from the repository folder:

```
.\scripts\release\Setup-ShipMachine.ps1 -Check
```

says what the machine has and what it would fetch or write, and changes
nothing.

```
.\scripts\release\Setup-ShipMachine.ps1
```

checks the tools a Ship calls (git, gh, PowerShell 7, node, ssh, the .NET
Framework compiler, signtool, az, the .NET 8 runtime), fetches the signing
client, writes `records\signing\signing.json`, checks the Azure sign in, fetches the
recorded client, and then runs `.\scripts\release\Check-ShipReady.ps1 -Channel dev`
for everything else Ship asks: the dev build, its game folder, the Vortex
profile, the VPS and the feed store. Each gap prints the command that closes
it and says when it is Patrick's. It never turns signing off, never edits a
`records\signing\signing.json` that is there, and never ships. Signing needs Patrick in
person: only his Azure account has signing access, so the `az login` on the
second machine is his, and that machine signs only while it is signed in as
him. When both say READY:

```
.\scripts\release\Ship.ps1 -Channel dev "what changed, in plain words
- one line for each thing a person will notice"
```

Any developer may run a main Ship from a machine that can sign (How work moves). The same script with
`-Channel main` checks a machine for it.

`tests\test-ship-machine.ps1` walks this section: every script it names is
in the repository with the parameters it is given, the template holds paths
only, and the fetch refuses a signing client or a client runtime that is not
the pinned or recorded bytes.

### Secrets, by name and place, never by value

None of these is tracked by git. Four of them sit inside the repo folder on
the machine that holds them and are kept out by `.gitignore`: the two webhooks,
`records\signing\signing.json` and the retired `server-secret.txt`. The rest are on the VPS or in
your own profile. Each row says what the thing actually protects today, and
says **not enforced** where nothing checks it.

| Secret | Where it lives | What it actually protects | Who reissues it |
| --- | --- | --- | --- |
| Server password, for joining the game server | Nowhere the game server looks. `serverPassword` in the site's `C:\Thornswood-Docs\config.json` on the VPS, where `Rotate-ServerPassword.ps1` writes it | **Not enforced.** Nothing reads it. SkyMP has no join password and the site's join reply stopped carrying one. The old four digit value was in the public `version.json` before 1.0.197, so treat it as known. | Nobody needs to. `Rotate-ServerPassword.ps1` still runs and changes a value nothing reads. |
| Character register secret, retired | `server-secret.txt` at the repo root on Patrick's machine, and `C:\Thornswood-Voice\secret.txt` on the VPS if it is still there. Nothing removed that one when the register went, and `C:\Thornswood-Voice-Dev` may hold a copy, because `vps-dev-instance.ps1` copied the live voice folder whole until #1083; it copies only the program, its page and the log roller now | **Not enforced.** Nothing has read it since 23 September, when the voice service's character register (`/whoami`, `/claim`, `/owners`) was taken out and `Install-Voice.ps1` stopped sending it. It is not the join password: since 18 September it has been 32 random bytes. | Nobody. With no reader there is nothing to reissue. It is listed so nobody takes it for a live secret, or for the join password. |
| Site member password | `password` in `C:\Thornswood-Docs\config.json`. When that is missing the site makes a random one, writes it, and prints it once. It does not print it on a later start | **Not enforced** while Discord sign in is set up: `/api/login` refuses it and the member cookie is ignored. It is a way in only to a site with no Discord client id and secret. | Nobody needs to while Discord is set up. Otherwise anyone with VPS access edits that line and restarts the site. |
| Site `botKey`, which is also the door key | `botKey` in `C:\Thornswood-Docs\config.json`. The same value is `THORNSWOOD_KEY` in `C:\Thornswood-Bot\bot.env.json`, and `key` in `C:\Thornswood-Server\private\door.json` and `C:\Thornswood-Server-Dev\private\door.json` | The site's `/api/ticket` (the bot filing tickets), `/api/roster` (the game server sending its character book) and `/api/allowed` and `/dev/api/allowed` (the door's list). Each answers 401 without it. Whoever holds it can read every allowed person's name and profile ids, the admins' included. | Anyone with VPS access: `Install-Bot.ps1 -RotateKey`, then `Deploy-Docs.ps1` so the site loads it, then `Set-Door.ps1 -Connect` and `Set-Door.ps1 -Connect -Root C:\Thornswood-Server-Dev -Site https://thornswood.net/dev`. Skip the last two and both doors are refused on their next fetch. |
| Site `secret` | `secret` in `C:\Thornswood-Docs\config.json`. The site makes it on its first start. | Signs the site's Discord sign in cookie and the ticket every launcher keeps in `Profile\discord.txt`. Whoever holds it can pass as any Discord account, to the site and to the launcher's check in. | Anyone with VPS access, and there is no script: delete that line and restart the site with `Deploy-Docs.ps1`, which makes a new one. Everybody is signed out of the site and every launcher has to link Discord again. |
| Discord client secret | `discord.clientSecret` in `C:\Thornswood-Docs\config.json` | Discord sign in on the site: with the client id it turns a sign in into who somebody is. | The Discord application's owner resets it in the developer portal (OAuth2). Then `Set-DiscordLogin.ps1` takes it at a prompt and restarts the site. |
| Discord bot token | `discord.botToken` in `C:\Thornswood-Docs\config.json` and `DISCORD_TOKEN` in `C:\Thornswood-Bot\bot.env.json`, the same token in both | Everything the bot may do in the Discord, and the site's reading of who holds which role, which is what decides who may play. | The application's owner resets it in the developer portal (Bot, Reset Token). Then `.\scripts\deploy\Rotate-BotToken.ps1`, one command: it asks at a prompt, writes both files or neither, restarts the bot and the site, and `-Check` afterwards says whether each file holds a token without showing it. `Install-Bot.ps1` and `Set-DiscordLogin.ps1` write it through the same writer, `scripts\vps\Write-BotToken.ps1`, so either one also updates both. Every backup made before the reset still holds the old token: the nightly ones in `C:\Thornswood-Backup` on the VPS and anything brought down to `Downloads\Thornswood-Backups`. |
| #news webhook | `C:\Thornswood-Bot\webhooks\news.txt` on the VPS, read over ssh by every machine that ships (`Discord-Hook.ps1`); `bot\news-webhook.txt` on a machine only as the fallback when the VPS cannot be asked | Posting in #news as the bot, for anybody holding the URL. | Delete the webhook called Thornswood in #news (Edit Channel, Integrations, Webhooks), make a new one, and put its URL in that file. |
| Dev updates webhook | `C:\Thornswood-Bot\webhooks\dev.txt` on the VPS, read the same way; `bot\dev-webhook.txt` only as the fallback | Posting in the dev updates channel as the bot, for anybody holding the URL. | Delete it in that channel's Integrations, Webhooks, make a new one, and give its URL to `Set-DevNews.ps1`, which checks it points at the dev channel before it saves anything. |
| Watchdog alerts webhook | `C:\Thornswood-Watch\alerts-webhook.txt` on the VPS, readable by SYSTEM and Administrators only, and `%LOCALAPPDATA%\Thornswood\Watch-Outside\alerts-webhook.txt` on One | Posting in the staff channel, for anybody holding the URL. The watchdog uses it only when the bot is down or silent. | Delete it in the staff channel's Integrations, Webhooks, make a new one, and give its URL to `.\scripts\vps\Watch-Services.ps1 -SetWebhook`, which asks at a prompt and posts a test message, and on One to `.\scripts\vps\Watch-Outside.ps1 -SetWebhook`, which keeps its own copy for when the VPS cannot be reached (issue #448). |
| Voice join token key | `token-key.txt` in `C:\Thornswood-Voice` on the VPS. `C:\Thornswood-Voice-Dev` has its own, which dev voice makes itself; `vps-dev-instance.ps1` never copies live's (#1083) | Signs the token that says which profile a voice connection belongs to. **Not enforced** unless the service runs with `-Auth on`: the default, `log`, lets an unproven connection in as whoever it claims and writes a line saying so. The `auth` field of the service's `/health` says which. | The service makes it itself. Delete the file and run `Install-Voice.ps1 -Restart`; tokens already issued stop working and the launcher fetches new ones on its next renewal. |
| TURN relay key, not in use yet | `turn-key.txt` in `C:\Thornswood-Voice` on the VPS, put there by hand, and its own in `C:\Thornswood-Voice-Dev`, put there by hand too; `vps-dev-instance.ps1` never copies the live one (#1083). Neither is there yet: no relay has been stood up, so the service offers STUN only | Nothing yet. Once a relay is up, the voice service makes each browser a credential from it, and a credential lets whoever holds it send traffic through the relay until it expires. **Not enforced** as to who gets one: `/ice` answers anybody who asks. | Whoever runs the relay changes its shared secret there, puts the same value in `turn-key.txt`, and runs `Install-Voice.ps1 -Restart`. Credentials already handed out stop working at once. |
| Backup passphrase | `C:\Thornswood-Backup\key.txt` on the VPS and `Documents\thornswood-backup-key.txt` on Patrick's machine, one copy in each on purpose | The nightly backups, which hold the site's `config.json`, `bot.env.json` and the live game server's `private` folder: every VPS secret above except the voice service's files. | `Install-Backup.ps1` sends the Documents copy up when the box has no `key.txt` (a new box, issue #454), makes one when neither has it, and copies it down when the Documents copy is missing. Keep the old one until the backups made with it have aged out. |
| GitHub access | your own `gh auth login`, kept in Windows' credential store | Pushing branches and opening pull requests here, and a main Ship's download of the launcher CI built. Releases go to the VPS, not GitHub, since #897 and #907. | You: `gh auth logout`, then `gh auth login`, or revoke it on GitHub under Settings, Applications. Collaborator access to the source repo is Patrick's to give or take away. |
| VPS access | your own key, `.ssh\thornswood_ed25519` in your profile, made by `Setup-SshKey.ps1`, and its public half in `C:\ProgramData\ssh\administrators_authorized_keys` on the VPS | Administrator on the VPS, and so every VPS row in this table: the site, the bot, both game servers, voice and the backups. None of the scripts needs the Administrator password; `Add-VpsKey.ps1` exists so nobody else has to hold it. | You. First move the old key aside: rename both `.ssh\thornswood_ed25519` and `.ssh\thornswood_ed25519.pub`, say by adding `.old`. While the old key still opens the VPS, `Setup-SshKey.ps1` says it already works and stops, and while the `.pub` is there it uses that one again rather than making a new one. Passing `-KeyPath` a new file does not get round this, because that first check goes through your ssh config, which still names the old key. Then `Setup-SshKey.ps1 -KeyOnly` makes a new key at the same path and prints its public line. Patrick adds it with `Add-VpsKey.ps1 -PublicKey '<the new line>'` and takes the old one off with `Add-VpsKey.ps1 -PublicKey '<the line in the .old .pub>' -Remove`. For his own key, Patrick runs `Setup-SshKey.ps1` without `-KeyOnly`, which asks for the Administrator password once and puts the new key on itself, and then removes the old line the same way. Delete the `.old` pair once `Setup-SshKey.ps1 -Test` passes and the old line is off. |
| VirusTotal API key | the environment variable `VT_API_KEY` on the machine that runs the optional manual upload, and nowhere in this repository: `Publish-VirusTotal.ps1` reads it from there only, so it has no file to be committed in and no parameter to be typed on a command line | Reading and uploading under our VirusTotal account when somebody runs the manual tool. Publish, Package, and Ship do not call it (#802). | Whoever owns the VirusTotal account, in the account's own API key page, then sets the variable on that machine. A machine without it skips a manual run; publish does not need the key. |
| Code signing | `records\signing\signing.json` on a machine that signs, written from `records\signing\signing.template.json` by `Setup-ShipMachine.ps1`. It names the setup and holds no key: the credential is the `az login` on that machine, as Patrick, whose Azure account is the only one with signing access (the Certificate Profile Signer role on the Artifact Signing profile), or a certificate in that machine's own store | Whether Windows treats the launcher and the installer as ours rather than as an unknown download. | Patrick, in Azure: the signing account is his, and a second machine signs only while `az` on it is signed in as him. Without the file `Sign-Artifact.ps1` signs nothing and a local build carries on unsigned. Ship and Publish-Installer refuse that soft skip before anything reaches the site or the feed. |
| The domain, thornswood.net | Registered at Cloudflare, in Patrick's own Cloudflare login, which he signs in to with GitHub (`docs\OWNERSHIP.md`). Nothing about it is kept on a machine or in this repository | The address everybody reaches the site, the feed and the launcher downloads at. Whoever holds the login can point it anywhere or let it lapse. | Patrick, in that Cloudflare login: renewing, moving or changing the records. Nobody else holds it. |

**The rule for this table.** A control that does not exist is listed as
**not enforced**, never left out and never left in as though it worked. The
first row used to say the game server had a password, in
`server-settings.json`, while the script that manages it said there was
nothing there to write.

**Who gets into the game.** No password decides it. `Deploy-Gamemode.ps1`
writes `offlineMode` true into `server-settings.json` on every deploy, and in
offline mode SkyMP lets a client connect as whatever profile id it names (the
fork's `docs\docs_server_configuration_reference.md`, under offlineMode). The
launcher's Discord check at Play stops people using our launcher, not a stock
SkyMP client. What the server has of its own is the door in `gamemode.js`: it
compares each connection's profile id with `private\allowed.json`, which it
refreshes from the site every five minutes, and turns somebody away only when
that file says `"enforce": true`. Until `Set-Door.ps1 -Enforce` sets that, it
writes WOULD TURN AWAY in `private\door.log` and lets them stay. Even
enforcing, it checks a number the client chose, so it keeps out somebody who
does not know a listed profile id and not somebody who does.

**Old launchers.** A launcher older than 1.0.197 read the join password out of
`version.json` rather than asking the site. `Publish-Update.ps1` takes it out
of the feed on every publish, so those copies keep whatever they last read. It
opens nothing either way.

**Copies.** The nightly backups, on the box and in `Downloads\Thornswood-Backups`
once `Fetch-Backups.ps1` has brought them down, are encrypted with the
passphrase. `Backup-Server.ps1` makes a plain zip in that same folder, with
the site's config, the bot and voice folders whole and every game server's
`private` folder, so a machine that has run it holds every VPS secret above
except the backup passphrase, in the clear.

**Checking a row.** Each of these reads, and none prints a value:

- `.\scripts\ops\Check-Roster.ps1`: whether `door.json` and `allowed.json` are in
  both servers' `private` folders, by name and size.
- `.\scripts\ops\Set-Door.ps1`: whether the live door is enforcing or only watching,
  and whether it is refreshing. Add `-Root C:\Thornswood-Server-Dev` for dev.
- `.\scripts\vps\Check-Site.ps1`: whether the site's client secret and bot token look
  right and the bot can read the Discord.
- `.\scripts\deploy\Install-Backup.ps1 -Status`: whether the passphrase is on the box,
  by length.
- `.\scripts\ops\Set-DevNews.ps1 -Check`: whether the dev webhook is set and which
  channel it points at.
- `.\scripts\vps\Setup-SshKey.ps1 -Test` and `gh auth status`: your own two.
- `https://thornswood.net/api/allowed` in a browser answers `no` with a 401
  while `botKey` is set, and `not set up` with a 404 when it is not.

Never paste any of them into a chat, a commit, a Discord message or a doc.

### One Skyrim of its own

Thornswood runs from its own game folder, `<Root>\Game`, and nothing here
supports another server's install. Decided by Patrick on 20 September, after
measuring what the old sharing code had actually let through: the SkyMP client
runtime in Thornswood's folder, the bundle, `MpClientPlugin.dll`, both
SkyrimPlatform DLLs, the CEF host and `TESModPlatform.pex`, were all another
launcher's builds, copied across from the Steam copy on every rebuild and then
patched by text. None of them had come from Vortex and none had come from
here.

**The folder.** The launcher makes `<Root>\Game` itself (`launcher\app\OwnGame.cs`,
Settings, Maintenance, "Thornswood's own Skyrim folder"). With the Thornswood
profile deployed in Vortex, it builds the folder from that deployment, then
restarts and runs from it. `Paths.Init` prefers `<Root>\Game` over the Steam
copy, so from then on the launcher points Windows' Skyrim settings, plugin list
and saves at `Profile` for each session and ignores which profile Vortex has
on. When Vortex deploys a newer Thornswood collection, the next launcher start
brings it in by itself. The offer to make the folder is made at startup
whenever it is possible; it used to wait for another server's files to be
found, and no longer looks for any.

**When Vortex deploys somewhere else.** Vortex can manage a Skyrim that is not
the Steam copy: on 24 September a tester's Vortex deployed the collection into
another SkyMP server's copy of the game, `steamapps\common\Keizaal Online`. The
launcher finds that folder by itself (`OwnGame.DeploysInto`: any folder
directly under a Steam library's `steamapps\common` with `SkyrimSE.exe` and
`Data\vortex.deployment.json`, a Steam copy of Skyrim Special Edition first,
otherwise the newest record). `VortexGame` in config.json wins over the search;
Fix and Settings' Choose Vortex's folder set it. Scan names the folder and Fix
points the launcher at it. Nothing of that folder's own reaches `<Root>\Game`:
the game itself comes from the Steam copy (`OwnGame.Source`, the one Downgrade
keeps on the server's build), and the mods are exactly the files Vortex's
records in that folder list, linked or copied from Vortex's staging folder.
With no Steam copy on the machine the folder is not made.
`tests\test-vortex-folder.ps1` proves it.

**The client.** The SkyMP client runtime is built from the fork, the
`engine\skymp` submodule on `thornswood/engine-changes`: `npx webpack` in
`skymp5-client` for the bundle and the native build for the rest. After a
rebuild, `scripts\release\New-ClientBuildRecord.ps1` records the six files that build
produces which differ from upstream, by hash, against the fork commit, into
`records\client-build.json`. `scripts\release\Sync-Client.ps1` copies those six from the
build output into the game folder and refuses any file that is not the
recorded one; `Go.ps1` runs it beside the overlays and the plugins. Ship runs
`Sync-Client.ps1 -Check` and refuses a release whose client is not the recorded
build. Ship never builds the engine: when the game folder already holds all
six as recorded, Sync-Client copies nothing and does not need the build, so a
checkout with no `engine\skymp` (a fresh Ship worktree) can still Ship, and
`Check-ShipReady.ps1` does not ask for the fork (issue #946). `OwnGame.Foreign` never takes those six paths from the Steam copy. The
launcher's Client row on the Play page compares all six with the same record
(`ClientRuntime`), and `ClientRuntime.Heal` puts back any that is missing or
not the recorded build.
`Ship-Rules.ps1` counts one of them as ours, for a pack or the installer, only
when its sha256 is the recorded one, and `Package-Thornswood.ps1` stops rather
than build an installer around any other.

**Links, not copies.** Big files (archives, textures, meshes, plugins) are hard
links to Vortex's copies, so a collection is not on the disk twice; this needs
the folders on the same drive as the Skyrim Vortex deploys into. When they are
not on one drive the folder cannot be made, and `OwnGame.OneDriveOnly` says so
by naming both ways out and their paths: install Thornswood on Skyrim's drive,
which lands in `<drive>\Thornswood`, or move the Steam library to Thornswood's
drive in Steam, Settings, Storage. A hard link is the same file under a second
name, so anything written into one in place lands
in every folder that links it. So these are always copied: the game's root
files, `Data\Platform`, `Data\NirnLabUIPlatform`, `Data\SKSE`, `Data\MCM`,
`Data\Video`, settings, script and program files, and the vanilla masters. The
launcher's own writes into the game folder go through `OwnGame.Unshare` or
`OwnGame.Separate` first.

**Left out of the folder, and of every pack and installer:** decided by what
belongs, never by whose a file is. `OwnGame.Foreign` in the launcher and
`Test-ShipOtherServer` in `scripts\release\Ship-Rules.ps1` are the same list; change both
together. In `Data\Platform\Plugins` only `thornswood-*.js` and the recorded
bundle belong; in `Data\Platform\UI` only `index.html`, `build.js` and
`thornswood-*.js`; `PluginsNoLoad` is sign-in data with a token in it and never
travels; NirnLab UI Platform is left out because SkyrimPlatform will not start
on its own browser with it present. Vortex's records and markers, logs and
`Claude outputs` are left out too.

**In the folder while the game runs.** Keep puts back every file our own
updates wrote under `Data\Platform` before Play and parks any `.js` in
`Plugins` that is not ours in `Profile\Parked`, then puts them back the moment
the game closes. Hold keeps its own files open read only while the game runs,
so nothing can swap them under Skyrim Platform's hot reload. Every Thornswood
plugin idles unless the client settings point at our server and the launcher
left a fresh session note, `Data\Platform\thornswood-session.txt`. No wrapper
script is needed around the launcher for any of this.

A Skyrim on a newer build than 1.6.1170 gets a Downgrade button on the Play
page (Downgrade.cs): the launcher opens Steam's console, types the three
`download_depot` commands itself, watches Steam's content_log.txt for each
depot to finish, copies the 1.6.1170 files over the Steam copy and removes the
downloads. Nothing is typed unless Steam's window is confirmed in front; if it
cannot be, the command goes on the clipboard and the log says where to paste.

**Records.** `Profile\OwnGame\files.txt` lists each file brought in, whether it
was linked or copied and whether Vortex deployed it. Ship-Rules.ps1 reads that
list (`Get-ShipOwnGameCollection`) so Publish-Update and Package-Thornswood keep
the collection out of packs and the installer, exactly as they read
`vortex.deployment.json` when the game is the Steam copy, and both refuse to go
on if the list is empty. `Profile\OwnGame\plugins.txt` and `loadorder.txt` are
the Vortex profile's lists as of the folder's last update, and are the
reference load order a release carries (`Get-ShipLoadOrderDir`). Ship checks
the client in `<Root>\Game` against `records\client-build.json`.

**The behavior files and the bodies, before a Ship.** Every release carries
the behavior files (the animations for the mod list, Nemesis' output until
29 September) and the bodies BodySlide builds. Decided by Patrick on
29 September (issue #1247): they are made in
Thornswood's own folder, as a step on the shipping machine before a Ship, and
never in the Steam copy, which stays the person's own. Since #1232 nothing run
into the Steam copy reaches Thornswood's folder or a release. With the game and
the launcher closed, on the machine that ships:

```
.\scripts\mods\Build-Generated.ps1 -Channel dev      C:\Thornswood-DevBuild\Game
.\scripts\mods\Build-Generated.ps1 -Channel main     C:\Thornswood\Game
```

It runs two tools the collection installs, with what `records\generated.json`
names. The behavior files come from Pandora Behaviour Engine+ (Nexus 133232,
in the collection from revision 2), with exactly the four patches the list
names and every other patch off. Nemesis cannot do it: its `-generate` never
starts its work (in its own source, the command line connects to a slot that
does not exist), which is why it leaves the collection in the same revision.
Pandora's output for the current mod list was compared with Nemesis' on
29 September: the same 20 behavior and character files with the same names in
them. The script runs a copy of Pandora in its work folder, with a
`Settings.json` beside it naming only that folder's Data and a work output
folder: Pandora 4.4.0 ignores `-o` and without that file would take the
registry's Skyrim, the Steam copy. It refuses if Pandora changed anything in
the game folder or its log has an error, and needs the .NET 10 runtime on the
machine. The bodies come from BodySlide's sets (the women's 3BA NeverNude body
and the men's HIMBO body with boxers, issue #405). Each body is built at its set's own
slider defaults and never with RaceMenu morph files; it refuses a set or a
slider move that would shape the breasts, the seat, the genitals or the
nipples (issue #1004) or take the underwear off, and reads every body it built
with `Check-CoveredBodies.ps1` before one goes in. First it gives the folder
its own copy of every file BodySlide writes in place, because the folder is
mostly hard links to Vortex's copies and a write through one lands in Vortex's
copy and the Steam copy too; it refuses, and records nothing, if a tool wrote
through a link anyway. A tool that sits using no processor time and writing
nothing for three minutes is stopped. It refuses while Skyrim or a launcher
runs from that install, and in any folder Vortex deploys into. `-DryRun` checks all of it and
changes nothing. What it made goes in `Profile\OwnGame\generated.txt`, with a
sha256 each and what it was built from (`scripts\mods\Generated.ps1`): the
launcher keeps those files as Thornswood's through every refresh
(`OwnGameKinds.cs`), and `Ship-Rules.ps1` lets the release carry them, though
Vortex deploys files of the same names. Ship and `Check-ShipReady.ps1` stop
when that record is missing or stale: the mod list, a file either tool reads,
`records\generated.json`, or a built file changed since. The fix is to run it
again.

**The Skyrim build.** Steam updates the Steam copy by itself. With Thornswood's
own folder, the Downgrade button works on the Steam copy the folder is made
from, never on the folder's copies, and the folder is then brought up to date
from it. Until the Steam copy is back on 1.6.1170 the folder is not made or
refreshed, so Thornswood keeps playing on the build it has, and the card above
Play says the Steam copy is on the wrong build. Files a mod replaces are left as
the mod has them. The sign in file the 16 Sep installer carried is removed from
the Steam copy as well as from the folder (`Leaks.cs`).

**Testing it on the dev channel.** The dev build runs from
`<Root>-DevBuild`, which has no Game folder when it is first installed. It
offers to make `<Root>-DevBuild\Game` the same way at its first start, its own
Settings, Maintenance has "Make it", and until the folder is there Play will
not start the game out of the Steam copy.

Skyrim reads its plugin list from one Windows folder per user. Thornswood swaps
it per session and ignores which profile Vortex has on.

### Where things are written down

- This guide. The table at the top is the way in. `CLAUDE.md`: what applies to a
  Claude on top of these rules. The To Do board,
  https://github.com/users/EvilPatrick06/projects/1: all outstanding work.
- `README.md`: what the repo is and where to start. A customer's install is
  the site's join page, `site\data\site\join.md`; setting up a
  developer's machine is "Setting up a machine" above.
- `launcher\app\ARCHITECTURE.md`: how the launcher starts, what each class owns
  on disk, and every step between pressing Play and the game starting.
- `docs\MOVING-THE-SERVER.md`, `docs\COLLECTION-METHOD.md`: the VPS and the
  mod collection.
- `docs\OWNERSHIP.md`: who holds each credential, account and build, and who
  the second holder is.
- `lore\`: history and the Accord. `site\data\site\*.md`: the public
  pages (join, rules, classes, world, credits, privacy, terms), also live on
  the site.
- The site's hub boards (Active Issues, Known Issues, Test These, Suggestions,
  Archive, the Patrick runbook) are older than the board and are being retired
  (issue #433); where they disagree with the board, the board is right.
- `docs\archive`: dated snapshots (HANDOFF, the 17 September audit,
  WORKING-NOTES and the old To Do List), history only.
