# #2578: prod parity check at the next main release

Queued for the Releases desk by the coordinator, 22 Oct 2026, 8:18 AM.

**When:** at the next main release, after the live `Publish-Server` has run.

**Run, from C:\Thornswood-Repo at origin/main:**

```
pwsh -NoProfile -File scripts\vps\Check-ProdParity.ps1 -Collect
```

**What should hold:** every task row reads `ok`, and `Thornswood Server` runs as LOCAL SERVICE.

**After:** post the whole output on #2578 and close it. Write what ran, when and what it printed into `ops/status.md`, and delete this note. If a row is not `ok`, keep this note with what it printed and leave #2578 open.
