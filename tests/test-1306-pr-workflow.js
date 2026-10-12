// #1306: pull requests build on GitHub's hosted runner, in their own workflow
// file, and never on the VPS; build.yml keeps main and manual runs on the VPS.
// build-pr.yml is generated from build.yml and must match it.
'use strict';
const fs = require('fs');
const path = require('path');
const REPO = path.join(__dirname, '..');
const WF = path.join(REPO, '.github', 'workflows');
let pass = 0, fail = 0;
function yes(what, ok) { if (ok) { pass++; console.log('  ok   ' + what); } else { fail++; console.log('  FAIL ' + what); } }
function read(f) { try { return fs.readFileSync(f, 'utf8').split('\r\n').join('\n'); } catch (e) { return ''; } }
function code(t) { return t.replace(/^\s*#.*$/gm, ''); }
function triggers(t) {
  const m = /\non:\n((?:  .*\n)+)/.exec(t);
  return m ? m[1].split('\n').filter(l => /^  [a-z_]+:/.test(l)).map(l => l.trim().replace(':', '')) : [];
}
const build = read(path.join(WF, 'build.yml'));
const pr = read(path.join(WF, 'build-pr.yml'));

yes('build.yml no longer runs on a pull request', build && triggers(build).indexOf('pull_request') < 0);
yes('build.yml still runs a push to main and a manual run', /push:\n    branches: \[main\]/.test(build) && triggers(build).indexOf('workflow_dispatch') >= 0);
yes('and those stay on the VPS runner', /runs-on: \[self-hosted, Windows, thornswood-vps\]/.test(build));
yes('build-pr.yml exists', !!pr);
yes('build-pr.yml runs on a pull request and nothing else', JSON.stringify(triggers(pr)) === '["pull_request"]');
yes('on GitHub\'s hosted windows-latest', /\n    runs-on: windows-latest\n/.test(pr));
yes('and the VPS label is nowhere in its jobs', !!pr && !/thornswood-vps|self-hosted/.test(code(pr)));
yes('it takes no secrets', !!pr && !/\$\{\{\s*secrets\./.test(pr));
yes('its check keeps the name Launcher builds', /\n    name: Launcher builds\n/.test(pr));
// No other workflow runs a pull request on the VPS either.
const others = fs.readdirSync(WF).filter(f => /\.ya?ml$/.test(f)).filter(f => {
  const t = read(path.join(WF, f));
  const tr = triggers(t);
  return (tr.indexOf('pull_request') >= 0 || tr.indexOf('pull_request_target') >= 0) && /thornswood-vps/.test(code(t));
});
yes('no workflow runs a pull request on the VPS (' + (others.join(', ') || 'none') + ')', others.length === 0);
let gen = null;
try { gen = require(path.join(REPO, 'scripts', 'dev', 'Build-PrWorkflow.js')); } catch (e) { gen = null; }
yes('the generator is there', !!gen);
let want = '';
try { want = gen ? gen.build(build) : ''; } catch (e) { console.log('  ' + e.message); }
yes('build-pr.yml is exactly what build.yml generates (run node scripts/dev/Build-PrWorkflow.js)', !!want && want === pr);
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
