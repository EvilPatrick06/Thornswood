'use strict';
// voice-launcher.js
//
// The launcher's voice for the JavaScript harnesses. Since #4823 voice is C#
// in the launcher (launcher\app\VoiceSession.cs and the Voice*.cs beside it),
// not a page, so a harness that ran voice-host.html's script in node's vm runs
// this instead: tests\voice-launcher\VoiceDriver.csproj, which compiles the
// launcher's own voice files with a stand-in for the Windows audio, built here
// with the .NET 10 SDK on any machine and started once per launcher.
//
//   const VL = require('./voice-launcher');
//   const a = await VL.start({ clock: 'manual', wire: 'fake', jitter: 0.5 });
//   await a.send({ do: 'configure', profileId: 7, name: 'Aela', token: 't',
//                  base: 'https://example.invalid/voice' });
//   a.events            every line the driver wrote, in order
//   a.dials()           the sockets the session opened ({ n, url, protocols })
//   a.sent(n)           what it wrote to socket n
//   a.host(kind)        what it told the launcher, by kind (log, status, ...)
//   await a.until(fn, ms, what)   real clock: waits for fn(a) to hold
//   await a.quit()
//
// With clock 'manual' every send resolves once the session has nothing left
// to do, so what it did is all in events; with 'real' it resolves once the
// call is made, and until() waits for the effect. The build goes to the
// machine's temp folder, one folder per set of sources, so a second harness
// starts at once and nothing is written into the repository.

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const cp = require('child_process');
const readline = require('readline');

const REPO = path.join(__dirname, '..');
const PROJ = path.join(__dirname, 'voice-launcher', 'VoiceDriver.csproj');

// What the driver is built from: its own files, the launcher's voice files it
// links, and the launcher's project, whose package versions it takes.
function sources() {
  const list = [PROJ, path.join(__dirname, 'voice-launcher', 'Driver.cs'), path.join(__dirname, 'voice-launcher', 'StandIns.cs'),
    path.join(REPO, 'launcher', 'app', 'Thornswood.csproj')];
  const proj = fs.readFileSync(PROJ, 'utf8');
  const re = /<Compile Include="\.\.\/\.\.\/launcher\/app\/([^"]+)"/g;
  let m;
  while ((m = re.exec(proj))) { list.push(path.join(REPO, 'launcher', 'app', m[1])); }
  return list;
}

function findDotnet() {
  const tries = [];
  if (process.env.DOTNET) { tries.push(process.env.DOTNET); }
  if (process.env.DOTNET_ROOT) { tries.push(path.join(process.env.DOTNET_ROOT, os.platform() === 'win32' ? 'dotnet.exe' : 'dotnet')); }
  tries.push(path.join(os.homedir(), '.dotnet', os.platform() === 'win32' ? 'dotnet.exe' : 'dotnet'));
  if (os.platform() === 'win32') { tries.push(path.join(process.env.ProgramFiles || 'C:\\Program Files', 'dotnet', 'dotnet.exe')); }
  for (const t of tries) { if (fs.existsSync(t)) { return t; } }
  // On PATH.
  const r = cp.spawnSync(os.platform() === 'win32' ? 'where' : 'which', ['dotnet'], { encoding: 'utf8' });
  const hit = (r.stdout || '').split(/\r?\n/).map((l) => l.trim()).filter(Boolean)[0];
  return hit || null;
}

let built = null;
/* Builds the driver once per set of sources; returns { dotnet, dll }. Throws,
   with the build's own words, when there is no SDK or the build fails: the
   launcher needs the same SDK, so a harness never passes without it. */
function build() {
  if (built) { return built; }
  const dotnet = findDotnet();
  if (!dotnet) { throw new Error('no .NET SDK (dotnet) on this machine: the launcher\'s voice is C# and needs it to run here (DOTNET names one)'); }
  const h = crypto.createHash('sha256');
  for (const f of sources()) { h.update(f.slice(REPO.length) + '\0'); h.update(fs.readFileSync(f)); }
  const key = h.digest('hex').slice(0, 16);
  const root = path.join(os.tmpdir(), 'thornswood-voice-driver', key);
  const dll = path.join(root, 'out', 'VoiceDriver.dll');
  if (!fs.existsSync(dll)) {
    const r = cp.spawnSync(dotnet, ['build', PROJ, '-c', 'Release', '-nologo', '-v', 'q',
      '-o', path.join(root, 'out'), '-p:VoiceDriverObj=' + path.join(root, 'obj') + path.sep],
    { encoding: 'utf8', env: Object.assign({}, process.env, { DOTNET_CLI_TELEMETRY_OPTOUT: '1', DOTNET_NOLOGO: '1' }) });
    if (r.status !== 0 || !fs.existsSync(dll)) {
      throw new Error('the voice driver did not build:\n' + (r.stdout || '') + (r.stderr || '') + (r.error ? String(r.error) : ''));
    }
  }
  built = { dotnet: dotnet, dll: dll, root: root };
  return built;
}

/* One launcher's voice. opts: clock ('real' | 'manual'), wire ('ws' | 'fake'),
   jitter (0 to 1), tone (Hz), name (for messages). */
function start(opts) {
  opts = opts || {};
  const b = build();
  const log = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'thornswood-voice-run-')), 'swallowed.log');
  const args = [b.dll, '--clock', opts.clock || 'real', '--wire', opts.wire || 'ws', '--log', log];
  if (opts.jitter !== undefined) { args.push('--jitter', String(opts.jitter)); }
  if (opts.tone !== undefined) { args.push('--tone', String(opts.tone)); }
  const child = cp.spawn(b.dotnet, args, { stdio: ['pipe', 'pipe', 'pipe'] });
  let err = '';
  child.stderr.on('data', (d) => { err += d; });
  const me = {
    name: opts.name || 'launcher',
    events: [],
    child: child,
    seq: 0,
    waiters: [],
    exited: null,
    swallowed: function () { try { return fs.readFileSync(log, 'utf8'); } catch (e) { return ''; } },
    stderr: function () { return err; }
  };
  const lines = readline.createInterface({ input: child.stdout });
  lines.on('line', (l) => {
    let e;
    try { e = JSON.parse(l); } catch (x) { e = { ev: 'unreadable', line: l }; }
    me.events.push(e);
    for (const w of me.waiters.slice()) { w(); }
  });
  child.on('exit', (code) => { me.exited = code; for (const w of me.waiters.slice()) { w(); } });

  /* Waits for fn() to hold, checked on every event; real-clock harnesses
     also call it on a timer, since a mixer's level is no event. */
  me.until = function (fn, ms, what) {
    return new Promise((ok, bad) => {
      let tick = null;
      const timer = setTimeout(() => { done(); bad(new Error(me.name + ': no ' + (what || 'answer') + ' within ' + ms + ' ms' + (err ? '\n' + err : ''))); }, ms);
      function check() {
        let v = false;
        try { v = fn(me); } catch (e) { v = false; }
        if (v) { done(); ok(v); } else if (me.exited !== null) { done(); bad(new Error(me.name + ': the driver stopped (' + me.exited + ')\n' + err)); }
      }
      function done() { clearTimeout(timer); if (tick) { clearInterval(tick); } const i = me.waiters.indexOf(check); if (i >= 0) { me.waiters.splice(i, 1); } }
      me.waiters.push(check);
      if (opts.poll !== false) { tick = setInterval(check, 50); }
      check();
    });
  };
  me.send = function (cmd) {
    const seq = ++me.seq;
    const from = me.events.length;
    child.stdin.write(JSON.stringify(Object.assign({ seq: seq }, cmd)) + '\n');
    return me.until(() => me.events.slice(from).some((e) => e.ev === 'done' && e.seq === seq), 60000, 'answer to ' + cmd.do)
      .then(() => me.events.slice(from));
  };
  me.dials = function () { return me.events.filter((e) => e.ev === 'dial'); };
  me.sent = function (n) { return me.events.filter((e) => e.ev === 'sent' && (n === undefined || e.n === n)).map((e) => e.msg); };
  me.closed = function (n) { return me.events.some((e) => e.ev === 'closed' && e.n === n); };
  me.host = function (kind) { return me.events.filter((e) => e.ev === 'host' && (!kind || e.kind === kind)).map((e) => e.text); };
  me.says = function (re) { return me.host('log').some((t) => re.test(t)); };
  me.hear = async function (tones) {
    const ev = await me.send({ do: 'hear', tones: tones });
    const h = ev.filter((e) => e.ev === 'heard')[0];
    return h ? h.levels : {};
  };
  me.quit = async function () {
    if (me.exited !== null) { return; }
    try { await me.send({ do: 'quit' }); } catch (e) { /* it stopped on its own, which exit below sees */ }
    await me.until(() => me.exited !== null, 5000, 'exit').catch(() => child.kill());
  };
  return me.until(() => me.events.some((e) => e.ev === 'ready'), 60000, 'start').then(() => me);
}

module.exports = { build: build, start: start, findDotnet: findDotnet };
