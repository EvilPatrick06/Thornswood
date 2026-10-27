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
//      App, never from the caller; installation-repos (#4013) lists the
//      repositories the App is on with a token that reads metadata alone,
//      and changes nothing; and the log holds no token;
//   4a. repository settings (#3683): the record's rules (Thornswood and the
//      engine fork only, each once; reporting true or false when given; per
//      ruleset a name, branch or tag, active or disabled, a ref, rules with
//      types, a bypass list, no name twice), what GitHub's copy must say
//      (every key the record gives, lists in any order, GitHub's own ids and
//      defaults ignored), and the service: a check says what would be made
//      or switched and changes nothing; a run makes the missing rulesets in
//      each repository with a token for that repository alone, puts a
//      changed one back by name, sending only the ruleset's own keys,
//      switches the fork's private reporting as the record says and leaves
//      it alone where the record says nothing, reads everything back, and a
//      second run changes nothing; a ruleset the record does not name stops
//      it and is never deleted; a repository the App is not installed on
//      stops for it with the install link while the other is still matched;
//      and the real records/github-repo-settings.json, when there is one,
//      passes;
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
// Build runners on One (26 Oct 2026): named in offBox, an off-box runner keeps it,
// but never one that carries thornswood-vps too.
const recOne = Object.assign({}, rec4, { offBox: ['thornswood-pr-one', 'thornswood-pr-one-2'] });
const withVps = mixed.concat([runner(41, 'thornswood-pr-one-2', ['self-hosted', 'Windows', 'thornswood-pr', 'thornswood-vps', 'thornswood-build'])]);
const pOne = admin.planLabels(recOne, withVps);
const didOne = (name) => (pOne.changes.find(c => c.name === name) || {}).do;
yes('an off-box runner the record names by name keeps the label', !didOne('thornswood-pr-one'));
yes('  but not one that also carries thornswood-vps', didOne('thornswood-pr-one-2') === 'take off');
yes('an off-box name with no runner under it is named', admin.planLabels(Object.assign({}, rec4, { offBox: ['thornswood-pr-one-5'] }), mixed).lines.some(l => /off-box runner thornswood-pr-one-5 is in/.test(l)));
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
yes('an off-box name that is not thornswood-pr-* stops', /not thornswood-pr-/.test(stops([Object.assign({}, rec4, { offBox: ['thornswood-vps-9'] })])));
yes('an off-box name listed twice stops', /off-box runner twice/.test(stops([Object.assign({}, rec4, { offBox: ['thornswood-pr-one', 'thornswood-pr-one'] })])));
yes('a runner number below 1 stops', /number from 1/.test(stops([{ file: 'r', label: 'thornswood-x', runners: [0] }])));
yes('the real records on this checkout pass', (() => {
  const dir = path.join(REPO, 'records');
  const recs = fs.readdirSync(dir).filter(f => /^[a-z0-9-]+-runners\.json$/.test(f)).map(f => {
    const j = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
    return { file: 'records/' + f, label: String(j.label || '').trim(), runners: (j.runners || []).map(Number) };
  });
  return recs.length > 0 && stops(recs) === '';
})());

// ---- 4a. the ruleset record and the plan ---------------------------------------------
console.log('the ruleset record and the plan');
const tagSet = {
  name: 'release tags', target: 'tag', enforcement: 'active', why: 'a note of the record\'s own',
  conditions: { ref_name: { include: ['refs/tags/v*'], exclude: [] } },
  rules: [{ type: 'creation' }, { type: 'update' }, { type: 'deletion' }],
  bypass_actors: [{ actor_id: 5, actor_type: 'RepositoryRole', bypass_mode: 'always' }, { actor_id: 15368, actor_type: 'Integration', bypass_mode: 'always' }],
};
const mainSet = {
  name: 'main', target: 'branch', enforcement: 'disabled',
  conditions: { ref_name: { include: ['~DEFAULT_BRANCH'], exclude: [] } },
  rules: [{ type: 'deletion' }, { type: 'non_fast_forward' },
    { type: 'required_status_checks', parameters: { strict_required_status_checks_policy: false, required_status_checks: [{ context: 'Launcher builds' }] } }],
  bypass_actors: [],
};
function rstops(list) { try { admin.checkRulesets('EvilPatrick06/Thornswood', list); return ''; } catch (e) { return e.message; } }
const with_ = (o, k, v) => Object.assign({}, o, { [k]: v });
yes('the two rulesets pass together', rstops([tagSet, mainSet]) === '');
yes('no list stops, and an empty one says there are none', /no rulesets list/.test(rstops(undefined)) && rstops([]) === '');
yes('a name twice stops', /twice/.test(rstops([tagSet, with_(mainSet, 'name', 'release tags')])));
yes('a target that is not branch or tag stops', /not branch or tag/.test(rstops([with_(tagSet, 'target', 'push')])));
yes('an enforcement that is not active or disabled stops', /not active or disabled/.test(rstops([with_(tagSet, 'enforcement', 'evaluate')])));
yes('a ruleset on no ref stops', /no ref/.test(rstops([with_(tagSet, 'conditions', { ref_name: { include: [] } })])));
yes('one with no rules, or a rule with no type, stops', /no rules/.test(rstops([with_(tagSet, 'rules', [])])) && /no type/.test(rstops([with_(tagSet, 'rules', [{}])])));
yes('one that does not say who may bypass it stops', /bypass/.test(rstops([with_(mainSet, 'bypass_actors', undefined)])));
yes('the body sent is the ruleset\'s own keys, never the record\'s note',
  JSON.stringify(Object.keys(admin.rulesetBody(tagSet))) === '["name","target","enforcement","conditions","rules","bypass_actors"]');
// GitHub's copy, as it reads one back: ids, links and defaults of its own, lists in its own order.
const ghCopy = (r, id) => Object.assign(JSON.parse(JSON.stringify(admin.rulesetBody(r))), {
  id, source_type: 'Repository', source: 'EvilPatrick06/Thornswood', node_id: 'RRS_' + id, current_user_can_bypass: 'always',
  _links: { self: { href: 'x' } }, created_at: '2026-10-26T00:00:00Z', updated_at: '2026-10-26T00:00:00Z',
  rules: r.rules.slice().reverse().map(x => x.type === 'required_status_checks'
    ? { type: x.type, parameters: Object.assign({ do_not_enforce_on_create: false }, x.parameters) } : x),
  bypass_actors: r.bypass_actors.slice().reverse(),
});
yes('GitHub\'s copy with its own ids, defaults and order says what the record says', admin.says(admin.rulesetBody(tagSet), ghCopy(tagSet, 1)) && admin.says(admin.rulesetBody(mainSet), ghCopy(mainSet, 2)));
yes('  and not once a bypass actor is added on GitHub', !admin.says(admin.rulesetBody(tagSet), Object.assign(ghCopy(tagSet, 1), { bypass_actors: tagSet.bypass_actors.concat([{ actor_id: 4, actor_type: 'RepositoryRole', bypass_mode: 'always' }]) })));
yes('  or its enforcement is changed', !admin.says(admin.rulesetBody(mainSet), Object.assign(ghCopy(mainSet, 2), { enforcement: 'active' })));
yes('  or a required check is renamed', !admin.says(admin.rulesetBody(mainSet), Object.assign(ghCopy(mainSet, 2), { rules: [{ type: 'deletion' }, { type: 'non_fast_forward' }, { type: 'required_status_checks', parameters: { strict_required_status_checks_policy: false, required_status_checks: [{ context: 'Launcher builds (VPS fallback)' }] } }] })));
const rp = admin.planRulesets([tagSet, mainSet], [Object.assign(ghCopy(mainSet, 2), { enforcement: 'active' }), ghCopy(Object.assign({}, tagSet, { name: 'by hand' }), 9)]);
yes('the plan makes the missing one, puts the changed one back by its id, and names the one the record does not',
  rp.make.length === 1 && rp.make[0].name === 'release tags' && rp.put.length === 1 && rp.put[0].id === 2 && JSON.stringify(rp.extra) === '["by hand"]');
function sstops(doc) { try { admin.checkSettings(doc); return ''; } catch (e) { return e.message; } }
const forkMain = {
  name: 'main', target: 'branch', enforcement: 'active',
  conditions: { ref_name: { include: ['refs/heads/main'], exclude: [] } },
  rules: [{ type: 'deletion' }, { type: 'non_fast_forward' }],
  bypass_actors: [],
};
const settings = () => ({ repositories: [
  { repository: 'EvilPatrick06/Thornswood', rulesets: [tagSet, mainSet] },
  { repository: 'EvilPatrick06/skymp', private_vulnerability_reporting: true, rulesets: [forkMain] },
] });
yes('Thornswood and the fork pass together', sstops(settings()) === '');
yes('the repositories it may change are Thornswood and the fork, and no other', JSON.stringify(admin.SETTINGS_REPOS) === '["EvilPatrick06/Thornswood","EvilPatrick06/skymp"]');
yes('a record with no repositories stops', /names no repositories/.test(sstops({})) && /names no repositories/.test(sstops({ repositories: [] })));
yes('another repository stops, named', /names EvilPatrick06\/other, and the only ones/.test(sstops({ repositories: [{ repository: 'EvilPatrick06/other', rulesets: [] }] })));
yes('a repository named twice stops', /twice/.test(sstops({ repositories: [settings().repositories[1], settings().repositories[1]] })));
yes('reporting that is not true or false stops', /true or false/.test(sstops({ repositories: [with_(settings().repositories[1], 'private_vulnerability_reporting', 'yes')] })));
yes('a bad ruleset stops, naming its repository', /EvilPatrick06\/skymp: main targets push/.test(sstops({ repositories: [with_(settings().repositories[1], 'rulesets', [with_(forkMain, 'target', 'push')])] })));
yes('the real records/github-repo-settings.json, when there is one, passes', (() => {
  const f = path.join(REPO, 'records', 'github-repo-settings.json');
  if (!fs.existsSync(f)) return true;
  return sstops(JSON.parse(fs.readFileSync(f, 'utf8'))) === '';
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
  forkToken: 'ghs_' + crypto.randomBytes(16).toString('hex'),
  installed: true,
  forkInstalled: true,
  installRepos: ['EvilPatrick06/Thornswood-Ops', 'EvilPatrick06/Thornswood'],
  conversion: null,
  sets: { Thornswood: [], skymp: [] },
  pvr: { Thornswood: false, skymp: false },
  nextRuleset: 100,
};
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
    const P = u.pathname;
    // Each installation token reaches the one repository it was asked for.
    const asInst = () => req.headers.authorization === 'Bearer ' + (P.startsWith('/repos/EvilPatrick06/skymp/') ? gh.forkToken : gh.instToken);
    if (P === '/jwks') return send(200, JWKS);
    let m = /^\/repos\/EvilPatrick06\/(Thornswood|skymp)\/installation$/.exec(P);
    if (m) return !asApp() ? send(401, { message: 'Bad credentials' }) : (m[1] === 'skymp' ? gh.forkInstalled : gh.installed) ? send(200, { id: 77 }) : send(404, { message: 'Not Found' });
    if (P === '/app/installations/77/access_tokens' && req.method === 'POST') {
      if (!asApp()) return send(401, { message: 'Bad credentials' });
      const one = body && body.repositories && body.repositories.length === 1 ? body.repositories[0] : '';
      // A token for no one repository (installation-repos) reads the metadata of all of them.
      if (!body || !body.repositories) return send(201, { token: gh.instToken });
      return one === 'skymp' ? send(201, { token: gh.forkToken }) : one === 'Thornswood' ? send(201, { token: gh.instToken }) : send(422, { message: 'one repository, please' });
    }
    if (!P.startsWith('/app-manifests/') && !asInst()) return send(401, { message: 'Bad credentials' });
    if (P === '/installation/repositories') return send(200, { total_count: gh.installRepos.length, repositories: gh.installRepos.map(n => ({ full_name: n })) });
    if (P === '/repos/EvilPatrick06/Thornswood/contents/records') {
      if (u.searchParams.get('ref') !== 'main') return send(404, { message: 'No commit found for the ref' });
      return send(200, Object.keys(gh.records).concat(['README.md']).map(n => ({ type: 'file', name: n })));
    }
    if (P === '/repos/EvilPatrick06/Thornswood/contents/records/github-repo-settings.json') {
      if (u.searchParams.get('ref') !== 'main' || !gh.settingsRecord) return send(404, { message: 'Not Found' });
      return send(200, { content: Buffer.from(JSON.stringify(gh.settingsRecord)).toString('base64') });
    }
    m = /^\/repos\/EvilPatrick06\/Thornswood\/contents\/records\/(.+)$/.exec(P);
    if (m && gh.records[m[1]] && u.searchParams.get('ref') === 'main') return send(200, { content: Buffer.from(JSON.stringify(gh.records[m[1]])).toString('base64') });
    m = /^\/repos\/EvilPatrick06\/(Thornswood|skymp)\/rulesets$/.exec(P);
    if (m && req.method === 'GET') {
      if (u.searchParams.get('includes_parents') !== 'false') return send(400, { message: 'ask for this repository\'s own' });
      return send(200, gh.sets[m[1]].map(r => ({ id: r.id, name: r.name, target: r.target, enforcement: r.enforcement, source_type: 'Repository' })));
    }
    if (m && req.method === 'POST') {
      const sets = gh.sets[m[1]];
      if (sets.some(r => r.name === body.name)) return send(422, { message: 'Name must be unique' });
      const made = ghCopy(body, gh.nextRuleset++);
      sets.push(made);
      return send(201, made);
    }
    m = /^\/repos\/EvilPatrick06\/(Thornswood|skymp)\/rulesets\/(\d+)$/.exec(P);
    if (m) {
      const sets = gh.sets[m[1]];
      const i = sets.findIndex(r => r.id === Number(m[2]));
      if (i < 0) return send(404, { message: 'Not Found' });
      if (req.method === 'GET') return send(200, sets[i]);
      if (req.method === 'PUT') { sets[i] = ghCopy(body, sets[i].id); return send(200, sets[i]); }
      if (req.method === 'DELETE') { sets.splice(i, 1); return send(204); }
    }
    m = /^\/repos\/EvilPatrick06\/(Thornswood|skymp)\/private-vulnerability-reporting$/.exec(P);
    if (m) {
      if (req.method === 'GET') return send(200, { enabled: gh.pvr[m[1]] });
      if (req.method === 'PUT') { gh.pvr[m[1]] = true; return send(204); }
      if (req.method === 'DELETE') { gh.pvr[m[1]] = false; return send(204); }
    }
    if (P === '/repos/EvilPatrick06/Thornswood/actions/runners') return send(200, { total_count: gh.runners.length, runners: gh.runners });
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
    yes('anything but runner-labels, repo-settings and installation-repos is refused (400)', r.status === 400 && /runner-labels, repo-settings and installation-repos/.test(r.text));

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
    gh.calls = [];
    r = await ask4(bearer(sign(good())), { what: 'installation-repos', check: false });
    const repoTok = gh.calls.find(c => /access_tokens$/.test(c.path));
    yes('installation-repos lists the repositories the App is on, sorted (200)',
      r.status === 200 && r.json.ok && JSON.stringify(r.json.repos) === '["EvilPatrick06/Thornswood","EvilPatrick06/Thornswood-Ops"]' && r.json.lines.includes('installed on EvilPatrick06/Thornswood-Ops'));
    yes('  with a token that reads metadata alone, for no one repository',
      repoTok && repoTok.body.repositories === undefined && JSON.stringify(repoTok.body.permissions) === '{"metadata":"read"}');
    yes('  asked with that token, and changing nothing, reading no record and no runner',
      gh.calls.some(c => c.path.startsWith('/installation/repositories') && c.auth === 'Bearer ' + gh.instToken) && writes().length === 0 && !gh.calls.some(c => /contents\/records|actions\/runners/.test(c.path)));
    gh.installRepos = [];
    r = await ask4(bearer(sign(good())), { what: 'installation-repos' });
    yes('  an installation on no repository says so', r.status === 200 && r.json.repos.length === 0 && r.json.lines[0] === 'installed on no repository');
    gh.installRepos = ['EvilPatrick06/Thornswood-Ops', 'EvilPatrick06/Thornswood'];
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

    // ---- 4a. repository settings ----
    console.log('repository settings');
    const T = 'EvilPatrick06/Thornswood', S = 'EvilPatrick06/skymp';
    const rsWrites = () => gh.calls.filter(c => /\/(rulesets|private-vulnerability-reporting)/.test(c.path) && c.method !== 'GET');
    const askRs = (check, over) => ask4(bearer(sign(good(over))), { what: 'repo-settings', check: !!check });
    const has = (re) => r.json.lines.some(l => re.test(l));
    gh.calls = [];
    r = await askRs();
    yes('with no record on main it says so and changes nothing (502)', r.status === 502 && /main has no records\/github-repo-settings\.json/.test(r.text) && rsWrites().length === 0);
    gh.settingsRecord = settings();
    gh.calls = [];
    r = await askRs(true);
    yes('a check says what would be made and switched, and changes nothing', r.status === 200 && r.json.ok && r.json.differs === 4 && r.json.changed === 0 && rsWrites().length === 0 &&
      has(/^EvilPatrick06\/Thornswood: the ruleset release tags would be made \(active\)$/) && has(/^EvilPatrick06\/Thornswood: the ruleset main would be made \(disabled\)$/) &&
      has(/^EvilPatrick06\/skymp: the ruleset main would be made \(active\)$/) && has(/^EvilPatrick06\/skymp: private vulnerability reporting would be switched on$/));
    gh.calls = [];
    r = await askRs(false, { event_name: 'push' });
    const posted = gh.calls.filter(c => c.method === 'POST' && /\/rulesets$/.test(c.path));
    yes('a run makes all three and switches the fork\'s reporting on (200, 4 changed)', r.status === 200 && r.json.ok && r.json.changed === 4 &&
      gh.sets.Thornswood.length === 2 && gh.sets.skymp.length === 1 && gh.pvr.skymp === true);
    yes('  sending each ruleset\'s own keys and not the record\'s note',
      posted.length === 3 && posted.every(c => !('why' in c.body)) &&
      JSON.stringify(posted.find(c => c.body.name === 'release tags').body.bypass_actors) === JSON.stringify(tagSet.bypass_actors));
    yes('  each repository\'s with a token for that repository alone',
      posted.filter(c => c.path.startsWith('/repos/' + T + '/')).every(c => c.auth === 'Bearer ' + gh.instToken) &&
      posted.filter(c => c.path.startsWith('/repos/' + S + '/')).every(c => c.auth === 'Bearer ' + gh.forkToken) &&
      gh.calls.some(c => c.method === 'PUT' && c.path === '/repos/' + S + '/private-vulnerability-reporting' && c.auth === 'Bearer ' + gh.forkToken));
    const forkTok = gh.calls.find(c => /access_tokens$/.test(c.path) && c.body.repositories[0] === 'skymp');
    yes('  the fork\'s token asked for skymp alone, with administration write only',
      forkTok && JSON.stringify(forkTok.body.repositories) === '["skymp"]' && JSON.stringify(forkTok.body.permissions) === '{"administration":"write"}');
    yes('  Thornswood\'s reporting, which the record does not mention, is not asked about or touched',
      gh.pvr.Thornswood === false && !gh.calls.some(c => c.path === '/repos/' + T + '/private-vulnerability-reporting'));
    yes('  and it reads everything back after',
      gh.calls.filter(c => c.method === 'GET' && c.path.startsWith('/repos/' + T + '/rulesets?')).length === 2 &&
      gh.calls.filter(c => c.method === 'GET' && c.path.startsWith('/repos/' + S + '/rulesets?')).length === 2 &&
      gh.calls.filter(c => c.method === 'GET' && c.path === '/repos/' + S + '/private-vulnerability-reporting').length === 2);
    gh.calls = [];
    r = await askRs();
    yes('a second run changes nothing', r.status === 200 && r.json.changed === 0 && rsWrites().length === 0 &&
      r.json.lines.filter(l => /GitHub matches the record for the ruleset/.test(l)).length === 3 && has(/^EvilPatrick06\/skymp: private vulnerability reporting is on, as the record says$/));
    const tagId = gh.sets.Thornswood.find(x => x.name === 'release tags').id;
    gh.sets.Thornswood.find(x => x.name === 'release tags').bypass_actors.push({ actor_id: 4, actor_type: 'RepositoryRole', bypass_mode: 'always' });
    gh.calls = [];
    r = await askRs();
    yes('a ruleset changed on GitHub is put back by its id', r.status === 200 && r.json.changed === 1 && rsWrites().length === 1 &&
      rsWrites()[0].method === 'PUT' && rsWrites()[0].path === '/repos/' + T + '/rulesets/' + tagId &&
      gh.sets.Thornswood.find(x => x.name === 'release tags').bypass_actors.length === 2);
    gh.pvr.skymp = false;
    gh.calls = [];
    r = await askRs();
    yes('the fork\'s reporting switched off on GitHub is switched on again', r.status === 200 && r.json.changed === 1 && gh.pvr.skymp === true && has(/skymp: private vulnerability reporting switched on$/));
    gh.settingsRecord.repositories[1].private_vulnerability_reporting = false;
    gh.calls = [];
    r = await askRs();
    yes('  and a record that says off switches it off', r.status === 200 && r.json.changed === 1 && gh.pvr.skymp === false &&
      rsWrites().length === 1 && rsWrites()[0].method === 'DELETE');
    gh.settingsRecord = settings();
    r = await askRs();
    gh.sets.skymp.push(ghCopy(Object.assign({}, forkMain, { name: 'by hand' }), 900));
    gh.calls = [];
    r = await askRs();
    yes('a ruleset the record does not name stops it (409), and is never deleted', r.status === 409 && /skymp: GitHub has a ruleset by hand/.test(r.text) && rsWrites().length === 0 && gh.sets.skymp.some(x => x.name === 'by hand'));
    yes('  while the other repository is still matched', r.json.lines.filter(l => /^EvilPatrick06\/Thornswood: GitHub matches/.test(l)).length === 2);
    gh.sets.skymp = gh.sets.skymp.filter(x => x.name !== 'by hand');
    gh.forkInstalled = false;
    gh.sets.Thornswood = gh.sets.Thornswood.filter(x => x.name !== 'main');
    gh.calls = [];
    r = await askRs();
    yes('a repository the App is not installed on stops for it (409) with the install link', r.status === 409 && has(/^STOP EvilPatrick06\/skymp: the App is not installed on EvilPatrick06\/skymp yet: \S+\/installations\/new; nothing more/) &&
      !gh.calls.some(c => c.path.startsWith('/repos/' + S + '/') && c.method !== 'GET'));
    yes('  and the other is still put right', gh.sets.Thornswood.some(x => x.name === 'main') && has(/^EvilPatrick06\/Thornswood: the ruleset main made \(disabled\)$/));
    gh.forkInstalled = true;
    gh.settingsRecord = { repositories: [{ repository: 'EvilPatrick06/other', rulesets: [] }] };
    gh.calls = [];
    r = await askRs();
    yes('a record naming another repository stops it, nothing changed (502)', r.status === 502 && /the only ones this changes are/.test(r.text) && rsWrites().length === 0);
    gh.settingsRecord = { repositories: [{ repository: T, rulesets: [with_(tagSet, 'target', 'push')] }] };
    gh.calls = [];
    r = await askRs();
    yes('a bad ruleset on main stops it, nothing changed (502)', r.status === 502 && /not branch or tag/.test(r.text) && rsWrites().length === 0);
    gh.settingsRecord = settings();
    r = await ask4(bearer(sign(good())), { what: 'repo-settings', repositories: [{ repository: S, private_vulnerability_reporting: false, rulesets: [] }] });
    yes('settings sent by the caller are not used', r.status === 200 && r.json.changed === 0 && gh.pvr.skymp === true && gh.sets.skymp.length === 1);

    const tokenSeen = sign(good());
    await ask4(bearer(tokenSeen));
    const log = svc.log();
    yes('the log names the run and what changed', /run 4242 \(workflow_dispatch by EvilPatrick06\)/.test(log));
    yes('  and never a token or the key', !log.includes(tokenSeen.split('.')[2]) && !log.includes(gh.instToken) && !log.includes(gh.forkToken) && !log.includes('PRIVATE KEY'));

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
    yes('  and says to pick Thornswood and skymp, the engine fork (#3683)', /pick <b>Thornswood<\/b> and <b>skymp<\/b>/.test(r.text));
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
