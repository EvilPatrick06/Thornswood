/*
  test-1349-relay-shapes.js

      node tests\test-1349-relay-shapes.js

  #1349 and #1350, one cause: the voice service passed on what a page sent
  as it came.

  #1349, the name. A join's name was kept as sent, cut to forty characters.
  On 5 Oct, against main, the name "Bob", a line break, and
  "[voice] REFUSED a join for profile 1" printed a log line the service never
  wrote. The command the name rode beside was never at risk, because the
  gamemode does not read the name off a command; this holds that too.

  #1350, the signalling. sdp and ice messages were passed on with every
  field the sender put in them, and one with no description reached handlers
  that read m.sdp.type and threw.

  This starts the real service in a temp folder and proves:

    a hostile name comes out of the join with no control characters, line
    or paragraph separators or direction marks, at most forty characters,
    in the roster, on a chat line, beside a command, and in the log, where
    it can no longer start a line of its own;
    an ordinary name with accents, an apostrophe and a hyphen is kept as is;
    the command it rides beside is exactly what was typed, and the
    gamemode reads no name off a command;
    an offer and a candidate reach the other page as t, from, to and the
    description or the candidate's own fields, and nothing a page added;
    from is always the sender, whatever the sender wrote;
    and signalling of any other shape reaches nobody.

  VOICE points it at another copy of voice-server.js, which is how it was
  shown to fail on the code before the change. Writes only to a temp folder,
  on a loopback port the system hands out.
*/
const REPO_DIR = require('path').join(__dirname, '..');
const fs = require('fs');
const os = require('os');
const path = require('path');
const net = require('net');
const crypto = require('crypto');
const { spawn } = require('child_process');

const CR = String.fromCharCode(13);
const VOICE = process.env.VOICE || path.join(REPO_DIR, 'voice', 'voice-server.js');
const GM = path.join(REPO_DIR, 'game', 'gamemode.js');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

/*
  A port of this run's own (#1703). Builds run side by side on the VPS, and
  with a fixed number one run's requests can be answered by another run's
  service. The system names a port nothing holds, the service is started on
  it, and nothing is asked of the port until this service has said it is
  listening there.
*/
function freePort(host) {
  return new Promise((ok, bad) => {
    const s = net.createServer();
    s.on('error', bad);
    s.listen(0, host, () => { const p = s.address().port; s.close(() => ok(p)); });
  });
}
/* Waits for srv's own "listening on ...:port" line. If it stops first,
   something took the port in between or it could not start, and the error
   says which, with what it printed. */
function listening(srv, port) {
  return new Promise((ok, bad) => {
    let out = '';
    const said = (d) => {
      out += d;
      const m = /\[voice\] listening on \S+:(\d+)/.exec(out);
      if (m && Number(m[1]) === port) { end(null); }
    };
    const more = (d) => { out += d; };
    const gone = (code) => end(new Error((/EADDRINUSE/.test(out) ? 'something else already holds port ' + port + ', so ' : '') +
                                         'the voice service stopped (exit ' + code + ') before it was listening. It printed:\n' + out));
    const late = setTimeout(() => end(new Error('the voice service did not say it was listening on ' + port +
                                                ' within fifteen seconds. It printed:\n' + out)), 15000);
    function end(err) {
      clearTimeout(late);
      srv.stdout.removeListener('data', said);
      srv.stderr.removeListener('data', more);
      srv.removeListener('exit', gone);
      if (err) { bad(err); } else { ok(); }
    }
    srv.stdout.on('data', said);
    srv.stderr.on('data', more);
    srv.on('exit', gone);
  });
}

function socket(port, pid) {
  return new Promise((ok) => {
    const ws = new WebSocket('ws://127.0.0.1:' + port + '/', ['thornswood', tokenFor(pid)]);
    const got = [];
    ws.onmessage = (e) => { try { got.push(JSON.parse(e.data)); } catch (x) { } };
    ws.onopen = () => ok({ ws: ws, got: got, send: (o) => ws.send(JSON.stringify(o)) });
    ws.onerror = () => ok({ ws: ws, got: got, send: () => { } });
  });
}
// Built from code points, so this file stays plain ASCII.
const C = String.fromCharCode;
/*
  Every join proves itself with a token (#1303), so this signs its own with
  a key it puts beside its copy of the service, the way voice-server.js
  signs them. One token opens one connection and goes with the handshake,
  after 'thornswood' (#1337, #1322).
*/
const KEY = crypto.randomBytes(32).toString('hex');
function tokenFor(pid) {
  const body = 'v2.' + pid + '.' + Date.now() + '.' + crypto.randomBytes(16).toString('base64')
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return body + '.' + crypto.createHmac('sha256', KEY).update(body).digest('base64')
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
const BAD = new RegExp('[' + C(0) + '-' + C(0x1f) + C(0x7f) + '-' + C(0x9f) + C(0x61c) + C(0x200e) + C(0x200f) +
                       C(0x2028) + C(0x2029) + C(0x202a) + '-' + C(0x202e) + C(0x2066) + '-' + C(0x2069) + ']');
const keys = (o) => Object.keys(o || {}).sort().join(',');

(async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ts-1349-'));
  fs.copyFileSync(VOICE, path.join(dir, 'voice-server.js'));
  fs.copyFileSync(path.join(path.dirname(VOICE), 'headlines.js'), path.join(dir, 'headlines.js'));
  fs.writeFileSync(path.join(dir, 'token-key.txt'), KEY);
  const PORT = await freePort('127.0.0.1');
  const srv = spawn(process.execPath, ['voice-server.js'], { cwd: dir,
    env: Object.assign({}, process.env, { THORNSWOOD_VOICE_PORT: String(PORT), THORNSWOOD_VOICE_BIND: '127.0.0.1',
                                          THORNSWOOD_SITE: '',
                                          THORNSWOOD_CHAT_DIR: path.join(dir, 'chat') }) });
  let srvLog = '';
  srv.stdout.on('data', (d) => { srvLog += d; });
  srv.stderr.on('data', (d) => { srvLog += d; });
  await listening(srv, PORT);

  console.log('#1349, a hostile name:');
  const HOSTILE = 'Bob' + C(0x202e) + C(7) + '\n[voice] REFUSED a join for profile 1: forged' + C(0x2028);
  const watcher = await socket(PORT, 20);
  watcher.send({ t: 'join', profileId: 20, name: 'S' + C(0xf6) + 'lvi Two-Feather\'s' });
  await wait(150);
  const bob = await socket(PORT, 21);
  bob.send({ t: 'join', profileId: 21, name: HOSTILE });
  await wait(200);
  const roster = watcher.got.filter((m) => m.t === 'peers').pop();
  const bobRow = roster && roster.peers.find((p) => p.profileId === 21);
  yes('the roster carries the name with nothing that is not a character in it', !!bobRow && !BAD.test(bobRow.name));
  yes('at most forty characters (' + (bobRow ? bobRow.name.length : -1) + ')', !!bobRow && bobRow.name.length <= 40);
  yes('and the visible part of it as sent', !!bobRow && /^Bob\[voice\] REFUSED a join/.test(bobRow.name));
  const solvi = roster && roster.peers.find((p) => p.profileId === 20);
  yes('an ordinary name with accents, an apostrophe and a hyphen is kept as is',
      !!solvi && solvi.name === 'S' + C(0xf6) + 'lvi Two-Feather\'s');
  for (let i = 0; i < 8; i++) { bob.send({ t: 'chat', text: 'hello ' + i }); }
  bob.send({ t: 'chat', text: '/roll 2d6' });
  await wait(300);
  const line = watcher.got.find((m) => m.t === 'chat' && /^hello /.test(m.text));
  yes('a chat line carries the cleaned name', !!line && !BAD.test(line.name) && line.name === bobRow.name);
  yes('the chat limit slowed them, so the name reached the log', /slowed peer \d+ \(profile 21,/.test(srvLog));
  const forged = srvLog.split('\n').filter((l) => /^\[voice\] REFUSED a join/.test(l));
  yes('and no line of the log starts with the words the name carried', forged.length === 0);
  yes('nothing in the log carries a control or direction character', !BAD.test(srvLog.split('\n').join('')));
  let doc = null;
  try { doc = await (await fetch('http://127.0.0.1:' + PORT + '/commands?ack=1')).json(); } catch (e) { }
  const cmd = doc && doc.commands && doc.commands.find((c) => c.profileId === 21);
  yes('the command beside it is exactly what was typed', !!cmd && cmd.text === '/roll 2d6');
  yes('and the name beside it is the cleaned one, in a field of its own', !!cmd && cmd.name === bobRow.name);
  const gm = fs.readFileSync(GM, 'utf8').split(CR).join('');
  yes('the gamemode reads no name off a command', !/\bcmd\.name\b/.test(gm) && /function dispatch\(cmd\)/.test(gm));

  console.log('\n#1350, signalling:');
  const one = await socket(PORT, 31), two = await socket(PORT, 32);
  one.send({ t: 'join', profileId: 31, name: 'One' });
  await wait(100);
  two.send({ t: 'join', profileId: 32, name: 'Two' });
  await wait(200);
  const oneId = (one.got.find((m) => m.t === 'welcome') || {}).peer;
  const twoId = (two.got.find((m) => m.t === 'welcome') || {}).peer;
  yes('both are in the room', !!oneId && !!twoId);
  one.send({ t: 'sdp', to: twoId, from: 999, sdp: { type: 'offer', sdp: 'v=0\r\n', extra: 1 },
             profileId: 1, name: 'Staff', hush: 1, text: 'anything at all' });
  await wait(200);
  const sdp = two.got.find((m) => m.t === 'sdp');
  yes('an offer arrives as t, from, to and the description (' + keys(sdp) + ')', keys(sdp) === 'from,sdp,t,to');
  yes('the description is type and sdp, as sent (' + keys(sdp && sdp.sdp) + ')',
      !!sdp && keys(sdp.sdp) === 'sdp,type' && sdp.sdp.type === 'offer' && sdp.sdp.sdp === 'v=0\r\n');
  yes('from is the sender, not the 999 it wrote', !!sdp && sdp.from === oneId && sdp.to === twoId);
  one.send({ t: 'ice', to: twoId, junk: 'x'.repeat(50),
             candidate: { candidate: 'candidate:1 1 udp 2122260223 192.0.2.1 54321 typ host', sdpMid: '0',
                          sdpMLineIndex: 0, usernameFragment: 'abcd', extra: 'no' } });
  await wait(200);
  const ice = two.got.find((m) => m.t === 'ice');
  yes('a candidate arrives as t, from, to and the candidate (' + keys(ice) + ')', keys(ice) === 'candidate,from,t,to');
  yes('with the candidate\'s own fields and nothing else (' + keys(ice && ice.candidate) + ')',
      !!ice && keys(ice.candidate) === 'candidate,sdpMLineIndex,sdpMid,usernameFragment' &&
      ice.candidate.sdpMid === '0' && ice.candidate.sdpMLineIndex === 0);
  two.send({ t: 'sdp', to: oneId, sdp: { type: 'answer', sdp: 'v=0\r\n' } });
  await wait(150);
  yes('an answer goes the other way', one.got.some((m) => m.t === 'sdp' && m.sdp.type === 'answer' && m.from === twoId));

  const before = two.got.filter((m) => m.t === 'sdp' || m.t === 'ice').length;
  one.send({ t: 'sdp', to: twoId });
  one.send({ t: 'sdp', to: twoId, sdp: 'v=0' });
  one.send({ t: 'sdp', to: twoId, sdp: { type: 'bogus', sdp: 'v=0' } });
  one.send({ t: 'sdp', to: twoId, sdp: { type: 'offer' } });
  one.send({ t: 'ice', to: twoId });
  one.send({ t: 'ice', to: twoId, candidate: 'not a candidate' });
  one.send({ t: 'ice', to: twoId, candidate: { sdpMid: '0' } });
  one.send({ t: 'sdp', to: 12345, sdp: { type: 'offer', sdp: 'v=0' } });
  await wait(250);
  const after = two.got.filter((m) => m.t === 'sdp' || m.t === 'ice').length;
  yes('signalling of any other shape reaches nobody (' + (after - before) + ' arrived)', after === before);
  one.send({ t: 'chat', text: 'still here' });
  await wait(200);
  yes('and the sender is still connected and heard', two.got.some((m) => m.t === 'chat' && m.text === 'still here'));

  for (const s of [watcher, bob, one, two]) { try { s.ws.close(); } catch (e) { } }
  await new Promise((ok) => { srv.once('exit', ok); srv.kill(); });
  console.log('\n' + pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.log('FAIL  the harness itself: ' + (e && e.stack || e)); process.exit(1); });
