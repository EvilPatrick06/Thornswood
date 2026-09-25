// Lift the url builders out of the shipped files so this tests them, not a copy.
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

const page = fs.readFileSync(R + '/tools/launcher/voice-host.html', 'utf8');
const pageFns = new Function('cfg', lift(page, 'voiceBase') + '\n' + lift(page, 'voiceSocket') +
  '; return { base: voiceBase, socket: voiceSocket };');

const chat = fs.readFileSync(R + '/game/ui/thornswood-chat.js', 'utf8');
const chatUrl = new Function('CFG', 'HOST', 'PORT', lift(chat, 'url') + '; return url;');

let fail = 0;
function check(what, got, want) {
  const ok = got === want;
  if (!ok) fail++;
  console.log('  ' + (ok ? 'ok   ' : 'FAIL ') + what.padEnd(34) + got + (ok ? '' : '   want ' + want));
}

console.log('the launcher page:');
let f = pageFns({ host: '192.135.112.23', port: '7778' });
check('nothing set, as today', f.socket(), 'ws://192.135.112.23:7778/');
check('nothing set, base', f.base(), 'http://192.135.112.23:7778');
f = pageFns({ host: 'x', port: '1', base: 'https://thornswood.net/voice', socket: 'wss://thornswood.net/voice/' });
check('launcher sent both', f.socket(), 'wss://thornswood.net/voice/');
f = pageFns({ host: 'x', port: '1', base: 'https://thornswood.net/voice' });
check('base only, socket derived', f.socket(), 'wss://thornswood.net/voice/');
f = pageFns({ host: 'x', port: '1', base: 'https://thornswood.net/voice/' });
check('trailing slash trimmed', f.base(), 'https://thornswood.net/voice');
f = pageFns({ host: 'x', port: '1', base: 'http://box/voice' });
check('plain http gives ws', f.socket(), 'ws://box/voice/');

console.log('\nthe chat socket in the game:');
check('no base, as today', chatUrl({}, '192.135.112.23', 7778)(), 'ws://192.135.112.23:7778/');
check('base set', chatUrl({ base: 'https://thornswood.net/voice' }, 'x', 1)(), 'wss://thornswood.net/voice/');
check('base with trailing slash', chatUrl({ base: 'https://thornswood.net/voice/' }, 'x', 1)(), 'wss://thornswood.net/voice/');
check('dev base', chatUrl({ base: 'https://thornswood.net/voice-dev' }, 'x', 1)(), 'wss://thornswood.net/voice-dev/');

console.log('\n' + (fail ? fail + ' FAILED' : 'all agree with the C# side'));
process.exitCode = fail ? 1 : 0;
