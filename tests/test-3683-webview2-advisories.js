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
// and asked of osv.dev, which carries GitHub's advisories for NuGet:
//   POST https://api.osv.dev/v1/query
//   {"package":{"name":"Microsoft.Web.WebView2","ecosystem":"NuGet"},"version":"<v>"}
// An answer with no vulns is a pass. Any vuln fails, naming each id and its
// summary; moving off it is taking the fixed package from nuget.org and
// rewriting that section, files, sha256 and version together.
// No answer is a fail, not a skip: a check that did not happen is the failure
// this exists to stop. It needs the network, so it runs in the nightly checks
// and not in the build check on every pull request (tests\gate-excluded.txt).
//
// THORNSWOOD_OSV_JSON, a path to a saved osv.dev answer, stands in for the
// network so the verdict can be checked by hand. The verdict is also driven
// over planted answers, so a reader that finds nothing cannot pass by
// accident. Read only.
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

// What an osv.dev answer says, as { ok, why }.
function verdict(answer) {
  if (!answer || typeof answer !== 'object' || Array.isArray(answer)) { return { ok: false, why: 'no answer from osv.dev' }; }
  const vulns = Array.isArray(answer.vulns) ? answer.vulns : [];
  if (answer.vulns !== undefined && !Array.isArray(answer.vulns)) { return { ok: false, why: 'osv.dev answered in a shape this does not read' }; }
  if (!vulns.length) { return { ok: true, why: 'no advisory is published for it' }; }
  return { ok: false, why: vulns.length + ' advisory(ies): ' +
    vulns.map(function (v) { return String(v.id || '?') + ' ' + String(v.summary || '').split('\n')[0]; }).join('; ') };
}

function ask(version) {
  const body = JSON.stringify({ package: { name: PACKAGE, ecosystem: 'NuGet' }, version: version });
  return new Promise(function (resolve) {
    const req = https.request({
      host: 'api.osv.dev', path: '/v1/query', method: 'POST', timeout: 30000,
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) }
    }, function (res) {
      let text = '';
      res.setEncoding('utf8');
      res.on('data', function (c) { text += c; });
      res.on('end', function () {
        if (res.statusCode !== 200) { console.log('  osv.dev answered HTTP ' + res.statusCode); return resolve(null); }
        try { resolve(JSON.parse(text)); } catch (e) { console.log('  osv.dev answer is not JSON: ' + e.message); resolve(null); }
      });
    });
    req.on('timeout', function () { req.destroy(new Error('no answer in 30 seconds')); });
    req.on('error', function (e) { console.log('  osv.dev: ' + e.message); resolve(null); });
    req.end(body);
  });
}

(async function () {
  // ---- the readers, over planted text --------------------------------------
  yes('the version reader finds a planted section\'s version',
      shippedVersion('## Microsoft WebView2 SDK, inside the launcher\n\nVersion 1.2.3.4, the file version all three carry.\n\n## Next\n') === '1.2.3.4');
  yes('  and not one written under the next section',
      shippedVersion('## Microsoft WebView2 SDK, inside the launcher\n\nNo version here.\n\n## Next\n\nVersion 1.2.3.4, the file version all three carry.\n') === '');
  yes('an empty answer passes', verdict({}).ok === true);
  yes('an answer with an advisory fails and names it',
      verdict({ vulns: [{ id: 'GHSA-xxxx-yyyy-zzzz', summary: 'A hole' }] }).ok === false &&
      verdict({ vulns: [{ id: 'GHSA-xxxx-yyyy-zzzz', summary: 'A hole' }] }).why.indexOf('GHSA-xxxx-yyyy-zzzz A hole') >= 0);
  yes('no answer fails', verdict(null).ok === false);

  // ---- the real version ----------------------------------------------------
  const version = shippedVersion(fs.readFileSync(path.join(REPO, 'THIRD-PARTY.md'), 'utf8').split('\r').join(''));
  yes('THIRD-PARTY.md says which ' + PACKAGE + ' version the launcher ships (' + (version || 'none found') + ')', !!version);
  if (version) {
    let answer = null;
    const saved = process.env.THORNSWOOD_OSV_JSON;
    if (saved) {
      console.log('  reading the answer from ' + saved + ', not the network');
      try { answer = JSON.parse(fs.readFileSync(saved, 'utf8')); } catch (e) { console.log('  ' + e.message); }
    } else {
      answer = await ask(version);
    }
    const v = verdict(answer);
    yes(PACKAGE + ' ' + version + ': ' + v.why, v.ok);
  }

  console.log('');
  console.log(pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
})().catch(function (e) {
  console.log('FAIL  the test itself threw: ' + (e && e.stack || e));
  process.exit(1);
});
