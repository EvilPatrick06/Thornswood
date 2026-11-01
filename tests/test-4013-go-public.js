// #4013 and #3721: the flip, through the box's GitHub App (admin.js's
// go-public ask), since a cloud thread's proxy refuses the visibility switch
// and every secrets and environments path, and Patrick said on 30 Oct 2026
// that the flip is not done on One.
//
// admin.js runs for real on loopback against a stand-in GitHub, and this
// holds that:
//   1. a check reads with read-only tokens, says what it would take and
//      changes nothing;
//   2. a runner still registered to this repository stops it, named, with
//      nothing changed (#3792);
//   3. the ops repository missing its own copy of a box secret stops it,
//      named, with nothing changed;
//   4. the App without Secrets or Environments write stops it, naming the
//      permission and what needs it, with nothing changed; a check still
//      answers;
//   5. a run deletes the turnstile secret, desk's DESK_KEY_B64 and the
//      notices environment, each with a token for this repository alone
//      holding write for just what it takes, and only then switches the
//      repository to public; desk keeps NEXUS_API_KEY; it reads back;
//   6. a delete GitHub refuses stops it before the switch, so the
//      repository stays private;
//   7. once done, a second run changes nothing and says so;
//   8. nothing the caller sends but check changes what it does, and the log
//      holds no token.
//
// Nothing leaves loopback, and nothing outside the temp folder is touched.
'use strict';
const fs = require('fs');
const os = require('os');
const http = require('http');
const path = require('path');
const crypto = require('crypto');
const { spawn } = require('child_process');

const ADMIN = path.join(__dirname, '..', 'scripts', 'vps', 'admin', 'admin.js');
let pass = 0, fail = 0;
function yes(what, ok) { if (ok) { pass++; console.log('  ok   ' + what); } else { fail++; console.log('  FAIL ' + what); } }

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'thornswood-go-public-'));
const b64url = b => Buffer.from(b).toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
const unb64url = s => Buffer.from(String(s).replace(/-/g, '+').replace(/_/g, '/'), 'base64');
const now = () => Math.floor(Date.now() / 1000);

const oidc = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const JWKS = { keys: [Object.assign(oidc.publicKey.export({ format: 'jwk' }), { kid: 'gh-1', use: 'sig', alg: 'RS256' })] };
function token() {
  const t = now();
  const claims = {
    iss: 'https://token.actions.githubusercontent.com', aud: 'thornswood-admin', iat: t - 5, nbf: t - 5, exp: t + 300,
    repository: 'EvilPatrick06/Thornswood-Ops', repository_id: '1435123931', ref: 'refs/heads/main',
    job_workflow_ref: 'EvilPatrick06/Thornswood-Ops/.github/workflows/github-admin.yml@refs/heads/main',
    event_name: 'workflow_dispatch', run_id: '4013', actor: 'EvilPatrick06',
  };
  const head = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT', kid: 'gh-1' }));
  const body = b64url(JSON.stringify(claims));
  return head + '.' + body + '.' + b64url(crypto.sign('RSA-SHA256', Buffer.from(head + '.' + body), oidc.privateKey));
}
const appKey = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });

// The stand-in GitHub. Each token GitHub gives is named by what it was
// asked for, so every call says which token made it.
let gh;
function fresh() {
  gh = {
    calls: [], tokens: {},
    perms: { administration: 'write', contents: 'read', metadata: 'read', secrets: 'write', environments: 'write', actions_variables: 'read' },
    visibility: 'private',
    runners: { Thornswood: [], 'Thornswood-Ops': ['thornswood-vps', 'thornswood-vps-2'] },
    secrets: { Thornswood: ['CLOUDFLARE_TURNSTILE_TOKEN', 'BOARD_TOKEN'], 'Thornswood-Ops': ['CLOUDFLARE_TURNSTILE_TOKEN'] },
    envs: {
      Thornswood: { desk: ['DESK_KEY_B64', 'NEXUS_API_KEY'], notices: ['NOTICE_KEY_B64'], board: ['BOARD_TOKEN'] },
      'Thornswood-Ops': { desk: ['DESK_KEY_B64'], notices: ['NOTICE_KEY_B64'] },
    },
    refuse: '',
  };
}
fresh();

function standIn(req, res) {
  const chunks = [];
  req.on('data', c => chunks.push(c));
  req.on('end', () => {
    const u = new URL(req.url, 'http://x');
    const body = chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : null;
    const auth = req.headers.authorization || '';
    const tok = gh.tokens[auth.replace(/^Bearer /, '')];
    gh.calls.push({ method: req.method, path: u.pathname, token: tok, body });
    const send = (code, o) => { res.writeHead(code, { 'Content-Type': 'application/json' }); res.end(o === undefined ? '' : JSON.stringify(o)); };
    const P = u.pathname;
    const asApp = () => {
      const m = /^Bearer (.+)$/.exec(auth);
      const t = m ? m[1].split('.') : [];
      return t.length === 3 && crypto.verify('RSA-SHA256', Buffer.from(t[0] + '.' + t[1]), appKey.publicKey, unb64url(t[2]));
    };
    if (P === '/jwks') return send(200, JWKS);
    if (P === '/repos/EvilPatrick06/Thornswood/installation') return asApp() ? send(200, { id: 77, permissions: gh.perms }) : send(401, { message: 'Bad credentials' });
    if (P === '/app/installations/77/access_tokens' && req.method === 'POST') {
      if (!asApp()) return send(401, { message: 'Bad credentials' });
      const perms = body.permissions || {};
      const rank = { read: 1, write: 2 };
      for (const k of Object.keys(perms)) if (!gh.perms[k] || rank[perms[k]] > rank[gh.perms[k]]) return send(422, { message: 'The permissions requested are not granted to this installation.' });
      const t = 'ghs_' + crypto.randomBytes(12).toString('hex');
      gh.tokens[t] = { repos: body.repositories || null, perms };
      return send(201, { token: t });
    }
    const m = /^\/repos\/EvilPatrick06\/(Thornswood|Thornswood-Ops)(\/.*)?$/.exec(P);
    if (!m) return send(404, { message: 'Not Found' });
    const repo = m[1], rest = m[2] || '';
    // A token reaches only the repository it was made for, with what it holds.
    const may = (perm, level) => tok && tok.repos && tok.repos.length === 1 && tok.repos[0] === repo && tok.perms[perm] && (level === 'read' || tok.perms[perm] === 'write');
    const no = () => send(403, { message: 'Resource not accessible by integration' });
    if (rest === '' && req.method === 'GET') return tok ? send(200, { full_name: 'EvilPatrick06/' + repo, visibility: repo === 'Thornswood' ? gh.visibility : 'private' }) : send(401, {});
    if (rest === '' && req.method === 'PATCH') {
      if (!may('administration', 'write')) return no();
      if (gh.refuse === 'visibility') return send(422, { message: 'refused' });
      gh.visibility = body.visibility;
      return send(200, { visibility: gh.visibility });
    }
    if (rest === '/actions/runners') return may('administration', 'read') ? send(200, { total_count: gh.runners[repo].length, runners: gh.runners[repo].map((n, i) => ({ id: i + 1, name: n })) }) : no();
    if (rest === '/actions/secrets') return may('secrets', 'read') ? send(200, { total_count: gh.secrets[repo].length, secrets: gh.secrets[repo].map(n => ({ name: n })) }) : no();
    let x = /^\/actions\/secrets\/([^/]+)$/.exec(rest);
    if (x && req.method === 'DELETE') {
      if (!may('secrets', 'write')) return no();
      if (gh.refuse === x[1]) return send(500, { message: 'refused' });
      gh.secrets[repo] = gh.secrets[repo].filter(n => n !== x[1]);
      return send(204);
    }
    x = /^\/environments\/([^/]+)\/secrets$/.exec(rest);
    if (x) {
      if (!may('environments', 'read')) return no();
      const e = gh.envs[repo][decodeURIComponent(x[1])];
      return e ? send(200, { total_count: e.length, secrets: e.map(n => ({ name: n })) }) : send(404, { message: 'Not Found' });
    }
    x = /^\/environments\/([^/]+)\/secrets\/([^/]+)$/.exec(rest);
    if (x && req.method === 'DELETE') {
      if (!may('environments', 'write')) return no();
      const e = gh.envs[repo][decodeURIComponent(x[1])];
      if (!e || !e.includes(x[2])) return send(404, { message: 'Not Found' });
      gh.envs[repo][decodeURIComponent(x[1])] = e.filter(n => n !== x[2]);
      return send(204);
    }
    x = /^\/environments\/([^/]+)$/.exec(rest);
    if (x && req.method === 'DELETE') {
      if (!may('administration', 'write')) return no();
      if (!gh.envs[repo][decodeURIComponent(x[1])]) return send(404, { message: 'Not Found' });
      delete gh.envs[repo][decodeURIComponent(x[1])];
      return send(204);
    }
    send(404, { message: 'Not Found' });
  });
}

function ask(port, body) {
  return new Promise((resolve, reject) => {
    const data = Buffer.from(JSON.stringify(body));
    const req = http.request({ host: '127.0.0.1', port, method: 'POST', path: '/converge', headers: { Authorization: 'Bearer ' + token(), 'Content-Type': 'application/json', 'Content-Length': data.length } }, res => {
      const c = [];
      res.on('data', d => c.push(d));
      res.on('end', () => { const text = Buffer.concat(c).toString('utf8'); let j = null; try { j = JSON.parse(text); } catch (e) { j = null; } resolve({ status: res.statusCode, text, json: j }); });
    });
    req.on('error', reject);
    req.end(data);
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
      const mm = /listening on 127\.0\.0\.1:(\d+)/.exec(out);
      if (mm && !child.port) { child.port = Number(mm[1]); clearTimeout(t); resolve(child); }
    });
    child.stderr.on('data', d => { out += d; });
    child.log = () => out;
    child.on('exit', () => { clearTimeout(t); if (!child.port) reject(new Error('admin.js exited: ' + out)); });
  });
}

const writes = () => gh.calls.filter(c => c.method !== 'GET' && c.path !== '/app/installations/77/access_tokens');
const lines = r => ((r.json && r.json.lines) || []).join('\n');

(async () => {
  const stand = http.createServer(standIn);
  await new Promise(r => stand.listen(0, '127.0.0.1', r));
  const state = path.join(tmp, 'state');
  fs.mkdirSync(state);
  fs.writeFileSync(path.join(state, 'key.pem'), appKey.privateKey.export({ type: 'pkcs1', format: 'pem' }));
  fs.writeFileSync(path.join(state, 'app.json'), JSON.stringify({ id: 123456, slug: 'thornswood-box-admin', owner: 'EvilPatrick06' }));
  const svc = await start(state, stand.address().port);
  const P = svc.port;
  try {
    console.log('a check');
    let r = await ask(P, { what: 'go-public', check: true });
    yes('answers 200 and says what it would take, in order: the secret, desk\'s DESK_KEY_B64, the notices environment, then the switch',
      r.status === 200 && r.json.ok && r.json.differs === 4 && /would take the secret CLOUDFLARE_TURNSTILE_TOKEN\nwould take the desk environment's secret DESK_KEY_B64\nwould take the notices environment, with its secrets NOTICE_KEY_B64\nwould take the switch from private to public/.test(lines(r)));
    yes('  and changes nothing', writes().length === 0 && gh.visibility === 'private');
    yes('  reading with read-only tokens, each for one repository', gh.calls.filter(c => c.token).every(c => c.token.repos.length === 1 && Object.values(c.token.perms).every(v => v === 'read')));

    console.log('what stops it');
    fresh(); gh.runners.Thornswood = ['thornswood-vps-3'];
    r = await ask(P, { what: 'go-public' });
    yes('a runner still registered to this repository: 409, named, nothing changed', r.status === 409 && /STOP these runners are still registered to EvilPatrick06\/Thornswood: thornswood-vps-3/.test(lines(r)) && writes().length === 0 && gh.visibility === 'private');
    fresh(); gh.envs['Thornswood-Ops'].notices = null; delete gh.envs['Thornswood-Ops'].notices;
    r = await ask(P, { what: 'go-public' });
    yes('the ops repository without its notices key: 409, named, nothing changed', r.status === 409 && /EvilPatrick06\/Thornswood-Ops has no notices environment secret NOTICE_KEY_B64/.test(lines(r)) && writes().length === 0);
    fresh(); gh.secrets['Thornswood-Ops'] = [];
    r = await ask(P, { what: 'go-public' });
    yes('the ops repository without the turnstile token: 409, nothing changed', r.status === 409 && /has no secret CLOUDFLARE_TURNSTILE_TOKEN of its own/.test(lines(r)) && writes().length === 0);
    fresh(); gh.perms.secrets = 'read'; gh.perms.environments = 'read';
    r = await ask(P, { what: 'go-public' });
    yes('the App with Secrets and Environments read only: 409, each named with what needs it, nothing changed',
      r.status === 409 && /the App has read secrets permission, and the secret CLOUDFLARE_TURNSTILE_TOKEN needs write/.test(lines(r)) && /the App has read environments permission, and the desk environment's secret DESK_KEY_B64 needs write/.test(lines(r)) && writes().length === 0);
    r = await ask(P, { what: 'go-public', check: true });
    yes('  and a check says the same, so it can be asked before the permissions are given', r.status === 409 && /needs write/.test(lines(r)) && writes().length === 0);

    console.log('the flip');
    fresh(); gh.calls = [];
    r = await ask(P, { what: 'go-public', repositories: ['EvilPatrick06/skymp'], drop: ['BOARD_TOKEN'], visibility: 'internal' });
    yes('a run answers 200 with 4 changes', r.status === 200 && r.json.ok && r.json.changed === 4);
    const w = writes();
    yes('  the three deletes come first and the switch last', w.length === 4 && w[0].path === '/repos/EvilPatrick06/Thornswood/actions/secrets/CLOUDFLARE_TURNSTILE_TOKEN' &&
      w[1].path === '/repos/EvilPatrick06/Thornswood/environments/desk/secrets/DESK_KEY_B64' && w[2].path === '/repos/EvilPatrick06/Thornswood/environments/notices' &&
      w[3].method === 'PATCH' && w[3].path === '/repos/EvilPatrick06/Thornswood' && JSON.stringify(w[3].body) === '{"visibility":"public"}');
    yes('  each with one token, for this repository alone, holding write for exactly what the run takes', w.every(c => c.token === w[0].token) &&
      JSON.stringify(w[0].token.repos) === '["Thornswood"]' && JSON.stringify(Object.keys(w[0].token.perms).sort()) === '["administration","environments","secrets"]' && Object.values(w[0].token.perms).every(v => v === 'write'));
    yes('  the repository is public; desk keeps NEXUS_API_KEY, the board environment and BOARD_TOKEN are left alone', gh.visibility === 'public' &&
      JSON.stringify(gh.envs.Thornswood.desk) === '["NEXUS_API_KEY"]' && !gh.envs.Thornswood.notices && JSON.stringify(gh.secrets.Thornswood) === '["BOARD_TOKEN"]' && JSON.stringify(gh.envs.Thornswood.board) === '["BOARD_TOKEN"]');
    yes('  the ops repository keeps every copy', JSON.stringify(gh.secrets['Thornswood-Ops']) === '["CLOUDFLARE_TURNSTILE_TOKEN"]' && gh.envs['Thornswood-Ops'].desk.length === 1 && gh.envs['Thornswood-Ops'].notices.length === 1);
    yes('  nothing the caller sent but the ask changed what it did', !gh.calls.some(c => /skymp/.test(c.path)));
    yes('  it read everything back, and says what desk holds', /EvilPatrick06\/Thornswood is public; the desk environment holds NEXUS_API_KEY/.test(lines(r)));
    gh.calls = [];
    r = await ask(P, { what: 'go-public' });
    yes('a second run changes nothing and says it is done', r.status === 200 && r.json.changed === 0 && /is public and holds none of the box's secrets/.test(lines(r)) && writes().length === 0);

    console.log('a refused delete');
    fresh(); gh.refuse = 'CLOUDFLARE_TURNSTILE_TOKEN';
    r = await ask(P, { what: 'go-public' });
    yes('stops it before the switch: 409, and the repository is still private', r.status === 409 && /STOP GitHub did not take the secret CLOUDFLARE_TURNSTILE_TOKEN \(HTTP 500: refused\); EvilPatrick06\/Thornswood is still private, and nothing after this was done/.test(lines(r)) &&
      gh.visibility === 'private' && writes().length === 1);
    fresh(); gh.refuse = 'visibility';
    r = await ask(P, { what: 'go-public' });
    yes('a refused switch says so, and the deletes it made are named', r.status === 409 && /took the notices environment/.test(lines(r)) && /STOP GitHub did not take the switch from private to public/.test(lines(r)) && gh.visibility === 'private');

    const tokens = Object.keys(gh.tokens);
    yes('the log holds no token', tokens.length > 0 && !tokens.some(t => svc.log().includes(t)) && !svc.log().includes('PRIVATE KEY'));
  } catch (e) {
    yes('the run did not throw: ' + e.stack, false);
  } finally {
    svc.kill();
    stand.close();
    fs.rmSync(tmp, { recursive: true, force: true });
  }
  console.log('\n' + pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
})();
