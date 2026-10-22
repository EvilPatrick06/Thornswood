# 3107 The box's GitHub admin service and its App

- **Lane:** Claude (cloud, #3107 thread)
- **Issue / PR:** #3107, this pull request; it carries #3312's runner 3 label from the cloud
- **Channel:** VPS (a new service and the Caddyfile); no game server, no Ship
- **Staff status updates:** none: nothing staff do changes
- **Needs first:** this pull request merged

## Run
From a fresh checkout at origin/main, on a machine whose way into the box works (One, or the Cloud Desk through the bridge), in this order:

    .\scripts\deploy\Install-AdminService.ps1 -NoPause
    .\scripts\deploy\Setup-Domain.ps1
    .\scripts\deploy\Install-AdminService.ps1 -Setup -NoPause

The first puts `scripts\vps\admin\admin.js` on the box as the task "Thornswood Admin" on 127.0.0.1:7791, LOCAL SERVICE with its own SID, in `C:\Thornswood-Admin`. It prints `ADMIN OK` and `it holds no App yet`. The second sends the Caddyfile with the `/github-app/` route; Caddy reloads it with no break in the site. The third arms the App's one-time setup for an hour and prints the address.

Then Patrick, signed in to GitHub as EvilPatrick06 (the one step only the account that owns the repository can do; it goes on his page as a hand step, whole, with the address the third command printed):

1. Open the address.
2. Press "Make it on GitHub", then "Create GitHub App for EvilPatrick06".
3. On the page that comes back, press "Install it", choose "Only select repositories", pick Thornswood, press "Install".

## Check afterwards
- `.\scripts\deploy\Install-AdminService.ps1 -Status -NoPause` prints `app       thornswood-box-admin (<id>), made <time>, key held` and `port      7791 answers as the admin service`.
- From the cloud: `pwsh scripts/deploy/Set-BuildRunners.ps1 -Check` exits 0 or 1 with each record's lines (the service answered). Then `pwsh scripts/deploy/Set-BuildRunners.ps1` puts runner 3's `thornswood-sign` label on once #3318's `records/sign-runners.json` is on main (a push that changes a runner record runs it by itself), and `-Check` after it exits 0.
- `.\scripts\vps\Check-RunnerIsolation.ps1` shows no runner account reading `C:\Thornswood-Admin`.

## Risks and how to put it back
- Nothing that runs goes down: the service is new, and the Caddyfile only gains a route.
- `.\scripts\deploy\Install-AdminService.ps1 -Remove -NoPause` takes the service and the key off; delete the App at github.com/settings/apps. Labels already on GitHub stay as they are.
- Until the App is installed, `github-admin.yml` runs (by hand or on a record change) go red saying there is no App yet. Nothing else waits on them.

## Release notes (draft)
none

## News post (draft)
none
