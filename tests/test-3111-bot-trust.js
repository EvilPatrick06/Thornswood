'use strict';
/*
  test-3111-bot-trust.js

      node .\tests\test-3111-bot-trust.js

  Issue #3111: eMudhra's emSign roots in the bot's trust. Eight eMudhra
  intermediates were found on 17 Oct 2026 with keys anyone could recover, and
  certifi 2026.10.19, the newest, still carries three emSign roots because
  Mozilla still lists them. The bot needs none of them, so bot\trust.py
  leaves every eMudhra root out of the bundle bot.py writes at every start and
  names in SSL_CERT_FILE. This holds that:

    A  trust.py run on tests\fixtures\3111-roots.pem (four emSign roots from
       certifi 2026.7.22 and four roots the bot does need) trusts the four it
       needs, names the four it leaves out, and writes exactly those four,
       byte for byte, over whatever was at the path before.
    B  a bundle of nothing but eMudhra roots is refused, not written as an
       empty trust.
    C  bot.py writes the bundle before it imports discord, from its data
       folder, and points SSL_CERT_FILE at it whatever the environment said.
    D  Install-Bot.ps1 packs, sends and parse-checks trust.py with the code,
       runs it against the certifi it installed before anything is stopped,
       and no longer writes an SSL_CERT_FILE of its own into bot.env.json.
    E  certifi is pinned at one version in requirements.in and requirements.txt,
       and the written bundle stays out of git.

  bot\test-3111-trust.py, in the nightly, does A and C again with the real
  certifi the bot pins and the real bot.py import.

  Standard library Python only. Nothing leaves the machine; the scratch folder
  is under the temp folder and removed at the end.
*/
const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawnSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const CR = String.fromCharCode(13);
const read = (rel) => fs.readFileSync(path.join(ROOT, rel), 'utf8').split(CR).join('');
const TRUST = path.join(ROOT, 'bot', 'trust.py');
const FIXTURE = path.join(ROOT, 'tests', 'fixtures', '3111-roots.pem');

let pass = 0, fail = 0;
function yes(what, cond, why) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what + (why ? '\n      ' + why : '')); }
}

// trust.py needs no library, so any Python 3 that runs it will do. The py
// launcher's 3.12 first, as tests\bot-python.js picks, then the plain names.
function findPython() {
  const tried = [];
  for (const c of [{ cmd: 'py', args: ['-3.12'] }, { cmd: 'python3.12', args: [] },
    { cmd: 'python', args: [] }, { cmd: 'python3', args: [] }]) {
    const r = spawnSync(c.cmd, c.args.concat(['-c', 'import ssl, sys; print(sys.version_info[0])']), { encoding: 'utf8' });
    if (r.status === 0 && String(r.stdout).trim() === '3') return c;
    tried.push(c.cmd + ': ' + (r.error ? r.error.code : 'exit ' + r.status));
  }
  return { cmd: null, why: tried.join('; ') };
}

function blocks(text) {
  return text.match(/-----BEGIN CERTIFICATE-----\s[\s\S]*?-----END CERTIFICATE-----/g) || [];
}

const py = findPython();
yes('a Python 3 is on this machine to run trust.py with', !!py.cmd, py.why);
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'test-3111-'));

try {
  if (py.cmd) {
    const run = (args, env) => spawnSync(py.cmd, py.args.concat(['-I']).concat(args),
      { encoding: 'utf8', env: Object.assign({}, process.env, env || {}) });

    // ---- A: the fixture
    const fixture = fs.readFileSync(FIXTURE, 'utf8').split(CR).join('');
    const all = blocks(fixture);
    const r = run([TRUST, FIXTURE]);
    const said = String(r.stdout).split(/\r?\n/).filter(Boolean);
    yes('A1 the fixture holds eight roots, four of them eMudhra\'s', all.length === 8 && (fixture.match(/^# Issuer: [^\n]*O=eMudhra/gm) || []).length === 4);
    yes('A2 trust.py trusts the four the bot needs', r.status === 0 && said[0] === 'trusts 4 roots', r.stdout + r.stderr);
    const out = said.slice(1).sort();
    yes('A3 and names each emSign root it leaves out',
      JSON.stringify(out) === JSON.stringify(['leaves out emSign ECC Root CA - C3', 'leaves out emSign ECC Root CA - G3',
        'leaves out emSign Root CA - C1', 'leaves out emSign Root CA - G1']), out.join(' | '));

    const dest = path.join(scratch, 'roots.pem');
    fs.writeFileSync(dest, 'planted by the harness, never to be trusted\n');
    const w = run(['-c', 'import sys; sys.path.insert(0, sys.argv[1]); import trust; print(trust.write_bundle(sys.argv[2], sys.argv[3]))',
      path.join(ROOT, 'bot'), dest, FIXTURE]);
    const written = fs.existsSync(dest) ? fs.readFileSync(dest, 'utf8') : '';
    const kept = all.slice(4);
    yes('A4 write_bundle writes the four kept roots byte for byte, in order, over what was at the path',
      w.status === 0 && JSON.stringify(blocks(written)) === JSON.stringify(kept) && written.indexOf('planted') === -1, w.stdout + w.stderr);
    yes('A5 nothing written names eMudhra or emSign', written && !/emudhra|emsign/i.test(written));
    yes('A6 and no half written .tmp is left beside it', !fs.existsSync(dest + '.tmp'));

    // ---- B: nothing but eMudhra
    const only = path.join(scratch, 'only-emudhra.pem');
    fs.writeFileSync(only, all.slice(0, 4).join('\n') + '\n');
    const b = run([TRUST, only]);
    yes('B1 a bundle of only eMudhra roots is refused, saying none is left', b.status !== 0 && /no root certificate is left/.test(b.stderr), b.stdout + b.stderr);
  }

  // ---- C: bot.py
  const bot = read('bot/bot.py');
  const iTrust = bot.indexOf('\nimport trust\n');
  const iDiscord = bot.indexOf('\nimport discord\n');
  yes('C1 bot.py imports trust before discord', iTrust > 0 && iDiscord > iTrust);
  const head = bot.slice(iTrust, iDiscord);
  yes('C2 it writes the bundle into its data folder before that import',
    head.indexOf("\nROOTS = os.path.join(DATA_DIR, 'roots.pem')\n") !== -1 &&
    head.indexOf('\n_trusted, _left_out = trust.write_bundle(ROOTS)\n') !== -1 &&
    bot.indexOf('\nDATA_DIR = ') !== -1 && bot.indexOf('\nDATA_DIR = ') < iTrust);
  yes('C3 and points SSL_CERT_FILE at it on every start, whatever the environment named',
    head.indexOf("\nos.environ['SSL_CERT_FILE'] = ROOTS\n") !== -1 &&
    bot.indexOf("if not os.environ.get('SSL_CERT_FILE')") === -1 &&
    !/certifi\.where\(\)/.test(bot));

  // ---- D: Install-Bot.ps1
  const ib = read('scripts/deploy/Install-Bot.ps1');
  yes('D1 Install-Bot packs trust.py into the bot artifact', /New-ThornswoodArtifact -Component bot [^\n]*'bot\/trust\.py'/.test(ib));
  yes('D2 sends it with the code and parse-checks it on the box',
    ib.indexOf("foreach ($f in 'bot.py', '_pyguard.py', 'trust.py', 'card.py',") !== -1 &&
    ib.indexOf("$hashes @('bot.py', '_pyguard.py', 'trust.py', 'card.py')") !== -1);
  yes('D3 runs trust.py against the installed certifi and stops before the bot is touched when it cannot',
    ib.indexOf("& python '$rootWin\\$stageName\\trust.py'") !== -1 &&
    /-match 'ROOTS NOT MADE'\) \{ Die /.test(ib));
  yes('D4 writes no SSL_CERT_FILE or REQUESTS_CA_BUNDLE of its own, and takes out one an earlier run wrote',
    !/\$env2\['(SSL_CERT_FILE|REQUESTS_CA_BUNDLE)'\]\s*=/.test(ib) &&
    ib.indexOf("foreach (`$k in 'SSL_CERT_FILE', 'REQUESTS_CA_BUNDLE') { if (`$env2.Contains(`$k)) { `$env2.Remove(`$k) } }") !== -1);

  // ---- E: the pin and git
  const pin = (text) => (text.match(/^certifi==(\S+)/m) || [])[1];
  const inPin = pin(read('bot/requirements.in'));
  const txtPin = pin(read('bot/requirements.txt'));
  yes('E1 certifi is pinned at one version in requirements.in and requirements.txt', !!inPin && inPin === txtPin, inPin + ' / ' + txtPin);
  const gi = read('.gitignore');
  yes('E2 bot/roots.pem and its .tmp stay out of git', /^bot\/roots\.pem$/m.test(gi) && /^bot\/roots\.pem\.tmp$/m.test(gi));
} finally {
  fs.rmSync(scratch, { recursive: true, force: true });
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
