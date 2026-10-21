/*
  test-3055-cloud-session.js

  #3055. A cloud thread had no Python that loads the bot, so the bot
  harnesses failed or skipped there over nothing the thread changed.
  scripts/dev/Setup-CloudSession.sh puts bot/requirements.txt into python3.12:
  the cloud environment's setup script runs it with --register, which adds it
  to the user's Claude settings as a SessionStart hook, and the hook runs it at
  every cloud session start.

  A  nothing in the repository registers it, so a Claude on One or on a
     developer's PC never runs it, and it installs exactly the bot's pins:
     bot/requirements.txt, by hash, wheels only, into python3.12.
  B  as the hook, outside a cloud session (CLAUDE_CODE_REMOTE not true) it
     does nothing at all: no output, and no Python asked.
  C  in a cloud session it runs that one pip line, says one line when it
     worked, and when pip fails it says so with pip's own words and exit 1.
  D  --register adds the hook once to the settings it is pointed at and keeps
     every other key; off Linux it refuses and writes nothing.

  B to D run the script with bash and a stand-in python3.12 that only writes
  down how it was called, so nothing is installed. They need a Linux bash: on
  Windows `bash` can be WSL's or Git's, and the script never runs there, so
  they say SKIP. Writes only its own temp folder.
*/
const fs = require('fs');
const os = require('os');
const path = require('path');
const cp = require('child_process');

const ROOT = path.join(__dirname, '..');
const SCRIPT = path.join(ROOT, 'scripts', 'dev', 'Setup-CloudSession.sh');
let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

// ---- A ----------------------------------------------------------------------
yes('A1 scripts/dev/Setup-CloudSession.sh is in the repository', fs.existsSync(SCRIPT));
// A Windows checkout can hold it CRLF (A5 checks what is stored), so the
// text is read without CRs.
const src = fs.existsSync(SCRIPT) ? fs.readFileSync(SCRIPT, 'utf8').split('\r').join('') : '';
let claudeFiles = [];
try {
  claudeFiles = cp.execFileSync('git', ['ls-files', '-z', '--', '.claude'], { cwd: ROOT, encoding: 'utf8' })
    .split('\0').filter(Boolean)
    .filter(function (f) { return fs.readFileSync(path.join(ROOT, f), 'utf8').indexOf('Setup-CloudSession') >= 0; });
}
catch (e) { console.log('NOTE  git did not answer, so .claude was not read: ' + e.message); }
yes('A2 no file the repository carries under .claude runs it (it is the cloud environment\'s, never One\'s)' +
  (claudeFiles.length ? ' (' + claudeFiles.join('; ') + ')' : ''), claudeFiles.length === 0);
const pipLine = (/python3\.12 -m pip install[^\n]*\\\n[^\n]*/.exec(src) || [''])[0];
yes('A3 it installs into python3.12 with --require-hashes and --only-binary :all:',
  pipLine.indexOf('--require-hashes') >= 0 && pipLine.indexOf('--only-binary :all:') >= 0);
yes('A4 from bot/requirements.txt, the bot\'s own pins, and from no other list',
  pipLine.indexOf('-r "$repo/bot/requirements.txt"') >= 0 && (src.match(/ -r /g) || []).length === 1);
// Stored LF is what a Linux checkout gets; a Windows one may hold it CRLF,
// and never runs it.
let eol = '';
try { eol = cp.execFileSync('git', ['ls-files', '--eol', '--', 'scripts/dev/Setup-CloudSession.sh'], { cwd: ROOT, encoding: 'utf8' }).trim(); }
catch (e) { eol = 'git did not answer: ' + e.message; }
yes('A5 it is stored LF, so bash reads it on the Linux machine it runs on (' + eol + ')', /^i\/lf\s/.test(eol));

// ---- B to D -------------------------------------------------------------------
if (process.platform === 'win32') {
  console.log('SKIP  B to D: Windows, where the script never runs and bash may be WSL\'s (A checked it here)');
}
else {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 't3055-'));
  const bin = path.join(tmp, 'bin');
  fs.mkdirSync(bin);
  const calls = path.join(tmp, 'calls.txt');
  const stub = path.join(bin, 'python3.12');
  function stand(code) {
    fs.writeFileSync(stub, '#!/bin/sh\necho "$*" >> \'' + calls + '\'\n' +
      (code ? 'echo "ERROR: stand-in pip said no" >&2\n' : '') + 'exit ' + code + '\n');
    fs.chmodSync(stub, 0o755);
  }
  function run(args, env) {
    const e = Object.assign({}, process.env, { PATH: bin + path.delimiter + process.env.PATH }, env || {});
    for (const k of Object.keys(e)) { if (e[k] === null) { delete e[k]; } }
    return cp.spawnSync('bash', [SCRIPT].concat(args || []), { env: e, encoding: 'utf8' });
  }
  function called() { return fs.existsSync(calls) ? fs.readFileSync(calls, 'utf8') : ''; }

  try {
    stand(0);
    // B
    let r = run([], { CLAUDE_CODE_REMOTE: null });
    yes('B1 with CLAUDE_CODE_REMOTE unset it exits 0 and says nothing',
      r.status === 0 && r.stdout === '' && r.stderr === '');
    r = run([], { CLAUDE_CODE_REMOTE: 'false' });
    yes('B2 with CLAUDE_CODE_REMOTE false it exits 0 and says nothing', r.status === 0 && r.stdout === '' && r.stderr === '');
    yes('B3 and no Python was asked either time', called() === '');

    // C
    r = run([], { CLAUDE_CODE_REMOTE: 'true' });
    const line = called().trim();
    yes('C1 in a cloud session it exits 0 (' + r.status + ') with one line', r.status === 0 && r.stdout.trim().split('\n').length === 1);
    yes('C2 having asked python3.12 for exactly bot/requirements.txt, by hash, wheels only (' + line + ')',
      line.indexOf('-m pip install --user --break-system-packages --require-hashes --only-binary :all:') === 0 &&
      line.indexOf('-r ' + path.join(ROOT, 'bot', 'requirements.txt')) >= 0);
    fs.unlinkSync(calls);
    stand(1);
    r = run([], { CLAUDE_CODE_REMOTE: 'true' });
    yes('C3 when pip fails it exits 1 and passes on pip\'s words',
      r.status === 1 && r.stderr.indexOf('stand-in pip said no') >= 0 && r.stderr.indexOf('bot/requirements.txt') >= 0);
    stand(0);

    // D
    const cfg = path.join(tmp, 'cfg');
    fs.mkdirSync(cfg);
    const settings = path.join(cfg, 'settings.json');
    fs.writeFileSync(settings, JSON.stringify({ model: 'kept', hooks: { Stop: [{ hooks: [{ type: 'command', command: 'true' }] }] } }));
    const uname = cp.spawnSync('uname', ['-s'], { encoding: 'utf8' }).stdout.trim();
    r = run(['--register'], { CLAUDE_CONFIG_DIR: cfg, CLAUDE_CODE_REMOTE: null });
    if (uname === 'Linux') {
      r = run(['--register'], { CLAUDE_CONFIG_DIR: cfg, CLAUDE_CODE_REMOTE: null });
      const s = JSON.parse(fs.readFileSync(settings, 'utf8'));
      const start = ((s.hooks || {}).SessionStart || []);
      const cmds = [].concat.apply([], start.map(function (g) { return (g.hooks || []).map(function (h) { return h.command; }); }));
      yes('D1 two runs of --register exit 0 and leave one SessionStart hook', r.status === 0 && cmds.length === 1);
      yes('D2 which runs this script when it is there (' + cmds[0] + ')',
        cmds.length === 1 && cmds[0] === "test ! -f '" + SCRIPT + "' || bash '" + SCRIPT + "'");
      yes('D3 and every other key in the settings is as it was',
        s.model === 'kept' && JSON.stringify(s.hooks.Stop) === JSON.stringify([{ hooks: [{ type: 'command', command: 'true' }] }]));
      yes('D4 --register installs too, so the image holds the libraries before any session', /--require-hashes/.test(called()));
    }
    else {
      yes('D1 off Linux (' + uname + ') --register refuses with exit 2 and writes nothing',
        r.status === 2 && fs.readFileSync(settings, 'utf8').indexOf('SessionStart') < 0 && called() === '');
    }
    r = run(['--bogus'], { CLAUDE_CODE_REMOTE: 'true' });
    yes('D5 an option it does not know stops it with exit 2', r.status === 2);
  }
  finally { fs.rmSync(tmp, { recursive: true, force: true }); }
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
