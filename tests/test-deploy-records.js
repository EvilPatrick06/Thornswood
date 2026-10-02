// test-deploy-records.js
//
//     node tests\test-deploy-records.js
//
// Issue #459: the box says over HTTP which commit each part runs. The deploy
// scripts leave a record per part (scripts\deploy\Artifact.ps1); this proves
// the two readers hand them back:
//
//   site  /api/deploys lists every record in the store's current folder.
//         readDeploys is lifted out of site\server.js by its markers and run
//         against a temp folder, and the route is checked to be there, before
//         the admin gate.
//   voice /health carries the record left beside voice-server.js. The real
//         service is started from a temp copy, once without a record and
//         once with one, and asked.
//
// Read only. Writes to temp folders and nowhere else.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const REPO = path.resolve(__dirname, '..');
const CR = String.fromCharCode(13);
const read = (p) => fs.readFileSync(path.join(REPO, p), 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function lift(src, from, to) {
  const a = src.indexOf(from);
  const b = src.indexOf(to, a);
  return (a >= 0 && b > a) ? src.slice(a, b) : '';
}

const record = {
  part: 'thornswood-server-dev', component: 'gamemode',
  name: 'gamemode-0123456789ab-fedcba9876543210.zip',
  commit: '0123456789abcdef0123456789abcdef01234567', edited: false, edits: [],
  sha256: 'fedcba9876543210'.repeat(4), size: 1234, files: 1,
  root: 'C:/Thornswood-Server-Dev', deployedUtc: '2026-09-29T10:00:00Z', from: 'ONE'
};

async function main() {
  // ------------------------------------------------------------------ site
  const server = read('site/server.js');
  const block = lift(server, '// ==== thornswood deploy records ====', '// ==== end thornswood deploy records ====');
  yes('site/server.js has the deploy records block', !!block);
  yes('it reads the store the deploy scripts write, unless told otherwise',
    block.includes("process.env.THORNSWOOD_DEPLOYS_DIR || 'C:\\\\Thornswood-Deploys\\\\current'"));
  const route = server.indexOf("route === '/api/deploys'");
  yes('/api/deploys is a route', route >= 0);
  yes('and it answers with readDeploys of that store', /route === '\/api\/deploys'[^\n]*\n\s*return sendJson\(res, 200, \{ parts: readDeploys\(DEPLOYS_DIR\) \}\)/.test(server));
  const publicRoute = server.indexOf("route === '/api/public'");
  yes('it sits with /api/public, before anything asks anybody to sign in', route >= 0 && publicRoute > route && publicRoute - route < 2000);

  const readDeploys = block ? new Function('fs', 'path', 'process', block + '\nreturn readDeploys;')(fs, path, process) : null;
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ts-deploys-'));
  try {
    fs.writeFileSync(path.join(dir, 'thornswood-server-dev.json'), '\uFEFF' + JSON.stringify(record));
    fs.writeFileSync(path.join(dir, 'thornswood-docs.json'),
      JSON.stringify(Object.assign({}, record, { part: 'thornswood-docs', component: 'site', edited: true, name: 'site-0123456789ab-edited-0000000000000000.zip' })));
    fs.writeFileSync(path.join(dir, 'thornswood-bot.json'), '{ not json');
    fs.writeFileSync(path.join(dir, 'README.txt'), 'not a record');
    const got = readDeploys ? readDeploys(dir) : {};
    yes('every record in the folder is listed by its part', JSON.stringify(Object.keys(got)) === JSON.stringify(['thornswood-bot', 'thornswood-docs', 'thornswood-server-dev']));
    const dev = got['thornswood-server-dev'] || {};
    yes('with its commit, zip, hash and when, a byte order mark or not',
      dev.commit === record.commit && dev.name === record.name && dev.sha256 === record.sha256 && dev.deployedUtc === record.deployedUtc && dev.component === 'gamemode' && dev.edited === false);
    yes('and nothing about where it runs or which machine sent it', !('root' in dev) && !('from' in dev) && !('edits' in dev));
    yes('an edited one says so', (got['thornswood-docs'] || {}).edited === true);
    yes('a record that does not read is named, not dropped, and hides nothing else', (got['thornswood-bot'] || {}).unreadable === true);
    yes('no folder is an empty answer, not a failure', JSON.stringify(readDeploys ? readDeploys(path.join(dir, 'nope')) : null) === '{}');
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }

  // ----------------------------------------------------------------- voice
  const voice = read('voice/voice-server.js');
  yes('voice-server.js reads the record beside itself', voice.includes("path.join(dir, 'thornswood-deploy.json')"));
  yes('and /health carries it', /build: BUILD, deploy: deployRecord\(HERE\)/.test(voice));
  const PORT = 7931;
  async function health(withRecord) {
    const d = fs.mkdtempSync(path.join(os.tmpdir(), 'ts-voice-deploy-'));
    fs.copyFileSync(path.join(REPO, 'voice', 'voice-server.js'), path.join(d, 'voice-server.js'));
    fs.copyFileSync(path.join(REPO, 'voice', 'headlines.js'), path.join(d, 'headlines.js'));
    if (withRecord) fs.writeFileSync(path.join(d, 'thornswood-deploy.json'), JSON.stringify(Object.assign({}, record, { component: 'voice' })));
    const srv = spawn(process.execPath, ['voice-server.js'], { cwd: d,
      env: Object.assign({}, process.env, { THORNSWOOD_VOICE_PORT: String(PORT), THORNSWOOD_SITE: '', THORNSWOOD_VOICE_BIND: '127.0.0.1' }) });
    srv.stdout.on('data', () => {}); srv.stderr.on('data', () => {});
    let h = null;
    try {
      for (let i = 0; i < 60 && !h; i++) {
        try { const r = await fetch('http://127.0.0.1:' + PORT + '/health'); if (r.ok) h = await r.json(); } catch (e) { }
        if (!h) await new Promise((r) => setTimeout(r, 150));
      }
    } finally {
      srv.kill();
      await new Promise((r) => setTimeout(r, 300));
      try { fs.rmSync(d, { recursive: true, force: true }); } catch (e) { }
    }
    return h;
  }
  const none = await health(false);
  yes('the voice service answers /health', !!none && none.ok === true);
  yes('with no record beside it, deploy is null', !!none && none.deploy === null);
  const some = await health(true);
  yes('with one, /health says its commit, zip and hash',
    !!some && !!some.deploy && some.deploy.commit === record.commit && some.deploy.name === record.name && some.deploy.sha256 === record.sha256 && some.deploy.edited === false);
  yes('and not where it runs or who sent it', !!some && !!some.deploy && !('root' in some.deploy) && !('from' in some.deploy));

  console.log('\n' + pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
}
main().catch((e) => { console.log('FAIL  ' + (e && e.stack || e)); process.exit(1); });
