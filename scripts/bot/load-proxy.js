// scripts/bot/load-proxy.js
//
// #4623. The load test's byte counter. Every bot connects to this instead of
// the game server, and this passes each datagram on unchanged, both ways,
// counting it. Each bot gets a socket of its own towards the server, so the
// server sees one address per bot exactly as it sees one per game. The bot
// client exposes no byte counts of its own and loopback traffic shows in no
// interface counter, so this is where the bandwidth of a person is read:
// every byte of SLikeNet's own, its acknowledgements and resends included.
// On the wire each datagram also carries 28 bytes of IPv4 and UDP header,
// which the load test adds per datagram.
//
// Run by Load-Test.js as a child with IPC:
//   node load-proxy.js --target 127.0.0.1:<port>
// It sends { listening: <port> } once it listens, answers
// { report: true } with { report: { clients, up, upDatagrams, down,
// downDatagrams } } (up is bots to the server), and ends on { stop: true }.
'use strict';
const dgram = require('dgram');

function makeProxy(targetHost, targetPort, onReady) {
  const front = dgram.createSocket('udp4');
  const clients = new Map();  // "address:port" of a bot -> { back, up, upD, down, downD }
  const totals = { up: 0, upDatagrams: 0, down: 0, downDatagrams: 0 };
  const problems = [];

  front.on('message', (buf, from) => {
    const key = from.address + ':' + from.port;
    let c = clients.get(key);
    if (!c) {
      const back = dgram.createSocket('udp4');
      c = { back, ready: false, queue: [] };
      clients.set(key, c);
      back.on('message', (reply) => {
        totals.down += reply.length; totals.downDatagrams++;
        front.send(reply, from.port, from.address);
      });
      back.on('error', (e) => { problems.push('the socket towards the server for ' + key + ': ' + e.message); });
      back.connect(targetPort, targetHost, () => {
        c.ready = true;
        for (const q of c.queue) { back.send(q); }
        c.queue = [];
      });
    }
    totals.up += buf.length; totals.upDatagrams++;
    if (c.ready) { c.back.send(buf); } else { c.queue.push(buf); }
  });
  front.on('error', (e) => { problems.push('the socket the bots connect to: ' + e.message); });
  front.bind(0, '127.0.0.1', () => onReady(front.address().port));

  return {
    report: () => Object.assign({ clients: clients.size, problems: problems.slice() }, totals),
    close: () => {
      for (const c of clients.values()) { c.back.close(); }
      front.close();
    }
  };
}

function main() {
  const i = process.argv.indexOf('--target');
  const target = i >= 0 ? String(process.argv[i + 1] || '') : '';
  const m = /^([^:]+):(\d+)$/.exec(target);
  if (!m || !process.send) {
    console.log('node load-proxy.js --target <host>:<port>, started by Load-Test.js with IPC');
    process.exit(2);
  }
  const proxy = makeProxy(m[1], Number(m[2]), (port) => process.send({ listening: port }));
  process.on('message', (msg) => {
    if (msg && msg.report) { process.send({ report: proxy.report() }); }
    if (msg && msg.stop) { proxy.close(); process.exit(0); }
  });
  process.on('disconnect', () => { proxy.close(); process.exit(0); });
}

if (require.main === module) { main(); }

module.exports = { makeProxy };
