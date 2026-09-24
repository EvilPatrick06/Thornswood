# Setting the repo up, once

You run these. I don't touch your GitHub credentials.

## 1. Make the repo

Private. The bundle it serves contains other people's mods, so this never goes public.

```
winget install GitHub.cli
gh auth login
cd <this folder>
git init -b main
git add .
git commit -m "Skyrim Together tooling"
gh repo create skyrim-together --private --source . --push
```

## 2. Make a read-only token

GitHub → Settings → Developer settings → **Fine-grained personal access tokens** → Generate new token.

- Repository access: **Only select repositories** → `skyrim-together`
- Permissions: **Contents: Read-only**. Nothing else.
- Expiry: whatever you're willing to rotate.

That token can read this one repo and do nothing else. Even so, treat it as
public the moment the bundle ships, because it's sitting in a file on four
other machines.

## 3. Wire it into the bundle

Copy `config.example.json` to `C:\SkyrimTogether\config.json`, put the token in
`UpdateToken` and your repo in `UpdateRepo`, then rebuild the bundle so your
friends get it. Until that file has a repo in it, the launcher never touches the
network beyond the server ping.

## 4. Record the starting point

Once, after the bundle is out:

```
.\tools\Publish-Update.ps1 -Baseline
```

That writes `C:\SkyrimTogether\_dist\published.json`, the state everyone is
known to have. Every later run diffs against it.

## Publishing a change

```
# mod changes: Vortex -> deploy -> confirm it launches -> Build-SkyrimTogether.ps1
.\tools\Publish-Update.ps1 -Notes "Swapped the map mod"

# launcher changes: bump Version in tools\app\Updater.cs -> Build-Launcher.ps1
.\tools\Publish-Update.ps1 -Launcher -Notes "Added a server browser"
```

It packs only what changed, uploads it to a release, rewrites `version.json`,
commits and pushes. Everyone's launcher offers it on next start.

## If you rotate the token

The launcher reads `config.json` on disk, so a new token has to reach your
friends inside a pack. Ship the new `config.json` in `profile/` of the next
pack, or send them the file. Do it before revoking the old one.
