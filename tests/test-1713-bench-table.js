// test-1713-bench-table.js
//
// #1713. scripts/dev/Build-BenchTable.py rewrites everything between the
// BENCH_ACCESS markers in game/gamemode.js. Three faults made a run unsafe:
//
// - The race gate (raceIndex, raceOf, RACE_CALLED, raceGate) sat inside those
//   markers, so a run deleted it, and craftAnswer calls raceGate.
// - It set a bench open for everybody only when the bench held a row nobody
//   owned. #1391 moved every cookpot row nobody owned into the refused map, so
//   a run shut the cookpot, which docs/systems/professions.md calls open
//   furniture. The page's open furniture is now a knob, OPEN_FURNITURE.
// - It wrote both blocks with CRLF whatever the gamemode held, so on a
//   checkout that keeps LF a run left two CRLF blocks in an LF file.
//
// #1384 took the armour table out of the open furniture: tempering is cut, so
// it and the sharpening wheel are shut for everybody (SHUT_BENCHES, held by
// tests/test-1384-shut-benches.js). The page names five open benches now.
//
// This holds the gamemode's markers, the knob against the page, the table in
// the gamemode against the page, and runs the builder against a small plugin
// made here and a copy of the real gamemode. Nothing outside a temporary
// folder is written.
const REPO_DIR = require("path").join(__dirname, "..");
const fs = require("fs");
const os = require("os");
const path = require("path");
const cp = require("child_process");
const CR = String.fromCharCode(13);
function read(rel) { return fs.readFileSync(path.join(REPO_DIR, rel), "utf8"); }

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log("PASS  " + what); }
  else { fail++; console.log("FAIL  " + what); }
}
function between(src, open, close) {
  const a = src.indexOf(open);
  const b = src.indexOf(close, a < 0 ? 0 : a);
  return a < 0 || b < 0 ? null : src.slice(a + open.length, b);
}

const OPEN = "// ==== BENCH_ACCESS, generated ====";
const CLOSE = "// ==== end BENCH_ACCESS ====";
const BOPEN = "// ==== BENCH_BY_BASE, generated ====";
const BCLOSE = "// ==== end BENCH_BY_BASE ====";
const gmRaw = read("game/gamemode.js");
const gm = gmRaw.split(CR).join("");
const py = read("scripts/dev/Build-BenchTable.py").split(CR).join("");
const page = read("docs/systems/professions.md").split(CR).join("");

// ---- the race gate is outside the generated markers ----------------------
const inside = between(gm, OPEN, CLOSE);
const insideBase = between(gm, BOPEN, BCLOSE);
yes("the gamemode has one BENCH_ACCESS block", inside !== null && gm.split(OPEN).length === 2 && gm.split(CLOSE).length === 2);
yes("and one BENCH_BY_BASE block", insideBase !== null && gm.split(BOPEN).length === 2);
["var raceIndex", "function raceOf(", "var RACE_CALLED", "function raceGate("].forEach(function (name) {
  yes(name + " is in the gamemode, once", gm.split(name).length === 2);
  yes(name + " is outside the BENCH_ACCESS markers", !!inside && inside.indexOf(name) < 0);
  yes(name + " is outside the BENCH_BY_BASE markers", !!insideBase && insideBase.indexOf(name) < 0);
});
yes("craftAnswer still calls raceGate", /raceGate\(actorId, row\)/.test(gm.slice(gm.indexOf(CLOSE))));
yes("the BENCH_ACCESS block holds its comment and the table and nothing else",
  !!inside && /^\n\/\* Bench keyword -> who can make anything at it\.[\s\S]*?\*\/\nconst BENCH_ACCESS = \{.*\};\n$/.test(inside));

// ---- the knob is the page ------------------------------------------------
// The page's bench table: | Bench | Who |.
const rows = {};
const tbl = between(page, "| Bench | Who |", "\n\n") || "";
tbl.split("\n").forEach(function (l) {
  const m = /^\| ([^|]+?) \| ([^|]+?) \|$/.exec(l);
  if (m && m[1] !== "---") { rows[m[1]] = m[2]; }
});
const openRows = Object.keys(rows).filter(function (b) { return /^Open furniture\./.test(rows[b]); });
yes("the professions page names five benches open furniture", openRows.length === 5);
const knobSrc = between(py, "OPEN_FURNITURE = {", "\n}\n") || "";
const knob = {};
knobSrc.replace(/^\s+'([^']+)': '((?:[^'\\]|\\.)*)',$/gm, function (_, k, v) { knob[k] = v.replace(/\\'/g, "'"); return ""; });
yes("OPEN_FURNITURE names five benches", Object.keys(knob).length === 5);
openRows.forEach(function (b) {
  const want = b + ". " + rows[b];
  yes("OPEN_FURNITURE carries the page's line for the " + b.toLowerCase(),
    Object.keys(knob).some(function (k) { return knob[k] === want; }));
});
yes("anyone is set from OPEN_FURNITURE, after the rows nobody owns",
  /for bname in sorted\(OPEN_FURNITURE\):[\s\S]*?a\['anyone'\] = True/.test(py) &&
  py.indexOf("for row in unowned.values():") < py.indexOf("for bname in sorted(OPEN_FURNITURE):"));

// ---- the table in the gamemode is the page -------------------------------
let ACCESS = null;
try { ACCESS = JSON.parse(/const BENCH_ACCESS = (\{.*\});/.exec(gm)[1]); } catch (e) { ACCESS = null; }
yes("BENCH_ACCESS parses", !!ACCESS);
function byName(n) {
  for (const k in (ACCESS || {})) { if (ACCESS[k].name === n) { return ACCESS[k]; } }
  return null;
}
Object.keys(knob).forEach(function (n) {
  const b = byName(n);
  yes(n + " is in BENCH_ACCESS and opens for anybody", !!b && b.anyone === true);
});
const CLOSED = {
  "Oven": "BYOHCraftingOven", "Grain mill": "isGrainMill", "Charcoal kiln": "ThornswoodCraftingCharcoalKiln",
  "Alchemy lab": "the alchemy lab", "Arcane enchanter": "the arcane enchanter", "Staff enchanter": "DLC2StaffEnchanter",
  "Sharpening wheel": "CraftingSmithingSharpeningWheel", "Armour table": "CraftingSmithingArmorTable",
  "Skyforge": "CraftingSmithingSkyforge",
  "Dawnguard bench": "DLC1CraftingDawnguard"
};
Object.keys(CLOSED).forEach(function (p) {
  const b = byName(CLOSED[p]);
  yes("the page closes the " + p.toLowerCase() + " and so does the table", !!rows[p] && !/^Open furniture/.test(rows[p]) && !!b && b.anyone === false);
});
yes("the cookpot is Hearthcook's at novice behind its open door",
  !!byName("CraftingCookpot") && JSON.stringify(byName("CraftingCookpot").halves) === '{"hearthcook":"novice"}');

// ---- the builder, run ----------------------------------------------------
// A plugin with three keywords and three pieces of furniture: a cookpot and an
// oven by keyword, and an alchemy lab by its workbench type (5).
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
function header() {
  const hedr = Buffer.alloc(12); hedr.writeFloatLE(1.7, 0);
  return rec("TES4", 0, [sub("HEDR", hedr)]);
}
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "tw-1713-"));
try {
  const data = path.join(tmp, "Data");
  fs.mkdirSync(data);
  const skyrim = Buffer.concat([header(),
    grup("KYWD", [rec("KYWD", 0x800, [sub("EDID", z("CraftingCookpot"))]),
                  rec("KYWD", 0x801, [sub("EDID", z("BYOHCraftingOven"))])]),
    grup("FURN", [rec("FURN", 0x900, [sub("EDID", z("Cookpot01")), sub("KWDA", u32(0x800))]),
                  rec("FURN", 0x901, [sub("EDID", z("Oven01")), sub("KWDA", u32(0x801))]),
                  rec("FURN", 0x902, [sub("EDID", z("Lab01")), sub("WBDT", Buffer.from([5, 0]))])])]);
  fs.writeFileSync(path.join(data, "Skyrim.esm"), skyrim);
  ["Update.esm", "Dawnguard.esm", "HearthFires.esm", "Dragonborn.esm"].forEach(function (m) {
    fs.writeFileSync(path.join(data, m), header());
  });
  const pluginsTxt = path.join(tmp, "plugins.txt");
  fs.writeFileSync(pluginsTxt, "# Automatically generated by Vortex\r\n");
  const recipes = path.join(tmp, "recipes.json");
  fs.writeFileSync(recipes, JSON.stringify({
    recipes: {
      "a1:Skyrim.esm": { bench: "800:Skyrim.esm", benchName: "CraftingCookpot", half: "Hearthcook", rank: "novice" },
      "a2:Skyrim.esm": { bench: "801:Skyrim.esm", benchName: "BYOHCraftingOven", half: "Confectioner", rank: "novice" }
    },
    unowned: {}
  }));

  const pyCmd = ["python", "python3"].filter(function (c) {
    const r = cp.spawnSync(c, ["--version"], { encoding: "utf8" });
    return !r.error && r.status === 0;
  })[0];
  yes("python is on this machine, so the bench builder can be run", !!pyCmd);
  function build(gamemode) {
    const r = cp.spawnSync(pyCmd, [path.join(REPO_DIR, "scripts", "dev", "Build-BenchTable.py"),
      "--data", data, "--plugins", pluginsTxt, "--recipes", recipes, "--gamemode", gamemode], { encoding: "utf8", timeout: 120000 });
    return { code: r.status, out: String(r.stdout || "") + String(r.stderr || "") };
  }
  if (pyCmd) {
    // The real gamemode, as an LF file.
    const lf = path.join(tmp, "gamemode-lf.js");
    fs.writeFileSync(lf, gm);
    const r = build(lf);
    yes("a run into a copy of the gamemode writes both blocks (exit " + r.code + ")", r.code === 0 && /wrote 3 furniture base\(s\)/.test(r.out));
    const after = fs.readFileSync(lf, "utf8");
    yes("an LF gamemode stays LF", after.indexOf(CR) < 0);
    const outside = function (t) {
      return t.slice(0, t.indexOf(BOPEN)) + t.slice(t.indexOf(BCLOSE), t.indexOf(OPEN)) + t.slice(t.indexOf(CLOSE));
    };
    yes("nothing outside the two blocks changed, so the race gate is still there",
      outside(after) === outside(gm) && after.split("function raceGate(").length === 2);
    let A = null;
    try { A = JSON.parse(/const BENCH_ACCESS = (\{.*\});/.exec(after)[1]); } catch (e) { A = null; }
    yes("the cookpot holds no row nobody owns and still opens for anybody",
      !!A && !!A["800:Skyrim.esm"] && A["800:Skyrim.esm"].anyone === true);
    yes("the oven, which the page does not call open, stays shut",
      !!A && !!A["801:Skyrim.esm"] && A["801:Skyrim.esm"].anyone === false &&
      JSON.stringify(A["801:Skyrim.esm"].halves) === '{"confectioner":"novice"}');
    yes("the alchemy lab is placed by its workbench type", !!A && !!A.alchemy && A.alchemy.anyone === false);
    yes("the four open benches this plugin does not have are named, not invented",
      /4 bench\(es\) the professions page calls open furniture are not in this load order/.test(r.out) &&
      !!A && Object.keys(A).length === 3);
    const r2 = build(lf);
    yes("a second run changes nothing", r2.code === 0 && fs.readFileSync(lf, "utf8") === after);

    // A CRLF gamemode stays CRLF.
    const crlf = path.join(tmp, "gamemode-crlf.js");
    fs.writeFileSync(crlf, ["// head", BOPEN, "old", BCLOSE, "", OPEN, "old", CLOSE, "// tail", ""].join("\r\n"));
    const r3 = build(crlf);
    const t3 = fs.readFileSync(crlf, "utf8");
    yes("a CRLF gamemode stays CRLF", r3.code === 0 && t3.split("\n").length - 1 === t3.split("\r\n").length - 1);
  }
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}

console.log("");
console.log(pass + " passed, " + fail + " failed");
process.exit(fail ? 1 : 0);
