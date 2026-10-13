// test-known-npcs.js
//
// The Known Issues page says what is decided about NPCs, under a heading of
// its own, and promises nothing about them that nobody is building.
//
// From the To Do List, entry 324: "With the cast cut to traders and transport
// workers, there is no crowd left to simulate, so this stops being a
// world-scale AI problem and becomes making a dozen named characters behave
// properly ... Correct the known issues page either way, because it
// currently tells people this is permanent". The cut is entry 320, settled by
// Patrick on 17 September: "What survives: traders you can buy from and sell
// to through the custom economy in entry 214, and the carriage and ferry
// workers in entry 215. Everything else is either rebuilt as a custom
// character or removed."
//
// WHAT WAS MEASURED ON 24 SEPTEMBER. The live page, read from
// https://thornswood.net/api/page/known, is byte for byte the repo's copy at
// fe66c8c (22 September) once line endings are set aside, so nobody edited it
// on the site; it has not been deployed since. It still says the first group
// "is not going to change" and heads the NPC rows "They are not going to
// change". main took that promise off in 0cb16bc (entry 296), so the literal
// done line of 324's doc half was already true in the repo. What main still
// did was keep both NPC rows in the first group, "Limits of a shared Skyrim",
// under a lead that names two roadmap titles and says nothing about what was
// decided. The page's own opening says the first group follows from SkyMP and
// everything after it is where things stand today, and after 17 September
// NPCs are the second kind.
//
// WHAT IS NOT PROMISED. The roadmap's NPCs with their own work reads "Jobs,
// routines and errands of their own, then quests", and home.html's feature
// card says "getting jobs, routines and errands". None of that has any code
// in game/gamemode.js, and the routine half of entry 324 waits on entry 320's
// cast list. So nothing the page says about NPCs may mention routines,
// errands, schedules, jobs or quests, or give a date.
//
// The page is the known board in site/data/board.json, written out the way
// /known writes it (#2414). Set KNOWN to a saved copy of the page to check
// that instead, the live one from /api/page/known for instance. Read only.
const REPO_DIR = require('path').join(__dirname, '..'); // the tests are in tests\, the repository is one folder up
const fs = require('fs');
const path = require('path');

const PAGE = process.env.KNOWN || 'the known board in site/data/board.json';
const CR = String.fromCharCode(13);
let text = null;
if (process.env.KNOWN) {
  try { text = fs.readFileSync(PAGE, 'utf8').split(CR).join(''); } catch (e) { text = null; }
} else {
  text = require('./fixtures/known-page').knownPage(REPO_DIR);
}

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

/* The same reading of a page as test-known-issues.js: the text before the
   first "## " heading, then one entry per heading with the words above its
   table and the first two cells of every row. */
function sections(md) {
  const out = { intro: '', list: [] };
  let cur = null, header = false;
  md.split('\n').forEach(function (line) {
    if (/^## /.test(line)) {
      cur = { heading: line.slice(3).trim(), lead: '', rows: [], text: '' };
      out.list.push(cur); header = false; return;
    }
    if (!cur) { if (!/^# /.test(line)) { out.intro += line + '\n'; } return; }
    cur.text += line + '\n';
    if (/^\|/.test(line)) {
      if (!header) { header = true; return; }
      if (/^\|\s*-/.test(line)) { return; }
      const cells = line.split('|');
      cur.rows.push({ what: (cells[1] || '').trim(), why: (cells[2] || '').trim() });
      return;
    }
    if (!cur.rows.length) { cur.lead += line + '\n'; }
  });
  return out;
}

/* Anything that tells a reader a row will stay the way it is. The phrases are
   the ones this site has used, as in test-known-issues.js. */
const PROMISE = /not going to change|none are changing|are not changing|never going to change|will not change|won't change|permanent limits/i;
/* What nobody is building yet. */
const UNBUILT = /\broutines?\b|\berrands?\b|\bschedules?\b|\bjobs?\b|\bquests?\b/i;
/* A date or a when, in any form a page might give one. Month names are
   matched with their capital, so "may" the verb is not a date. */
const MONTH = /\b(January|February|March|April|May|June|July|August|September|October|November|December)\b/;
const WHEN = /\b20\d\d\b|\bsoon\b|\bnext (week|month)\b|\bthis (week|month)\b|\bby the end of\b/i;
function isNpc(row) { return /\bNPCs?\b/.test(row.what); }

yes('the Known Issues page is there: ' + PAGE, text !== null);
const page = sections(text || '');
const first = page.list[0] || { heading: '', lead: '', rows: [], text: '' };
yes('its first table is the group that follows from SkyMP',
    /shared Skyrim/i.test(first.heading) && first.rows.length > 0);
{
  const opening = page.intro.replace(/\s+/g, ' ');
  yes('and the opening says everything after that group is where things stand today',
      /first group/i.test(opening) && /where things stand today/i.test(opening));
}

/* Both rows are still on the page. The entry corrects what the page says
   about them; it does not take them away, because both are still true. */
const npcRows = [];
page.list.forEach(function (s, i) {
  s.rows.forEach(function (r) { if (isNpc(r)) { npcRows.push({ row: r, at: i, section: s }); } });
});
const still = npcRows.filter(function (x) { return /stand still/i.test(x.row.what); })[0];
const differs = npcRows.filter(function (x) { return /differ/i.test(x.row.what); })[0];
/* Issue #504, 11 Oct: release 1.2.3 runs NPCs on the server, and they keep
   moving with nobody connected (the "Shared NPC activity" line in
   game/gamemode.js). The standing still row, and its "no server side AI"
   reason, became false about the server, so it is gone and the section says
   what replaced it. The differing row stays until two people have checked it
   in the game. */
yes('no row says NPCs stand still when nobody is nearby any more', !still);
yes('and nothing on the page says SkyMP has no server side AI', !/server side AI/i.test(text || ''));
yes('the row for NPC behaviour differing near the same enemy is still on the page', !!differs);
yes('the differing row still gives the reason: hosting changes every two seconds',
    !!differs && /(2|two) seconds/i.test(differs.row.why));

/*
  THE CORRECTION ITSELF. On main before this, both rows sat in the first
  group, the one the opening calls SkyMP's limits, and its lead spoke about
  NPCs in one sentence and the rest of the table in the next.
*/
const inFirst = npcRows.filter(function (x) { return x.at === 0; })
                       .map(function (x) { return x.row.what; });
if (inFirst.length) { console.log('      still in the SkyMP group: ' + inFirst.join('; ')); }
yes('no NPC row is in the SkyMP group any more', npcRows.length > 0 && inFirst.length === 0);
yes('and the SkyMP group\'s lead no longer speaks about NPCs', !/\bNPCs?\b/.test(first.lead));

/* All of them under one heading, and the heading says it is about NPCs. */
const homes = [];
npcRows.forEach(function (x) { if (homes.indexOf(x.section) < 0) { homes.push(x.section); } });
yes('every NPC row sits under one heading', homes.length === 1);
const home = homes.length === 1 ? homes[0] : { heading: '', lead: '', rows: [], text: '' };
yes('and that heading is about NPCs: "' + home.heading + '"', /\bNPCs?\b/.test(home.heading));

/* What was decided on 17 September, said to the people it affects. */
yes('the NPC section says the traders stay', /\btraders?\b/i.test(home.lead));
yes('and the carriage workers', /\bcarriages?\b/i.test(home.lead));
yes('and the ferry workers', /\bferr(y|ies)\b/i.test(home.lead));
yes('and that the rest go or are remade', /\b(taken out|removed|remade|rebuilt)\b/i.test(home.lead));
yes('the NPC section says the server keeps them moving with nobody nearby',
    /server[^.]*keep moving when nobody is nearby/i.test(home.lead.replace(/\s+/g, ' ')));
yes('it says what is still worth reporting',
    /report[^.]*only if|only report|worth reporting|worth a report/i.test(home.lead));

/* Nothing about NPCs promises what nobody is building, or gives a date for
   what is decided. That covers the section and any other line on the page
   that names NPCs. */
{
  const lines = home.text.split('\n').concat((text || '').split('\n').filter(function (l) {
    return /\bNPCs?\b/.test(l);
  }));
  const bad = lines.filter(function (l) { return UNBUILT.test(l); });
  if (bad.length) { console.log('      promises: ' + bad.join(' / ')); }
  yes('nothing about NPCs mentions routines, errands, schedules, jobs or quests', bad.length === 0);
  const dated = home.text.split('\n').filter(function (l) { return MONTH.test(l) || WHEN.test(l); });
  if (dated.length) { console.log('      dated: ' + dated.join(' / ')); }
  yes('and nothing in the NPC section gives a date', dated.length === 0);
}

/* The done line of 324's doc half: Select-String over the page for "stand
   still" or "not going to change" returns no line calling this permanent. */
{
  const bad = (text || '').split('\n').filter(function (l) {
    return /stand still|not going to change/i.test(l) && PROMISE.test(l);
  });
  yes('no line the done check finds calls NPC behaviour permanent', bad.length === 0);
  yes('and nothing on the page promises a row will not change', !PROMISE.test(text || ''));
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
