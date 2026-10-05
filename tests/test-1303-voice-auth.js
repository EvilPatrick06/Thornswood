// test-1303-voice-auth.js
//
//     node tests\test-1303-voice-auth.js
//
// #1303, #1315. Who the voice service lets in, on every pull request.
//
// The voice harnesses beside the service (voice\test-*.js) run every night,
// not in Launcher builds. A change that let an unproven join back in, or
// minted a join token without the site's yes, would let a stranger into
// every conversation and onto the roster, and would sit on main until the
// next night. So this runs voice\test-auth.js, which starts the real
// voice-server.js beside a small site of its own and drives /token and the
// join, and fails with it. Nothing is copied out of it, so the two cannot
// drift apart.
//
// Writes only to temp folders, through voice\test-auth.js.
const path = require('path');
const { spawnSync } = require('child_process');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const r = spawnSync(process.execPath, [path.join(__dirname, '..', 'voice', 'test-auth.js')],
  { encoding: 'utf8', timeout: 90000 });
const out = String(r.stdout || '') + String(r.stderr || '');
console.log(out.split('\n').map((l) => '    ' + l).join('\n'));
const m = /(\d+) passed, (\d+) failed/.exec(out);
yes('voice\\test-auth.js ran to the end', !!m && !r.error);
yes('and every check in it passed (' + (m ? m[1] + ' passed, ' + m[2] + ' failed' : 'no count') + ')',
    !!m && Number(m[2]) === 0 && Number(m[1]) >= 20 && r.status === 0);
yes('including the ones this issue is about: no unproven join, no token without the site',
    /ok\s+no token at all is refused/.test(out) && /ok\s+a service with no THORNSWOOD_SITE mints nothing: 503/.test(out) &&
    /ok\s+the site never answered: 503/.test(out));

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exitCode = fail ? 1 : 0;
