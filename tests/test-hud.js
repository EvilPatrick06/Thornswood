// test-hud.js
//
// The on-screen HUD and the on-screen warning, run rather than read.
//
// Both are updateOwner scripts: JavaScript written as a string inside
// gamemode.js, shipped to the client, and then handing ANOTHER string to the
// browser. Two layers of quoting, no compiler between them, and a mistake in
// either one fails silently on somebody else's screen. So this pulls the real
// functions out of the gamemode, runs what they produce against a fake
// SkyrimPlatform and a fake document, and looks at the markup that comes out.
//
// Patrick, 22 September: "There is no indicator for the hunger food or
// exhasution on screen", "the temp stuff should also have a hud element",
// "hunger and thirst element should have nice icons for them and say the
// percentage", and for the countdown: "I need it to do an onscreen warninjg
// and not just in chat at one minute and at 30 seoconds".
//
// Read only.
const TOOLS_DIR = require('path').join(__dirname, '..', 'tools'); // the tests are in tests\, what they test is in tools\
const fs = require('fs');
const path = require('path');
const SRC = process.env.GM || path.join(TOOLS_DIR, '..', 'game', 'gamemode.js');
const CR = String.fromCharCode(13);
const src = fs.readFileSync(SRC, 'utf8').split(CR).join('');
const BS = String.fromCharCode(92);

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

/** Lift one whole function out of the source by name. */
function lift(name) {
  const a = src.indexOf('function ' + name + '()');
  if (a < 0) { return null; }
  const b = src.indexOf('\n  }', a);
  const c = src.indexOf('\n}', a);
  const end = (b >= 0 && (c < 0 || b < c)) ? b + 4 : (c >= 0 ? c + 2 : -1);
  return end > 0 ? src.slice(a, end) : null;
}

/** A document that records the one element these scripts build. */
function fakeDoc() {
  const made = {};
  const doc = {
    getElementById: function (id) { return made[id] || null; },
    createElement: function () {
      return { id: '', style: { cssText: '', display: '' }, innerHTML: '' };
    },
    body: { appendChild: function (el) { made[el.id] = el; } }
  };
  return { doc: doc, made: made };
}

/** Run an updateOwner script, then run whatever it handed the browser. */
function run(made, value, state) {
  let handed = null;
  const notes = [];
  const ctx = {
    value: value,
    state: state,
    sp: {
      Debug: { notification: function (t) { notes.push(String(t)); } },
      browser: { executeJavaScript: function (s) { handed = s; } }
    }
  };
  new Function('ctx', made)(ctx);
  const f = fakeDoc();
  if (handed) {
    new Function('document', 'window', 'setTimeout', 'clearTimeout', handed)(
      f.doc, {}, function () { return 1; }, function () { });
  }
  return { handed: handed, made: f.made, notes: notes };
}

// ---------------------------------------------------------------- the HUD
const hud = lift('hudScript');
yes('the HUD script is in the gamemode', hud !== null);

if (hud) {
  const made = new Function(hud + '\nreturn hudScript();')();
  const full = { food: 100, drink: 100, rest: 100, temp: 50 };

  // S1: it runs, builds an element, and hands the browser something.
  {
    const r = run(made, { food: 62, drink: 41, rest: 88, temp: 22 }, {});
    yes('S1 the HUD runs and hands the browser a script', !!r.handed);
    const el = r.made['ts-hud'];
    yes('S1 and builds one element with a known id', !!el);
    if (el) {
      yes('S1 the markup carries no stray backslash from the quoting',
          el.innerHTML.indexOf(BS) === -1);
      yes('S1 it is fixed to the screen and does not eat clicks',
          el.style.cssText.indexOf('position:fixed') !== -1 &&
          el.style.cssText.indexOf('pointer-events:none') !== -1);
    }
  }

  // S2: what Patrick asked for by name. Icons and a percentage.
  {
    const r = run(made, { food: 62, drink: 41, rest: 88, temp: 22 }, {});
    const h = r.made['ts-hud'].innerHTML;
    yes('S2 every row has an icon', (h.match(/<svg /g) || []).length === 4);
    yes('S2 and the icons are drawn, not linked to a file',
        h.indexOf('<path d="') !== -1 && h.indexOf('src=') === -1);
    yes('S2 the percentage is written out', h.indexOf('62%') !== -1 &&
        h.indexOf('41%') !== -1 && h.indexOf('88%') !== -1);
    /*
      HUNGER AND THIRST, NOT FOOD AND WATER. Patrick, 23 September: "also
      rename to Hunger and Thirst". They are the words the rest of the genre
      uses and they are what he asked for.
    */
    yes('S2 all four rows are named, and they are the words he asked for',
        h.indexOf('>Hunger<') !== -1 && h.indexOf('>Thirst<') !== -1 &&
        h.indexOf('>Rest<') !== -1 && h.indexOf('>Temp<') !== -1 &&
        h.indexOf('>Heat<') === -1 && h.indexOf('>Water<') === -1);
  }

  /*
    S3: TEMPERATURE IS A WORD AND A NUMBER, NOT A PERCENTAGE.

    Patrick, 23 September: "heat shouldnt be a percentage to it should be a
    number plus a color to reflect hot, cold, cmoftroable, anbd the
    ionbetweens", and "instead of heat it should say Temp".

    A percentage said 20% for freezing AND 20% for overheating, which are
    opposite states, and a percentage of what was never answerable.
  */
  {
    function tempReadout(temp) {
      const r = run(made, { food: 100, drink: 100, rest: 100, temp: temp }, {});
      const seg = r.made['ts-hud'].innerHTML.split('>Temp<')[1] || '';
      const m = />([A-Za-z]+) (\d+)<\/span>/.exec(seg);
      return m ? { word: m[1], num: Number(m[2]), html: seg } : null;
    }
    const cold = tempReadout(8);
    const fine = tempReadout(50);
    const hot = tempReadout(92);
    /*
      THE READOUT, NOT THE WHOLE ROW. The first version of this asked whether
      the row contained a percent sign anywhere, and of course it does: the
      bar's own style says height:100% and width:8%. It reported a correct
      readout as wrong, which is the SECOND time in this file that reading CSS
      as if it were content has produced a false failure. Match the readout
      span and nothing else.

      Matching at all is the check: a percentage readout renders as >8%</span>
      and cannot match a word followed by a number.
    */
    yes('S3 it reads as a word and the number itself, with no percent sign',
        !!cold && !!fine && !!hot &&
        cold.num === 8 && fine.num === 50 && hot.num === 92);
    yes('S3 the two ends say opposite things rather than the same thing',
        cold.word !== hot.word);
    yes('S3 cold reads cold, the middle comfortable, hot reads hot',
        /freez|cold/i.test(cold.word) && /fine|comfort/i.test(fine.word) &&
        /hot|burn/i.test(hot.word));
    function colourAt(t) {
      const seg = tempReadout(t).html;
      const m = /color:(#[0-9a-f]{6})/i.exec(seg);
      return m ? m[1].toLowerCase() : null;
    }
    const shades = [8, 25, 35, 50, 65, 80, 95].map(colourAt);
    yes('S3 and every band has its own colour, including the in betweens',
        shades.every(function (c) { return !!c; }) &&
        new Set(shades).size === shades.length);
  }

  /*
    S3b: readable, which the first one was not.

    Patrick: "the indicators are too small and hard to see with the color they
    are ... that's all trasparent". It drew at 0.38 opacity, 12px, with no
    backing, over whatever happened to be behind it.
  */
  {
    const r = run(made, { food: 100, drink: 100, rest: 100, temp: 50 }, {});
    const el = r.made['ts-hud'];
    yes('S3b a healthy HUD is not faded out of sight',
        !/opacity:0\.[0-7]/.test(el.innerHTML));
    yes('S3b it has a backing so it does not fight the scene',
        /background:rgba\(/.test(el.style.cssText));
    const size = /font-size:(\d+)px/.exec(el.style.cssText);
    yes('S3b and the text is big enough to read', !!size && Number(size[1]) >= 14);
  }

  /*
    S3c: the size Patrick actually asked for.

    23 September, looking at the 15px version: "The indicator area is still to
    small it all needs to be like 1.5x the current size". 15 x 1.5 is 22, the
    132px bar becomes 198 and the 19px icon becomes 28. Numbers, not
    adjectives, so nobody can shrink it back by accident and call it readable.
  */
  {
    const r = run(made, { food: 100, drink: 100, rest: 100, temp: 50 }, {});
    const el = r.made['ts-hud'];
    const size = /font-size:(\d+)px/.exec(el.style.cssText);
    yes('S3c the text is the asked for 1.5x, not the old 15px',
        !!size && Number(size[1]) >= 22);
    const bar = /width:(\d+)px;height:(\d+)px/.exec(el.innerHTML);
    yes('S3c the bars grew with it', !!bar && Number(bar[1]) >= 198 && Number(bar[2]) >= 16);
    const icon = /<svg width="(\d+)"/.exec(el.innerHTML);
    yes('S3c and so did the icons', !!icon && Number(icon[1]) >= 28);
    // The panel has to grow too, or bigger text inside the same box overflows.
    const pad = /padding:(\d+)px/.exec(el.style.cssText);
    yes('S3c the panel behind it grew as well', !!pad && Number(pad[1]) >= 13);
  }

  // S4: THE PER-FRAME GUARD. updateOwner runs every frame; this is what stops
  // the HUD being rebuilt sixty times a second for ever.
  {
    const st = {};
    const a = run(made, { food: 62.4, drink: 41, rest: 88, temp: 22 }, st);
    yes('S4 the first frame draws', !!a.handed);
    const b = run(made, { food: 62.4, drink: 41, rest: 88, temp: 22 }, st);
    yes('S4 the same numbers again draw nothing', !b.handed);
    // A number that moves but rounds the same must also draw nothing: these
    // meters move continuously and the screen does not.
    const c = run(made, { food: 62.49, drink: 41, rest: 88, temp: 22 }, st);
    yes('S4 and neither does a value that rounds to the same whole number', !c.handed);
    const d = run(made, { food: 61, drink: 41, rest: 88, temp: 22 }, st);
    yes('S4 but a real change does draw', !!d.handed);
  }

  // S5: no state, no drawing. Fails shut rather than every frame.
  {
    const r = run(made, { food: 50, drink: 50, rest: 50, temp: 50 }, null);
    yes('S5 with nowhere to remember the last frame it draws nothing', !r.handed);
  }

  // S6: rubbish in does not throw.
  {
    let threw = false;
    try {
      run(made, { food: 'x', drink: null, rest: undefined, temp: {} }, {});
      run(made, null, {});
      run(made, {}, {});
    } catch (e) { threw = true; }
    yes('S6 a broken or missing value is ignored rather than thrown', !threw);
  }
}

// ------------------------------------------------------------- the warning
const alert = lift('alertScript');
yes('the on-screen warning script is in the gamemode', alert !== null);

if (alert) {
  const made = new Function(alert + '\nreturn alertScript();')();

  {
    const r = run(made, { text: 'You are put back to the launcher in 1 minute.', tone: 'bad', ms: 9000, at: 111 }, {});
    yes('S7 the warning reaches Skyrim\'s own corner message', r.notes.length === 1);
    const el = r.made['ts-alert'];
    yes('S7 and builds a banner', !!el);
    if (el) {
      yes('S7 carrying the words', el.innerHTML.indexOf('put back to the launcher') !== -1);
      yes('S7 with no stray backslash', el.innerHTML.indexOf(BS) === -1);
    }
  }

  // S8: the same guard as the HUD, on the stamp.
  {
    const st = {};
    const a = run(made, { text: 'one', tone: 'bad', ms: 9000, at: 7 }, st);
    const b = run(made, { text: 'one', tone: 'bad', ms: 9000, at: 7 }, st);
    const c = run(made, { text: 'two', tone: 'bad', ms: 9000, at: 8 }, st);
    yes('S8 a warning shows once per stamp, not once per frame',
        !!a.handed && !b.handed && !!c.handed);
  }

  // S9: the countdown only shouts at the two marks Patrick named.
  {
    const tick = src.slice(src.indexOf('function restartTick'), src.indexOf('function poll'));
    yes('S9 the banner fires at one minute and at thirty seconds',
        /m === 60 \|\| m === 30/.test(tick));
    yes('S9 and the ten second mark is deliberately left to chat',
        tick.indexOf('alertAll') !== -1 && !/m === 10/.test(tick));
  }
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
