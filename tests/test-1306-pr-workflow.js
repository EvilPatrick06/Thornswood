// #1306: pull requests build on GitHub's hosted runner, in their own workflow
// file. The VPS is the fallback for them too (Patrick, 12 Oct 2026), for a
// branch of this repository only, never a fork.
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
yes('main builds default to GitHub\'s hosted runner', /\n  launcher:\n    name: Launcher builds\n    if: \$\{\{ vars\.BUILD_RUNNER != 'vps' && inputs\.runner != 'vps' \}\}\n    runs-on: windows-latest\n/.test(build));
yes('the VPS is a fallback job, on the box\'s build runners (#2994)', /\n  launcher-vps:\n[\s\S]*?\n    runs-on: \[self-hosted, Windows, thornswood-vps, thornswood-build\]\n/.test(build));
yes('  run only when the hosted job did not succeed (skipped by BUILD_RUNNER or a manual vps run, or failed)',
    /\n  launcher-vps:\n    name: [^\n]*\n    needs: launcher\n    if: \$\{\{ !cancelled\(\) && needs\.launcher\.result != 'success' && needs\.launcher\.result != 'cancelled' \}\}\n/.test(build));
yes('  with the same steps as the hosted job (one anchor)', /steps: &checks\n/.test(build) && /steps: \*checks\n/.test(build));
yes('a manual run can pick the box', /runner:\n[\s\S]*?options: \[hosted, vps\]/.test(build));
yes('build-pr.yml exists', !!pr);
yes('build-pr.yml runs on a pull request and nothing else', JSON.stringify(triggers(pr)) === '["pull_request"]');
yes('on GitHub\'s hosted windows-latest', /\n    runs-on: windows-latest\n/.test(pr));
const SAME = "github.event.pull_request.head.repo.full_name == github.repository";
const prVps = /\n  launcher-vps:\n[\s\S]*?\n    runs-on: \[self-hosted, Windows, thornswood-vps, thornswood-build\]\n/.exec(pr);
yes('a VPS fallback job builds a pull request the hosted job did not', !!prVps &&
    /\n  launcher-vps:\n    name: Launcher builds \(VPS fallback\)\n    needs: launcher\n    if: \$\{\{ !cancelled\(\) && needs\.launcher\.result != 'success' && needs\.launcher\.result != 'cancelled' && github\.event\.pull_request\.head\.repo\.full_name == github\.repository \}\}\n/.test(pr));
yes('  only for a branch of this repository, never a fork', !!prVps && code(pr).split(SAME).length - 1 === 1);
yes('  and that job is the only one on the VPS', code(pr).split('runs-on: [self-hosted').length - 1 === 1);
yes('  so the hosted job keeps its own check, and its red stays visible', /\n  launcher:\n    name: Launcher builds\n/.test(pr));
yes('it takes no secrets', !!pr && !/\$\{\{\s*secrets\./.test(pr));
yes('its check keeps the name Launcher builds', /\n    name: Launcher builds\n/.test(pr));
// No other workflow runs a pull request on the VPS, and none without the
// same-repository condition.
const others = fs.readdirSync(WF).filter(f => /\.ya?ml$/.test(f)).filter(f => {
  const t = read(path.join(WF, f));
  const tr = triggers(t);
  if (tr.indexOf('pull_request_target') >= 0) { return true; }
  if (tr.indexOf('pull_request') < 0 || !/thornswood-vps/.test(code(t))) { return false; }
  return f !== 'build-pr.yml' || code(t).indexOf(SAME) < 0;
});
yes('no other workflow runs a pull request on the VPS (' + (others.join(', ') || 'none') + ')', others.length === 0);
let gen = null;
try { gen = require(path.join(REPO, 'scripts', 'dev', 'Build-PrWorkflow.js')); } catch (e) { gen = null; }
yes('the generator is there', !!gen);
let want = '';
try { want = gen ? gen.build(build) : ''; } catch (e) { console.log('  ' + e.message); }
yes('build-pr.yml is exactly what build.yml generates (run node scripts/dev/Build-PrWorkflow.js)', !!want && want === pr);
// #1306, 12 Oct: always() ignores a cancelled run, so a new push could not
// cancel an older run whose fallback waited for a runner. The older run held
// the concurrency group and the new run sat pending behind it. !cancelled()
// lets cancel-in-progress take the waiting fallback down with its run.
yes('main\'s fallback does not use always(), so a newer run cancels it', code(build).indexOf('always()') < 0);
yes('the pull request fallback does not use always() either', code(pr).indexOf('always()') < 0);
yes('both workflows still cancel the older run on the same ref', /\n  cancel-in-progress: true\n/.test(build) && /\n  cancel-in-progress: true\n/.test(pr));
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
