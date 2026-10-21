// test-1787-ore-eol.js
//
// #1787. scripts/dev/Build-OreTable.ps1 joined game/data/ores.json and the
// ORES_BY_BASE block of game/gamemode.js with CRLF whatever line ending the
// file already had. A Windows checkout hid it; a checkout that keeps LF (the
// agents' VM, the VPS runner's clones) got a whole-file diff of ores.json and
// CRLF lines inside an LF gamemode. #1622 fixed the same fault in
// Build-RecipeTable.ps1 and #1713 in Build-BenchTable.py, by taking the ending
// of the file found. Since #3029 .gitattributes checks both files out with LF
// on every machine, so the builder writes LF and takes nothing from the file.
//
// This runs the builder against a small Data folder made here (two ores, two
// veins) and a copy of the builder beside a copy of the real gamemode, so the
// install step writes into the copy. An LF table and gamemode stay LF, a CRLF
// table comes out LF, the block it writes into a CRLF gamemode is LF, a new
// table is LF, and a second run changes nothing. Nothing outside a temporary
// folder is written.
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

const OPEN = "  var ORES_BY_BASE = {";
const CLOSE = "  // ==== end ORES_BY_BASE ====";
const script = fs.readFileSync(path.join(REPO_DIR, "scripts", "dev", "Build-OreTable.ps1"), "utf8");
const gmReal = fs.readFileSync(path.join(REPO_DIR, "game", "gamemode.js"), "utf8").split(CR).join("");

// ---- the script, read ----------------------------------------------------
yes("Build-OreTable.ps1 writes with LF, the same as Build-RecipeTable.ps1",
  script.indexOf('$Eol = "`n"') >= 0 && script.indexOf("EolOf") < 0);
yes("the table is joined with it",
  script.indexOf("$jsonEol = $Eol") >= 0 && script.indexOf("$json = ($docLines -join $jsonEol) + $jsonEol") >= 0);
yes("and the detail rows inside it as well", script.indexOf("$docLines.Add(($fields -join (',' + $jsonEol)))") >= 0);
yes("the gamemode block is joined with it",
  script.indexOf("$new = $text.Substring(0, $a) + (($body -join $eol)) + $eol + $text.Substring($b)") >= 0 &&
  /\$eol = \$Eol\s+\$new = \$text\.Substring\(0, \$a\)/.test(script));
yes("no CRLF is written anywhere", script.split('"`r`n"').length - 1 === 0);

// ---- a plugin with two ores and two veins --------------------------------
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
function header() {
  const hedr = Buffer.alloc(12); hedr.writeFloatLE(1.7, 0);
  return rec("TES4", 0, [sub("HEDR", hedr)]);
}
function wstr(s) { const b = Buffer.alloc(2); b.writeUInt16LE(s.length, 0); return Buffer.concat([b, Buffer.from(s, "ascii")]); }
// VMAD version 5, object format 2: MineOreScript with one object property, Ore.
function vmad(oreFid) {
  const head = Buffer.alloc(6); head.writeInt16LE(5, 0); head.writeInt16LE(2, 2); head.writeUInt16LE(1, 4);
  const count = Buffer.alloc(2); count.writeUInt16LE(1, 0);
  const obj = Buffer.alloc(8); obj.writeUInt32LE(oreFid, 4);
  return Buffer.concat([head, wstr("MineOreScript"), Buffer.from([0]), count, wstr("Ore"), Buffer.from([1, 0]), obj]);
}
function misc(fid, edid, name, value) {
  const data = Buffer.alloc(8); data.writeUInt32LE(value, 0); data.writeFloatLE(1, 4);
  return rec("MISC", fid, [sub("EDID", z(edid)), sub("FULL", z(name)), sub("DATA", data)]);
}
function vein(fid, edid, oreFid) {
  return rec("ACTI", fid, [sub("EDID", z(edid)), sub("VMAD", vmad(oreFid)), sub("FULL", z(edid))]);
}

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "tw-1787-"));
try {
  const data = path.join(tmp, "Data");
  fs.mkdirSync(data);
  // DLC2HeartStone is one of them because RANK_BY_ORE names it, and a build
  // without it stops rather than writing.
  fs.writeFileSync(path.join(data, "Skyrim.esm"), Buffer.concat([header(),
    grup("MISC", [misc(0x800, "OreIron", "Iron Ore", 2), misc(0x801, "DLC2HeartStone", "Heart Stone", 100)]),
    grup("ACTI", [vein(0x900, "MineOreIron01", 0x800), vein(0x901, "MineOreHeartStone01", 0x801)])]));
  ["Update.esm", "Dawnguard.esm", "HearthFires.esm", "Dragonborn.esm"].forEach(function (m) {
    fs.writeFileSync(path.join(data, m), header());
  });
  const pluginsTxt = path.join(tmp, "plugins.txt");
  fs.writeFileSync(pluginsTxt, "# Automatically generated by Vortex\r\n");

  // The builder installs into ..\..\game\gamemode.js beside itself, so a copy
  // of it sits in a repository shape of its own here.
  const repo = path.join(tmp, "repo");
  fs.mkdirSync(path.join(repo, "scripts", "dev"), { recursive: true });
  fs.mkdirSync(path.join(repo, "game", "data"), { recursive: true });
  const ps1 = path.join(repo, "scripts", "dev", "Build-OreTable.ps1");
  fs.writeFileSync(ps1, script);
  fs.copyFileSync(path.join(REPO_DIR, "scripts", "dev", "OwnPlugins.ps1"), path.join(repo, "scripts", "dev", "OwnPlugins.ps1"));
  const gm = path.join(repo, "game", "gamemode.js");
  const out = path.join(repo, "game", "data", "ores.json");

  const ver = cp.spawnSync("pwsh", ["--version"], { encoding: "utf8" });
  yes("pwsh is on this machine, so the ore builder can be run", !ver.error && ver.status === 0);
  function build() {
    const r = cp.spawnSync("pwsh", ["-NoProfile", "-File", ps1, "-Data", data, "-PluginsTxt", pluginsTxt, "-Out", out],
      { encoding: "utf8", timeout: 120000 });
    return { code: r.status, out: String(r.stdout || "") + String(r.stderr || "") };
  }
  function block(t) { const a = t.indexOf(OPEN); const b = t.indexOf(CLOSE); return a < 0 || b < 0 ? null : t.slice(a, b); }
  function outside(t) { return t.slice(0, t.indexOf(OPEN)) + t.slice(t.indexOf(CLOSE)); }

  if (!ver.error && ver.status === 0) {
    // ---- an LF checkout: the table and the real gamemode, both LF ----------
    fs.writeFileSync(gm, gmReal);
    fs.writeFileSync(out, "{\n  \"old\": true\n}\n");
    const r = build();
    yes("a run against the small Data folder writes the table and the block (exit " + r.code + ")",
      r.code === 0 && /wrote .*ores\.json \(2 veins/.test(r.out) && /wrote 2 veins into the ORES_BY_BASE block/.test(r.out));
    if (r.code !== 0) { console.log(r.out.split("\n").slice(-30).join("\n")); }
    const t1 = fs.readFileSync(out, "utf8");
    const g1 = fs.readFileSync(gm, "utf8");
    yes("an LF ores.json stays LF", t1.indexOf(CR) < 0 && t1.indexOf("\n") >= 0);
    yes("the detail rows inside it are LF too", /"editorId": "MineOreIron01",\n      "plugin"/.test(t1));
    let doc = null;
    try { doc = JSON.parse(t1); } catch (e) { doc = null; }
    yes("the table parses and holds the two veins", !!doc && doc.count === 2 &&
      !!doc.ores["900:Skyrim.esm"] && doc.ores["900:Skyrim.esm"].ore === "800:Skyrim.esm");
    yes("an LF gamemode stays LF", g1.indexOf(CR) < 0);
    yes("the block holds the two veins", (block(g1) || "").indexOf('"901:Skyrim.esm": { "ore": "801:Skyrim.esm"') >= 0);
    yes("nothing outside the ORES_BY_BASE block changed", outside(g1) === outside(gmReal));
    const r2 = build();
    yes("a second run changes neither file", r2.code === 0 &&
      fs.readFileSync(out, "utf8") === t1 && fs.readFileSync(gm, "utf8") === g1);

    // ---- a checkout from before .gitattributes: both CRLF ------------------
    fs.writeFileSync(gm, ["// head", OPEN, "    old", "  };", "", CLOSE, "// tail", ""].join("\r\n"));
    fs.writeFileSync(out, "{\r\n  \"old\": true\r\n}\r\n");
    const r3 = build();
    yes("a CRLF ores.json comes out LF", r3.code === 0 && fs.readFileSync(out, "utf8").indexOf(CR) < 0 &&
      fs.readFileSync(out, "utf8") === t1);
    const g3 = fs.readFileSync(gm, "utf8");
    yes("the block written into a CRLF gamemode is LF", r3.code === 0 &&
      g3.indexOf('"900:Skyrim.esm"') >= 0 && (block(g3) || CR).indexOf(CR) < 0);

    // ---- no table yet: LF as well ------------------------------------------
    fs.unlinkSync(out);
    const r4 = build();
    yes("a new ores.json is written with LF", r4.code === 0 && fs.readFileSync(out, "utf8") === t1);
  }
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}

console.log("");
console.log(pass + " passed, " + fail + " failed");
process.exit(fail ? 1 : 0);
