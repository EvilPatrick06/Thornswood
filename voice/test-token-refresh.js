/*
  Proves setToken does what entry 6's gap needed: it changes what the NEXT
  socket sends, and changes nothing about the one already open.

  Runs the shipped game/ui/thornswood-chat.js in a sandboxed `window`,
  with a fake WebSocket that records what gets sent. Nothing here is a stand-in
  for the file under test.
*/
const vm = require('vm');
const fs = require('fs');
const path = require('path');

const SRC = fs.readFileSync(path.join(__dirname, '..', 'game', 'ui', 'thornswood-chat.js'), 'utf8');

let pass = 0, fail = 0;
function check(what, got, want) {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  console.log((ok ? '  ok   ' : '  FAIL ') + what + (ok ? '' : '  got ' + JSON.stringify(got) + ' want ' + JSON.stringify(want)));
  ok ? pass++ : fail++;
}

class FakeSocket {
  constructor(url) {
    FakeSocket.instances.push(this);
    this.url = url;
    this.readyState = 0;
    this.sent = [];
    setImmediate(() => { this.readyState = 1; if (this.onopen) this.onopen(); });
  }
  send(m) { this.sent.push(JSON.parse(m)); }
  close() { this.readyState = 3; if (this.onclose) this.onclose(); }
}
FakeSocket.instances = [];

const win = { THORNSWOOD: { host: '127.0.0.1', port: 7778, profileId: 4242, name: 'tester', token: 'v1.original-token' } };
const sandbox = {
  window: win,
  WebSocket: FakeSocket,
  console,
  // Run every timer immediately: this test is about what a reconnect sends,
  // not about how long the backoff actually waits.
  setTimeout: (fn) => { fn(); return 0; },
  clearTimeout: () => {},
  // The page's own keepalive (issue #519) ticks on this; nothing here waits
  // long enough for it to matter.
  setInterval: () => 0,
  clearInterval: () => {},
};
vm.createContext(sandbox);
vm.runInContext(SRC, sandbox);

(async () => {
  await new Promise((r) => setImmediate(r));
  const first = FakeSocket.instances[0];
  check('the first join carries the token injected at load', first.sent[0].token, 'v1.original-token');

  // The renewed token arrives mid-session, same as Voice.cs pushing one in.
  sandbox.window.thornswoodNet.post; // touch, no-op
  sandbox.window.thornswoodNet.setToken('v1.renewed-token');

  check('the open socket was not touched', first.readyState, 1);
  check('and nothing new was opened', FakeSocket.instances.length, 1);

  // The kind of event this exists for: the socket drops on its own later.
  first.close();
  await new Promise((r) => setImmediate(r));
  await new Promise((r) => setImmediate(r));
  const second = FakeSocket.instances[1];
  check('a reconnect exists', !!second, true);
  if (second) {
    check('and it carries the renewed token, not the stale one', second.sent[0].token, 'v1.renewed-token');
  }

  console.log('\n' + pass + ' passed, ' + fail + ' failed');
  process.exitCode = fail ? 1 : 0;
})();
