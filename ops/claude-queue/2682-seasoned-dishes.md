# 2682 seasoned dishes: the extra ingredient at the pot (content plugin), and the per-effect eat filter (engine)

Issue: https://github.com/EvilPatrick06/Thornswood/issues/2682
Design: https://github.com/EvilPatrick06/Thornswood/issues/2682#issuecomment-6253340775
Lane: Anvil. Held draft PR: https://github.com/EvilPatrick06/Thornswood/pull/2718 (branch anvil/2682-meal-help, stacked on Herald's #2684, herald/1383-injury).
Split issues (unclaimed, blocked on Claude): content plugin https://github.com/EvilPatrick06/Thornswood/issues/2719, engine https://github.com/EvilPatrick06/Thornswood/issues/2720

## Why this is in the queue

Patrick ruled on 18 October 2026 (relayed by Smeagle, 11:31 AM MT): a cooked meal gives only its temperature help by default (a soup, stew or chowder warms), and stamina recovery or the disease guard comes only when the cook adds one extra ingredient at the pot. Vanilla food's own magic goes, except temperature effects.

The server half is in the held draft. Two pieces are not server work and are Claude's:

1. The seasoned dishes, as records in the content plugin.
2. An engine filter so a record's temperature effect can land without the rest of its effects.

## 1. Seasoned dishes (content plugin) (issue #2719)

The eat event only carries a record's base id, so a dish made with the extra ingredient has to be its own ALCH record. A recipe can't take an optional ingredient, so it also needs its own COBJ.

What to make:

- For every COBJ at the cookpot (workbench keyword CraftingCookpot, a5cb3:Skyrim.esm) whose result is in the cooked or soup group of game/data/food-groups.json: 97 recipes, 45 distinct dishes, read from game/data/recipes.json on 18 October 2026.
- For each such recipe and each extra in `season.extras`, one variant COBJ: the same inputs, conditions and bench as the plain recipe, plus one of the extra. Today the extras are Garlic (34d22:Skyrim.esm, guard) and Salt Pile (34cdf:Skyrim.esm, stamina).
- For each dish and each extra, one new ALCH: a copy of the plain dish with its own name ("Garlic Venison Stew", "Salted Venison Chop" or similar), the same keywords, value and model. Its effects can stay as copied, because the server takes away all of a stripped group's own magic anyway.
- The oven (HearthFires, 117f7:HearthFires.esm) is not the pot and gets no variants, per the ruling's "at the pot".

Then, in the same change, the server data (game/data/food-groups.json, and the same JSON on the `const FOOD_GROUPS = ` line of game/gamemode.js; test-1382-food-groups.js checks they match):

- Add each new ALCH to `items` with its plain dish's group.
- Add each to `season.dishes` as `"<new desc>": { "of": "<plain dish desc>", "extra": "<ingredient desc>" }`.
- tests/test-2682-meal-help.js checks that every dish is grouped like its plain dish and made with a listed extra.

Until this lands, only the default warmth and the removal of food's own magic are live.

## 2. The per-effect eat filter (engine fork) (issue #2720)

In fork 3bdf3d3c, `EatItemEvent::OnFireSuccess` scales every effect of the eaten record by `eatItemScale`, and skips them all at 0 or less. That's all or nothing per record.

Three food records carry a temperature effect alongside a small non-temperature one, so they are kept whole for now (`strip.keep` in food-groups.json):

- Sack of Frostwheat Flour (12f9c4:WindhelmSSE.esp): Resist Frost 3 for 60s, with Restore Health 1
- Frostwheat Bread (12010f:WindhelmSSE.esp): Resist Frost 5 for 60s, with Restore Health 3
- Snowberry Juice (17167b:WindhelmSSE.esp): Resist Frost 5 for 30s, with Restore Stamina 5

The engine change: a way for the server to name which effects of the eaten record land, for example a list of magic effect ids to keep, set in mp.onEatItem the way eatItemScale is. When it lands, these three move from `strip.keep` to a keep-only-these-effects rule, and the harness changes with them.

## Steps for Claude

1. From a fresh worktree of main (after #2684 and #2682's draft have merged, or stacked on anvil/2682-meal-help), build the variant COBJ and ALCH records with the content-plugin tooling. The plugin is a freeze path, so it's held under 1.2.4 like the rest.
2. Update food-groups.json `items` and `season.dishes`, and mirror the change into the FOOD_GROUPS line. Run tests/test-1382-food-groups.js and tests/test-2682-meal-help.js.
3. Separately, the engine filter in the fork, then the server change for the three kept records.
4. Playtest:
   - Cook a plain stew: it warms, 15 hunger and 10 thirst, no vanilla regen.
   - Cook it with garlic: the disease guard.
   - Cook a chop with salt: +10% stamina recovery.
   - Each help lasts 20 real minutes, and the latest meal's help is the one that counts.
