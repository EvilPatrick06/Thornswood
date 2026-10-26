# 3690 The box is reached by its name, play.thornswood.net, and no file names its address

- **Issue / PR:** #3690 (part of #3721, going public), the pull request this note came in with.
- **Where:** every machine that reaches the box over ssh (One, each developer's PC, the Cloud Desk), the next dev Ship and the next main Ship, and the public repository thornswood-watch-outside. No game server, voice or site deploy.
- **Needs first:** nothing. The DNS record `play.thornswood.net` (A, DNS only, pointing at the box) was made in Cloudflare on 26 Oct and resolves; ssh by that name through the bridge was proved from a cloud thread the same day.
- **Staff notice:** no. A developer whose box scripts stop is told by the scripts themselves (step 1), and nothing about a shift changes.

What it does:

- `scripts/vps/vps.json`, `launcher/app/Config.cs`, `config.example.json` and the whose-game gate in `game/plugins/thornswood-front.js` say `play.thornswood.net` instead of the box's address, and every doc, ops note, archive page and the site's board copy stopped naming the address. `tests/test-vps-defaults.ps1` resolves the name and fails if any tracked file names what it resolves to.
- ssh is keyed by the address in `vps.json`: the Host block in `.ssh/config` and the line in `known_hosts`. Both were written for the old address, so until a machine runs its setup again, its box scripts go to port 22 by the name, which the box refuses.
- The whose-game gate now calls only the name ours, and a launcher writes whatever its config says into `server-ip`. So the feed's `serverAddress` and the new plugin must reach a channel in the same release. `Set-Server.ps1` would change the live feed at once, ahead of the plugin, and every Thornswood plugin would sit idle until the Ship: do not run it for this.

## Run, from the repository root at main after the merge

1. **ssh on each machine, by the name.** On One, from `C:\Thornswood-Repo` at main:

       .\scripts\vps\Setup-SshKey.ps1 -NoPause

   It should end with the login working (`ssh Administrator@play.thornswood.net` in its last lines). Every other step is already done, so it only writes the Host block and the known_hosts line for the name. Then the copy Fetch-Backups keeps of `vps.json`:

       .\scripts\vps\Fetch-Backups.ps1 -Schedule

   The Cloud Desk, from a fresh checkout of main: `pwsh scripts/vps/Setup-CloudSsh.ps1`, which ends with `ssh Administrator@play.thornswood.net works`. New cloud sessions get it from the setup script by themselves. Djinn's PC runs the same Setup-SshKey line once; put that on the issue for whoever works with Djinn next, never as a hand step for Patrick.

2. **The dev Ship carries it.** In the dev ship root's `config.json` (`.\scripts\release\Where.ps1 ShipRootDev`), set `ServerAddress` to `play.thornswood.net` and nothing else:

       $c = Join-Path (.\scripts\release\Where.ps1 ShipRootDev) 'config.json'; $j = Get-Content -LiteralPath $c -Raw | ConvertFrom-Json; $j.ServerAddress = 'play.thornswood.net'; [IO.File]::WriteAllText($c, ($j | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))

   Then the dev Ship as usual. Publish-Update copies the name into the dev feed in the same publish that carries the new plugin and launcher.

3. **The main Ship carries it**, when Patrick says main ships, never straight after dev. The same line with `ShipRoot` in place of `ShipRootDev`, then the main Ship with `-MoveServer`, which lets the feed's `serverAddress` change. The refusal without it ("The server address in version.json is about to change") is the check that this was meant.

4. **The public watcher repository**, after step 1 so the export reads main's `vps.json`. From a clone of `EvilPatrick06/thornswood-watch-outside` beside the repository:

       pwsh scripts/vps/Watch-Outside.ps1 -Export ../thornswood-watch-outside -NoPause

   It should print `wrote the watcher, watch-outside.json, its two workflows and the README`. Commit and push there: `watch-outside.json` now holds `GameHost` and no address. Its old commits still hold the address until the repository is deleted at the flip (Patrick, 26 Oct, B on the page).

## Check afterwards

- `.\scripts\vps\Setup-SshKey.ps1 -Test` on One passes.
- The dev feed (https://thornswood.net/feed-dev/version.json) says `"serverAddress": "play.thornswood.net"`, and a dev client's console shows `Connecting to play.thornswood.net:7787` with the Thornswood plugins running (the voice indicator shows).
- After the main Ship, the live feed says the same.
- The next "Watch outside" run in thornswood-watch-outside lists `game` as ok.
- Then delete this note and put what ran on #3690.

## Risks

- Between the merge and step 1, box scripts on One and on an old cloud session fail at ssh. Nothing on the box changes and nothing goes down.
- Between step 2 and step 3, dev launchers use the name and main launchers the address. Both reach the same box.
