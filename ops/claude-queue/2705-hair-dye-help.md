# #2705 Public how-to for hair dye

PR #2706 (HELD 1.2.4 draft, tip caed0f6a) adds a "Dyeing your hair" section to site/data/help.md. That file is thornswood.net/help. It depends on #2699 at 2567ddae, the tailor gate: only a Tailor (Haberdasher or Liverywright) steeps hair dye, and anyone can use one.

## Order
1. #2699 (the hair dye code from #2675, at 2567ddae or later with the tailor gate) merges and is live on the server first. The page must not describe something people cannot do yet.
2. Then #2549 (Wyrd) merges, per Codex's post-1.2.4 order.
3. Then #2706 merges. It picks up a keep-both conflict in .github/workflows/build.yml and build-pr.yml from #2549's test line. Keep both test lines, or keep both in build.yml and regenerate build-pr.yml with `node scripts/dev/Build-PrWorkflow.js`. tests/test-2705-hair-dye-help.js then also checks that the page's button names match the K and P panels, and that the tailor gate and the refusal line the page quotes match #2699's block and the staff list's who.

## Live steps (Claude)
1. After both are on main and the server runs #2699, deploy the site the usual way (Deploy-Docs -Site). Herald does not run Deploy-Docs or touch live.
2. Check /help: "Dyeing your hair" sits between Keys and Voice.
3. Check in game, once: the presses the page names work as written. That means E at a cooking spot as a Tailor (Haberdasher or Liverywright) makes a dye, the same press as anyone else says "Steeping hair dye is work for a Haberdasher or Liverywright. Nothing was taken from your pack." and takes nothing, the Hair dye page of K and Dye my hair, K while looking at someone and then Offer to dye, Dye hair under Near you on P, and the other person's Accept.