#!/usr/bin/env node
'use strict';
/*
  admin.js

  The box's GitHub admin service (#3107, Patrick's A of 22 Oct 2026). A cloud
  Claude thread cannot make a repository-admin call: the cloud environment's
  proxy refuses every actions/runners, variables, secrets and environments
  path (measured 22 Oct 2026, 10:20 AM), and a workflow's own token has no
  permission for any of them. So a GitHub App made for Thornswood holds that
  right, its key lives here and nowhere else, and this is the only thing
  that uses it.

  WHAT IT DOES. It makes GitHub's admin settings match what main records, and
  nothing else:
    runner-labels   every records/<name>-runners.json on main, { label,
                    runners }: the runners it lists (thornswood-vps is 1,
                    thornswood-vps-<n> is n) carry the label and no other
                    runner does. records/build-runners.json is the build cap
                    (#2994). It stops for a record whose runners GitHub does
                    not have, since every job asking for its label would
                    then wait for a runner that never comes.
    repo-settings   records/github-repo-settings.json on main (#3683,
                    Patrick's answers of 26 Oct 2026), { repositories: [{
                    repository, rulesets: [...],
                    private_vulnerability_reporting }] }, for Thornswood and
                    the engine fork, EvilPatrick06/skymp, and no other
                    repository: each ruleset an entry names is on GitHub
                    with exactly its target, enforcement, conditions, rules
                    and bypass list, made or put back by name, and private
                    vulnerability reporting is on or off as the entry says
                    (left as it is when the entry does not say). A ruleset
                    GitHub has that the record does not name is never
                    deleted here; it stops the run, named, so a protection
                    nobody wrote down is a pull request to the record or a
                    deliberate removal, never a silent loss. A repository
                    the App is not installed on stops the run for it, with
                    the link that installs it, and the others go on.
  What to do comes from Thornswood's main, read through the App, never from the caller,
  so whoever asks can only make GitHub match main. A change is a pull
  request to the record.

  WHO MAY ASK. A run of .github/workflows/github-admin.yml on main, and
  nothing else: it sends the OIDC token GitHub gave that run, for the
  audience thornswood-admin, and this checks it against GitHub's published
  keys (fetched each time) and its claims: GitHub's issuer, the audience,
  not expired, this repository, refs/heads/main, that exact workflow on
  main, started by hand or by a push. A pull request's run has another ref
  and another workflow ref, so it cannot. No secret is involved: the token
  is GitHub's word for which run is asking.

  WHERE. 127.0.0.1:7791. Caddy carries https://thornswood.net/github-app/ to
  it for the App's one-time setup only (scripts\deploy\Caddyfile), and
  anything that came through Caddy (it has X-Forwarded-For) is refused
  everything but the setup pages.

  THE APP'S SETUP. Install-AdminService.ps1 -Setup arms it: state\setup.json
  with a one-time state and an hour to live, and prints the address
  https://thornswood.net/github-app/setup?state=<state>. That page sends the
  App's manifest to GitHub (name, no webhook, private, administration write
  and contents read on the repositories it is installed on); Patrick creates
  it, GitHub sends him back to /setup/done with a one-time code, and this
  trades the code for the App's key straight from GitHub. The key goes into
  state\key.pem, the App's id and name into state\app.json, the setup is
  disarmed, and the page links the App's install page. The key is never
  shown, logged or sent anywhere. An App another account made is refused.

  It logs one line per request: what was asked, by which run, and what
  changed. Never a token or the key.

      node admin.js                      listens on 127.0.0.1:7791
      THORNSWOOD_ADMIN_PORT              another port; 0 takes a free one,
                                         which the first line names
      THORNSWOOD_ADMIN_STATE             the state folder; state beside this
                                         file when unset
      THORNSWOOD_ADMIN_GITHUB_API        https://api.github.com when unset
      THORNSWOOD_ADMIN_GITHUB_WEB        https://github.com when unset
      THORNSWOOD_ADMIN_JWKS              GitHub Actions' OIDC keys when unset
                                         (the harness points these at
                                         stand-ins)

  Install-AdminService.ps1 puts it on the box as the task "Thornswood
  Admin", LOCAL SERVICE with a SID of its own, its folder closed to every
  other account, the runners' included. tests\test-3107-admin.js drives it.
*/
const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const PORT = process.env.THORNSWOOD_ADMIN_PORT ? Number(process.env.THORNSWOOD_ADMIN_PORT) : 7791;
const STATE = process.env.THORNSWOOD_ADMIN_STATE || path.join(__dirname, 'state');
const API = (process.env.THORNSWOOD_ADMIN_GITHUB_API || 'https://api.github.com').replace(/\/$/, '');
const WEB = (process.env.THORNSWOOD_ADMIN_GITHUB_WEB || 'https://github.com').replace(/\/$/, '');
const JWKS = process.env.THORNSWOOD_ADMIN_JWKS || 'https://token.actions.githubusercontent.com/.well-known/jwks';
const PLAIN = 'box admin: not here';

const REPO = 'EvilPatrick06/Thornswood';
const OWNER = 'EvilPatrick06';
const RULES = {
  iss: 'https://token.actions.githubusercontent.com',
  aud: 'thornswood-admin',
  repository: REPO,
  ref: 'refs/heads/main',
  workflow: REPO + '/.github/workflows/github-admin.yml@refs/heads/main',
  events: ['workflow_dispatch', 'push'],
};
// The labels every VPS runner carries, or GitHub gives itself; a record may
// never name one, since taking it off would strand every job that asks.
const RESERVED = ['self-hosted', 'windows', 'linux', 'macos', 'x64', 'arm64', 'thornswood-vps', 'thornswood-pr'];
// What each ask matches, and the record it reads on main.
const ASKS = ['runner-labels', 'repo-settings'];
const SETTINGS_FILE = 'records/github-repo-settings.json';
// The repositories repo-settings may change: this one and the engine fork.
// The App reaches only those it is installed on, and this stops a record
// naming any other even then.
const SETTINGS_REPOS = [REPO, OWNER + '/skymp'];
// What each installation token may do: Thornswood's reads main's records
// too; the fork's only needs its settings.
const HOME_PERMISSIONS = { administration: 'write', contents: 'read' };
const FORK_PERMISSIONS = { administration: 'write' };
// The parts of a ruleset the record says and GitHub is made to match. Any
// other key in a record entry (why) is the record's own note and never sent.
const RULESET_KEYS = ['name', 'target', 'enforcement', 'conditions', 'rules', 'bypass_actors'];

// Server-Log.js --stamp puts the time on each line, as it does for the bridge.
function log(line) {
  console.log(line);
}

function b64url(buf) {
  return Buffer.from(buf).toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
}
function unb64url(s) {
  return Buffer.from(String(s).replace(/-/g, '+').replace(/_/g, '/'), 'base64');
}

// The claims of a GitHub Actions OIDC token, once its signature checks out
// against one of GitHub's keys and every claim is what RULES says. Throws
// with why otherwise. now is in seconds.
function verifyOidc(token, jwks, now, rules) {
  const parts = String(token || '').split('.');
  if (parts.length !== 3) throw new Error('not a token');
  let head, claims;
  try {
    head = JSON.parse(unb64url(parts[0]).toString('utf8'));
    claims = JSON.parse(unb64url(parts[1]).toString('utf8'));
  } catch (e) {
    throw new Error('not a token');
  }
  if (head.alg !== 'RS256') throw new Error('signed with ' + head.alg + ', not RS256');
  const jwk = ((jwks && jwks.keys) || []).find(k => k.kid === head.kid && k.kty === 'RSA');
  if (!jwk) throw new Error('signed with a key GitHub does not publish');
  const key = crypto.createPublicKey({ key: { kty: 'RSA', n: jwk.n, e: jwk.e }, format: 'jwk' });
  const ok = crypto.verify('RSA-SHA256', Buffer.from(parts[0] + '.' + parts[1]), key, unb64url(parts[2]));
  if (!ok) throw new Error('its signature does not check out');
  if (claims.iss !== rules.iss) throw new Error('issued by ' + claims.iss);
  const aud = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  if (aud.indexOf(rules.aud) < 0) throw new Error('for the audience ' + aud.join(', '));
  if (!(Number(claims.exp) > now)) throw new Error('expired');
  if (claims.nbf !== undefined && Number(claims.nbf) > now + 60) throw new Error('not valid yet');
  if (claims.repository !== rules.repository) throw new Error('from ' + claims.repository);
  if (claims.ref !== rules.ref) throw new Error('from ' + claims.ref + ', not ' + rules.ref);
  if (claims.job_workflow_ref !== rules.workflow) throw new Error('from the workflow ' + claims.job_workflow_ref);
  if (rules.events.indexOf(claims.event_name) < 0) throw new Error('started by ' + claims.event_name);
  return claims;
}

// The App's own token, ten minutes at most, for asking GitHub for an
// installation token. now is in seconds.
function appJwt(appId, pem, now) {
  const head = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const body = b64url(JSON.stringify({ iat: now - 60, exp: now + 540, iss: String(appId) }));
  const sig = crypto.sign('RSA-SHA256', Buffer.from(head + '.' + body), crypto.createPrivateKey(pem));
  return head + '.' + body + '.' + b64url(sig);
}

// A VPS runner's number from its name: thornswood-vps is 1, thornswood-vps-<n> is n.
function runnerNumber(name) {
  if (name === 'thornswood-vps') return 1;
  const m = /^thornswood-vps-(\d+)$/.exec(String(name));
  return m ? Number(m[1]) : 0;
}

// Checks each record and that no two name the same label. Throws with why.
function checkRecords(records) {
  const seen = {};
  for (const r of records) {
    const label = String(r.label || '').trim();
    if (!/^[a-z0-9][a-z0-9-]{0,62}$/.test(label)) throw new Error(r.file + ': the label must be one lower case word, and it is "' + r.label + '"');
    if (RESERVED.indexOf(label) >= 0) throw new Error(r.file + ': ' + label + ' is a label every runner carries or GitHub gives, so no record may name it');
    if (seen[label]) throw new Error(r.file + ' and ' + seen[label] + ' both name ' + label);
    seen[label] = r.file;
    const nums = Array.isArray(r.runners) ? r.runners : [];
    if (!nums.length) throw new Error(r.file + ' lists no runners, so no job asking for ' + label + ' could ever run');
    if (nums.some(n => !Number.isInteger(n) || n < 1)) throw new Error(r.file + ' lists a runner that is not a number from 1');
    if (new Set(nums).size !== nums.length) throw new Error(r.file + ' lists a runner twice');
  }
}

// What has to change for GitHub's runners to match one record:
// { changes: [{ id, name, do: 'put on'|'take off' }], lines, refuse }. refuse
// is why nothing may change for it, or ''.
function planLabels(record, runners) {
  const label = record.label;
  const want = record.runners;
  const changes = [];
  const lines = [];
  let carry = 0;
  for (const r of runners) {
    const n = runnerNumber(r.name);
    const has = (r.labels || []).some(l => l.name === label);
    const should = n > 0 && want.indexOf(n) >= 0;
    if (should) carry++;
    if (has && !should) changes.push({ id: r.id, name: r.name, do: 'take off' });
    else if (should && !has) changes.push({ id: r.id, name: r.name, do: 'put on' });
  }
  for (const n of want) {
    if (!runners.some(r => runnerNumber(r.name) === n)) lines.push('runner ' + n + ' is in ' + record.file + ' but not registered on GitHub');
  }
  const refuse = carry ? '' : 'no runner ' + record.file + ' lists is registered on GitHub, so every job asking for ' + label + ' would wait for a runner that never comes';
  return { changes, lines, refuse };
}

// Checks one repository's rulesets in main's settings record. An empty list
// says the repository has none. Throws with why.
function checkRulesets(repo, list) {
  const at = SETTINGS_FILE + ', ' + repo;
  if (!Array.isArray(list)) throw new Error(at + ': no rulesets list (an empty one says it has none)');
  const seen = {};
  for (const r of list) {
    const name = String((r && r.name) || '').trim();
    if (!name) throw new Error(at + ': a ruleset has no name');
    if (seen[name]) throw new Error(at + ' names ' + name + ' twice');
    seen[name] = true;
    if (['branch', 'tag'].indexOf(r.target) < 0) throw new Error(at + ': ' + name + ' targets ' + r.target + ', not branch or tag');
    if (['active', 'disabled'].indexOf(r.enforcement) < 0) throw new Error(at + ': ' + name + ' is ' + r.enforcement + ', not active or disabled');
    const inc = r.conditions && r.conditions.ref_name && r.conditions.ref_name.include;
    if (!Array.isArray(inc) || !inc.length) throw new Error(at + ': ' + name + ' applies to no ref');
    if (!Array.isArray(r.rules) || !r.rules.length || r.rules.some(x => !x || typeof x.type !== 'string')) throw new Error(at + ': ' + name + ' has no rules, or one with no type');
    if (!Array.isArray(r.bypass_actors)) throw new Error(at + ': ' + name + ' does not say who may bypass it (an empty list is nobody)');
  }
}

// Checks main's settings record: Thornswood and the fork only, each once,
// with its rulesets, and reporting a yes or no when it is given. Throws.
function checkSettings(doc) {
  const list = doc && doc.repositories;
  if (!Array.isArray(list) || !list.length) throw new Error(SETTINGS_FILE + ' names no repositories');
  const seen = {};
  for (const e of list) {
    const repo = String((e && e.repository) || '');
    if (SETTINGS_REPOS.indexOf(repo) < 0) throw new Error(SETTINGS_FILE + ' names ' + (repo || 'a repository with no name') + ', and the only ones this changes are ' + SETTINGS_REPOS.join(' and '));
    if (seen[repo]) throw new Error(SETTINGS_FILE + ' names ' + repo + ' twice');
    seen[repo] = true;
    if (e.private_vulnerability_reporting !== undefined && typeof e.private_vulnerability_reporting !== 'boolean') throw new Error(SETTINGS_FILE + ', ' + repo + ': private_vulnerability_reporting is true or false, not ' + JSON.stringify(e.private_vulnerability_reporting));
    checkRulesets(repo, e.rulesets);
  }
}

// The body GitHub is sent for one record entry: its API keys and nothing else.
function rulesetBody(r) {
  const out = {};
  for (const k of RULESET_KEYS) out[k] = r[k];
  return out;
}

// Whether GitHub's copy says everything the record says. An object matches
// when each key the record gives matches (GitHub adds ids, links and
// defaults of its own); a list matches when it has as many entries and, in
// a stable order, each matches; anything else is equal.
function says(want, have) {
  if (Array.isArray(want)) {
    if (!Array.isArray(have) || have.length !== want.length) return false;
    const key = x => JSON.stringify(x && typeof x === 'object' ? [x.type, x.actor_type, x.actor_id, x.context] : x);
    const w = want.slice().sort((a, b) => (key(a) < key(b) ? -1 : key(a) > key(b) ? 1 : 0));
    const h = have.slice().sort((a, b) => (key(a) < key(b) ? -1 : key(a) > key(b) ? 1 : 0));
    return w.every((x, i) => says(x, h[i]));
  }
  if (want && typeof want === 'object') {
    if (!have || typeof have !== 'object') return false;
    return Object.keys(want).every(k => says(want[k], have[k]));
  }
  return want === have;
}

// What has to change for GitHub's rulesets to match the record:
// { make: [entry], put: [{ id, entry }], extra: [name], right: [name] }.
// have is GitHub's rulesets, each read in full.
function planRulesets(list, have) {
  const make = [], put = [], right = [];
  for (const r of list) {
    const g = have.find(x => x.name === r.name);
    if (!g) make.push(r);
    else if (!says(rulesetBody(r), g)) put.push({ id: g.id, entry: r });
    else right.push(r.name);
  }
  const extra = have.filter(g => !list.some(r => r.name === g.name)).map(g => g.name);
  return { make, put, extra, right };
}

// ------------------------------------------------------------------ GitHub --
// One HTTPS call. Resolves { status, body } with the body parsed when it is
// JSON; never rejects for a status, only when nothing answered.
function call(method, url, headers, body) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const data = body === undefined ? null : Buffer.from(JSON.stringify(body));
    const h = Object.assign({ 'User-Agent': 'thornswood-admin', Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28' }, headers || {});
    if (data) { h['Content-Type'] = 'application/json'; h['Content-Length'] = data.length; }
    const req = (u.protocol === 'http:' ? http : https).request(u, { method, headers: h, timeout: 30000 }, res => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => {
        const text = Buffer.concat(chunks).toString('utf8');
        let parsed = text;
        if (text.trim()) { try { parsed = JSON.parse(text); } catch (e) { parsed = text; } } else parsed = null;
        resolve({ status: res.statusCode, body: parsed });
      });
    });
    req.on('timeout', () => req.destroy(new Error(method + ' ' + u.pathname + ' had no answer in 30 seconds')));
    req.on('error', reject);
    if (data) req.write(data);
    req.end();
  });
}
function said(a) {
  return 'HTTP ' + a.status + (a.body && a.body.message ? ': ' + a.body.message : '');
}

function readApp() {
  const keyPath = path.join(STATE, 'key.pem');
  const appPath = path.join(STATE, 'app.json');
  if (!fs.existsSync(keyPath) || !fs.existsSync(appPath)) return null;
  return { pem: fs.readFileSync(keyPath, 'utf8'), app: JSON.parse(fs.readFileSync(appPath, 'utf8')) };
}

// A token for one repository only, with only what the ask needs there, for
// the hour GitHub gives it; nothing keeps it after the request.
async function installationToken(held, now, repo, permissions) {
  const jwt = appJwt(held.app.id, held.pem, now);
  const auth = { Authorization: 'Bearer ' + jwt };
  const inst = await call('GET', API + '/repos/' + repo + '/installation', auth);
  if (inst.status === 404) throw new Error('the App is not installed on ' + repo + ' yet: ' + WEB + '/apps/' + held.app.slug + '/installations/new');
  if (inst.status !== 200) throw new Error('GitHub would not say where the App is installed on ' + repo + ' (' + said(inst) + ')');
  const tok = await call('POST', API + '/app/installations/' + inst.body.id + '/access_tokens', auth,
    { repositories: [repo.split('/')[1]], permissions });
  if (tok.status !== 201) throw new Error('GitHub gave the App no token (' + said(tok) + ')');
  return tok.body.token;
}

// Every records/<name>-runners.json on main, read through the App.
async function mainRecords(token) {
  const auth = { Authorization: 'Bearer ' + token };
  const dir = await call('GET', API + '/repos/' + REPO + '/contents/records?ref=main', auth);
  if (dir.status !== 200 || !Array.isArray(dir.body)) throw new Error('GitHub would not list records on main (' + said(dir) + ')');
  const out = [];
  for (const f of dir.body.filter(x => x.type === 'file' && /^[a-z0-9-]+-runners\.json$/.test(x.name)).sort((a, b) => (a.name < b.name ? -1 : 1))) {
    const got = await call('GET', API + '/repos/' + REPO + '/contents/records/' + f.name + '?ref=main', auth);
    if (got.status !== 200 || !got.body || !got.body.content) throw new Error('GitHub would not give records/' + f.name + ' on main (' + said(got) + ')');
    let j;
    try { j = JSON.parse(Buffer.from(got.body.content, 'base64').toString('utf8').replace(/^﻿/, '')); }
    catch (e) { throw new Error('records/' + f.name + ' on main is not JSON'); }
    out.push({ file: 'records/' + f.name, label: String(j.label || '').trim(), runners: Array.isArray(j.runners) ? j.runners.map(Number) : [] });
  }
  return out;
}

// main's settings record, read through the App.
async function mainSettings(token) {
  const got = await call('GET', API + '/repos/' + REPO + '/contents/' + SETTINGS_FILE + '?ref=main', { Authorization: 'Bearer ' + token });
  if (got.status === 404) throw new Error('main has no ' + SETTINGS_FILE + ', so there is nothing to match');
  if (got.status !== 200 || !got.body || !got.body.content) throw new Error('GitHub would not give ' + SETTINGS_FILE + ' on main (' + said(got) + ')');
  try { return JSON.parse(Buffer.from(got.body.content, 'base64').toString('utf8').replace(/^\uFEFF/, '')); }
  catch (e) { throw new Error(SETTINGS_FILE + ' on main is not JSON'); }
}

// A repository's own rulesets, each read in full.
async function listRulesets(token, repo) {
  const auth = { Authorization: 'Bearer ' + token };
  const a = await call('GET', API + '/repos/' + repo + '/rulesets?includes_parents=false&per_page=100', auth);
  if (a.status !== 200 || !Array.isArray(a.body)) throw new Error('GitHub would not list the rulesets of ' + repo + ' (' + said(a) + ')');
  const out = [];
  for (const s of a.body) {
    const one = await call('GET', API + '/repos/' + repo + '/rulesets/' + s.id, auth);
    if (one.status !== 200 || !one.body) throw new Error('GitHub would not give the ruleset ' + s.name + ' of ' + repo + ' (' + said(one) + ')');
    out.push(one.body);
  }
  return out;
}

// Makes one repository's rulesets match its entry, or with check says only
// what differs. { ok, lines, changed, differs }.
async function rulesets(token, repo, list, check) {
  const p = planRulesets(list, await listRulesets(token, repo));
  const lines = [];
  let changed = 0;
  let ok = true;
  for (const n of p.right) lines.push(repo + ': GitHub matches the record for the ruleset ' + n);
  for (const n of p.extra) { lines.push('STOP ' + repo + ': GitHub has a ruleset ' + n + ' that ' + SETTINGS_FILE + ' does not name; it was left as it is. Add it to the record, or remove it on GitHub on purpose'); ok = false; }
  const differs = p.make.length + p.put.length;
  const auth = { Authorization: 'Bearer ' + token };
  for (const r of p.make) {
    if (check) { lines.push(repo + ': the ruleset ' + r.name + ' would be made (' + r.enforcement + ')'); continue; }
    const a = await call('POST', API + '/repos/' + repo + '/rulesets', auth, rulesetBody(r));
    if (a.status !== 201) { lines.push('STOP ' + repo + ': GitHub did not make the ruleset ' + r.name + ' (' + said(a) + ')'); ok = false; continue; }
    changed++;
    lines.push(repo + ': the ruleset ' + r.name + ' made (' + r.enforcement + ')');
  }
  for (const c of p.put) {
    if (check) { lines.push(repo + ': the ruleset ' + c.entry.name + ' differs and would be put back'); continue; }
    const a = await call('PUT', API + '/repos/' + repo + '/rulesets/' + c.id, auth, rulesetBody(c.entry));
    if (a.status !== 200) { lines.push('STOP ' + repo + ': GitHub did not put the ruleset ' + c.entry.name + ' back (' + said(a) + ')'); ok = false; continue; }
    changed++;
    lines.push(repo + ': the ruleset ' + c.entry.name + ' put back (' + c.entry.enforcement + ')');
  }
  if (!check && changed) {
    // Read back rather than trust the calls.
    const again = planRulesets(list, await listRulesets(token, repo));
    for (const r of again.make.concat(again.put.map(c => c.entry))) { lines.push('STOP ' + repo + ': GitHub still differs for the ruleset ' + r.name); ok = false; }
  }
  return { ok, lines, changed, differs };
}

// Makes a repository's private vulnerability reporting on or off as its
// entry says, or with check says only whether it differs.
async function reporting(token, repo, want, check) {
  const auth = { Authorization: 'Bearer ' + token };
  const url = API + '/repos/' + repo + '/private-vulnerability-reporting';
  const word = want ? 'on' : 'off';
  const read = async () => {
    const a = await call('GET', url, auth);
    if (a.status !== 200 || !a.body || typeof a.body.enabled !== 'boolean') throw new Error('GitHub would not say whether private vulnerability reporting is on for ' + repo + ' (' + said(a) + ')');
    return a.body.enabled;
  };
  if ((await read()) === want) return { ok: true, lines: [repo + ': private vulnerability reporting is ' + word + ', as the record says'], changed: 0, differs: 0 };
  if (check) return { ok: true, lines: [repo + ': private vulnerability reporting would be switched ' + word], changed: 0, differs: 1 };
  const a = await call(want ? 'PUT' : 'DELETE', url, auth);
  if (a.status !== 204) return { ok: false, lines: ['STOP ' + repo + ': GitHub did not switch private vulnerability reporting ' + word + ' (' + said(a) + ')'], changed: 0, differs: 1 };
  // Read back rather than trust the call.
  if ((await read()) !== want) return { ok: false, lines: ['STOP ' + repo + ': GitHub still has private vulnerability reporting ' + (want ? 'off' : 'on')], changed: 1, differs: 1 };
  return { ok: true, lines: [repo + ': private vulnerability reporting switched ' + word], changed: 1, differs: 1 };
}

// Makes every repository main's settings record names match its entry, or
// with check says only what differs. One repository's stop does not keep
// the others from being matched. { ok, lines, changed, differs }.
async function repoSettings(held, now, check) {
  const home = await installationToken(held, now, REPO, HOME_PERMISSIONS);
  const doc = await mainSettings(home);
  checkSettings(doc);
  const out = { ok: true, lines: [], changed: 0, differs: 0 };
  const add = r => { out.ok = out.ok && r.ok; out.lines.push(...r.lines); out.changed += r.changed; out.differs += r.differs; };
  for (const e of doc.repositories) {
    try {
      const token = e.repository === REPO ? home : await installationToken(held, now, e.repository, FORK_PERMISSIONS);
      add(await rulesets(token, e.repository, e.rulesets, check));
      if (typeof e.private_vulnerability_reporting === 'boolean') add(await reporting(token, e.repository, e.private_vulnerability_reporting, check));
    } catch (err) {
      add({ ok: false, lines: ['STOP ' + e.repository + ': ' + err.message + '; nothing more was changed there'], changed: 0, differs: 0 });
    }
  }
  return out;
}

async function listRunners(token) {
  const a = await call('GET', API + '/repos/' + REPO + '/actions/runners?per_page=100', { Authorization: 'Bearer ' + token });
  if (a.status !== 200 || !a.body || !Array.isArray(a.body.runners)) throw new Error('GitHub would not list the runners (' + said(a) + ')');
  return a.body.runners;
}

// Makes the runners' labels match main's records, or with check says only
// what differs. { ok, lines, changed, differs }.
async function runnerLabels(token, check) {
  const records = await mainRecords(token);
  if (!records.length) throw new Error('main has no records/*-runners.json, so there is nothing to match');
  checkRecords(records);
  const runners = await listRunners(token);
  const lines = [];
  let changed = 0;
  let differs = 0;
  let ok = true;
  for (const rec of records) {
    const p = planLabels(rec, runners);
    lines.push(...p.lines);
    if (p.refuse) { lines.push('STOP ' + p.refuse + '; nothing was changed for it'); ok = false; continue; }
    if (!p.changes.length) { lines.push(rec.file + ': GitHub matches it, ' + rec.label + ' on runner(s) ' + rec.runners.join(', ')); continue; }
    differs += p.changes.length;
    for (const c of p.changes) {
      if (check) { lines.push(rec.file + ': ' + c.name + ' would have ' + rec.label + ' ' + (c.do === 'put on' ? 'put on' : 'taken off')); continue; }
      const auth = { Authorization: 'Bearer ' + token };
      const a = c.do === 'put on'
        ? await call('POST', API + '/repos/' + REPO + '/actions/runners/' + c.id + '/labels', auth, { labels: [rec.label] })
        : await call('DELETE', API + '/repos/' + REPO + '/actions/runners/' + c.id + '/labels/' + encodeURIComponent(rec.label), auth);
      if (a.status !== 200) { lines.push('STOP ' + c.name + ': GitHub did not ' + c.do + ' ' + rec.label + ' (' + said(a) + ')'); ok = false; continue; }
      changed++;
      lines.push(rec.file + ': ' + c.name + ', ' + rec.label + ' ' + (c.do === 'put on' ? 'put on' : 'taken off'));
    }
  }
  if (!check && changed) {
    // Read back rather than trust the calls.
    const after = await listRunners(token);
    for (const rec of records) {
      const p = planLabels(rec, after);
      if (!p.refuse && p.changes.length) { lines.push('STOP ' + rec.file + ': GitHub still differs for ' + p.changes.map(c => c.name).join(', ')); ok = false; }
    }
  }
  return { ok, lines, changed, differs };
}

// ------------------------------------------------------------------- setup --
function readSetup(now) {
  const p = path.join(STATE, 'setup.json');
  if (!fs.existsSync(p)) return null;
  const s = JSON.parse(fs.readFileSync(p, 'utf8'));
  if (!s.state || !(Number(s.expires) > now)) return null;
  return s;
}
function sameState(a, b) {
  const x = Buffer.from(String(a || ''));
  const y = Buffer.from(String(b || ''));
  return x.length === y.length && x.length >= 32 && crypto.timingSafeEqual(x, y);
}
function manifest() {
  return {
    name: 'Thornswood box admin',
    url: 'https://thornswood.net',
    hook_attributes: { url: 'https://thornswood.net/github-app/hook', active: false },
    redirect_url: 'https://thornswood.net/github-app/setup/done',
    public: false,
    default_permissions: { administration: 'write', contents: 'read' },
    default_events: [],
  };
}
function esc(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}
function page(res, status, title, body) {
  res.writeHead(status, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer' });
  res.end('<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>' + esc(title) +
    '</title><body style="font-family:sans-serif;max-width:40em;margin:2em auto;padding:0 1em"><h1>' + esc(title) + '</h1>' + body + '</body>');
}

async function setupStart(res, q, now) {
  const s = readSetup(now);
  if (!s || readApp() || !sameState(q.get('state'), s.state)) { plain(res); return; }
  const action = WEB + '/settings/apps/new?state=' + encodeURIComponent(s.state);
  page(res, 200, 'Make the Thornswood box admin App',
    '<p>This makes a private GitHub App on your account that can change the runners\' labels, the rulesets and private vulnerability reporting, and read the repository, and nothing else. Its key comes straight back to the box and is never shown.</p>' +
    '<form action="' + esc(action) + '" method="post"><input type="hidden" name="manifest" value="' + esc(JSON.stringify(manifest())) + '">' +
    '<p><button type="submit" style="font-size:1.2em;padding:.5em 1em">Make it on GitHub</button></p></form>');
}

async function setupDone(res, q, now) {
  const s = readSetup(now);
  if (!s || readApp() || !sameState(q.get('state'), s.state)) { plain(res); return; }
  const code = String(q.get('code') || '');
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(code)) { plain(res); return; }
  const a = await call('POST', API + '/app-manifests/' + encodeURIComponent(code) + '/conversions', {}, undefined);
  if (a.status !== 201 || !a.body || !a.body.pem || !a.body.id) {
    log('setup: GitHub would not make the App (' + said(a) + ')');
    page(res, 502, 'GitHub did not make the App', '<p>GitHub answered ' + esc(said(a)) + '. Nothing was kept. Ask for a new setup link.</p>');
    return;
  }
  const owner = a.body.owner && a.body.owner.login;
  if (owner !== OWNER) {
    log('setup: refused an App made by ' + owner);
    page(res, 403, 'Not this App', '<p>That App belongs to ' + esc(owner) + ', not ' + OWNER + ', so nothing was kept.</p>');
    return;
  }
  fs.writeFileSync(path.join(STATE, 'key.pem'), a.body.pem, { mode: 0o600 });
  fs.writeFileSync(path.join(STATE, 'app.json'), JSON.stringify({ id: a.body.id, slug: a.body.slug, owner, made: new Date(now * 1000).toISOString() }, null, 2));
  fs.unlinkSync(path.join(STATE, 'setup.json'));
  log('setup: App ' + a.body.slug + ' (' + a.body.id + ') made by ' + owner + '; its key is kept here and the setup is closed');
  const install = WEB + '/apps/' + encodeURIComponent(a.body.slug) + '/installations/new';
  page(res, 200, 'Made. Now install it',
    '<p>The App is made and its key is on the box. Last step: install it on Thornswood and skymp only.</p>' +
    '<p><a href="' + esc(install) + '" style="font-size:1.2em">Install it</a>, choose <b>Only select repositories</b>, pick <b>Thornswood</b> and <b>skymp</b>, then Install.</p>');
}

// ------------------------------------------------------------------ server --
function plain(res) {
  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end(PLAIN);
}
function json(res, status, o) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(o));
}
function readBody(req, max) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let n = 0;
    req.on('data', c => { n += c.length; if (n > max) { reject(new Error('too long')); req.destroy(); } else chunks.push(c); });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

async function converge(req, res, now) {
  const auth = String(req.headers.authorization || '');
  const m = /^Bearer (\S+)$/.exec(auth);
  let claims;
  try {
    if (!m) throw new Error('no token');
    const keys = await call('GET', JWKS, {});
    if (keys.status !== 200) throw new Error('GitHub\'s keys could not be read (' + said(keys) + ')');
    claims = verifyOidc(m[1], keys.body, now, RULES);
  } catch (e) {
    log('refused: ' + e.message);
    json(res, 403, { ok: false, lines: ['refused: the token is ' + e.message.replace(/^the token is /, '')] });
    return;
  }
  let ask;
  try { ask = JSON.parse((await readBody(req, 4096)) || '{}'); } catch (e) { ask = null; }
  if (!ask || ASKS.indexOf(ask.what) < 0) { json(res, 400, { ok: false, lines: ['the only things this does are ' + ASKS.join(' and ')] }); return; }
  const run = claims.run_id + ' (' + claims.event_name + ' by ' + claims.actor + ')';
  const held = readApp();
  if (!held) { log('run ' + run + ': no App yet'); json(res, 503, { ok: false, lines: ['there is no App here yet: Install-AdminService.ps1 -Setup makes it'] }); return; }
  try {
    const r = ask.what === 'repo-settings'
      ? await repoSettings(held, now, !!ask.check)
      : await runnerLabels(await installationToken(held, now, REPO, HOME_PERMISSIONS), !!ask.check);
    log('run ' + run + ': ' + ask.what + (ask.check ? ' check' : '') + ', ' + r.changed + ' changed, ' + (r.ok ? 'ok' : 'stopped'));
    for (const l of r.lines) log('  ' + l);
    json(res, r.ok ? 200 : 409, r);
  } catch (e) {
    log('run ' + run + ': ' + e.message);
    json(res, 502, { ok: false, lines: [e.message] });
  }
}

function serve() {
  const server = http.createServer((req, res) => {
    const now = Math.floor(Date.now() / 1000);
    const u = new URL(req.url, 'http://127.0.0.1');
    // Through Caddy: the setup pages and nothing else.
    const outside = !!(req.headers['x-forwarded-for'] || req.headers['x-forwarded-host'] || req.headers.forwarded);
    let work;
    if (req.method === 'GET' && u.pathname === '/setup') work = setupStart(res, u.searchParams, now);
    else if (req.method === 'GET' && u.pathname === '/setup/done') work = setupDone(res, u.searchParams, now);
    else if (!outside && req.method === 'POST' && u.pathname === '/converge') work = converge(req, res, now);
    else { plain(res); return; }
    work.catch(e => {
      log('failed: ' + e.message);
      if (!res.headersSent) json(res, 500, { ok: false, lines: [e.message] });
      else res.end();
    });
  });
  server.listen(PORT, '127.0.0.1', () => log('listening on 127.0.0.1:' + server.address().port));
  return server;
}

module.exports = { verifyOidc, appJwt, planLabels, checkRecords, runnerNumber, checkRulesets, checkSettings, planRulesets, rulesetBody, says, manifest, RULES, ASKS, SETTINGS_REPOS, serve };
if (require.main === module) serve();
