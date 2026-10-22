# #2695 The trading company: Patrick's answers, the lore deploy, and #2687 on dev

Patrick answered #2695 at 11:30 AM MT on 18 Oct, via Smeagle, and took every recommendation:
1. The lore matches.
2. Terms are changed on an in-game staff panel, with propose and confirm.
3. The Trading Company role charters by default.
4. No freight by default, with a ledger fee as a setting.
5. The haul fee stays apart from the board job fee.

## 1. The lore is on main: site and docs deploy (Claude)
PR #2690 is squash-merged as c72baa8e. It changes lore/accord.md, lore/history.md and site/data/site/world.md.
- Deploy the site and docs the usual way (Deploy-Docs -Site). Herald does not run Deploy-Docs or touch live.
- Check that thornswood.net's World page has the Free Skyrim Trading Company, and that the Dominion lines leave the war open.

## 2. #2687 on dev after 1.2.4 (HELD 1.2.4 draft)
Head 7a595e24, branch herald/512-trading-company. Trial merges against #2685 (6d35296b), #2698 (fdbf9172) and main are clean. #2700 (Waystone, trade ships) merges after it and builds on mayCharter().

Dev steps, once it is on a dev build:
1. **The shipped terms.** Start the dev server with no private/company-terms.json. The log says:
   `[thornswood company] the company's terms are read: haul fee 30 , haul cut 10% , charter company , freight 0`.
2. **A haul and a job.**
   - Post a haul at a board: it costs the haul fee (30) plus the pay.
   - Post an ordinary job: it still costs the job fee (30).
   - Deliver the haul: the company keeps 10% of a pay of 10 or more.
3. **The staff card.**
   - As staff, open K, then Office. "The company's terms" shows every term.
   - As somebody who is not staff, the card is not there. A /companyterms line from them gets "The company's terms are staff's. Nothing changed."
4. **Propose, then confirm.**
   - On the card, change the haul fee to 40 and press Propose. Nothing changes yet, and the staff channel hears companypropose.
   - Press Confirm twice. A new haul now costs 40 + pay. A haul posted before the confirm still pays out by the cut it was posted under.
   - private/company-terms.json has the change and who made it.
5. **A restart keeps it.** Restart the dev server: the haul fee is still 40.
6. **Drop.** Propose a change, then press Drop. Nothing changes, and the staff channel hears companydrop.
7. **A company sale** through the trade panel splits 10% to the worker, 10% that leaves, and the rest to the seller.
8. **Set it back** (haul fee 30) through the card, propose and confirm, before the dev build is used for anything else.

Nothing here is to run on live. Every number is staff data, and nothing scripts who hauls, for whom, where, when or how long.