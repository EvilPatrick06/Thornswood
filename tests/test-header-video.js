/*
  test-header-video.js

  The moving strip behind the title on the Play page stops while the game runs.

  WHY THIS EXISTS. To Do List entry 195. StartHeaderVideo in Shell.cs plays the
  video only while somebody can see it, and until 24 September "see it" meant
  the Play page is showing and the window is not minimised. The entry says what
  that missed: "with Keep Launcher Open on, the launcher is not minimised while
  the game runs, so the video keeps playing behind the game and nothing pauses
  it". The music (MusicDecide) has always stopped while the game runs. Playing,
  the video measured 3 to 14% of one core.

  The launcher cannot be started from here (CLAUDE.md), so this does two things:

    - It lifts the video's own decide delegate out of Shell.cs as it is written
      and runs it against a stand-in clock, window and page: a game start and a
      game close with the window up, minimising and restoring while the game
      runs, a launcher opened on a game already running, and the old cases
      (another page, minimised) so they still behave as Djinn measured them.
    - It reads the source for the wiring: every place that changes playing once
      the window is up tells the video straight after, and the one at startup
      runs before the window is shown.

  Read only. It reads launcher\app\*.cs and nothing else.
*/
const REPO_DIR = require('path').join(__dirname, '..'); // the tests are in tests\, the repository is one folder up
const fs = require('fs');
const path = require('path');

const APP = path.join(REPO_DIR, 'launcher', 'app');
const CR = String.fromCharCode(13);
function read(f) { return fs.readFileSync(path.join(APP, f), 'utf8').split(CR).join(''); }
const SHELL = read('Shell.cs');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function done() {
  console.log('');
  console.log(pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
}

/* From the opening brace at or after `from` to its matching closing brace. */
function braces(src, from) {
  const open = src.indexOf('{', from);
  if (open < 0) return null;
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === '{') depth++;
    else if (src[i] === '}') { depth--; if (depth === 0) return { open: open, close: i, inner: src.slice(open + 1, i) }; }
  }
  return null;
}
function method(src, signature) {
  const at = src.indexOf(signature);
  if (at < 0) return '';
  const b = braces(src, at);
  return b ? src.slice(at, b.close + 1) : '';
}

// ---- the video's decide, lifted and run ---------------------------------------
const start = method(SHELL, 'static void StartHeaderVideo()');
yes('StartHeaderVideo is in Shell.cs', start.length > 0);
if (!start) done();

const decideAt = start.indexOf('Action decide = delegate');
yes('StartHeaderVideo still has its decide delegate', decideAt > 0);
if (decideAt < 0) done();
const decideSrc = braces(start, decideAt).inner;

// C# to JavaScript, for this one delegate only. It is a few lines of
// conditions and calls, so the handful of C# spellings it uses are swapped
// for JavaScript ones and the rest runs as it is.
const decideJs = decideSrc
  .replace(/\bbool\s+(\w+)\s*=/g, 'var $1 =')
  .replace(/\bTimeSpan\s+(\w+)\s*=/g, 'var $1 =')
  .replace(/\bheldAt\.Value\b/g, 'heldAt');
let decideFn = null;
try {
  // `with` so that the delegate's own names (page, win, clock, heldAt, playing,
  // gone) read and write the stand-in's fields, as the C# closure does.
  decideFn = new Function('env', 'with (env) {' + decideJs + '\n}');
} catch (e) {
  console.log('      ' + e.message);
}
yes('the decide delegate reads as a function the stand-ins can run', decideFn !== null);
if (!decideFn) done();

/* A stand-in for the MediaClock: Begin, Seek and Stop, and a time that only
   moves while it runs. CurrentTime is null once stopped, as a stopped WPF clock
   reports it. */
function makeClock() {
  const c = { state: 'Active', time: 0, calls: [] };
  Object.defineProperty(c, 'CurrentTime', { get: function () { return c.state === 'Stopped' ? null : c.time; } });
  c.Controller = {
    Begin: function () { c.state = 'Active'; c.time = 0; c.calls.push('Begin'); },
    Seek: function (at) { c.time = at; c.calls.push('Seek ' + at); },
    Stop: function () { c.state = 'Stopped'; c.calls.push('Stop'); }
  };
  c.run = function (seconds) { if (c.state === 'Active') c.time += seconds; };
  return c;
}
function makeWorld(o) {
  o = o || {};
  const env = {
    gone: false,
    clock: makeClock(),
    heldAt: null,
    playing: !!o.playing,
    page: { IsVisible: o.visible !== false },
    win: { WindowState: o.minimised ? 'Minimized' : 'Normal' },
    WindowState: { Minimized: 'Minimized', Normal: 'Normal', Maximized: 'Maximized' },
    TimeSpan: { Zero: 0 },
    System: { Windows: { Media: { Animation: { TimeSeekOrigin: { BeginTime: 'BeginTime' } } } } }
  };
  env.decide = function () { decideFn(env); };
  return env;
}
function runs(env) { return env.clock.state === 'Active'; }

let threw = null;
try {
  // A game started with Keep Launcher Open ticked: the window stays up and the
  // Play page stays on it.
  let w = makeWorld();
  w.decide();
  yes('before the game, with the Play page up, the video plays', runs(w));
  w.clock.run(7.5);
  w.playing = true; w.decide();
  yes('the game starts with the window still up: the video stops', !runs(w));
  yes('and it remembers where it was, 7.5 seconds in', w.heldAt === 7.5);
  w.clock.run(60);
  w.win.WindowState = 'Minimized'; w.decide();
  w.win.WindowState = 'Normal'; w.decide();
  yes('minimising and restoring while the game runs does not start it', !runs(w));
  w.page.IsVisible = false; w.decide();
  w.page.IsVisible = true; w.decide();
  yes('another page and back while the game runs does not start it', !runs(w));
  w.playing = false; w.decide();
  yes('the game closes: the video plays again', runs(w));
  yes('from where it stopped, not from the start',
      w.clock.time === 7.5 && w.clock.calls.slice(-2).join(',') === 'Begin,Seek 7.5');
  yes('and it is not held any more', w.heldAt === null);

  // Keep Launcher Open off: Play minimises the window after the start. The
  // game ends while it is still minimised, and restoring it is what resumes.
  w = makeWorld();
  w.decide();
  w.clock.run(3);
  w.playing = true; w.decide();
  w.win.WindowState = 'Minimized'; w.decide();
  yes('the game starts and the window is minimised: stopped', !runs(w) && w.heldAt === 3);
  w.playing = false; w.decide();
  yes('the game closes while minimised: still stopped', !runs(w));
  w.win.WindowState = 'Normal'; w.decide();
  yes('the window comes back: it plays from 3 seconds', runs(w) && w.clock.time === 3);

  // A launcher opened while the game is already running. The first decide
  // runs before the window is shown, so the page is not visible yet; showing
  // the window is the next decide, and the game is still up.
  w = makeWorld({ visible: false });
  w.decide();
  yes('before the window is shown, the video is stopped', !runs(w) && w.heldAt === 0);
  w.playing = true;
  w.page.IsVisible = true; w.decide();
  yes('a launcher opened on a running game shows its window with the video stopped', !runs(w));
  w.playing = false; w.decide();
  yes('and the video starts when that game closes', runs(w));

  // What Djinn measured stays as it was.
  w = makeWorld();
  w.decide();
  w.clock.run(12);
  w.page.IsVisible = false; w.decide();
  yes('another page, no game: stopped, as before', !runs(w) && w.heldAt === 12);
  w.page.IsVisible = true; w.decide();
  yes('back on the Play page: plays from the same point, as before', runs(w) && w.clock.time === 12);
  w.win.WindowState = 'Minimized'; w.decide();
  yes('minimised, no game: stopped, as before', !runs(w));
  w.win.WindowState = 'Maximized'; w.decide();
  yes('maximised counts as seen, as before', runs(w));
  const before = w.clock.calls.length;
  w.decide(); w.decide();
  yes('deciding twice in the same state changes nothing', w.clock.calls.length === before);

  // A video that failed to play is left alone, game or no game.
  w = makeWorld();
  w.gone = true;
  w.playing = true; w.decide();
  w.playing = false; w.decide();
  yes('once the video has been dropped, deciding does nothing', w.clock.calls.length === 0);
} catch (e) {
  threw = e;
}
yes('the lifted decide ran without an error' + (threw ? ' (' + threw.message + ')' : ''), threw === null);

// ---- the wiring -----------------------------------------------------------------
yes('headerVideoDecide is a field that does nothing until the video starts, so a call can never throw',
    /\bstatic Action headerVideoDecide = delegate \{ \};/.test(SHELL));
const handOver = start.indexOf('headerVideoDecide = decide;');
const lastWire = start.indexOf('page.IsVisibleChanged += delegate { decide(); };');
yes('StartHeaderVideo hands its decide over', handOver > 0);
yes('only once the video is set up and wired to the window and the page',
    handOver > 0 && lastWire > 0 && handOver > lastWire);
yes('the window being minimised still decides', start.indexOf('win.StateChanged += delegate { decide(); };') > 0);

// Every assignment to playing in the Shell class, whichever file it is in.
const shellFiles = fs.readdirSync(APP).filter(function (f) {
  return f.endsWith('.cs') && (f === 'Shell.cs' || /\bpartial class Shell\b/.test(read(f)));
});
yes('the Shell class is found in more than one file, and all of them are read', shellFiles.length > 1);

const runBody = method(SHELL, 'static void Run(string[] args)');
const shown = runBody.indexOf('app.Run(win);');
let assignments = 0;
for (const f of shellFiles) {
  const lines = read(f).split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const t = line.trim();
    if (t.startsWith('//') || t.startsWith('*') || t.startsWith('/*')) continue;
    const m = /(^|[^.\w])playing\s*=(?!=)\s*([^;]+);/.exec(line);
    if (!m) continue;
    assignments++;
    const where = f + ':' + (i + 1) + ' playing = ' + m[2].trim();
    if (m[2].trim() === 'true' || m[2].trim() === 'false') {
      // Straight after, in the same block, before anything can return.
      const indent = line.length - line.trimStart().length;
      let told = false;
      for (let k = i + 1; k < lines.length && k <= i + 3; k++) {
        const next = lines[k];
        if (next.trim() === '') continue;
        if (next.length - next.trimStart().length < indent) break;
        if (/\breturn\b/.test(next)) break;
        if (next.trim() === 'headerVideoDecide();') { told = true; break; }
      }
      yes(where + ' tells the video straight after', told);
    } else if (f === 'Shell.cs' && m[2].trim() === 'Checks.GameRunning()') {
      // The launcher opened on a game already running. The window is shown by
      // app.Run, and the page becoming visible is the decide that counts.
      const inRun = runBody.indexOf(line.trim());
      yes(where + ' is in Run, before the window is shown', inRun > 0 && shown > 0 && inRun < shown);
      yes('and the video cannot play before the window is shown, because it needs the page visible',
          /bool seen = page\.IsVisible\b/.test(decideSrc));
    } else if (m[2].trim() === 'Checks.GameRunning()') {
      // The same check in another way in, such as OpenForUninstall in
      // ShellUninstall.cs (pull request 270): it has to come before that
      // method shows the window with its own app.Run, for the same reason.
      let runAt = -1;
      for (let k = i + 1; k < lines.length; k++) {
        if (/^\s*(public |private |internal )?static\s+\w[\w<>\[\]]*\s+\w+\s*\(/.test(lines[k])) break;
        if (lines[k].indexOf('app.Run(win);') >= 0) { runAt = k; break; }
      }
      yes(where + ' comes before its own method shows the window', runAt > i);
    } else {
      yes(where + ' is an assignment this harness does not know: tell the video after it and add it here', false);
    }
  }
}
yes('the four places that change playing are all found (' + assignments + ')', assignments >= 4);

// The music has the same rule, and the video now reads the same flag.
yes('the music still stops while the game runs', /bool want = [^;]*!playing/.test(method(SHELL, 'static void MusicDecide()')));
yes('the video reads the same flag the music does', /bool seen = [^;]*!playing/.test(decideSrc));

done();
