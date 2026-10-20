#!/usr/bin/env node
'use strict';
/*
  bridge.js

  The box's end of ssh from a cloud Claude thread (#2753). Decided by Patrick
  on 19 Oct 2026 (#2750, the logs decision, C): cloud threads get an ssh key
  to the box, "because it needs the VPS for more than just this". A cloud
  thread's proxy carries HTTPS only, so port 22 never opens from there, but a
  WebSocket on 443 goes through (measured 19 Oct). So Caddy hands
  wss://thornswood.net/box/ to this, on loopback, and this joins each
  WebSocket it accepts to the box's own sshd on 127.0.0.1:22. connect.js is
  the cloud end.

  WHO GETS THROUGH. A WebSocket opens only with the bridge's token in
  "Authorization: Bearer", compared in constant time; anything else is a 401
  and closed, and a plain request is a 404. The token only reaches sshd's
  login: a shell still needs the cloud key, which the box accepts only from
  127.0.0.1 (Add-VpsKey.ps1 -OnlyFrom), so that key is no use anywhere but
  through here, and port 22's address list (Set-SshScope.ps1) never needs a
  cloud address. At most MAX_OPEN sessions at once.

  It writes one line per session to its log: when it opened, how it ended
  and how many bytes went each way. No address and no content: it never sees
  inside the ssh session, which is encrypted end to end.

      node bridge.js                 listens on 127.0.0.1:7790
      THORNSWOOD_BRIDGE_PORT         another port
      THORNSWOOD_BRIDGE_TOKEN_FILE   where the token is; token.txt beside
                                     this file when unset
      THORNSWOOD_BRIDGE_TARGET       host:port to join to; 127.0.0.1:22
                                     when unset (the harness points it at
                                     an echo server)

  Install-Bridge.ps1 puts it on the box as the task "Thornswood Bridge",
  LOCAL SERVICE with a SID of its own, like voice and the site (#2578).
*/
const http = require('http');
const net = require('net');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { OP, accept, encode, Reader } = require('./ws.js');

const PORT = Number(process.env.THORNSWOOD_BRIDGE_PORT) || 7790;
const TOKEN_FILE = process.env.THORNSWOOD_BRIDGE_TOKEN_FILE || path.join(__dirname, 'token.txt');
const TARGET = process.env.THORNSWOOD_BRIDGE_TARGET || '127.0.0.1:22';
const MAX_OPEN = 8;
// A ping when nothing has gone either way for this long, and the session is
// let go after three unanswered (voice-server.js says why, #519).
const PING_EVERY = Number(process.env.THORNSWOOD_BRIDGE_PING_MS) || 25000;

// Server-Log.js --stamp puts the time on each line, as it does for voice.
function log(line) {
  console.log(line);
}

// The token is read at every upgrade, so a new one written by
// New-CloudAccess.ps1 counts at once and a removed file refuses everybody.
// Compared as SHA-256 digests so the comparison takes the same time whatever
// the length of what was sent.
function tokenMatches(sent) {
  let want;
  try { want = fs.readFileSync(TOKEN_FILE, 'utf8').trim(); } catch (e) { return false; }
  if (!want || !sent) return false;
  const a = crypto.createHash('sha256').update(want).digest();
  const b = crypto.createHash('sha256').update(sent).digest();
  return crypto.timingSafeEqual(a, b);
}

function refuse(socket, status, why) {
  socket.end('HTTP/1.1 ' + status + '\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');
  log('refused: ' + why);
}

let open = 0;
let seq = 0;

// A plain request gets a 404 with a line nothing else on the box says. The
// site's own 404 is "not here", so Install-Bridge.ps1's checks look for this
// whole line, and an answer from the site is never taken for the bridge (#2875).
const PLAIN = 'box bridge: not here';

const server = http.createServer((req, res) => {
  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end(PLAIN + '\n');
});

server.on('upgrade', (req, socket, head) => {
  socket.on('error', () => {});
  const auth = String(req.headers['authorization'] || '');
  const sent = auth.startsWith('Bearer ') ? auth.slice(7).trim() : '';
  if (req.method !== 'GET' || String(req.headers['upgrade'] || '').toLowerCase() !== 'websocket') return refuse(socket, '400 Bad Request', 'not a WebSocket upgrade');
  if (req.headers['sec-websocket-version'] !== '13' || !req.headers['sec-websocket-key']) return refuse(socket, '400 Bad Request', 'no WebSocket key or version 13');
  if (!tokenMatches(sent)) return refuse(socket, '401 Unauthorized', sent ? 'a token that is not the bridge\'s' : 'no token');
  if (open >= MAX_OPEN) return refuse(socket, '503 Service Unavailable', MAX_OPEN + ' sessions already open');

  const [host, port] = TARGET.split(':');
  const ssh = net.connect({ host, port: Number(port) });
  const id = ++seq;
  const started = Date.now();
  let up = 0;
  let down = 0;
  let ended = '';
  let heard = Date.now();
  let unanswered = 0;
  open++;

  function finish(why) {
    if (ended) return;
    ended = why;
    open--;
    clearInterval(pinger);
    log('session ' + id + ' ended: ' + why + ', ' + Math.round((Date.now() - started) / 1000) + ' s, ' + up + ' bytes in, ' + down + ' bytes out');
    if (!socket.destroyed) {
      try { socket.end(encode(OP.CLOSE, Buffer.from([0x03, 0xe8]), false)); } catch (e) { socket.destroy(); }
    }
    ssh.destroy();
  }

  ssh.once('connect', () => {
    socket.write('HTTP/1.1 101 Switching Protocols\r\n' +
      'Upgrade: websocket\r\n' +
      'Connection: Upgrade\r\n' +
      'Sec-WebSocket-Accept: ' + accept(req.headers['sec-websocket-key']) + '\r\n\r\n');
    log('session ' + id + ' opened (' + open + ' open)');
    if (head && head.length) take(head);
  });
  ssh.on('error', (e) => finish('sshd: ' + e.message));
  ssh.on('end', () => finish('sshd closed it'));
  ssh.on('data', (chunk) => {
    down += chunk.length;
    if (!socket.write(encode(OP.BINARY, chunk, false))) {
      ssh.pause();
      socket.once('drain', () => ssh.resume());
    }
  });

  const reader = new Reader({ masked: true });
  function take(chunk) {
    heard = Date.now();
    unanswered = 0;
    let msgs;
    try { msgs = reader.push(chunk); } catch (e) { return finish('a bad frame: ' + e.message); }
    for (const m of msgs) {
      if (m.op === OP.BINARY) {
        up += m.data.length;
        if (!ssh.write(m.data)) {
          socket.pause();
          ssh.once('drain', () => socket.resume());
        }
      } else if (m.op === OP.PING) {
        socket.write(encode(OP.PONG, m.data, false));
      } else if (m.op === OP.CLOSE) {
        return finish('the cloud end closed it');
      } else if (m.op === OP.TEXT) {
        return finish('a text frame, which ssh never sends');
      }
    }
  }
  socket.on('data', take);
  // The HTTP server keeps its sockets half open, so a cloud end that goes
  // away says so with 'end', and 'close' would wait for this end forever.
  socket.on('end', () => finish('the WebSocket closed'));
  socket.on('close', () => finish('the WebSocket closed'));

  const pinger = setInterval(() => {
    if (Date.now() - heard < PING_EVERY) return;
    if (++unanswered > 3) return finish('the cloud end answered nothing for ' + Math.round((Date.now() - heard) / 1000) + ' s');
    socket.write(encode(OP.PING, Buffer.alloc(0), false));
  }, PING_EVERY);
});

server.listen(PORT, '127.0.0.1', () => {
  log('box bridge listening on 127.0.0.1:' + PORT + ', joining to ' + TARGET + ', token from ' + TOKEN_FILE);
});
