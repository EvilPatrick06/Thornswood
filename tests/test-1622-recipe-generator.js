// test-1622-recipe-generator.js
//
// #1622. scripts/dev/Build-RecipeTable.ps1 writes game/data/recipes.json and
// the RECIPES_BY_ID block, and four merged changes put their decisions into
// those two by hand after the build: the cut file (#1391), the one smelt row
// per ingot and the leather rows (#1391, #1400), the refused dwarven scrap
// smelts (#613) and the poles and the trap (#1379). A rebuild undid all of
// them. The build now carries them, and this holds the build and the tables
// it wrote to the same answers, so the next rebuild changes nothing it was not
// meant to. It also holds the load order to the plugins Vortex switched on.
//
// The build itself reads the game's plugins and is not run here. Read only.
const REPO_DIR = require("path").join(__dirname, "..");
const fs = require("fs");
const path = require("path");
const CR = String.fromCharCode(13);
function read(rel) { return fs.readFileSync(path.join(REPO_DIR, rel), "utf8").split(CR).join(""); }

const ps = read("scripts/dev/Build-RecipeTable.ps1").replace(/^﻿/, "");
const gm = read("game/gamemode.js");
const recipes = JSON.parse(read("game/data/recipes.json"));
const cutDoc = JSON.parse(read("docs/systems/cut-items.json"));
const fisher = read("docs/systems/classes/fisher.md");

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log("PASS  " + what); }
  else { fail++; console.log("FAIL  " + what); }
}
function slice(src, start, end) {
  const a = src.indexOf(start);
  if (a < 0) { return null; }
  const b = src.indexOf(end, a + start.length);
  return b < 0 ? null : src.slice(a, b + end.length);
}
// A PowerShell single quoted string, with '' for a quote inside it.
const PSSTR = "'((?:[^']|'')*)'";
function unq(s) { return String(s).split("''").join("'"); }
// One [ordered]@{ ... } knob of the build, as name -> its fields.
function knob(name) {
  const src = slice(ps, "$" + name + " = [ordered]@{", "\n}\n");
  const out = {};
  if (!src) { return null; }
  const re = new RegExp("^\\s+" + PSSTR + "\\s*=\\s*(.*)$", "gm");
  let m;
  while ((m = re.exec(src)) !== null) {
    const key = unq(m[1]);
    const rest = m[2];
    if (rest.indexOf("@{") === 0) {
      const f = {};
      const fr = new RegExp("(\\w+)\\s*=\\s*" + PSSTR, "g");
      let n;
      while ((n = fr.exec(rest)) !== null) { f[n[1]] = unq(n[2]); }
      out[key] = f;
    } else {
      const s = new RegExp("^" + PSSTR).exec(rest);
      out[key] = s ? unq(s[1]) : rest;
    }
  }
  return out;
}
function oneString(name) {
  const m = new RegExp("^\\$" + name + " = " + PSSTR + "\\s*$", "m").exec(ps);
  return m ? unq(m[1]) : null;
}

// ---- the load order is the plugins that are switched on -----------------
const loadOrder = slice(ps, "foreach ($p in $MASTERS_FIRST) { $order.Add($p) }", "Ok (\"{0} plugins: the five masters, then {1}\"");
yes("the plugins.txt loop is in the build", loadOrder !== null);
yes("a line Vortex switched off (no '*') is left out of the load order",
  !!loadOrder && loadOrder.indexOf("if (-not $t.StartsWith('*')) { $offCount++; continue }") >= 0);
yes("and the run says how many were left out", ps.indexOf("line(s) in that list are switched off and were left out") >= 0);

// ---- the cut file (#1391) ------------------------------------------------
yes("the build reads docs/systems/cut-items.json",
  ps.indexOf("$CUT_FILE = Join-Path $PSScriptRoot '..\\..\\docs\\systems\\cut-items.json'") >= 0);
const rolls = knob("CUT_ROLLS") || {};
const rollsLine = /^\$CUT_ROLLS = \[ordered\]@\{ 'embassy' = 'embassy'; 'thalmor' = 'remnant' \}$/m.test(ps);
yes("embassy rows go on the embassy roll and thalmor rows on the remnant roll", rollsLine || (rolls.embassy === "embassy" && rolls.thalmor === "remnant"));
const ROLL = { embassy: "embassy", thalmor: "remnant" };
const CUT_SENTENCE = oneString("CUT_SENTENCE");
yes("the build says what the gate says for a cut row", !!CUT_SENTENCE);

const sections = ["# ------------------------------------------------------------- the counts ---",
                  "# ------------------------------------------------------------ the cut file -",
                  "# ------------------------------------------------------------- the writing -"].map(function (h) { return ps.indexOf(h); });
yes("the cut file is applied after every rank and count and before anything is written",
  sections[0] > 0 && sections[1] > sections[0] && sections[2] > sections[1]);

const items = cutDoc.items || [];
let cutOwned = 0, cutRefused = 0, rolled = 0, wrong = [];
items.forEach(function (it) {
  const owned = recipes.recipes[it.id], refused = recipes.refused[it.id], open = recipes.unowned[it.id];
  if (it.disposition === "cut") {
    if (owned && owned.book === "cut") { cutOwned++; return; }
    if (refused) { cutRefused++; return; }
  } else if (ROLL[it.disposition]) {
    if (owned && owned.roll === ROLL[it.disposition] && owned.book !== "cut") { rolled++; return; }
  }
  if (wrong.length < 5) { wrong.push(it.id + " (" + it.disposition + ") is " + (owned ? "owned" : refused ? "refused" : open ? "open to anybody" : "not in the table")); }
  else { wrong.push(""); }
});
wrong.forEach(function (w) { if (w) { console.log("      " + w); } });
yes("every cut owned row in recipes.json carries book cut, as the build writes it (" + cutOwned + ")", cutOwned > 3000);
yes("every cut row nobody owned is refused, as the build writes it (" + cutRefused + ")", cutRefused > 200);
yes("every embassy and thalmor row carries its roll (" + rolled + ")", rolled === 24);
yes("and no row of the cut file is open to anybody or carries the wrong mark", wrong.length === 0);
const stray = Object.keys(recipes.recipes).filter(function (k) {
  const r = recipes.recipes[k];
  return (r.book === "cut" || r.roll) && !items.some(function (it) { return it.id === k; });
});
yes("nothing in recipes.json is cut or rolled that the cut file does not name", stray.length === 0);

const recSrc = slice(gm, "var RECIPES_BY_ID = {", "\n  };");
let BLOCK = null;
try { BLOCK = recSrc ? new Function("return " + recSrc.slice("var RECIPES_BY_ID = ".length).replace(/;$/, ""))() : null; } catch (e) { BLOCK = null; }
yes("the RECIPES_BY_ID block reads", !!BLOCK && Object.keys(BLOCK).length > 1500);
const cutFiring = Object.keys(recipes.recipes).filter(function (k) { return recipes.recipes[k].book === "cut" && recipes.recipes[k].fires; });
yes("every cut row the server is asked about is a row nobody makes in the block, with the build's sentence (" + cutFiring.length + ")",
  !!BLOCK && cutFiring.length > 1000 && cutFiring.every(function (k) { return BLOCK[k] && BLOCK[k].nobody === CUT_SENTENCE && !BLOCK[k].half; }));
yes("every rolled row carries its roll in the block",
  !!BLOCK && Object.keys(recipes.recipes).filter(function (k) { return recipes.recipes[k].roll; })
    .every(function (k) { return BLOCK[k] && BLOCK[k].roll === recipes.recipes[k].roll; }));
yes("the block writer writes a cut row as nobody's, with its race", ps.indexOf("', \"nobody\": ' + (JsonStr $CUT_SENTENCE) + ' },')") >= 0 &&
  ps.indexOf("', \"owner\": \"\", \"half\": \"\", \"race\": ' + (JsonStr $r.Race) + ', \"rank\": \"\", \"family\": \"\"'") >= 0);
yes("and a refused row the cut file sent there says the same sentence", ps.indexOf("if ($r.PSObject.Properties['Cut'] -and $r.Cut) { $nobodyWhy = $CUT_SENTENCE }") >= 0);
yes("recipes.json gets book and roll on the row", ps.indexOf("', \"book\": ' + (JsonStr $r.Book)") >= 0 && ps.indexOf("', \"roll\": ' + (JsonStr $r.Roll)") >= 0);

// ---- one smelt row per ingot and the leather rows (#1391, #1400) ---------
const OWNER = knob("RECIPE_OWNER") || {};
const RANK = knob("RECIPE_RANK") || {};
// Every smelt row a half owns, and the tanning rows that make leather, that
// the cut file did not cut.
const keptHere = Object.keys(recipes.recipes).filter(function (k) {
  const r = recipes.recipes[k];
  if (r.book === "cut") { return false; }
  if (r.benchName === "CraftingSmelter") { return true; }
  return r.benchName === "CraftingTanningRack" && (r.name === "Leather" || r.name === "Leather Strips");
});
yes("recipes.json keeps 13 of them: one smelt row per ingot and two leather rows (" + keptHere.length + ")", keptHere.length === 13);
const keptOk = keptHere.filter(function (k) {
  const r = recipes.recipes[k];
  const o = OWNER[r.editorId], n = RANK[r.editorId];
  return o && n && o.Owner === r.owner && o.Half === r.half && o.Family === r.family && o.Why === r.why &&
    r.owner === "Smith" && r.half === "Platewright" && r.rank === "novice" && n.Rank === "novice";
});
yes("each is named in RECIPE_OWNER and RECIPE_RANK with the owner, half, family, reason and rank recipes.json gives it", keptOk.length === 13);
yes("Ingots and Leather, the families the recipe book shows", keptHere.every(function (k) { return ["Ingots", "Leather"].indexOf(recipes.recipes[k].family) >= 0; }));
yes("a recipe named in RECIPE_OWNER is not handed to the smelter's open bench rule",
  ps.indexOf("if ($benchOwner -and -not $benchOwner.Owner -and -not $RECIPE_OWNER.Contains($r.Edid)) {") >= 0);
yes("and its family comes from the knob", ps.indexOf("$famRead = @([string]$RECIPE_OWNER[$r.Edid].Family, 'named in RECIPE_OWNER', 'named')") >= 0);
const openWhy = knob("OPEN_ROW_WHY") || {};
const keeper = recipes.unowned["10dd28:Skyrim.esm"];
yes("the dwarven scrap smelt that stays open keeps #1400's reason", !!keeper && openWhy.RecipeIngotDwarvenScrapPlateMetalLarge === keeper.why);

// ---- the five refused dwarven scrap smelts (#613) -------------------------
const collapsed = knob("COLLAPSED_SMELT_EDITOR_IDS") || {};
const scrap = Object.keys(recipes.refused).filter(function (k) { return collapsed[recipes.refused[k].editorId]; });
yes("five scrap smelts are refused with the build's own reason", scrap.length === 5 &&
  scrap.every(function (k) { return collapsed[recipes.refused[k].editorId] === recipes.refused[k].why; }));
yes("and no reason says the word the words rule bans", Object.keys(collapsed).every(function (k) { return !/player/i.test(collapsed[k]); }));
const routeA = ps.indexOf("if ($COLLAPSED_SMELT_EDITOR_IDS.Contains($r.Edid)) {");
const routeNone = ps.indexOf("    # 2. A recipe with no bench keyword.");
yes("they are refused before the bench NONE rule, which the plugin's override would otherwise hand them to", routeA > 0 && routeNone > routeA);
yes("and refused in one place only", ps.split("$COLLAPSED_SMELT_EDITOR_IDS.Contains($r.Edid)").length === 2);

// ---- the poles and the trap (#1379), at the fisher page's ranks ----------
const POLES = { "Crude pole": "ThornswoodRecipePoleCrude", "Fine pole": "ThornswoodRecipePoleFine",
                "Master pole": "ThornswoodRecipePoleMaster", "Fish trap": "ThornswoodRecipeFishTrap" };
const table = slice(fisher, "## The poles and the trap", "## How much");
const pageRank = {};
if (table) {
  table.split("\n").forEach(function (line) {
    const m = /^\| ([^|]+?) \| (Novice|Advanced|Expert|Master) \|/.exec(line);
    if (m) { pageRank[m[1]] = m[2].toLowerCase(); }
  });
}
yes("the fisher page ranks the three poles and the trap", Object.keys(POLES).every(function (p) { return !!pageRank[p]; }));
yes("RECIPE_RANK gives each the fisher page's rank", Object.keys(POLES).every(function (p) {
  return RANK[POLES[p]] && RANK[POLES[p]].Rank === pageRank[p];
}));
yes("the trap is the Woodwright's in RECIPE_OWNER", !!OWNER.ThornswoodRecipeFishTrap &&
  OWNER.ThornswoodRecipeFishTrap.Owner === "Woodworker" && OWNER.ThornswoodRecipeFishTrap.Half === "Woodwright");
const ids = { ThornswoodRecipePoleCrude: "1549c:Thornswood-Content.esp", ThornswoodRecipePoleFine: "1549d:Thornswood-Content.esp",
              ThornswoodRecipePoleMaster: "1549e:Thornswood-Content.esp", ThornswoodRecipeFishTrap: "1549f:Thornswood-Content.esp" };
// The gamemode carries them, in the block once it is rebuilt and in the four
// lines after it until then; either way the gate must say the page's rank.
const gate = {};
Object.keys(ids).forEach(function (e) {
  const k = ids[e];
  if (BLOCK && BLOCK[k]) { gate[e] = BLOCK[k]; return; }
  const m = new RegExp("RECIPES_BY_ID\\['" + k.replace(/[.]/g, "\\.") + "'\\] = (\\{[^\\n]*\\});").exec(gm);
  if (m) { try { gate[e] = new Function("return " + m[1])(); } catch (err) { gate[e] = null; } }
});
yes("the gate asks the Woodwright for each at the rank RECIPE_RANK names", Object.keys(ids).every(function (e) {
  return gate[e] && gate[e].owner === "Woodworker" && gate[e].half === "Woodwright" && RANK[e] && gate[e].rank === RANK[e].Rank;
}));

// ---- the repair kits (#1384) ---------------------------------------------
const KITS = { ThornswoodRecipeWeaponKit: ["Smith", "Edgewright"], ThornswoodRecipeArmorKit: ["Smith", "Platewright"],
               ThornswoodRecipeSewingKit: ["Tailor", "Haberdasher"] };
yes("the three kits are named to the halves #1384 picked", Object.keys(KITS).every(function (e) {
  return OWNER[e] && OWNER[e].Owner === KITS[e][0] && OWNER[e].Half === KITS[e][1];
}));

console.log(pass + " passed, " + fail + " failed");
process.exit(fail ? 1 : 0);
