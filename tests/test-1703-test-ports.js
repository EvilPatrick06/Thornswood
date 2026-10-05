// test-1703-test-ports.js
//
//     node tests\test-1703-test-ports.js
//
// #1703. Since #1690 the VPS runs several "Launcher builds" jobs at once, and
// they share one 127.0.0.1. Harnesses started the voice service on fixed
// ports (7931 in test-deploy-records.js and test-staff-commands.js, 7911 and
// 7912 in test-command-ack.js, 7901 to 7921 in voice\), so one run's /health
// was answered by another run's service: on 5 Oct, twice, a run read "deploy"
// off the other run's copy, the one with a record beside it, or found the
// port held and got nothing.
//
// Now each harness asks the system for a port nothing holds, starts the
// service on it, and asks nothing of it until that service has said
// "[voice] listening on ...:port" itself. If the service stops first, the
// port was taken in between, and the harness fails saying so.
//
// This checks:
//   1. no .js harness in tests\ or voice\ gives a service a fixed port, by
//      environment or by listen();
//   2. every harness that starts voice-server.js waits for its own line, and
//      that wait, lifted out of each one, refuses a port somebody else holds
//      and takes one the service does hold;
//   3. three copies of test-deploy-records.js started at the same moment all
//      pass, which is what failed on the VPS. Before the change, two copies
//      at once failed in three runs of six on one machine.
//
// HARNESS_ROOT points it at another copy of the repository, which is how it
// was shown to fail on the harnesses before the change.
//
// Writes only to temp folders.
const REPO_DIR = process.env.HARNESS_ROOT || require('path').join(__dirname, '..');
const fs = require('fs');
const os = require('os');
const net = require('net');
const http = require('http');
const path = require('path');
const { spawn } = require('child_process');
const CR = String.fromCharCode(13);
const read = (p) => fs.readFileSync(p, 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

// ------------------------------------------------------------ the harnesses
const files = [];
for (const dir of ['tests', 'voice']) {
  for (const n of fs.readdirSync(path.join(REPO_DIR, dir)).sort()) {
    if (/^test-.*\.js$/.test(n)) { files.push(dir + '/' + n); }
  }
}
const text = {};
for (const f of files) { text[f] = read(path.join(REPO_DIR, f)); }

/*
  A value is fixed when it is a number other than 0, or a name the file sets
  to one (const PORT = 7931). The port reaches a service two ways: an
  environment entry whose name ends in _PORT (THORNSWOOD_VOICE_PORT,
  THORNSWOOD_DOCS_PORT, FAKE_DISCORD_PORT), or listen() in this process.
*/
function fixed(src, expr) {
  let v = String(expr).trim();
  const s = /^String\(\s*([\w$.]+)\s*\)$/.exec(v);
  if (s) { v = s[1]; }
  v = v.replace(/^['"]|['"]$/g, '');
  if (/^\d+$/.test(v)) { return Number(v) !== 0; }
  if (!/^[A-Za-z_$][\w$]*$/.test(v)) { return false; }
  return new RegExp('\\b(?:const|let|var)\\s+' + v + '\\s*=\\s*[\'"]?[1-9]\\d*\\b').test(src);
}
const hits = [];
for (const f of files) {
  const src = text[f];
  let m;
  const env = /\b([A-Z][A-Z0-9_]*_PORT)\s*:\s*([^,}\n]+)/g;
  while ((m = env.exec(src))) {
    if (fixed(src, m[2])) { hits.push(f + ': ' + m[1] + ' is ' + m[2].trim()); }
  }
  const lis = /\.listen\(\s*([^,)\n]+)/g;
  while ((m = lis.exec(src))) {
    if (fixed(src, m[1])) { hits.push(f + ': listen(' + m[1].trim() + ')'); }
  }
}
console.log('fixed ports:');
yes('the scan reads the harnesses (' + files.length + ')', files.length > 250);
yes('and finds the services they start (' +
    files.filter((f) => /_PORT\s*:/.test(text[f]) || /\.listen\(/.test(text[f])).length + ' that start one)',
    files.filter((f) => /_PORT\s*:/.test(text[f]) || /\.listen\(/.test(text[f])).length >= 30);
// The scan itself, on the lines this issue took out.
yes('it would have caught const PORT = 7931 handed over as THORNSWOOD_VOICE_PORT',
    fixed('const PORT = 7931;\n', 'String(PORT)'));
yes('and listen(FAKE) with const FAKE = 7912', fixed('const FAKE = 7912;\n', 'FAKE'));
yes('and leaves a port the system named alone', !fixed('let PORT = 0;\nPORT = await freePort();\n', 'String(PORT)') &&
    !fixed('', '0') && !fixed('const port = await freePort();\n', 'String(port)'));
yes('no harness gives a service a fixed port' + (hits.length ? ': ' + hits.join('; ') : ''), hits.length === 0);

// ------------------------------------------------- the voice service's own word
const SELF = 'tests/' + path.basename(__filename);
const starters = files.filter((f) => f !== SELF && /spawn\(/.test(text[f]) && /'voice-server\.js'/.test(text[f]));
console.log('\nthe harnesses that start the voice service (' + starters.length + '):');
yes('there are the twelve this issue found, and test-local-chat.js',
    ['tests/test-command-ack.js', 'tests/test-deploy-records.js', 'tests/test-staff-commands.js',
     'voice/test-auth.js', 'voice/test-backpressure.js', 'voice/test-chat-limit.js', 'voice/test-cull.js',
     'voice/test-ice.js', 'voice/test-keepalive.js', 'voice/test-line-close.js', 'voice/test-local-chat.js',
     'voice/test-moved.js', 'voice/test-turn-key.js'].every((f) => starters.indexOf(f) >= 0));
function lift(src) {
  const a = src.indexOf('function listening(srv, port) {');
  if (a < 0) { return null; }
  const b = src.indexOf('\n}\n', a);
  if (b < 0) { return null; }
  try { return new Function('return ' + src.slice(a, b + 2))(); } catch (e) { return null; }
}
const waits = {};
for (const f of starters) {
  waits[f] = lift(text[f]);
  yes(f + ' waits for its own service to say it is listening before asking it anything',
      !!waits[f] && /await listening\(srv, (PORT|port)\)/.test(text[f]));
}

const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'ts-1703-'));
for (const n of ['voice-server.js', 'headlines.js']) {
  fs.copyFileSync(path.join(REPO_DIR, 'voice', n), path.join(scratch, n));
}
function voice(port) {
  const srv = spawn(process.execPath, ['voice-server.js'], { cwd: scratch,
    env: Object.assign({}, process.env, { THORNSWOOD_VOICE_PORT: String(port), THORNSWOOD_VOICE_BIND: '127.0.0.1',
                                          THORNSWOOD_SITE: '', THORNSWOOD_CHAT_DIR: path.join(scratch, 'chat') }) });
  srv.stdout.on('data', () => {}); srv.stderr.on('data', () => {});
  return srv;
}
function gone(srv) {
  return new Promise((ok) => {
    if (srv.exitCode !== null || srv.signalCode !== null) { ok(); return; }
    srv.once('exit', () => ok());
    srv.kill();
  });
}
function get(port, where) {
  return new Promise((ok) => {
    const req = http.get({ host: '127.0.0.1', port: port, path: where, agent: false }, (res) => {
      let b = ''; res.on('data', (d) => { b += d; }); res.on('end', () => ok({ status: res.statusCode, body: b }));
    });
    req.on('error', () => ok({ status: 0, body: '' }));
  });
}

/*
  Copies of one harness at the same moment, the way two runners on the VPS
  reached test-deploy-records.js in the same second. Each must pass.
*/
function runHarness(rel) {
  return new Promise((ok) => {
    const c = spawn(process.execPath, [path.join(REPO_DIR, rel)], { cwd: REPO_DIR });
    let out = '';
    c.stdout.on('data', (d) => { out += d; });
    c.stderr.on('data', (d) => { out += d; });
    c.on('exit', (code) => ok({ code: code, out: out }));
  });
}

(async () => {
  // Somebody else on the port: a server that answers /health the way a voice
  // service with a deploy record would.
  const other = http.createServer((q, r) => {
    r.writeHead(200, { 'content-type': 'application/json' });
    r.end('{"ok":true,"build":"not this run","deploy":{"commit":"another run"}}');
  });
  await new Promise((r) => other.listen(0, '127.0.0.1', r));
  const held = other.address().port;
  for (const f of starters) {
    if (!waits[f]) { continue; }
    const srv = voice(held);
    let said = '';
    try { await waits[f](srv, held); said = 'took it'; } catch (e) { said = e.message.split('\n')[0]; }
    await gone(srv);
    yes(f + ': with another server on its port, the wait fails and says so ("' + said + '")',
        said.indexOf('something else already holds port ' + held) === 0);
  }
  other.close();

  // And the service's own port: the wait ends, and what answers is this service.
  const first = starters.filter((f) => !!waits[f])[0];
  if (first) {
    const port = await new Promise((ok) => {
      const s = net.createServer();
      s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => ok(p)); });
    });
    const srv = voice(port);
    let up = false;
    try { await waits[first](srv, port); up = true; } catch (e) { console.log('      ' + e.message); }
    const h = up ? await get(port, '/health') : { status: 0, body: '' };
    let j = null; try { j = JSON.parse(h.body); } catch (e) { j = null; }
    yes('on a port the service holds, the wait ends and /health is this service\'s own',
        up && h.status === 200 && !!j && j.ok === true && j.build !== 'not this run');
    await gone(srv);
  }

  console.log('\nbuilds at once:');
  const runs = await Promise.all([1, 2, 3].map(() => runHarness('tests/test-deploy-records.js')));
  for (let i = 0; i < runs.length; i++) {
    const r = runs[i];
    const tail = (r.out.trim().split(/\r?\n/).pop() || '');
    yes('test-deploy-records.js, copy ' + (i + 1) + ' of ' + runs.length + ' started together, passes (' + tail + ')',
        r.code === 0 && / 0 failed$/.test(tail));
    if (r.code !== 0) {
      for (const l of r.out.split(/\r?\n/).filter((x) => /^FAIL|^ {6}\S/.test(x))) { console.log('      copy ' + (i + 1) + ' said: ' + l.trim()); }
    }
  }

  try { fs.rmSync(scratch, { recursive: true, force: true }); } catch (e) { }
  console.log('\n' + pass + ' passed, ' + fail + ' failed');
  process.exitCode = fail ? 1 : 0;
})().catch((e) => { console.log('FAIL  ' + (e && e.stack || e)); process.exitCode = 1; });
