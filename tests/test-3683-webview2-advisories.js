// test-3683-webview2-advisories.js
//
//     node tests\test-3683-webview2-advisories.js
//
// The launcher's WebView2 files have no published security advisory (#3683).
// The three files in launcher\lib\webview2 are copied in from Microsoft's
// NuGet package Microsoft.Web.WebView2 rather than restored by a package
// manager, by design (#498), so Dependabot has no manifest to read and never
// sees them. Patrick, 26 Oct 2026 (report page, q-3683-webview2-watch, A): a
// nightly check asks for advisories on the version we ship, and a red night
// opens the board issue by itself. Red only when there is a real hole, not on
// every new Microsoft release.
//
// The version is read from THIRD-PARTY.md's WebView2 section, the one place
// it is written ("Version 1.0.2903.40, the file version all three carry"),
// and asked of GitHub's advisory database, where NuGet's advisories are kept:
//   GET https://api.github.com/advisories?ecosystem=nuget&affects=Microsoft.Web.WebView2@<v>
// The nightly runs on the box, whose runner account reaches GitHub and
// nothing else on the internet (Install-Runner.ps1's Set-RunnerFirewall), so
// GitHub is the one it can ask (#4092). It asks with no token: GitHub answers
// this path to anybody, sixty an hour from one address, and the harness step
// is given no token on purpose, since every harness in the share would hold
// it.
//
// Only when GitHub gives no answer does it ask osv.dev, which carries the
// same GitHub advisories for NuGet:
//   POST https://api.osv.dev/v1/query
//   {"package":{"name":"Microsoft.Web.WebView2","ecosystem":"NuGet"},"version":"<v>"}
// That is the path from a cloud session, whose proxy refuses
// api.github.com/advisories. Either answer with no advisory is a pass. Any
// advisory fails, naming each id and its summary; moving off it is taking
// the fixed package from nuget.org and rewriting that section, files, sha256
// and version together. One withdrawn by GitHub is not a hole.
// No answer from either is a fail, not a skip: a check that did not happen is
// the failure this exists to stop. It needs the network, so it runs in the
// nightly checks and not in the build check on every pull request
// (tests\gate-excluded.txt).
//
// THORNSWOOD_GHSA_JSON and THORNSWOOD_OSV_JSON, each a path to a saved
// answer, stand in for the network so the verdict can be checked by hand.
// The verdict is also driven over planted answers, so a reader that finds
// nothing cannot pass by accident. Read only.
'use strict';
const fs = require('fs');
const https = require('https');
const path = require('path');

const REPO = path.resolve(__dirname, '..');
const PACKAGE = 'Microsoft.Web.WebView2';

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

// The version THIRD-PARTY.md says the three files are, or '' when the section
// or its version line is not there.
function shippedVersion(text) {
  const at = text.indexOf('## Microsoft WebView2 SDK, inside the launcher');
  if (at < 0) { return ''; }
  const rest = text.slice(at + 3);
  const next = rest.indexOf('\n## ');
  const section = next < 0 ? rest : rest.slice(0, next);
  const m = /Version (\d+\.\d+\.\d+\.\d+), the file version all three carry/.exec(section);
  return m ? m[1] : '';
}

// The advisories in an answer, as [{ id, summary }], or a string saying why
// the answer cannot be read. GitHub answers with a list of advisories,
// osv.dev with an object whose vulns (absent when there is none) are.
function fromGitHub(answer) {
  if (!Array.isArray(answer)) { return 'GitHub answered in a shape this does not read'; }
  return answer.filter(function (a) { return a && !a.withdrawn_at; })
    .map(function (a) { return { id: a.ghsa_id || a.cve_id || '?', summary: a.summary }; });
}
function fromOsv(answer) {
  if (!answer || typeof answer !== 'object' || Array.isArray(answer) ||
      (answer.vulns !== undefined && !Array.isArray(answer.vulns))) { return 'osv.dev answered in a shape this does not read'; }
  return (answer.vulns || []).map(function (v) { return { id: v.id || '?', summary: v.summary }; });
}

// What the advisories say, as { ok, why }.
function verdict(found) {
  if (typeof found === 'string') { return { ok: false, why: found }; }
  if (!Array.isArray(found)) { return { ok: false, why: 'no answer from GitHub\'s advisory database or from osv.dev' }; }
  if (!found.length) { return { ok: true, why: 'no advisory is published for it' }; }
  return { ok: false, why: found.length + ' advisory(ies): ' +
    found.map(function (v) { return String(v.id) + ' ' + String(v.summary || '').split('\n')[0]; }).join('; ') };
}

// One HTTPS request, answering the parsed JSON, or null with a line saying why.
function request(who, options, body) {
  return new Promise(function (resolve) {
    const req = https.request(Object.assign({ timeout: 30000 }, options), function (res) {
      let text = '';
      res.setEncoding('utf8');
      res.on('data', function (c) { text += c; });
      res.on('end', function () {
        if (res.statusCode !== 200) { console.log('  ' + who + ' answered HTTP ' + res.statusCode + ': ' + text.slice(0, 200).replace(/\s+/g, ' ')); return resolve(null); }
        try { resolve(JSON.parse(text)); } catch (e) { console.log('  ' + who + '\'s answer is not JSON: ' + e.message); resolve(null); }
      });
    });
    req.on('timeout', function () { req.destroy(new Error('no answer in 30 seconds')); });
    req.on('error', function (e) { console.log('  ' + who + ': ' + e.message); resolve(null); });
    req.end(body);
  });
}

function askGitHub(version) {
  return request('GitHub', {
    host: 'api.github.com', method: 'GET',
    headers: { 'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'thornswood-webview2-advisories' },
    path: '/advisories?ecosystem=nuget&per_page=100&affects=' + encodeURIComponent(PACKAGE + '@' + version)
  });
}

function askOsv(version) {
  const body = JSON.stringify({ package: { name: PACKAGE, ecosystem: 'NuGet' }, version: version });
  return request('osv.dev', {
    host: 'api.osv.dev', path: '/v1/query', method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) }
  }, body);
}

function saved(name) {
  const file = process.env[name];
  if (!file) { return undefined; }
  console.log('  reading the answer from ' + file + ' (' + name + '), not the network');
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch (e) { console.log('  ' + e.message); return null; }
}

(async function () {
  // ---- the readers, over planted text --------------------------------------
  yes('the version reader finds a planted section\'s version',
      shippedVersion('## Microsoft WebView2 SDK, inside the launcher\n\nVersion 1.2.3.4, the file version all three carry.\n\n## Next\n') === '1.2.3.4');
  yes('  and not one written under the next section',
      shippedVersion('## Microsoft WebView2 SDK, inside the launcher\n\nNo version here.\n\n## Next\n\nVersion 1.2.3.4, the file version all three carry.\n') === '');
  yes('GitHub answering an empty list passes', verdict(fromGitHub([])).ok === true);
  const gh = verdict(fromGitHub([{ ghsa_id: 'GHSA-xxxx-yyyy-zzzz', summary: 'A hole\nmore', withdrawn_at: null }]));
  yes('  an advisory from GitHub fails and names it', gh.ok === false && gh.why.indexOf('GHSA-xxxx-yyyy-zzzz A hole') >= 0 && gh.why.indexOf('more') < 0);
  yes('  one GitHub withdrew does not', verdict(fromGitHub([{ ghsa_id: 'GHSA-aaaa-bbbb-cccc', summary: 'Not a hole', withdrawn_at: '2026-01-01T00:00:00Z' }])).ok === true);
  yes('  and an answer that is not a list fails', verdict(fromGitHub({ message: 'Not Found' })).ok === false);
  yes('osv.dev answering nothing passes', verdict(fromOsv({})).ok === true);
  const osv = verdict(fromOsv({ vulns: [{ id: 'GHSA-xxxx-yyyy-zzzz', summary: 'A hole' }] }));
  yes('  an advisory from osv.dev fails and names it', osv.ok === false && osv.why.indexOf('GHSA-xxxx-yyyy-zzzz A hole') >= 0);
  yes('  and an answer in another shape fails', verdict(fromOsv({ vulns: 'x' })).ok === false && verdict(fromOsv([])).ok === false);
  yes('no answer from either fails', verdict(null).ok === false);

  // ---- the real version ----------------------------------------------------
  const version = shippedVersion(fs.readFileSync(path.join(REPO, 'THIRD-PARTY.md'), 'utf8').split('\r').join(''));
  yes('THIRD-PARTY.md says which ' + PACKAGE + ' version the launcher ships (' + (version || 'none found') + ')', !!version);
  if (version) {
    let found = null;
    let answer = saved('THORNSWOOD_GHSA_JSON');
    if (answer === undefined && !process.env.THORNSWOOD_OSV_JSON) { answer = await askGitHub(version); }
    if (answer) {
      console.log('  GitHub\'s advisory database answered');
      found = fromGitHub(answer);
    } else {
      console.log('  no answer from GitHub, so osv.dev is asked');
      answer = saved('THORNSWOOD_OSV_JSON');
      if (answer === undefined) { answer = await askOsv(version); }
      if (answer) { console.log('  osv.dev answered'); found = fromOsv(answer); }
    }
    const v = verdict(found);
    yes(PACKAGE + ' ' + version + ': ' + v.why, v.ok);
  }

  console.log('');
  console.log(pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
})().catch(function (e) {
  console.log('FAIL  the test itself threw: ' + (e && e.stack || e));
  process.exit(1);
});
