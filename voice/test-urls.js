// Lift the url builders out of the shipped files so this tests them, not a copy.
//
// Since #1304 every client builds https and wss and nothing else: the raw
// port they fell back to without an https address is shut, and the service
// refuses a join token over plain ws. Config.cs's side is held by
// tests/test-1304-voice-tls-only.js.
const fs = require('fs');
const R = require('path').resolve(__dirname, '..');

function lift(src, name) {
  const i = src.indexOf('function ' + name + '(');
  if (i < 0) throw new Error('no ' + name);
  let d = 0, started = false;
  for (let j = i; j < src.length; j++) {
    if (src[j] === '{') { d++; started = true; }
    else if (src[j] === '}') { d--; if (started && d === 0) return src.slice(i, j + 1); }
  }
  throw new Error('unbalanced ' + name);
}

const page = fs.readFileSync(R + '/launcher/voice-host.html', 'utf8');
const pageFns = new Function('cfg', lift(page, 'voiceBase') + '\n' + lift(page, 'voiceSocket') +
  '; return { base: voiceBase, socket: voiceSocket };');

const chat = fs.readFileSync(R + '/game/ui/thornswood-chat.js', 'utf8');
const chatUrl = new Function('CFG', 'HOST', 'PORT', lift(chat, 'url') + '; return url;');

let fail = 0;
function check(what, got, want) {
  const ok = got === want;
  if (!ok) fail++;
  console.log('  ' + (ok ? 'ok   ' : 'FAIL ') + what.padEnd(40) + JSON.stringify(got) + (ok ? '' : '   want ' + JSON.stringify(want)));
}

console.log('the launcher page:');
let f = pageFns({ host: '203.0.113.7', port: '7778' });
check('only host and port: no address', f.socket(), '');
check('only host and port: no base', f.base(), '');
f = pageFns({ host: 'x', port: '1', base: 'https://thornswood.net/voice', socket: 'wss://thornswood.net/voice/' });
check('launcher sent both', f.socket(), 'wss://thornswood.net/voice/');
f = pageFns({ host: 'x', port: '1', base: 'https://thornswood.net/voice' });
check('base only, socket derived', f.socket(), 'wss://thornswood.net/voice/');
f = pageFns({ host: 'x', port: '1', base: 'https://thornswood.net/voice/' });
check('trailing slash trimmed', f.base(), 'https://thornswood.net/voice');
f = pageFns({ host: 'x', port: '1', base: 'http://box/voice' });
check('plain http is no address, not ws', f.socket(), '');
f = pageFns({ host: 'x', port: '1', base: 'https://box/voice', socket: 'ws://box/voice/' });
check('a ws socket is not taken, wss derived', f.socket(), 'wss://box/voice/');

console.log('\nthe chat socket in the game:');
check('no base: no address, not ws', chatUrl({}, '203.0.113.7', 7778)(), '');
check('base set', chatUrl({ base: 'https://thornswood.net/voice' }, 'x', 1)(), 'wss://thornswood.net/voice/');
check('base with trailing slash', chatUrl({ base: 'https://thornswood.net/voice/' }, 'x', 1)(), 'wss://thornswood.net/voice/');
check('dev base', chatUrl({ base: 'https://thornswood.net/voice-dev' }, 'x', 1)(), 'wss://thornswood.net/voice-dev/');
check('plain http base: no address', chatUrl({ base: 'http://box/voice' }, 'x', 1)(), '');

console.log('\n' + (fail ? fail + ' FAILED' : 'all agree with the C# side'));
process.exitCode = fail ? 1 : 0;
