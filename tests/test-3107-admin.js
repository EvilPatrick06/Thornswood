// #3107 (Patrick's A of 22 Oct 2026): the box's GitHub admin service.
//
// A cloud Claude thread cannot change a runner's labels (its proxy refuses
// every actions/runners path) and a workflow's own token cannot either, so a
// GitHub App made for Thornswood holds that right, its key kept on the box by
// scripts/vps/admin/admin.js, which listens only to a run of
// .github/workflows/github-admin.yml on main and only makes GitHub match
// main's runner records. This runs it for real on loopback:
//   1. the OIDC check, against tokens signed here with a key a stand-in for
//      GitHub's published keys serves: a run of github-admin.yml on main,
//      started by hand or by a push, passes; a token from another workflow,
//      another branch, a pull request, another repository, another
//      audience or issuer, an expired one, one signed by a key GitHub does
//      not publish, one whose body was changed after signing, and one that
//      says it needs no signature, each fail;
//   2. the App's own token: RS256, signed by the App's key, issued by its id,
//      ten minutes at most;
//   3. the records' rules and the plan for one record, the cases #2994's
//      test held Set-BuildRunners.ps1 to: a listed runner without the label
//      gets it, a VPS runner or an off-box runner the record does not list
//      loses it, a right one is left alone, a listed runner GitHub does not
//      have is named, and a record whose runners GitHub has none of, one
//      that names a label every runner carries, lists no runners, or names a
//      label another record names, stops;
//   4. admin.js spawned against a stand-in GitHub: anything through Caddy
//      (X-Forwarded-For) but the setup pages is the plain 404; no token, a
//      branch's token, and a token for another audience are 403 with nothing
//      asked of GitHub; with no App it says how to make one; with one, a
//      check says what differs and changes nothing, a run puts the labels
//      right with the installation token GitHub gave, reads them back, and
//      a second run changes nothing; the records come from main through the
//      App, never from the caller; and the log holds no token; settings
//      (#3534) only reads, with a read-only token that asks for the secret,
//      variable and environment names only when the App holds them, says
//      which it could not read and why, and never hands back a value;
//   5. the App's setup: no armed setup, a wrong or expired state, and an App
//      already held are the plain 404; the armed page sends the manifest
//      (administration write, contents read, no webhook, private) to GitHub
//      with the state; GitHub's code comes back to /setup/done, the key
//      lands in the state folder, the setup is disarmed, and the key is in
//      neither the page nor the log; an App another account made is refused
//      and nothing is kept.
//
// Nothing leaves loopback, and nothing outside the temp folder is touched.
'use strict';
const fs = require('fs');
const os = require('os');
const http = require('http');
const path = require('path');
const crypto = require('crypto');
const { spawn } = require('child_process');

const REPO = path.join(__dirname, '..');
const ADMIN = path.join(REPO, 'scripts', 'vps', 'admin', 'admin.js');
let pass = 0, fail = 0;
function yes(what, ok) { if (ok) { pass++; console.log('  ok   ' + what); } else { fail++; console.log('  FAIL ' + what); } }

const admin = require(ADMIN);
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'thornswood-admin-'));

const b64url = b => Buffer.from(b).toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
const unb64url = s => Buffer.from(String(s).replace(/-/g, '+').replace(/_/g, '/'), 'base64');
const now = () => Math.floor(Date.now() / 1000);

// GitHub's OIDC key, here, and one it does not publish.
const oidc = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const stray = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const jwk = Object.assign(oidc.publicKey.export({ format: 'jwk' }), { kid: 'gh-1', use: 'sig', alg: 'RS256' });
const JWKS = { keys: [jwk] };

function sign(claims, opts) {
  const o = opts || {};
  const head = b64url(JSON.stringify({ alg: o.alg || 'RS256', typ: 'JWT', kid: o.kid || 'gh-1' }));
  const body = b64url(JSON.stringify(claims));
  if (o.alg === 'none') return head + '.' + body + '.';
  const sig = crypto.sign('RSA-SHA256', Buffer.from(head + '.' + body), (o.key || oidc).privateKey);
  return head + '.' + body + '.' + b64url(sig);
}
function good(over) {
  const t = now();
  return Object.assign({
    iss: 'https://token.actions.githubusercontent.com', aud: 'thornswood-admin', iat: t - 5, nbf: t - 5, exp: t + 300,
    repository: 'EvilPatrick06/Thornswood', ref: 'refs/heads/main',
    job_workflow_ref: 'EvilPatrick06/Thornswood/.github/workflows/github-admin.yml@refs/heads/main',
    workflow_ref: 'EvilPatrick06/Thornswood/.github/workflows/github-admin.yml@refs/heads/main',
    event_name: 'workflow_dispatch', run_id: '4242', actor: 'EvilPatrick06',
  }, over || {});
}
function why(token) {
  try { admin.verifyOidc(token, JWKS, now(), admin.RULES); return ''; } catch (e) { return e.message || 'refused'; }
}

// ---- 1. the OIDC check ----------------------------------------------------------
console.log('the OIDC check');
yes('a hand-started run of github-admin.yml on main passes', why(sign(good())) === '');
yes('  and one a push to main started', why(sign(good({ event_name: 'push' }))) === '');
yes('  with the audience as a list too', why(sign(good({ aud: ['x', 'thornswood-admin'] }))) === '');
yes('another workflow on main fails', /workflow/.test(why(sign(good({ job_workflow_ref: 'EvilPatrick06/Thornswood/.github/workflows/build.yml@refs/heads/main' })))));
yes('github-admin.yml from a branch fails',
  why(sign(good({ ref: 'refs/heads/claude/x', job_workflow_ref: 'EvilPatrick06/Thornswood/.github/workflows/github-admin.yml@refs/heads/claude/x' }))) !== '');
yes('  even with a ref claim that says main', /workflow/.test(why(sign(good({ job_workflow_ref: 'EvilPatrick06/Thornswood/.github/workflows/github-admin.yml@refs/heads/claude/x' })))));
yes('a pull request\'s run fails',
  why(sign(good({ ref: 'refs/pull/3323/merge', event_name: 'pull_request', job_workflow_ref: 'EvilPatrick06/Thornswood/.github/workflows/github-admin.yml@refs/pull/3323/merge' }))) !== '');
yes('  and a pull_request_target run on main, by its event', /started by/.test(why(sign(good({ event_name: 'pull_request_target' })))));
yes('another repository fails', /from EvilPatrick06\/skymp/.test(why(sign(good({ repository: 'EvilPatrick06/skymp' })))));
yes('another audience fails', /audience/.test(why(sign(good({ aud: 'sigstore' })))));
yes('another issuer fails', /issued by/.test(why(sign(good({ iss: 'https://example.com' })))));
yes('an expired token fails', why(sign(good({ exp: now() - 1 }))) === 'expired');
yes('one signed by a key GitHub does not publish fails', /key GitHub does not publish/.test(why(sign(good(), { kid: 'other', key: stray }))));
yes('  or by another key under GitHub\'s key id', /signature/.test(why(sign(good(), { key: stray }))));
const real = sign(good()).split('.');
const changed = [real[0], b64url(JSON.stringify(good({ repository: 'EvilPatrick06/Thornswood', run_id: '1' }))), real[2]].join('.');
yes('one whose body was changed after signing fails', /signature/.test(why(changed)));
yes('one that says it needs no signature fails', /not RS256/.test(why(sign(good(), { alg: 'none' }))));
yes('something that is not a token fails', why('Bearer') === 'not a token' && why('') === 'not a token');

// ---- 2. the App's own token -------------------------------------------------------
console.log('the App\'s own token');
const app = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const appPem = app.privateKey.export({ type: 'pkcs1', format: 'pem' });
const jwt = admin.appJwt(123456, appPem, now()).split('.');
const jhead = JSON.parse(unb64url(jwt[0]));
const jbody = JSON.parse(unb64url(jwt[1]));
yes('RS256, signed by the App\'s key', jhead.alg === 'RS256' && crypto.verify('RSA-SHA256', Buffer.from(jwt[0] + '.' + jwt[1]), app.publicKey, unb64url(jwt[2])));
yes('issued by the App\'s id, ten minutes at most', jbody.iss === '123456' && jbody.exp - jbody.iat <= 600 && jbody.exp > now());

// ---- 3. the records and the plan ----------------------------------------------------
console.log('the records and the plan');
const base = ['self-hosted', 'Windows', 'X64', 'thornswood-vps'];
const runner = (id, name, labels, status) => ({ id, name, status: status || 'online', busy: false, labels: labels.map(n => ({ name: n })) });
const mixed = [
  runner(1, 'thornswood-vps', base.concat('thornswood-build')),
  runner(2, 'thornswood-vps-2', base),
  runner(3, 'thornswood-vps-3', base.concat('thornswood-build')),
  runner(27, 'thornswood-vps-5', base.concat('thornswood-build')),
  runner(40, 'thornswood-pr-one', ['self-hosted', 'Windows', 'thornswood-pr', 'thornswood-build']),
];
const rec4 = { file: 'records/build-runners.json', label: 'thornswood-build', runners: [1, 2, 3, 4] };
const p = admin.planLabels(rec4, mixed);
const did = (name) => (p.changes.find(c => c.name === name) || {}).do;
yes('a listed runner without the label gets it', did('thornswood-vps-2') === 'put on');
yes('a VPS runner the record does not list loses it', did('thornswood-vps-5') === 'take off');
yes('  and so does an off-box runner, which never takes box jobs', did('thornswood-pr-one') === 'take off');
yes('a runner that is right is left alone', !did('thornswood-vps') && !did('thornswood-vps-3') && p.changes.length === 3);
yes('a listed runner GitHub does not have is named', p.lines.some(l => /runner 4 is in records\/build-runners\.json but not registered/.test(l)));
yes('  and nothing is refused', p.refuse === '');
yes('a record whose runners GitHub has none of is refused', /never comes/.test(admin.planLabels({ file: 'r', label: 'thornswood-build', runners: [9] }, mixed).refuse));
yes('runner numbers: thornswood-vps is 1, thornswood-vps-<n> is n, anything else none',
  admin.runnerNumber('thornswood-vps') === 1 && admin.runnerNumber('thornswood-vps-7') === 7 && admin.runnerNumber('thornswood-pr-one') === 0 && admin.runnerNumber('thornswood-vps-x') === 0);
function stops(records) { try { admin.checkRecords(records); return ''; } catch (e) { return e.message; } }
const sign3 = { file: 'records/sign-runners.json', label: 'thornswood-sign', runners: [3] };
yes('the build and sign records pass together', stops([rec4, sign3]) === '');
yes('a record naming thornswood-vps stops', /every runner carries/.test(stops([{ file: 'r', label: 'thornswood-vps', runners: [1] }])));
yes('  and one naming self-hosted', /every runner carries/.test(stops([{ file: 'r', label: 'self-hosted', runners: [1] }])));
yes('a record listing no runners stops', /lists no runners/.test(stops([{ file: 'r', label: 'thornswood-x', runners: [] }])));
yes('two records naming one label stop', /both name/.test(stops([rec4, Object.assign({}, sign3, { label: 'thornswood-build' })])));
yes('a label that is not one lower case word stops', /one lower case word/.test(stops([{ file: 'r', label: 'a b', runners: [1] }])));
yes('a runner number below 1 stops', /number from 1/.test(stops([{ file: 'r', label: 'thornswood-x', runners: [0] }])));
yes('the real records on this checkout pass', (() => {
  const dir = path.join(REPO, 'records');
  const recs = fs.readdirSync(dir).filter(f => /^[a-z0-9-]+-runners\.json$/.test(f)).map(f => {
    const j = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
    return { file: 'records/' + f, label: String(j.label || '').trim(), runners: (j.runners || []).map(Number) };
  });
  return recs.length > 0 && stops(recs) === '';
})());

// ---- 4 and 5. the service, against a stand-in GitHub ---------------------------------
const gh = {
  calls: [],
  records: {
    'build-runners.json': { label: 'thornswood-build', runners: [1, 2] },
    'sign-runners.json': { label: 'thornswood-sign', runners: [3] },
  },
  runners: [
    runner(11, 'thornswood-vps', base.concat('thornswood-build')),
    runner(12, 'thornswood-vps-2', base),
    runner(13, 'thornswood-vps-3', base.concat('thornswood-build')),
    runner(14, 'thornswood-vps-4', base),
  ],
  instToken: 'ghs_' + crypto.randomBytes(16).toString('hex'),
  installed: true,
  conversion: null,
  instPerms: { administration: 'write', contents: 'read', metadata: 'read' },
  settings: {
    '/repos/EvilPatrick06/Thornswood/actions/permissions': { enabled: true, allowed_actions: 'all', sha_pinning_required: false },
    '/repos/EvilPatrick06/Thornswood/actions/permissions/workflow': { default_workflow_permissions: 'read', can_approve_pull_request_reviews: false },
    '/repos/EvilPatrick06/Thornswood/actions/permissions/access': { access_level: 'none' },
    '/repos/EvilPatrick06/Thornswood/actions/permissions/artifact-and-log-retention': { days: 90, maximum_allowed_days: 400 },
    '/repos/EvilPatrick06/Thornswood/actions/permissions/fork-pr-workflows-private-repos': { run_workflows_from_fork_pull_requests: false, send_write_tokens_to_workflows: false, send_secrets_and_variables: false, require_approval_for_fork_pr_workflows: false },
  },
  repoNames: { secrets: ['CLOUDFLARE_TURNSTILE_TOKEN'], variables: ['BUILD_RUNNER'] },
  envNames: { board: { secrets: ['BOARD_TOKEN'], variables: [] }, notices: { secrets: ['NOTICE_KEY_B64'], variables: [] } },
};
gh.records['github-settings.json'] = { environments: { board: {}, notices: {}, 'bad name/../x': {} } };
const appKey = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const appKeyPem = appKey.privateKey.export({ type: 'pkcs1', format: 'pem' });

function standIn(req, res) {
  const chunks = [];
  req.on('data', c => chunks.push(c));
  req.on('end', () => {
    const u = new URL(req.url, 'http://x');
    const body = chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : null;
    gh.calls.push({ method: req.method, path: u.pathname + u.search, auth: req.headers.authorization || '', body });
    const send = (code, o) => { res.writeHead(code, { 'Content-Type': 'application/json' }); res.end(o === undefined ? '' : JSON.stringify(o)); };
    const asApp = () => {
      const m = /^Bearer (.+)$/.exec(req.headers.authorization || '');
      if (!m) return false;
      const t = m[1].split('.');
      return t.length === 3 && crypto.verify('RSA-SHA256', Buffer.from(t[0] + '.' + t[1]), appKey.publicKey, unb64url(t[2]));
    };
    const asInst = () => req.headers.authorization === 'Bearer ' + gh.instToken;
    const P = u.pathname;
    if (P === '/jwks') return send(200, JWKS);
    if (P === '/repos/EvilPatrick06/Thornswood/installation') return !asApp() ? send(401, { message: 'Bad credentials' }) : gh.installed ? send(200, { id: 77, permissions: gh.instPerms }) : send(404, { message: 'Not Found' });
    if (P === '/app/installations/77/access_tokens' && req.method === 'POST') return asApp() ? send(201, { token: gh.instToken }) : send(401, { message: 'Bad credentials' });
    if (!P.startsWith('/app-manifests/') && !asInst()) return send(401, { message: 'Bad credentials' });
    if (P === '/repos/EvilPatrick06/Thornswood/contents/records') {
      if (u.searchParams.get('ref') !== 'main') return send(404, { message: 'No commit found for the ref' });
      return send(200, Object.keys(gh.records).concat(['README.md']).map(n => ({ type: 'file', name: n })));
    }
    let m = /^\/repos\/EvilPatrick06\/Thornswood\/contents\/records\/(.+)$/.exec(P);
    if (m && gh.records[m[1]] && u.searchParams.get('ref') === 'main') return send(200, { content: Buffer.from(JSON.stringify(gh.records[m[1]])).toString('base64') });
    if (P === '/repos/EvilPatrick06/Thornswood/actions/runners') return send(200, { total_count: gh.runners.length, runners: gh.runners });
    if (req.method === 'GET' && gh.settings[P]) return send(200, gh.settings[P]);
    m = /^\/repos\/EvilPatrick06\/Thornswood\/(?:environments\/([^/]+)\/)?actions\/(secrets|variables)$|^\/repos\/EvilPatrick06\/Thornswood\/environments\/([^/]+)\/(secrets|variables)$/.exec(P);
    if (m && req.method === 'GET') {
      const env = m[3] ? decodeURIComponent(m[3]) : '';
      const kind = m[2] || m[4];
      const names = env ? ((gh.envNames[env] || {})[kind] || []) : (gh.repoNames[kind] || []);
      return send(200, { total_count: names.length, [kind]: names.map(n => ({ name: n, value: kind === 'variables' ? 'the value' : undefined })) });
    }
    m = /^\/repos\/EvilPatrick06\/Thornswood\/actions\/runners\/(\d+)\/labels(?:\/(.+))?$/.exec(P);
    if (m) {
      const r = gh.runners.find(x => x.id === Number(m[1]));
      if (!r) return send(404, { message: 'Not Found' });
      if (req.method === 'POST') { for (const l of body.labels) if (!r.labels.some(x => x.name === l)) r.labels.push({ name: l }); return send(200, { labels: r.labels }); }
      if (req.method === 'DELETE') { r.labels = r.labels.filter(x => x.name !== decodeURIComponent(m[2])); return send(200, { labels: r.labels }); }
    }
    m = /^\/app-manifests\/([^/]+)\/conversions$/.exec(P);
    if (m && req.method === 'POST') return gh.conversion ? send(201, gh.conversion) : send(404, { message: 'Not Found' });
    send(404, { message: 'Not Found' });
  });
}

function ask(port, method, p, headers, body) {
  return new Promise((resolve, reject) => {
    const data = body === undefined ? null : Buffer.from(typeof body === 'string' ? body : JSON.stringify(body));
    const h = Object.assign({}, headers || {});
    if (data) { h['Content-Type'] = 'application/json'; h['Content-Length'] = data.length; }
    const req = http.request({ host: '127.0.0.1', port, method, path: p, headers: h }, res => {
      const c = [];
      res.on('data', x => c.push(x));
      res.on('end', () => {
        const text = Buffer.concat(c).toString('utf8');
        let j = null;
        try { j = JSON.parse(text); } catch (e) { j = null; }
        resolve({ status: res.statusCode, headers: res.headers, text, json: j });
      });
    });
    req.on('error', reject);
    if (data) req.write(data);
    req.end();
  });
}

function start(stateDir, ghPort) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [ADMIN], {
      env: Object.assign({}, process.env, {
        THORNSWOOD_ADMIN_PORT: '0', THORNSWOOD_ADMIN_STATE: stateDir,
        THORNSWOOD_ADMIN_GITHUB_API: 'http://127.0.0.1:' + ghPort, THORNSWOOD_ADMIN_GITHUB_WEB: 'http://127.0.0.1:' + ghPort + '/web',
        THORNSWOOD_ADMIN_JWKS: 'http://127.0.0.1:' + ghPort + '/jwks',
      }),
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let out = '';
    const t = setTimeout(() => reject(new Error('admin.js did not start: ' + out)), 10000);
    child.stdout.on('data', d => {
      out += d;
      const m = /listening on 127\.0\.0\.1:(\d+)/.exec(out);
      if (m && !child.port) { child.port = Number(m[1]); clearTimeout(t); resolve(child); }
    });
    child.stderr.on('data', d => { out += d; });
    child.log = () => out;
    child.on('exit', () => { clearTimeout(t); if (!child.port) reject(new Error('admin.js exited: ' + out)); });
  });
}

(async () => {
  const stand = http.createServer(standIn);
  await new Promise(r => stand.listen(0, '127.0.0.1', r));
  const ghPort = stand.address().port;
  const state = path.join(tmp, 'state');
  fs.mkdirSync(state);
  const svc = await start(state, ghPort);
  const P = svc.port;
  const bearer = t => ({ Authorization: 'Bearer ' + t });
  const ask4 = (headers, body) => ask(P, 'POST', '/converge', headers, body === undefined ? { what: 'runner-labels' } : body);
  try {
    console.log('the service');
    let r = await ask(P, 'GET', '/', {});
    yes('a plain request is the plain 404, which says which service it is', r.status === 404 && r.text === 'box admin: not here');
    gh.calls = [];
    r = await ask4(Object.assign({ 'X-Forwarded-For': '203.0.113.9' }, bearer(sign(good()))));
    yes('anything through Caddy but the setup pages is the plain 404, even a good token', r.status === 404 && r.text === 'box admin: not here' && gh.calls.length === 0);
    r = await ask(P, 'GET', '/converge', bearer(sign(good())));
    yes('  and so is a GET', r.status === 404);
    r = await ask4({});
    yes('no token: 403, and GitHub is asked nothing but its keys', r.status === 403 && gh.calls.every(c => c.path === '/jwks'));
    gh.calls = [];
    r = await ask4(bearer(sign(good({ ref: 'refs/heads/claude/x', job_workflow_ref: 'EvilPatrick06/Thornswood/.github/workflows/github-admin.yml@refs/heads/claude/x' }))));
    yes('a branch\'s token: 403, and nothing but the keys asked', r.status === 403 && /refs\/heads\/claude\/x/.test(r.text) && gh.calls.every(c => c.path === '/jwks'));
    r = await ask4(bearer(sign(good({ aud: 'sigstore' }))));
    yes('a token for another audience: 403', r.status === 403);
    r = await ask4(bearer(sign(good())));
    yes('with no App yet it says how to make one (503)', r.status === 503 && /Install-AdminService\.ps1 -Setup/.test(r.text));
    r = await ask4(bearer(sign(good())), { what: 'secrets' });
    yes('anything but runner-labels is refused (400)', r.status === 400);

    // The App, as the setup would leave it.
    fs.writeFileSync(path.join(state, 'key.pem'), appKeyPem);
    fs.writeFileSync(path.join(state, 'app.json'), JSON.stringify({ id: 123456, slug: 'thornswood-box-admin', owner: 'EvilPatrick06' }));
    gh.installed = false;
    r = await ask4(bearer(sign(good())));
    yes('an App not installed on Thornswood says where to install it', r.status === 502 && /not installed/.test(r.text) && /installations\/new/.test(r.text));
    gh.installed = true;

    gh.calls = [];
    r = await ask4(bearer(sign(good())), { what: 'runner-labels', check: true });
    const writes = () => gh.calls.filter(c => c.method === 'POST' && /labels/.test(c.path) || c.method === 'DELETE');
    yes('a check answers 200 with what differs, and changes nothing', r.status === 200 && r.json.ok && r.json.differs === 3 && r.json.changed === 0 && writes().length === 0);
    yes('  runner 2 would get the build label, runner 3 lose it', r.json.lines.some(l => /thornswood-vps-2 would have thornswood-build put on/.test(l)) && r.json.lines.some(l => /thornswood-vps-3 would have thornswood-build taken off/.test(l)));
    yes('  and runner 3 the sign label', r.json.lines.some(l => /sign-runners\.json: thornswood-vps-3 would have thornswood-sign put on/.test(l)));
    const tok = gh.calls.find(c => /access_tokens$/.test(c.path));
    yes('the installation token is asked for Thornswood alone, with administration write and contents read only',
      tok && JSON.stringify(tok.body.repositories) === '["Thornswood"]' && tok.body.permissions.administration === 'write' && tok.body.permissions.contents === 'read' && Object.keys(tok.body.permissions).length === 2);
    yes('the records come from main, read with the installation token', gh.calls.filter(c => /contents\/records/.test(c.path)).every(c => /ref=main/.test(c.path) && c.auth === 'Bearer ' + gh.instToken));

    // The sign label belongs on runner 3 and is not there yet: #3312's case.
    gh.calls = [];
    r = await ask4(bearer(sign(good({ event_name: 'push' }))));
    yes('a run puts every label right (200, 3 changed)', r.status === 200 && r.json.ok && r.json.changed === 3);
    const labels = n => gh.runners.find(x => x.name === n).labels.map(l => l.name);
    yes('  runner 1 and 2 carry the build label, 3 and 4 do not',
      labels('thornswood-vps').includes('thornswood-build') && labels('thornswood-vps-2').includes('thornswood-build') && !labels('thornswood-vps-3').includes('thornswood-build') && !labels('thornswood-vps-4').includes('thornswood-build'));
    yes('  runner 3 carries the sign label and no other does', labels('thornswood-vps-3').includes('thornswood-sign') && gh.runners.filter(x => labels(x.name).includes('thornswood-sign')).length === 1);
    yes('  the labels every runner carries are untouched', gh.runners.every(x => base.every(b => labels(x.name).includes(b))));
    yes('  each change is one call with the installation token', writes().length === 3 && writes().every(c => c.auth === 'Bearer ' + gh.instToken));
    yes('  and it reads them back after', gh.calls.filter(c => /actions\/runners\?/.test(c.path)).length === 2);
    gh.calls = [];
    r = await ask4(bearer(sign(good())));
    yes('a second run changes nothing', r.status === 200 && r.json.changed === 0 && writes().length === 0);
    r = await ask4(bearer(sign(good())), { what: 'runner-labels', records: { 'x-runners.json': { label: 'thornswood-x', runners: [4] } } });
    yes('records sent by the caller are not used', r.status === 200 && r.json.changed === 0 && !labels('thornswood-vps-4').includes('thornswood-x'));

    gh.records['bad-runners.json'] = { label: 'thornswood-vps', runners: [1] };
    gh.calls = [];
    r = await ask4(bearer(sign(good())));
    yes('a bad record on main stops it, nothing changed (502)', r.status === 502 && /every runner carries/.test(r.text) && writes().length === 0);
    delete gh.records['bad-runners.json'];
    gh.records['sign-runners.json'] = { label: 'thornswood-sign', runners: [9] };
    gh.calls = [];
    r = await ask4(bearer(sign(good())));
    yes('a record whose runners GitHub has none of stops for it (409) and leaves its label where it is', r.status === 409 && /never comes/.test(r.text) && labels('thornswood-vps-3').includes('thornswood-sign') && writes().length === 0);
    gh.records['sign-runners.json'] = { label: 'thornswood-sign', runners: [3] };

    const tokenSeen = sign(good());
    await ask4(bearer(tokenSeen));
    const log = svc.log();
    yes('the log names the run and what changed', /run 4242 \(workflow_dispatch by EvilPatrick06\)/.test(log));
    yes('  and never a token or the key', !log.includes(tokenSeen.split('.')[2]) && !log.includes(gh.instToken) && !log.includes('PRIVATE KEY'));

    // ---- settings (#3534): read only ----
    console.log('the settings read');
    gh.calls = [];
    r = await ask4(bearer(sign(good())), { what: 'settings' });
    const reads = () => gh.calls.filter(c => c.method !== 'GET' && !/access_tokens$/.test(c.path));
    yes('settings answers 200 and makes no call but GETs and the token', r.status === 200 && r.json.ok && reads().length === 0);
    let stok = gh.calls.find(c => /access_tokens$/.test(c.path));
    yes('  its token is for Thornswood alone, administration and contents read only, while the App holds no more',
      stok && JSON.stringify(stok.body.repositories) === '["Thornswood"]' && JSON.stringify(stok.body.permissions) === '{"administration":"read","contents":"read"}');
    const rd = (r.json && r.json.readings) || {};
    yes('  it reads the Actions settings, the workflow token, sharing, retention and fork pull requests',
      rd.actions && rd.actions.allowed_actions === 'all' && rd.workflow_token.default_workflow_permissions === 'read' && rd.sharing.access_level === 'none' &&
      rd.retention.days === 90 && rd.fork_pull_requests.send_secrets_and_variables === false);
    yes('  and the runners, with their labels', Array.isArray(rd.runners) && rd.runners.length === 4 && rd.runners[0].labels.includes('thornswood-vps'));
    yes('  says the secret and variable names are not read, naming the permission, and asks for none of them',
      !rd.secrets && !rd.variables && r.json.unread.some(l => /^secrets: the App has no Secrets permission/.test(l)) &&
      r.json.unread.some(l => /^variables: the App has no Variables permission/.test(l)) && r.json.unread.some(l => /Environments permission/.test(l)) &&
      !gh.calls.some(c => /secrets|variables/.test(c.path)));
    yes('  the environments are the record\'s on main, a name GitHub could not have left out', JSON.stringify(Object.keys(rd.environments)) === '["board","notices"]');
    gh.instPerms = { administration: 'write', contents: 'read', metadata: 'read', secrets: 'read', variables: 'read', environments: 'read' };
    gh.calls = [];
    r = await ask4(bearer(sign(good())), { what: 'settings' });
    stok = gh.calls.find(c => /access_tokens$/.test(c.path));
    yes('with the App holding them, the token asks for secrets, variables and environments read too, and nothing more',
      stok && JSON.stringify(stok.body.permissions) === '{"administration":"read","contents":"read","secrets":"read","variables":"read","environments":"read"}');
    const rd2 = r.json.readings;
    yes('  and the names are read: the repository\'s and each environment\'s', r.status === 200 && JSON.stringify(rd2.secrets) === '["CLOUDFLARE_TURNSTILE_TOKEN"]' &&
      JSON.stringify(rd2.variables) === '["BUILD_RUNNER"]' && JSON.stringify(rd2.environments.board.secrets) === '["BOARD_TOKEN"]' && r.json.unread.length === 0);
    yes('  a variable\'s value never comes back, only its name', !r.text.includes('the value'));
    yes('  and still nothing but GETs', reads().length === 0);
    gh.instPerms = { administration: 'write', contents: 'read', metadata: 'read' };

    // ---- 5. setup ----
    console.log('the App\'s setup');
    fs.unlinkSync(path.join(state, 'key.pem'));
    fs.unlinkSync(path.join(state, 'app.json'));
    const st = crypto.randomBytes(24).toString('hex');
    const fwd = { 'X-Forwarded-For': '203.0.113.9' };
    r = await ask(P, 'GET', '/setup?state=' + st, fwd);
    yes('no armed setup: the plain 404', r.status === 404 && r.text === 'box admin: not here');
    fs.writeFileSync(path.join(state, 'setup.json'), JSON.stringify({ state: st, expires: now() + 3600 }));
    r = await ask(P, 'GET', '/setup?state=' + crypto.randomBytes(24).toString('hex'), fwd);
    yes('a wrong state: the plain 404', r.status === 404);
    r = await ask(P, 'GET', '/setup?state=' + st.slice(0, 8), fwd);
    yes('  and a short one', r.status === 404);
    r = await ask(P, 'GET', '/setup?state=' + st, fwd);
    const form = /<form action="([^"]+)" method="post"><input type="hidden" name="manifest" value="([^"]+)">/.exec(r.text);
    const unesc = s => s.replace(/&quot;/g, '"').replace(/&#39;/g, '\'').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
    yes('the armed page, through Caddy, posts the manifest to GitHub with the state', r.status === 200 && form && unesc(form[1]) === 'http://127.0.0.1:' + ghPort + '/web/settings/apps/new?state=' + st);
    const mf = form ? JSON.parse(unesc(form[2])) : {};
    yes('  the manifest: private, administration write and contents read only, no webhook, back to /github-app/setup/done',
      mf.public === false && JSON.stringify(mf.default_permissions) === '{"administration":"write","contents":"read"}' && mf.hook_attributes.active === false &&
      mf.redirect_url === 'https://thornswood.net/github-app/setup/done' && (mf.default_events || []).length === 0);
    yes('  and the page is neither kept nor passed on', /no-store/.test(r.headers['cache-control'] || '') && r.headers['referrer-policy'] === 'no-referrer');

    // A key made here for the stand-in to hand over; a line of its body is
    // what the page and the log must never hold.
    const madeKey = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 }).privateKey.export({ type: 'pkcs1', format: 'pem' });
    const keyLine = madeKey.split('\n')[1];
    gh.conversion = { id: 999, slug: 'thornswood-box-admin', pem: madeKey, owner: { login: 'SomebodyElse' } };
    r = await ask(P, 'GET', '/setup/done?code=abcdef123456&state=' + st, fwd);
    yes('an App another account made is refused, and nothing is kept', r.status === 403 && !fs.existsSync(path.join(state, 'key.pem')) && fs.existsSync(path.join(state, 'setup.json')));
    gh.conversion.owner = { login: 'EvilPatrick06' };
    r = await ask(P, 'GET', '/setup/done?code=abcdef123456&state=' + crypto.randomBytes(24).toString('hex'), fwd);
    yes('/setup/done with a wrong state: the plain 404', r.status === 404 && !fs.existsSync(path.join(state, 'key.pem')));
    gh.calls = [];
    r = await ask(P, 'GET', '/setup/done?code=abcdef123456&state=' + st, fwd);
    yes('GitHub\'s code comes back: the key and the App\'s id are kept', r.status === 200 && fs.readFileSync(path.join(state, 'key.pem'), 'utf8') === gh.conversion.pem &&
      JSON.parse(fs.readFileSync(path.join(state, 'app.json'), 'utf8')).id === 999);
    yes('  traded with GitHub by the code alone', gh.calls.length === 1 && gh.calls[0].path === '/app-manifests/abcdef123456/conversions' && gh.calls[0].auth === '');
    yes('  the setup is disarmed', !fs.existsSync(path.join(state, 'setup.json')));
    yes('  the page links the App\'s install page and never shows the key', /\/apps\/thornswood-box-admin\/installations\/new/.test(r.text) && !r.text.includes(keyLine));
    yes('  and the log never holds the key', !svc.log().includes(keyLine));
    fs.writeFileSync(path.join(state, 'setup.json'), JSON.stringify({ state: st, expires: now() + 3600 }));
    r = await ask(P, 'GET', '/setup?state=' + st, fwd);
    yes('with an App held, an armed setup still shows nothing', r.status === 404);
    fs.unlinkSync(path.join(state, 'key.pem'));
    fs.unlinkSync(path.join(state, 'app.json'));
    fs.writeFileSync(path.join(state, 'setup.json'), JSON.stringify({ state: st, expires: now() - 1 }));
    r = await ask(P, 'GET', '/setup?state=' + st, fwd);
    yes('an expired setup: the plain 404', r.status === 404);
  } catch (e) {
    yes('the run went through without throwing: ' + e.stack, false);
  } finally {
    svc.kill();
    stand.close();
    fs.rmSync(tmp, { recursive: true, force: true });
  }
  console.log('');
  console.log(pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
})();
