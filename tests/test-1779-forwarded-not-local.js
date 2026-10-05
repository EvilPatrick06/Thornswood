/*
  test-1779-forwarded-not-local.js

      node tests\test-1779-forwarded-not-local.js

  #1779. The routes only the gamemode uses (/positions, /commands,
  /commands/ack, /silenced, /textmute, /say) decided "this machine" by the
  socket's address alone. Caddy carries https://thornswood.net/voice/ to the
  service from 127.0.0.1, so a request from anybody on the internet passed
  as the gamemode: on 5 Oct, against main, a stranger read a join pass out
  of GET /commands, said a line to everybody as Staff through POST /say, and
  silenced somebody through POST /silenced.

  This starts the real service in a temp folder and puts a forwarder in
  front of it shaped like Caddy's reverse_proxy (the same Host, and
  X-Forwarded-For, X-Forwarded-Proto and X-Forwarded-Host added, upgrades
  carried). It proves:

    through the forwarder, every one of the six answers 403, gives nothing
    away and changes nothing;
    straight, a request carrying Forwarded or X-Real-IP is refused the same;
    straight on loopback with no such header, which is how the gamemode asks,
    every one of them still works;
    through the forwarder, /health, /ice, the page and the socket still work,
    because those are meant for everybody;
    and the gamemode's own requests to the service carry no forwarding header.

  VOICE points it at another copy of voice-server.js, which is how it was
  shown to fail on the code before the change. Writes only to a temp folder,
  on loopback ports the system hands out.
*/
const REPO_DIR = require('path').join(__dirname, '..');
const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');
const net = require('net');
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

/*
  Caddy's reverse_proxy, as far as this needs it: the Host as asked, the
  three X-Forwarded headers it always adds, and an upgrade carried through
  as bytes. It reaches the service from 127.0.0.1, as Caddy does on the VPS.
*/
function forwarder(target) {
  const s = http.createServer((req, res) => {
    const headers = Object.assign({}, req.headers, {
      'x-forwarded-for': '203.0.113.7', 'x-forwarded-proto': 'https', 'x-forwarded-host': req.headers.host || ''
    });
    const up = http.request({ host: '127.0.0.1', port: target, path: req.url, method: req.method, headers: headers },
      (r) => { res.writeHead(r.statusCode, r.headers); r.pipe(res); });
    up.on('error', () => { try { res.writeHead(502).end(); } catch (e) { } });
    req.pipe(up);
  });
  s.on('upgrade', (req, sock, head) => {
    const c = net.connect(target, '127.0.0.1', () => {
      let h = req.method + ' ' + req.url + ' HTTP/1.1\r\n';
      const hs = Object.assign({}, req.headers, { 'x-forwarded-for': '203.0.113.7' });
      for (const k of Object.keys(hs)) { h += k + ': ' + hs[k] + '\r\n'; }
      c.write(h + '\r\n');
      if (head && head.length) { c.write(head); }
      c.pipe(sock); sock.pipe(c);
    });
    c.on('error', () => sock.destroy());
    sock.on('error', () => c.destroy());
  });
  return new Promise((ok) => s.listen(0, '127.0.0.1', () => ok({ port: s.address().port, server: s })));
}

async function ask(port, method, where, body, headers) {
  try {
    const r = await fetch('http://127.0.0.1:' + port + where, {
      method: method, headers: headers || {},
      body: body == null ? undefined : JSON.stringify(body)
    });
    return { status: r.status, text: await r.text() };
  } catch (e) { return { status: 0, text: String(e && e.message) }; }
}

function socket(port) {
  return new Promise((ok) => {
    const ws = new WebSocket('ws://127.0.0.1:' + port + '/');
    const got = [];
    ws.onmessage = (e) => { try { got.push(JSON.parse(e.data)); } catch (x) { } };
    ws.onopen = () => ok({ ws: ws, got: got, open: true });
    ws.onerror = () => ok({ ws: ws, got: got, open: false });
  });
}

(async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ts-1779-'));
  fs.copyFileSync(VOICE, path.join(dir, 'voice-server.js'));
  fs.copyFileSync(path.join(path.dirname(VOICE), 'headlines.js'), path.join(dir, 'headlines.js'));
  fs.mkdirSync(path.join(dir, 'public'));
  for (const n of fs.readdirSync(path.join(REPO_DIR, 'voice', 'public'))) {
    fs.copyFileSync(path.join(REPO_DIR, 'voice', 'public', n), path.join(dir, 'public', n));
  }
  const PORT = await freePort('127.0.0.1');
  const srv = spawn(process.execPath, ['voice-server.js'], { cwd: dir,
    env: Object.assign({}, process.env, { THORNSWOOD_VOICE_PORT: String(PORT), THORNSWOOD_VOICE_BIND: '127.0.0.1',
                                          THORNSWOOD_VOICE_AUTH: 'off', THORNSWOOD_SITE: '',
                                          THORNSWOOD_CHAT_DIR: path.join(dir, 'chat') }) });
  let srvLog = '';
  srv.stdout.on('data', (d) => { srvLog += d; });
  srv.stderr.on('data', (d) => { srvLog += d; });
  await listening(srv, PORT);
  const fwd = await forwarder(PORT);

  // Somebody in the world, straight on the socket, who types a join pass.
  const alva = await socket(PORT);
  alva.ws.send(JSON.stringify({ t: 'join', profileId: 5, name: 'Alva' }));
  await wait(150);
  alva.ws.send(JSON.stringify({ t: 'chat', text: '/joinpass SECRETPASS-1779' }));
  await wait(150);

  console.log('through a Caddy-shaped forwarder, a stranger:');
  let r = await ask(fwd.port, 'GET', '/commands?ack=1');
  yes('GET /commands answers 403 (it answered ' + r.status + ')', r.status === 403);
  yes('and the join pass typed a moment ago is not in the answer', r.text.indexOf('SECRETPASS-1779') < 0);
  const before = alva.got.length;
  r = await ask(fwd.port, 'POST', '/say', { name: 'Staff', text: 'Server restarting now, log out' });
  await wait(150);
  yes('POST /say answers 403 (it answered ' + r.status + ')', r.status === 403);
  yes('and nobody is sent the line', !alva.got.slice(before).some((m) => m.t === 'chat' && /restarting/.test(m.text)));
  r = await ask(fwd.port, 'POST', '/silenced', { profiles: { 5: Date.now() + 3600000 } });
  await wait(100);
  yes('POST /silenced answers 403 (it answered ' + r.status + ')', r.status === 403);
  yes('and nobody is silenced', !alva.got.some((m) => m.t === 'hush' && m.on === true));
  r = await ask(fwd.port, 'POST', '/positions', { who: [{ profileId: 5, pos: [1, 2, 3], cell: 'x', name: 'Moved' }], requirePass: true });
  yes('POST /positions answers 403 (it answered ' + r.status + ')', r.status === 403);
  r = await ask(PORT, 'GET', '/health');
  yes('and the positions it sent were not taken', r.status === 200 && JSON.parse(r.text).tracked === 0);
  r = await ask(fwd.port, 'POST', '/commands/ack', { ids: [] });
  yes('POST /commands/ack answers 403 (it answered ' + r.status + ')', r.status === 403);
  r = await ask(fwd.port, 'POST', '/textmute', { by: {} });
  yes('POST /textmute answers 403 (it answered ' + r.status + ')', r.status === 403);

  console.log('\nstraight on loopback, with a proxy\'s header of another name:');
  r = await ask(PORT, 'GET', '/commands?ack=1', null, { forwarded: 'for=203.0.113.7' });
  yes('Forwarded is refused (' + r.status + ')', r.status === 403 && r.text.indexOf('SECRETPASS-1779') < 0);
  r = await ask(PORT, 'GET', '/commands?ack=1', null, { 'x-real-ip': '203.0.113.7' });
  yes('X-Real-IP is refused (' + r.status + ')', r.status === 403 && r.text.indexOf('SECRETPASS-1779') < 0);
  r = await ask(PORT, 'POST', '/positions', { who: [] }, { 'x-forwarded-for': '203.0.113.7' });
  yes('and X-Forwarded-For on /positions (' + r.status + ')', r.status === 403);

  console.log('\nthe gamemode, straight on loopback with no such header:');
  r = await ask(PORT, 'GET', '/commands?ack=1');
  let doc = null;
  try { doc = JSON.parse(r.text); } catch (e) { }
  const cmd = doc && doc.commands && doc.commands.find((c) => /^\/joinpass /.test(c.text));
  yes('GET /commands answers 200 with the command waiting', r.status === 200 && !!cmd);
  r = await ask(PORT, 'POST', '/commands/ack', { ids: cmd ? [cmd.id] : [] });
  yes('POST /commands/ack takes it away', r.status === 200 && /"removed":1/.test(r.text));
  const mark = alva.got.length;
  r = await ask(PORT, 'POST', '/say', { profileId: 5, text: 'Only you can read this.' });
  await wait(150);
  yes('POST /say answers 204 and the line arrives', r.status === 204 &&
      alva.got.slice(mark).some((m) => m.t === 'chat' && m.text === 'Only you can read this.'));
  r = await ask(PORT, 'POST', '/positions', { who: [{ profileId: 5, pos: [1, 2, 3], cell: 'x', name: 'Alva' }] });
  yes('POST /positions answers 204', r.status === 204);
  r = await ask(PORT, 'GET', '/health');
  yes('and the position is taken', r.status === 200 && JSON.parse(r.text).tracked === 1);
  r = await ask(PORT, 'POST', '/silenced', { profiles: {} });
  yes('POST /silenced answers 200', r.status === 200);
  r = await ask(PORT, 'POST', '/textmute', { by: {} });
  yes('POST /textmute answers 200', r.status === 200);

  console.log('\nthrough the forwarder, what is meant for everybody:');
  r = await ask(fwd.port, 'GET', '/health');
  yes('/health answers 200', r.status === 200 && /"ok":true/.test(r.text));
  r = await ask(fwd.port, 'GET', '/ice');
  yes('/ice answers 200', r.status === 200 && /iceServers/.test(r.text));
  r = await ask(fwd.port, 'GET', '/');
  yes('the page answers 200', r.status === 200);
  const viaSite = await socket(fwd.port);
  viaSite.ws.send(JSON.stringify({ t: 'join', profileId: 6, name: 'Brand' }));
  await wait(200);
  yes('and the socket opens and joins', viaSite.open && viaSite.got.some((m) => m.t === 'welcome'));

  console.log('\nthe gamemode\'s side:');
  const gm = fs.readFileSync(GM, 'utf8').split(CR).join('');
  yes('gamemode.js asks the voice service on 127.0.0.1', /host: '127\.0\.0\.1', port: (voicePort\(\)|VOICE_PORT)/.test(gm));
  yes('and never sends a forwarding header', !/x-forwarded|x-real-ip|['"]forwarded['"]/i.test(gm));

  try { alva.ws.close(); viaSite.ws.close(); } catch (e) { }
  fwd.server.close();
  await new Promise((ok) => { srv.once('exit', ok); srv.kill(); });
  console.log('\n' + pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.log('FAIL  the harness itself: ' + (e && e.stack || e)); process.exit(1); });
