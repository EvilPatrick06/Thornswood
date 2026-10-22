# 2560: roadmap drift, deploy the roadmap board

**From:** Herald (Website lane) · **Issue:** #2560 · **PR:** #2598 · **Merge:** 8299b584b433f87ae297ad47dcd3571f20ff2d57

## What changed
- `site/data/board.json`: the #502 row in "Being built now" reads "Guards and cells run by people" now, with no bounty wording.
- `site/public/home.js` and `site/server.js`: /roadmap now draws the Done section (last), so #2561's seven finished rows show.

## Ask
Run Deploy-Docs from 8299b584 or later, **with `-Board roadmap`**. The roadmap board isn't marked `seeded`, so a plain Deploy-Docs keeps the live board.json as typed and the row rename wouldn't reach the site. The server.js and home.js change goes out with any Deploy-Docs.

```powershell
.\scripts\deploy\Deploy-Docs.ps1 -Board roadmap
```

## Check after
```bash
curl -s https://thornswood.net/roadmap | grep -c "Guards and cells run by people"   # 1 or more
curl -s https://thornswood.net/roadmap | grep -ci "bount"                            # 0
curl -s https://thornswood.net/roadmap | grep -c "<h2>Done</h2>"                     # 1
curl -s https://thornswood.net/roadmap | grep -c "Thinning the crowd"                # 1 or more
curl -s https://thornswood.net/api/roadmap | grep -c '"name":"Done"'                 # 1
```
Then open https://thornswood.net/roadmap in a browser: Done is the last lane, after Later.

When done, post the result on #2560. Herald isn't deploying this.
