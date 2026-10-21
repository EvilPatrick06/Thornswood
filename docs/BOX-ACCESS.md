# Reaching the box from your own PC

The box (the VPS) takes ssh only through the bridge at
`wss://thornswood.net/box/`, and each person comes in with a key and a token
of their own (#2891). Your home address does not matter, and it can change
as often as it likes. Taking one person's access away leaves everybody
else's working.

You need two things from Patrick, one at a time: he puts your key on the box,
and he sends you your token. Neither is the server password, which nobody
needs.

## On your PC, once

1. Install these, then close PowerShell and open it again so they are on the
   path:
   - the OpenSSH Client: Settings, Apps, Optional features, Add a feature,
     OpenSSH Client (Windows 10 and 11 usually have it already);
   - node, the LTS: https://nodejs.org.

   Check them. Each prints a version:

   ```powershell
   ssh -V
   node --version
   ```

2. In your clone of the repository, make your key and send its public line:

   ```powershell
   cd C:\Dev\Thornswood
   git pull
   .\scripts\vps\Setup-SshKey.ps1
   ```

   It makes `.ssh\thornswood_ed25519`, points ssh at the box through the
   bridge, and prints one line that starts with `ssh-ed25519`. Copy that
   whole line to Patrick in Discord. It is the public half and safe to send
   anywhere. The private half never leaves your PC. When it asks for the
   token, press Enter alone: you do not have it yet.

3. Patrick sends you a token in a Discord DM. Run the same line again and
   paste the token when it asks (nothing shows as you paste, on purpose):

   ```powershell
   .\scripts\vps\Setup-SshKey.ps1
   ```

   It keeps the token in `.ssh\thornswood-box-token`, readable by your
   account only, writes the box's own key into `known_hosts` once it matches
   the one `scripts\vps\vps.json` pins, and logs in. It ends with
   `ssh Administrator@... works`. Delete the DM.

4. From then on every script that talks to the box (`Get-Logs.ps1`,
   `Remote.ps1`, the `Deploy-*` and `Install-*` scripts) goes through by
   itself. To check at any time:

   ```powershell
   .\scripts\vps\Setup-SshKey.ps1 -Test
   ```

## On One, for Patrick

Give a person access, with the line they sent (`-FromClipboard` takes it out
of a copied Discord message):

```powershell
.\scripts\vps\Grant-BoxAccess.ps1 -Name djinn -FromClipboard
```

It puts their key on the box, taken only through the bridge, makes their
token, proves a new login from One still gets in, and writes the token to
`box-access\djinn\box-token.txt` in the scratch folder, printing the whole
path. Send what is in that file to them alone, then delete it and its
folder. Running it again
for the same name replaces both, so the old pair stops working.

Take one person's access away. Nobody else's changes:

```powershell
.\scripts\vps\Grant-BoxAccess.ps1 -Name djinn -Remove
```

Who has a way in, read only:

```powershell
.\scripts\vps\Grant-BoxAccess.ps1 -List
```

The names are one word, lower case: `one` is One itself, `cloud` is the
cloud Claude threads (made with `-MakeKey`), and each person has their own.

## When it stops working

- `box bridge: the bridge refused this token`: your token was replaced or
  taken away. `Setup-SshKey.ps1` deletes it; ask Patrick for a new one and run
  it again.
- `Permission denied (publickey)`: the bridge let you in but the box does not
  hold your key. Send Patrick the line `Setup-SshKey.ps1` prints again.
- `box bridge: no WebSocket` or `the bridge did not open a WebSocket`: the
  bridge or the site is down for everybody. Say so in #staff-updates. If
  nobody can get in, the way back is the VNC console in the BisectHosting
  panel: `Start-ScheduledTask 'Thornswood Bridge'` and
  `Start-ScheduledTask 'Thornswood Web'` there (`Set-SshScope.ps1` has the
  rest).
- `Host key verification failed`: `known_hosts` holds a key for the box that
  is not the pinned one. Do not go on; ask in #staff-updates.
