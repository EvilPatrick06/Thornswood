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
    settings        reads, and changes nothing (#3534): the Actions settings
                    (on or off, which actions may run, the workflow token's
                    default, sharing, log and artifact retention, fork pull
                    requests), the runners, and the names (never the values,
                    which GitHub never gives) of the secrets and variables of
                    the repository and of each environment
                    records/github-settings.json on main names. A name the
                    App has no permission to read is said, with the
                    permission it needs, instead of being read.
  What to do comes from main, read through the App, never from the caller,
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

// What runner-labels needs, and nothing more.
const LABEL_PERMISSIONS = { administration: 'write', contents: 'read' };
// What settings reads with, all of it read only. The last three are asked for
// only when the installation holds them (SETTINGS_EXTRA); the App was made
// with administration and contents alone.
const SETTINGS_PERMISSIONS = { administration: 'read', contents: 'read' };
const SETTINGS_EXTRA = ['secrets', 'variables', 'environments'];

// Which permissions the installation holds, and where it is:
// { id, permissions }.
async function installation(held, now) {
  const jwt = appJwt(held.app.id, held.pem, now);
  const inst = await call('GET', API + '/repos/' + REPO + '/installation', { Authorization: 'Bearer ' + jwt });
  if (inst.status === 404) throw new Error('the App is not installed on ' + REPO + ' yet: ' + WEB + '/apps/' + held.app.slug + '/installations/new');
  if (inst.status !== 200) throw new Error('GitHub would not say where the App is installed (' + said(inst) + ')');
  return { id: inst.body.id, permissions: (inst.body && inst.body.permissions) || {} };
}

// A token for this repository only, with only the permissions given, for
// the hour GitHub gives it; nothing keeps it after the request.
async function installationToken(held, now, permissions, inst) {
  const where = inst || await installation(held, now);
  const jwt = appJwt(held.app.id, held.pem, now);
  const tok = await call('POST', API + '/app/installations/' + where.id + '/access_tokens', { Authorization: 'Bearer ' + jwt },
    { repositories: [REPO.split('/')[1]], permissions: permissions || LABEL_PERMISSIONS });
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

// ---------------------------------------------------------------- settings --
// The environments records/github-settings.json on main names, read through
// the App, so the caller never says which to read.
async function mainSettingsRecord(token) {
  const got = await call('GET', API + '/repos/' + REPO + '/contents/records/github-settings.json?ref=main', { Authorization: 'Bearer ' + token });
  if (got.status === 404) return { environments: [] };
  if (got.status !== 200 || !got.body || !got.body.content) throw new Error('GitHub would not give records/github-settings.json on main (' + said(got) + ')');
  let j;
  try { j = JSON.parse(Buffer.from(got.body.content, 'base64').toString('utf8').replace(/^\uFEFF/, '')); }
  catch (e) { throw new Error('records/github-settings.json on main is not JSON'); }
  const envs = Object.keys((j && j.environments) || {}).filter(n => /^[A-Za-z0-9._-]{1,255}$/.test(n)).sort();
  return { environments: envs };
}

// Every name on every page of a list GitHub pages, key being the array's
// name in the answer (secrets, variables, runners).
async function pagedNames(token, pathPart, key, pick) {
  const out = [];
  for (let page = 1; page <= 20; page++) {
    const a = await call('GET', API + '/repos/' + REPO + '/' + pathPart + (pathPart.indexOf('?') >= 0 ? '&' : '?') + 'per_page=100&page=' + page, { Authorization: 'Bearer ' + token });
    if (a.status !== 200 || !a.body || !Array.isArray(a.body[key])) return { ok: false, why: 'GET ' + pathPart + ' answered ' + said(a) };
    for (const x of a.body[key]) out.push(pick ? pick(x) : x.name);
    if (a.body[key].length < 100) break;
  }
  return { ok: true, items: out };
}

// The settings, read and never changed: { ok, readings, unread }. unread
// says, per thing not read, why. held is what the installation holds.
async function readSettings(token, held) {
  const auth = { Authorization: 'Bearer ' + token };
  const readings = {};
  const unread = [];
  const one = async (key, pathPart) => {
    const a = await call('GET', API + '/repos/' + REPO + '/' + pathPart, auth);
    if (a.status === 200) readings[key] = a.body;
    else unread.push(key + ': GET ' + pathPart + ' answered ' + said(a));
  };
  await one('actions', 'actions/permissions');
  if (readings.actions && readings.actions.allowed_actions === 'selected') await one('selected_actions', 'actions/permissions/selected-actions');
  await one('workflow_token', 'actions/permissions/workflow');
  await one('sharing', 'actions/permissions/access');
  await one('retention', 'actions/permissions/artifact-and-log-retention');
  await one('fork_pull_requests', 'actions/permissions/fork-pr-workflows-private-repos');
  const runners = await pagedNames(token, 'actions/runners', 'runners', r => ({ name: r.name, status: r.status, labels: (r.labels || []).map(l => l.name).sort() }));
  if (runners.ok) readings.runners = runners.items; else unread.push('runners: ' + runners.why);

  const has = p => held[p] === 'read' || held[p] === 'write';
  const need = p => 'the App has no ' + p.charAt(0).toUpperCase() + p.slice(1) + ' permission, so GitHub gives it none of these names';
  if (has('secrets')) {
    const r = await pagedNames(token, 'actions/secrets', 'secrets');
    if (r.ok) readings.secrets = r.items.sort(); else unread.push('secrets: ' + r.why);
  } else unread.push('secrets: ' + need('secrets'));
  if (has('variables')) {
    const r = await pagedNames(token, 'actions/variables', 'variables');
    if (r.ok) readings.variables = r.items.sort(); else unread.push('variables: ' + r.why);
  } else unread.push('variables: ' + need('variables'));

  const rec = await mainSettingsRecord(token);
  readings.environments = {};
  for (const env of rec.environments) {
    const e = {};
    const at = 'environments/' + encodeURIComponent(env);
    if (has('environments')) {
      const s = await pagedNames(token, at + '/secrets', 'secrets');
      if (s.ok) e.secrets = s.items.sort(); else unread.push('environment ' + env + ' secrets: ' + s.why);
      const v = await pagedNames(token, at + '/variables', 'variables');
      if (v.ok) e.variables = v.items.sort(); else unread.push('environment ' + env + ' variables: ' + v.why);
    }
    readings.environments[env] = e;
  }
  if (rec.environments.length && !has('environments')) unread.push('environment secrets and variables: ' + need('environments'));
  return { ok: true, readings, unread };
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
    '<p>This makes a private GitHub App on your account that can change the runners\' labels and read the repository, and nothing else. Its key comes straight back to the box and is never shown.</p>' +
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
    '<p>The App is made and its key is on the box. Last step: install it on Thornswood only.</p>' +
    '<p><a href="' + esc(install) + '" style="font-size:1.2em">Install it</a>, choose <b>Only select repositories</b>, pick <b>Thornswood</b>, then Install.</p>');
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
  if (!ask || (ask.what !== 'runner-labels' && ask.what !== 'settings')) { json(res, 400, { ok: false, lines: ['the only things this does are runner-labels and settings'] }); return; }
  const run = claims.run_id + ' (' + claims.event_name + ' by ' + claims.actor + ')';
  const held = readApp();
  if (!held) { log('run ' + run + ': no App yet'); json(res, 503, { ok: false, lines: ['there is no App here yet: Install-AdminService.ps1 -Setup makes it'] }); return; }
  if (ask.what === 'settings') {
    try {
      const inst = await installation(held, now);
      const perms = Object.assign({}, SETTINGS_PERMISSIONS);
      for (const p of SETTINGS_EXTRA) if (inst.permissions[p] === 'read' || inst.permissions[p] === 'write') perms[p] = 'read';
      const token = await installationToken(held, now, perms, inst);
      const r = await readSettings(token, inst.permissions);
      log('run ' + run + ': settings read, ' + r.unread.length + ' not read');
      for (const l of r.unread) log('  not read: ' + l);
      json(res, 200, { ok: true, readings: r.readings, unread: r.unread, lines: r.unread.map(l => 'not read: ' + l) });
    } catch (e) {
      log('run ' + run + ': settings: ' + e.message);
      json(res, 502, { ok: false, lines: [e.message] });
    }
    return;
  }
  try {
    const token = await installationToken(held, now, LABEL_PERMISSIONS);
    const r = await runnerLabels(token, !!ask.check);
    log('run ' + run + ': runner-labels' + (ask.check ? ' check' : '') + ', ' + r.changed + ' changed, ' + (r.ok ? 'ok' : 'stopped'));
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

module.exports = { verifyOidc, appJwt, planLabels, checkRecords, runnerNumber, manifest, RULES, SETTINGS_PERMISSIONS, SETTINGS_EXTRA, serve };
if (require.main === module) serve();
