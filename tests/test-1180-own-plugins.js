// test-1180-own-plugins.js
//
// #1180. The launcher's Fix fetched the server's copy of any plugin whose
// bytes differed, and the server handed out every plugin in its load order
// but Bethesda's five masters: measured on 5 Oct, 43 plugins on the main and
// the dev server alike, 42 of them other authors' mods. Now the server serves
// Thornswood's own plugin and nothing else, names it in the manifest's
// "served" list, and the launcher fetches only what that list names; for
// another author's plugin Scan and Fix name the mod to put right in Vortex.
//
// The gamemode's server manifest block is run here against a pretend disk.
// The launcher cannot be compiled here, so its half is held by its text.
//
// Read only.
const REPO_DIR = require("path").join(__dirname, "..");
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const CR = String.fromCharCode(13);
function read() {
  return fs.readFileSync(path.join.apply(path, [REPO_DIR].concat([].slice.call(arguments))), "utf8").split(CR).join("");
}
const gm = read("game", "gamemode.js");
const verify = read("launcher", "app", "Verify.cs");
const ownGame = read("launcher", "app", "OwnGame.cs");
const rules = read("scripts", "release", "Ship-Rules.ps1");

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

// ------------------------------------------------ the gamemode's half

const block = slice(gm, "// ==== thornswood server manifest ====", "// ==== end thornswood server manifest ====");
yes("the server manifest block is in the gamemode", block !== null);

// The live load order's shape on 5 Oct, shortened: Bethesda's five, other
// authors' mods, ours (position 30 there), and more of theirs after it.
const BETHESDA = ["Skyrim.esm", "Update.esm", "Dawnguard.esm", "HearthFires.esm", "Dragonborn.esm"];
const THEIRS = ["Water for ENB.esm", "Embers XD.esm", "RaceCompatibility.esm", "JKs Skyrim.esp",
                "WindhelmSSE.esp", "Cloaks&Capes.esp", "UIExtensions.esp"];
const AFTER = ["Populated Cities Towns Villages Legendary.esp", "Playable Rieklings.esp"];
const ORDER = BETHESDA.concat(THEIRS, ["Thornswood-Content.esp"], AFTER);
const OUR_AT = ORDER.indexOf("Thornswood-Content.esp");

// A pretend disk: a flat map of normalised path to { data, links }.
function disk(opts) {
  opts = opts || {};
  const files = {};
  const dirs = {};
  const log = [];
  const links = [];
  function norm(p) { return path.posix.normalize(String(p).split("\\").join("/")); }
  function put(p, data) { files[norm(p)] = data; dirs[path.posix.dirname(norm(p))] = true; }
  const mods = ORDER.map(function (n, i) { return { filename: n, size: 1000 + i, crc32: i }; });
  mods.splice(6, 0, { filename: "Embers XD - Textures.bsa", size: 5, crc32: 5 });
  // A server that loads light plugins (#1715) publishes them apart, in
  // light index order; #2627 serves ours among them.
  const light = (opts.light || []).map(function (n, i) { return { filename: n, size: 2000 + i, crc32: 100 + i }; });
  const whole = ORDER.concat(opts.light || []);
  const doc = { versionMajor: 1, mods: mods, loadOrder: whole };
  if (opts.light) { doc.light = light; }
  put("data/manifest.json", JSON.stringify(doc));
  const present = whole.filter(function (n) { return !(opts.without || []).includes(n); });
  put("server-settings.json", JSON.stringify({ dataDir: "data", loadOrder: whole.map(function (n) { return "/srv/thornswood/plugins/" + n; }) }));
  present.forEach(function (n) { put("/srv/thornswood/plugins/" + n, "bytes of " + n); });
  // What an older start published: every plugin but Bethesda's, by index.
  (opts.stale || []).forEach(function (f) { put("data/api/servers/thornswood/plugins/" + f, "old"); });
  const fake = {
    readFileSync: function (p) {
      const k = norm(p);
      if (!(k in files)) { const e = new Error("ENOENT: " + k); e.code = "ENOENT"; throw e; }
      return files[k];
    },
    writeFileSync: function (p, d) { put(p, String(d)); },
    existsSync: function (p) { return norm(p) in files || norm(p) in dirs; },
    mkdirSync: function (p) { dirs[norm(p)] = true; },
    readdirSync: function (p) {
      const k = norm(p);
      return Object.keys(files).filter(function (f) { return path.posix.dirname(f) === k; })
        .map(function (f) { return path.posix.basename(f); });
    },
    unlinkSync: function (p) {
      const k = norm(p);
      if ((opts.stuck || []).includes(path.posix.basename(k))) { throw new Error("EBUSY: resource busy"); }
      delete files[k];
    },
    linkSync: function (src, dst) {
      if (!(norm(src) in files)) { throw new Error("ENOENT"); }
      if (norm(dst) in files) { throw new Error("EEXIST"); }
      files[norm(dst)] = files[norm(src)];
      links.push([norm(src), norm(dst)]);
    },
    copyFileSync: function (src, dst) { files[norm(dst)] = files[norm(src)]; }
  };
  return { fs: fake, files: files, log: log, links: links };
}

function run(opts) {
  const d = disk(opts);
  const box = {
    require: function (name) { return name === "fs" ? d.fs : name === "path" ? path.posix : null; },
    console: { log: function () { d.log.push([].join.call(arguments, " ")); } },
    // The engine's whole-file write (#2740), onto the fake disk.
    mp: { writeFileWhole: function (p, text) { d.fs.writeFileSync(p, text); } },
    setInterval: function () { d.log.push("a retry was started"); return 0; },
    clearInterval: function () {}
  };
  box.globalThis = box;
  vm.runInNewContext(block, box);
  d.box = box;
  d.served = Object.keys(d.files).filter(function (f) { return f.indexOf("data/api/servers/thornswood/plugins/") === 0; })
    .map(function (f) { return path.posix.basename(f); }).sort();
  try { d.manifest = JSON.parse(d.files["data/api/servers/thornswood/manifest.json"]); } catch (e) { d.manifest = null; }
  return d;
}

if (block) {
  const everyOld = ORDER.map(function (n, i) { return i; }).filter(function (i) { return i >= 5; }).map(function (i) { return i + ".bin"; });
  const a = run({ stale: everyOld });

  yes("the manifest is published with the client's two fields as before (mods, loadOrder)",
      !!a.manifest && Array.isArray(a.manifest.mods) && a.manifest.mods.length === ORDER.length &&
      Array.isArray(a.manifest.loadOrder) && a.manifest.loadOrder.length === ORDER.length);
  yes("the archive entry is still left out of mods, so positions are the client's",
      !!a.manifest && a.manifest.mods.every(function (m) { return /\.(esp|esm|esl)$/i.test(m.filename); }) &&
      a.manifest.mods[OUR_AT].filename === "Thornswood-Content.esp");
  yes("the manifest names what the server hands out: Thornswood-Content.esp and nothing else",
      !!a.manifest && JSON.stringify(a.manifest.served) === JSON.stringify(["Thornswood-Content.esp"]));
  yes("the refusal block still gets every plugin the client is compared with",
      Array.isArray(a.box.__thornswoodManifestMods) && a.box.__thornswoodManifestMods.length === ORDER.length);
  yes("only our plugin is under /plugins/, at its manifest position (" + OUR_AT + ".bin): " + a.served.join(", "),
      a.served.length === 1 && a.served[0] === OUR_AT + ".bin");
  yes("it is a hard link to the server's own plugin file, not a second copy",
      a.links.length === 1 && a.links[0][0] === "/srv/thornswood/plugins/Thornswood-Content.esp" &&
      a.links[0][1] === "data/api/servers/thornswood/plugins/" + OUR_AT + ".bin");
  yes("every other author's plugin an older start published is taken off the box",
      THEIRS.concat(AFTER).every(function (n) { return a.served.indexOf(ORDER.indexOf(n) + ".bin") < 0; }));
  yes("Bethesda's masters are not served, as before",
      BETHESDA.every(function (n, i) { return a.served.indexOf(i + ".bin") < 0; }));
  yes("the log says one plugin of ours was published",
      a.log.some(function (l) { return /^\[thornswood\] 1 of our plugin files published at \/api\/servers\/thornswood\/plugins\//.test(l); }));
  yes("the manifest was there, so no retry ran", !a.log.includes("a retry was started"));

  const b = run({ stale: ["12.bin", "13.bin"], stuck: ["12.bin"] });
  yes("an older file that cannot be taken off is said, by name, as still served",
      b.log.some(function (l) { return /could not take 12\.bin off \/plugins\/, so it is still served: EBUSY/.test(l); }) &&
      b.served.indexOf("13.bin") < 0);

  const c = run({ without: ["Thornswood-Content.esp"] });
  yes("with our plugin not on the box nothing is served, and the log says one was not found",
      c.served.length === 0 && c.log.some(function (l) { return /0 of our plugin files published[\s\S]*1 not found on this box/.test(l); }));
  yes("and the manifest still names it, so the launcher says the server did not hand it over",
      !!c.manifest && JSON.stringify(c.manifest.served) === JSON.stringify(["Thornswood-Content.esp"]));

  // #2627: our light plugin is published too. On 16 Oct the server's light
  // order named Thornswood-Last.esp and nothing served it, so a machine
  // without it had nothing for Fix to fetch.
  const LIGHT = ["_ResourcePack.esl", "KhisartinBeards.esp", "Thornswood-Last.esp"];
  const d = run({ light: LIGHT });
  const lastAt = LIGHT.indexOf("Thornswood-Last.esp");
  yes("a server with a light list names our light plugin as served, beside our full one",
      !!d.manifest && JSON.stringify(d.manifest.served) === JSON.stringify(["Thornswood-Content.esp", "Thornswood-Last.esp"]));
  yes("it is published as light-" + lastAt + ".bin, its place in the light list, and our full one stays at its place in mods: " + d.served.join(", "),
      d.served.length === 2 && d.served.indexOf("light-" + lastAt + ".bin") >= 0 && d.served.indexOf(OUR_AT + ".bin") >= 0);
  yes("the light file is a hard link to the server's own Thornswood-Last.esp",
      d.links.some(function (l) { return l[0] === "/srv/thornswood/plugins/Thornswood-Last.esp" && l[1] === "data/api/servers/thornswood/plugins/light-" + lastAt + ".bin"; }));
  yes("another author's light plugin is not served", d.served.every(function (f) { return f === OUR_AT + ".bin" || f === "light-" + lastAt + ".bin"; }));
  yes("the log counts both of ours", d.log.some(function (l) { return /^\[thornswood\] 2 of our plugin files published at \/api\/servers\/thornswood\/plugins\//.test(l); }));
  yes("the client's own lists are as they were: mods the full plugins, light the light ones",
      !!d.manifest && d.manifest.mods.length === ORDER.length && Array.isArray(d.manifest.light) && d.manifest.light.length === LIGHT.length);

  const code = block.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");
  yes("the rule names what is ours, not what to leave out (no STOREFRONT list in the block)",
      !/STOREFRONT/.test(code) && /if \(!OURS\[name\.toLowerCase\(\)\]\) continue;/.test(code));
}

// ------------------------------------------------ one list of ours

{
  const m = /var OURS = \{([^}]*)\};/.exec(gm);
  const inGamemode = m ? m[1].split(",").map(function (s) { return s.split(":")[0].trim().replace(/^'|'$/g, ""); })
    .filter(Boolean).sort() : [];
  const list = /\$ShipOursFiles = @\(([\s\S]*?)\n\)/.exec(rules);
  const inRules = list ? (list[1].replace(/#.*$/gm, "").match(/'[^']+'/g) || [])
    .map(function (s) { return s.slice(1, -1); })
    .filter(function (p) { return /^Data\\[^\\]+\.(esp|esm|esl)$/i.test(p); })
    .map(function (p) { return p.slice(5).toLowerCase(); }).sort() : [];
  yes("Ship-Rules.ps1 names our plugins in $ShipOursFiles (" + inRules.join(", ") + ")", inRules.length > 0);
  yes("the gamemode serves exactly the plugins Ship-Rules.ps1 calls ours (" + inGamemode.join(", ") + ")",
      inGamemode.length > 0 && JSON.stringify(inGamemode) === JSON.stringify(inRules));
}

// ------------------------------------------------ the launcher's half

{
  yes("Verify reads the manifest's served list", /\[DataMember\] public string\[\] served;/.test(verify));
  yes("Manifest marks each plugin served or not from that list, and nothing else sets it",
      /m\.Served = served\.Contains\(m\.filename\);/.test(verify) &&
      (verify.match(/\bm\.Served = /g) || []).length === 1);

  const fetch = slice(verify, "static bool FetchPlugin(Config cfg, Issue i, Action<string> say)", "\n        }\n");
  yes("FetchPlugin is in Verify.cs", !!fetch);
  if (fetch) {
    const guard = fetch.indexOf("if (!i.Served)");
    const get = fetch.indexOf("Get(ServerBase(cfg) + \"/plugins/\"");
    yes("FetchPlugin refuses a plugin the server does not serve before it asks the server for anything",
        guard > 0 && get > guard && /if \(!i\.Served\)\s*\{[^}]*FromVortex\(cfg, i\.Plugin\)[^}]*return false;\s*\}/.test(fetch));
  }
  const gets = verify.match(/"\/plugins\/"/g) || [];
  yes("the one place the launcher asks for /plugins/ is FetchPlugin's", gets.length === 1 && !!fetch && /"\/plugins\/"/.test(fetch));
  const others = fs.readdirSync(path.join(REPO_DIR, "launcher", "app")).filter(function (f) { return /\.cs$/.test(f) && f !== "Verify.cs"; })
    .filter(function (f) { return /\/plugins\/"|\/plugins\/" \+/.test(read("launcher", "app", f)); });
  yes("no other launcher file fetches from /plugins/" + (others.length ? " (" + others.join(", ") + ")" : ""), others.length === 0);

  const bytes = slice(verify, "public static List<Issue> Bytes(Config cfg)", "\n        }\n");
  yes("Scan carries served on each issue and names Vortex for another author's plugin",
      !!bytes && /i\.Served = m\.Served;/.test(bytes) &&
      /m\.Served \? "Fix fetches the server's copy\." : null,/.test(bytes) &&
      /m\.Served \? NotHandedOver : FromVortex\(cfg, m\.filename\)/.test(bytes));
  // #2627: a light plugin of ours is served too, at light-<index in light>.bin.
  yes("Scan says where a light plugin of ours is served: its place in the light list",
      !!bytes && /i\.WantLight = isLight;/.test(bytes) && /i\.WantIndex = isLight \? idx - mods\.Length : idx;/.test(bytes));
  yes("Manifest marks served on the light list as well as mods",
      /foreach \(ServerMod\[\] list in new ServerMod\[\]\[\] \{ doc\.mods, light \}\)/.test(verify));
  yes("FetchPlugin asks for light-<index>.bin for a light plugin and <index>.bin for a full one",
      !!fetch && /"\/plugins\/" \+ \(i\.WantLight \? "light-" : ""\) \+ i\.WantIndex \+ "\.bin"/.test(fetch));

  const fix = slice(verify, "public static int Fix(Config cfg, Action<string> say)", "\n        }\n");
  yes("Fix's fetch of a missing plugin passes over any the server does not serve",
      !!fix && /Storefront\.Contains\(m\.filename\) \|\| !m\.Served\) continue;/.test(fix) &&
      /miss\.Served = true;\s*if \(FetchPlugin\(cfg, miss, say\)\) n\+\+;/.test(fix));
  yes("Fix fetches a missing plugin of ours from the light list as well as mods",
      !!fix && /int all = mods\.Length \+ light\.Length;/.test(fix) && /miss\.WantLight = isLight;/.test(fix));
  yes("Fix's fetch of a plugin that differs goes through FetchPlugin with Scan's issue",
      !!fix && /foreach \(Issue i in Bytes\(cfg\)\)\s*if \(i\.Plugin != null && FetchPlugin\(cfg, i, say\)\) n\+\+;/.test(fix));

  const from = slice(verify, "static string FromVortex(Config cfg, string plugin)", "\n        }\n");
  yes("what to do about another author's plugin names the mod in Vortex and says to update or reinstall it",
      !!from && /OwnGame\.VortexModOf\(cfg, plugin\)/.test(from) &&
      /update the Thornswood collection, or reinstall/.test(from) && /Reinstall\), then press Scan\./.test(from) &&
      /the server does not hand it out/.test(from));
  const mod = slice(ownGame, "public static string VortexModOf(Config cfg, string plugin)", "\n        }\n");
  yes("OwnGame.VortexModOf reads Vortex's own deployment record for the plugin's mod folder",
      !!mod && /Staged\(src\)\.From\.TryGetValue\("Data\\\\" \+ plugin, out from\)/.test(mod) &&
      /Path\.GetFileName\(Path\.GetDirectoryName\(from\)\)/.test(mod));
  yes("and it writes nothing", !!mod && !/File\.(Write|Copy|Move|Delete)|Directory\.(Create|Delete|Move)/.test(mod));
}

// ------------------------------------------------ what people read

{
  const help = read("launcher", "app", "Help.cs");
  const join = read("site", "data", "site", "join.md");
  const known = require("./fixtures/known-page").knownPage() || "";  // the page /known writes, from the bot's list (#3140)
  const md = read("site", "data", "help.md");
  yes("the launcher's help says Fix fetches only our own plugin and names the Vortex mod for another's",
      /downloads the server's copy of Thornswood's own plugin when its bytes differ, names the mod to update or reinstall in Vortex when another author's plugin differs/.test(help));
  yes("the LOAD ORDER ERROR help no longer says nothing in Vortex has to change",
      !/Nothing in Vortex has to change/.test(help) && /Scan names the mod to update or reinstall in Vortex/.test(help));
  yes("the join page says the same", /For Thornswood's own plugin \*\*Fix\*\* downloads the server's copy; for\s+another author's mod it names the mod to update or reinstall in Vortex\./.test(join));
  yes("the known issues page leaves the load order to the help (#3137)", known.length > 0 && !/LOAD ORDER ERROR/.test(known));
  yes("the site's help says the same", /the server hands out Thornswood's own plugin\s+and nobody else's/.test(md));
  yes("nothing people read still says Fix downloads the server's copy of any plugin",
      [help, join, known, md].every(function (t) { return !/server's copy of\s+(any|that) plugin/.test(t); }));
}

console.log("");
console.log(pass + " passed, " + fail + " failed");
process.exit(fail ? 1 : 0);
