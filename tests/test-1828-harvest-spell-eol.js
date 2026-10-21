// test-1828-harvest-spell-eol.js
//
// #1828. scripts/dev/Build-HarvestTable.ps1 and scripts/dev/Build-SpellTable.ps1
// joined their tables (game/data/harvests.json, game/data/spells.json) and
// their gamemode blocks with CRLF whatever line ending the file already had,
// the fault #1787 fixed in Build-OreTable.ps1 and #1622 in
// Build-RecipeTable.ps1. A Windows checkout hid it; a checkout that keeps LF
// (the agents' VM, the VPS runner's clones) got a whole-file diff of the table
// and CRLF lines inside an LF gamemode. They then took the ending of the file
// they found; since #3029 .gitattributes checks both files out with LF on every
// machine, so they write LF and take nothing from the file.
//
// This runs each builder against a small Data folder made here, from a copy of
// the builder beside a copy of the real gamemode, so the install step writes
// into the copy. An LF table and gamemode stay LF, nothing outside the blocks
// changes, a second run changes nothing, a CRLF table comes out LF, the blocks
// written into a CRLF gamemode are LF, and a new table is LF. Nothing outside a
// temporary folder is written.
const REPO_DIR = require("path").join(__dirname, "..");
const fs = require("fs");
const os = require("os");
const path = require("path");
const cp = require("child_process");
const CR = String.fromCharCode(13);

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log("PASS  " + what); }
  else { fail++; console.log("FAIL  " + what); }
}

const gmReal = fs.readFileSync(path.join(REPO_DIR, "game", "gamemode.js"), "utf8").split(CR).join("");
const harvestPs1 = fs.readFileSync(path.join(REPO_DIR, "scripts", "dev", "Build-HarvestTable.ps1"), "utf8");
const spellPs1 = fs.readFileSync(path.join(REPO_DIR, "scripts", "dev", "Build-SpellTable.ps1"), "utf8");

// ---- the scripts, read ----------------------------------------------------
for (const [name, s, installs] of [["Build-HarvestTable.ps1", harvestPs1, 4], ["Build-SpellTable.ps1", spellPs1, 1]]) {
  yes(name + " writes with LF, the same as Build-RecipeTable.ps1 and Build-OreTable.ps1",
    s.indexOf('$Eol = "`n"') >= 0 && s.indexOf("EolOf") < 0);
  yes(name + ": the table is joined with it",
    s.indexOf("$jsonEol = $Eol") >= 0 && s.indexOf("$json = ($docLines -join $jsonEol) + $jsonEol") >= 0);
  yes(name + ": every gamemode block is joined with it (" + installs + ")",
    (s.match(/\$eol = \$Eol\s+\$new = \$text\.Substring\(0, \$(m\.Index|a)\) \+ \(\(\$body -join \$eol\)\) \+ \$eol \+ \$text\.Substring\(\$b\)/g) || []).length === installs);
  yes(name + ": no CRLF is written anywhere", s.split('"`r`n"').length - 1 === 0);
}

// ---- plugin records ---------------------------------------------------------
function sub(tag, body) {
  const h = Buffer.alloc(6); h.write(tag, 0, "ascii"); h.writeUInt16LE(body.length, 4);
  return Buffer.concat([h, body]);
}
function rec(tag, fid, subs) {
  const body = Buffer.concat(subs);
  const h = Buffer.alloc(24); h.write(tag, 0, "ascii"); h.writeUInt32LE(body.length, 4); h.writeUInt32LE(fid, 12);
  return Buffer.concat([h, body]);
}
function grup(label, recs) {
  const body = Buffer.concat(recs);
  const h = Buffer.alloc(24); h.write("GRUP", 0, "ascii"); h.writeUInt32LE(body.length + 24, 4); h.write(label, 8, "ascii");
  return Buffer.concat([h, body]);
}
function z(s) { return Buffer.from(s + "\0", "ascii"); }
function u32(n) { const b = Buffer.alloc(4); b.writeUInt32LE(n, 0); return b; }
// not localised: the names sit in the records, so no string table is needed
function header() {
  const hedr = Buffer.alloc(12); hedr.writeFloatLE(1.7, 0);
  return rec("TES4", 0, [sub("HEDR", hedr)]);
}
const MASTERS = ["Skyrim.esm", "Update.esm", "Dawnguard.esm", "HearthFires.esm", "Dragonborn.esm"];

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "tw-1828-"));
// The text from a block's declaration to its end marker: what a run writes.
function written(t, open, close) { const a = t.indexOf(open), b = t.indexOf(close); return a < 0 || b < a ? null : t.slice(a, b); }
function pwshRun(ps1, args) {
  const r = cp.spawnSync("pwsh", ["-NoProfile", "-File", ps1].concat(args), { encoding: "utf8", timeout: 170000 });
  return { code: r.status, out: String(r.stdout || "") + String(r.stderr || "") };
}
// The builders install into ..\..\game\gamemode.js beside themselves, so each
// copy sits in a repository shape of its own.
function repoFor(name, ps1Text, extra) {
  const repo = path.join(tmp, name);
  fs.mkdirSync(path.join(repo, "scripts", "dev"), { recursive: true });
  fs.mkdirSync(path.join(repo, "game", "data"), { recursive: true });
  fs.mkdirSync(path.join(repo, "records"), { recursive: true });
  const ps1 = path.join(repo, "scripts", "dev", name);
  fs.writeFileSync(ps1, ps1Text);
  fs.copyFileSync(path.join(REPO_DIR, "scripts", "dev", "OwnPlugins.ps1"), path.join(repo, "scripts", "dev", "OwnPlugins.ps1"));
  for (const f of extra || []) { fs.copyFileSync(path.join(REPO_DIR, f), path.join(repo, f)); }
  return { repo: repo, ps1: ps1, gm: path.join(repo, "game", "gamemode.js") };
}
function blocks(t, names) {
  // everything outside the named blocks, so a run can be shown to touch nothing else
  let out = t;
  for (const n of names) {
    const m = new RegExp("^[ \\t]*var[ \\t]+" + n + "[ \\t]*=[ \\t]*\\{", "m").exec(out);
    const b = out.indexOf("// ==== end " + n + " ====");
    if (!m || b < 0) { return null; }
    out = out.slice(0, m.index) + "<" + n + ">" + out.slice(b);
  }
  return out;
}

try {
  const ver = cp.spawnSync("pwsh", ["--version"], { encoding: "utf8" });
  yes("pwsh is on this machine, so the builders can be run", !ver.error && ver.status === 0);
  if (!ver.error && ver.status === 0) {

    // ======================= Build-HarvestTable.ps1 ===========================
    // One of every row the builder insists on: a plant a novice gatherer may
    // pick, every record named in the fish, game, prop, stays and farmyard
    // knobs, and a crop on the farm ladder. Read off the script so the test
    // follows the knobs rather than a copy of them.
    function knobList(name) {
      const m = new RegExp("\\$" + name + " = @\\(([\\s\\S]*?)\\)\\r?\\n").exec(harvestPs1);
      return m ? (m[1].match(/'([^']+)'/g) || []).map(function (s) { return s.slice(1, -1); }) : [];
    }
    const fishIds = knobList("FISH_BY_EDITOR_ID");
    const gameIds = knobList("GAME_BY_EDITOR_ID");
    const propIds = knobList("FOOD_PROP_BY_EDITOR_ID");
    const staysIds = knobList("FOOD_STAYS_THE_GATHERERS");
    const yardIds = knobList("FARMYARD_BY_EDITOR_ID");
    yes("the harvest knobs read: " + fishIds.length + " fish, " + gameIds.length + " game, " + propIds.length + " props, " +
      staysIds.length + " stays, " + yardIds.length + " farmyard",
      fishIds.length > 10 && gameIds.length > 2 && propIds.length > 0 && staysIds.length > 0 && yardIds.length > 0);

    const INGR = 0x800, FOOD = 0x801;
    function ingr(fid, edid, name, value) {
      const data = Buffer.alloc(8); data.writeUInt32LE(value, 0); data.writeFloatLE(0.1, 4);
      return rec("INGR", fid, [sub("EDID", z(edid)), sub("FULL", z(name)), sub("DATA", data)]);
    }
    function food(fid, edid, name, value) {
      const enit = Buffer.alloc(20); enit.writeUInt32LE(value, 0); enit.writeUInt32LE(0x2, 4);
      return rec("ALCH", fid, [sub("EDID", z(edid)), sub("FULL", z(name)), sub("DATA", Buffer.from([0, 0, 0, 0])), sub("ENIT", enit)]);
    }
    let fid = 0x1000;
    function flor(edid, produce) {
      return rec("FLOR", fid++, [sub("EDID", z(edid)), sub("FULL", z(edid)), sub("PFIG", u32(produce))]);
    }
    const flora = [flor("TestFlower01", INGR), flor("TreeFloraCabbage01", FOOD)];
    for (const e of fishIds) { flora.push(flor(e, INGR)); }
    for (const e of gameIds.concat(propIds, staysIds)) { flora.push(flor(e, FOOD)); }
    for (const e of yardIds) { flora.push(flor(e, INGR)); }
    const hData = path.join(tmp, "HarvestData");
    fs.mkdirSync(hData);
    fs.writeFileSync(path.join(hData, "Skyrim.esm"), Buffer.concat([header(),
      grup("INGR", [ingr(INGR, "TestIngr", "Test Petal", 1)]),
      grup("ALCH", [food(FOOD, "TestCabbage", "Cabbage", 2)]),
      grup("FLOR", flora)]));
    for (const m of MASTERS.slice(1)) { fs.writeFileSync(path.join(hData, m), header()); }
    const hList = path.join(tmp, "plugins.txt");
    fs.writeFileSync(hList, "# Automatically generated by Vortex\r\n");

    const H = repoFor("Build-HarvestTable.ps1", harvestPs1, ["game/data/stations.json", "records/update-creation-club.json"]);
    const hOut = path.join(H.repo, "game", "data", "harvests.json");
    const HB = ["HARVESTS_BY_BASE", "CROPS_BY_BASE", "FISH_BY_BASE", "GAME_BY_BASE"];
    function harvest() { return pwshRun(H.ps1, ["-Data", hData, "-PluginList", hList, "-Out", hOut]); }

    // an LF checkout: the table and the real gamemode, both LF
    fs.writeFileSync(H.gm, gmReal);
    fs.writeFileSync(hOut, "{\n  \"old\": true\n}\n");
    const h1 = harvest();
    yes("a harvest run against the small Data folder writes the table and the four blocks (exit " + h1.code + ")",
      h1.code === 0 && /wrote .*harvests\.json \(\d+ plants/.test(h1.out) &&
      /into the HARVESTS_BY_BASE block/.test(h1.out) && /into the CROPS_BY_BASE block/.test(h1.out) &&
      /into the FISH_BY_BASE block/.test(h1.out) && /into the GAME_BY_BASE block/.test(h1.out));
    if (h1.code !== 0) { console.log(h1.out.split("\n").filter(function (l) { return /FAIL|rror/.test(l); }).slice(0, 30).join("\n")); }
    const ht1 = fs.readFileSync(hOut, "utf8");
    const hg1 = fs.readFileSync(H.gm, "utf8");
    yes("an LF harvests.json stays LF", ht1.indexOf(CR) < 0 && ht1.indexOf("\n") >= 0);
    yes("the rank rows and the detail rows inside it are LF too",
      /"novice": 1,\n    "advanced"/.test(ht1) && /"rank": "novice",\n      "produce"/.test(ht1));
    let hdoc = null;
    try { hdoc = JSON.parse(ht1); } catch (e) { hdoc = null; }
    yes("the table parses and holds the novice plant", !!hdoc && hdoc.harvests && hdoc.harvests["1000:Skyrim.esm"] &&
      hdoc.harvests["1000:Skyrim.esm"].rank === "novice");
    yes("an LF gamemode stays LF after the four blocks", hg1.indexOf(CR) < 0);
    yes("the blocks hold what was built",
      hg1.indexOf('"1000:Skyrim.esm": { "produce": "800:Skyrim.esm"') >= 0 && hg1.indexOf('"1001:Skyrim.esm"') >= 0);
    yes("nothing outside the four blocks changed", blocks(hg1, HB) !== null && blocks(hg1, HB) === blocks(gmReal, HB));
    const h2 = harvest();
    yes("a second harvest run changes neither file", h2.code === 0 &&
      fs.readFileSync(hOut, "utf8") === ht1 && fs.readFileSync(H.gm, "utf8") === hg1);

    // a checkout from before .gitattributes: both CRLF
    const smallGm = ["// head"];
    for (const n of HB) { smallGm.push("var " + n + " = {", "  \"old\": 1", "};", "", "// ==== end " + n + " ===="); }
    smallGm.push("// tail", "");
    fs.writeFileSync(H.gm, smallGm.join("\r\n"));
    fs.writeFileSync(hOut, "{\r\n  \"old\": true\r\n}\r\n");
    const h3 = harvest();
    yes("a CRLF harvests.json comes out LF", h3.code === 0 && fs.readFileSync(hOut, "utf8") === ht1);
    const hg3 = fs.readFileSync(H.gm, "utf8");
    yes("the four blocks written into a CRLF gamemode are LF", h3.code === 0 &&
      hg3.indexOf('"1000:Skyrim.esm"') >= 0 && hg3.indexOf('"old"') < 0 &&
      HB.every(function (n) { const w = written(hg3, "var " + n + " = {", "// ==== end " + n + " ===="); return w !== null && w.indexOf(CR) < 0; }));

    // no table yet: LF as well
    fs.unlinkSync(hOut);
    const h4 = harvest();
    yes("a new harvests.json is written with LF", h4.code === 0 && fs.readFileSync(hOut, "utf8") === ht1);

    // ======================= Build-SpellTable.ps1 =============================
    // Two spells in a book of its own, each taught by a tome, in one master.
    function spel(f, edid, name) {
      const spit = Buffer.alloc(36); spit.writeUInt32LE(14, 0); spit.writeUInt32LE(0, 8); spit.writeUInt32LE(1, 16); spit.writeUInt32LE(2, 20);
      return rec("SPEL", f, [sub("EDID", z(edid)), sub("FULL", z(name)), sub("SPIT", spit)]);
    }
    function tome(f, edid, spell) {
      const data = Buffer.alloc(16); data[0] = 0x04; data.writeUInt32LE(spell, 4);
      return rec("BOOK", f, [sub("EDID", z(edid)), sub("DATA", data)]);
    }
    const sData = path.join(tmp, "SpellData");
    fs.mkdirSync(sData);
    fs.writeFileSync(path.join(sData, "Skyrim.esm"), Buffer.concat([header(),
      grup("SPEL", [spel(0x12fcd, "Flames", "Flames"), spel(0x2b96b, "Sparks", "Sparks")]),
      grup("BOOK", [tome(0x2000, "SpellTomeFlames", 0x12fcd), tome(0x2001, "SpellTomeSparks", 0x2b96b)])]));
    const S = repoFor("Build-SpellTable.ps1", spellPs1, []);
    const book = path.join(tmp, "book.js");
    fs.writeFileSync(book, ["var DATA = {", "    spells: {", "      schools: {",
      "        destruction: { novice: ['Flames', 'Sparks'] }", "      }", "    },", "};", ""].join("\n"));
    const sOut = path.join(S.repo, "game", "data", "spells.json");
    function spells() { return pwshRun(S.ps1, ["-Data", sData, "-Book", book, "-Out", sOut, "-Plugins", "Skyrim.esm"]); }

    fs.writeFileSync(S.gm, gmReal);
    fs.writeFileSync(sOut, "{\n  \"old\": true\n}\n");
    const s1 = spells();
    yes("a spell run against the small Data folder writes the table and the block (exit " + s1.code + ")",
      s1.code === 0 && /wrote .*spells\.json \(2 spells/.test(s1.out) && /wrote 2 spells into the SPELL_IDS block/.test(s1.out));
    if (s1.code !== 0) { console.log(s1.out.split("\n").filter(function (l) { return /FAIL|rror/.test(l); }).slice(0, 30).join("\n")); }
    const st1 = fs.readFileSync(sOut, "utf8");
    const sg1 = fs.readFileSync(S.gm, "utf8");
    yes("an LF spells.json stays LF", st1.indexOf(CR) < 0 && st1.indexOf("\n") >= 0);
    yes("the detail rows inside it are LF too", /"desc": "12fcd:Skyrim.esm",\n      "editorId"/.test(st1));
    let sdoc = null;
    try { sdoc = JSON.parse(st1); } catch (e) { sdoc = null; }
    yes("the table parses and holds the two spells", !!sdoc && sdoc.count === 2 && sdoc.spells.Sparks === "2b96b:Skyrim.esm");
    yes("an LF gamemode stays LF after SPELL_IDS", sg1.indexOf(CR) < 0);
    yes("the block holds the two spells", sg1.indexOf('    "Flames": "12fcd:Skyrim.esm",\n    "Sparks": "2b96b:Skyrim.esm"\n  };') >= 0);
    const ga = gmReal.indexOf("  var SPELL_IDS = {"), gb = gmReal.indexOf("  // ==== end SPELL_IDS ====");
    const sa = sg1.indexOf("  var SPELL_IDS = {"), sb = sg1.indexOf("  // ==== end SPELL_IDS ====");
    yes("nothing outside the SPELL_IDS block changed", ga >= 0 && sa >= 0 &&
      sg1.slice(0, sa) === gmReal.slice(0, ga) && sg1.slice(sb) === gmReal.slice(gb));
    const s2 = spells();
    yes("a second spell run changes neither file", s2.code === 0 &&
      fs.readFileSync(sOut, "utf8") === st1 && fs.readFileSync(S.gm, "utf8") === sg1);

    fs.writeFileSync(S.gm, ["// head", "  var SPELL_IDS = {", "    \"old\": 1", "  };", "", "  // ==== end SPELL_IDS ====", "// tail", ""].join("\r\n"));
    fs.writeFileSync(sOut, "{\r\n  \"old\": true\r\n}\r\n");
    const s3 = spells();
    yes("a CRLF spells.json comes out LF", s3.code === 0 && fs.readFileSync(sOut, "utf8") === st1);
    const sg3 = fs.readFileSync(S.gm, "utf8");
    const sw3 = written(sg3, "  var SPELL_IDS = {", "  // ==== end SPELL_IDS ====");
    yes("the SPELL_IDS block written into a CRLF gamemode is LF", s3.code === 0 &&
      sg3.indexOf('"Flames": "12fcd:Skyrim.esm"') >= 0 && sw3 !== null && sw3.indexOf(CR) < 0);

    fs.unlinkSync(sOut);
    const s4 = spells();
    yes("a new spells.json is written with LF", s4.code === 0 && fs.readFileSync(sOut, "utf8") === st1);
  }
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}

console.log("");
console.log(pass + " passed, " + fail + " failed");
process.exit(fail ? 1 : 0);
