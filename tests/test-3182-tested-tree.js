// #3182: main's build stops green when a pull request build of this
// repository already passed HEAD's tree, and builds in full otherwise.
// Offline: scripts/dev/Tested-Tree.js against stand-in GitHub answers, and
// build.yml's wiring read from the file. Nothing reaches GitHub.
//
// What is held here:
//   1. only a green build-pr.yml run of a pull request from this repository,
//      whose Launcher builds job reached its last step, counts; an expired
//      note, a fork, a push run, a failed job, a job that stopped before the
//      note, another tree, a question GitHub will not answer: main builds.
//   2. build.yml asks first, on push only, on a light runner, with nothing
//      but actions: read; both launcher jobs wait for it and build when it
//      found nothing; the note is the last step of the checks, pull request
//      only, under the names the script looks for.
//   3. why the tree is enough. One commit is checked out on both builds, so
//      a check sees the same files and no history either way. What differs
//      is the event, the ref, the commit's id: no check step and no harness
//      or script reads GitHub's event or ref variables, which is what would
//      make one tree pass on a pull request and fail on main. (A check that
//      reads the commit id or branch name off git was looked for by running
//      every gate harness on a pull request checkout and a main checkout of
//      one tree, #3114; the nightly runs them all on main each night.)
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const REPO = path.join(__dirname, '..');
let pass = 0, fail = 0;
function yes(what, ok) { if (ok) { pass++; console.log('  ok   ' + what); } else { fail++; console.log('  FAIL ' + what); } }
function read(f) { try { return fs.readFileSync(f, 'utf8').split('\r\n').join('\n'); } catch (e) { return ''; } }

const T = require(path.join(REPO, 'scripts', 'dev', 'Tested-Tree.js'));
const REPO_NAME = 'EvilPatrick06/Thornswood';
const TREE = 'a'.repeat(40);
const OTHER = 'b'.repeat(40);

/* A stand-in GitHub: artifacts by name, runs by id, jobs by run id. */
function github(o) {
  const asked = [];
  const get = async p => {
    asked.push(p);
    if (o.down) { throw new Error('GET answered 502'); }
    let m = /^repos\/([^/]+\/[^/]+)\/actions\/artifacts\?name=([^&]+)&per_page=100$/.exec(p);
    if (m) { return { artifacts: (o.artifacts || []).filter(a => a.name === m[2]) }; }
    m = /^repos\/[^/]+\/[^/]+\/actions\/runs\/(\d+)$/.exec(p);
    if (m) { if (!o.runs[m[1]]) { throw new Error('GET answered 404'); } return o.runs[m[1]]; }
    m = /^repos\/[^/]+\/[^/]+\/actions\/runs\/(\d+)\/jobs\?per_page=100$/.exec(p);
    if (m) { return { jobs: o.jobs[m[1]] || [] }; }
    throw new Error('the stand-in was asked ' + p);
  };
  get.asked = asked;
  return get;
}
function art(id, tree, extra) { return Object.assign({ name: T.PREFIX + (tree || TREE), expired: false, workflow_run: { id: id } }, extra || {}); }
function run(id, extra) {
  return Object.assign({ id: id, path: T.WORKFLOW, event: 'pull_request', html_url: 'https://github.com/' + REPO_NAME + '/actions/runs/' + id,
    repository: { full_name: REPO_NAME }, head_repository: { full_name: REPO_NAME }, pull_requests: [{ number: 3190 }] }, extra || {});
}
function jobs(name, conclusion, stepConclusion) {
  const steps = [{ name: 'Run the gate harnesses', conclusion: 'success' }];
  if (stepConclusion !== null) { steps.push({ name: T.STEP, conclusion: stepConclusion || 'success' }); }
  return [{ name: 'Launcher builds', conclusion: 'skipped', steps: [] }, { name: name, conclusion: conclusion, steps: steps }];
}
async function ask(o, tree) { return T.find({ tree: tree || TREE, repo: REPO_NAME, get: github(o) }); }

(async () => {
  // ---- 1. what counts --------------------------------------------------------
  const good = { artifacts: [art(11)], runs: { 11: run(11) }, jobs: { 11: jobs('Launcher builds (VPS fallback)', 'success') } };
  let r = await ask(good);
  yes('a green fallback build of this tree from this repository counts, and names its run: ' + r.why,
      r.run === 'https://github.com/' + REPO_NAME + '/actions/runs/11' && /#3190/.test(r.why));
  r = await ask({ artifacts: [art(12)], runs: { 12: run(12) }, jobs: { 12: [{ name: 'Launcher builds', conclusion: 'success', steps: [{ name: T.STEP, conclusion: 'success' }] }] } });
  yes('so does a green hosted build', r.run.endsWith('/12'));
  r = await ask(good, OTHER);
  yes('another tree does not: ' + r.why, r.run === '' && /no pull request build kept this tree/.test(r.why));
  r = await ask({ artifacts: [art(11, TREE, { expired: true })], runs: good.runs, jobs: good.jobs });
  yes('an expired note does not: ' + r.why, r.run === '' && /expired/.test(r.why));
  r = await ask({ artifacts: [art(13)], runs: { 13: run(13, { head_repository: { full_name: 'someone/Thornswood' } }) }, jobs: { 13: jobs('Launcher builds', 'success') } });
  yes('a fork\'s pull request build does not, whatever tree it names: ' + r.why, r.run === '' && /not this repository/.test(r.why));
  r = await ask({ artifacts: [art(14)], runs: { 14: run(14, { event: 'push', path: '.github/workflows/build.yml' }) }, jobs: { 14: jobs('Launcher builds (VPS fallback)', 'success') } });
  yes('a run of another workflow does not: ' + r.why, r.run === '' && /not \.github\/workflows\/build-pr\.yml/.test(r.why));
  r = await ask({ artifacts: [art(15)], runs: { 15: run(15, { event: 'workflow_dispatch' }) }, jobs: { 15: jobs('Launcher builds (VPS fallback)', 'success') } });
  yes('a build-pr.yml run that is not a pull request does not', r.run === '' && /not a pull request build/.test(r.why));
  r = await ask({ artifacts: [art(16)], runs: { 16: run(16) }, jobs: { 16: jobs('Launcher builds (VPS fallback)', 'failure') } });
  yes('a build whose job failed does not: ' + r.why, r.run === '' && /no Launcher builds job passed/.test(r.why));
  r = await ask({ artifacts: [art(17)], runs: { 17: run(17) }, jobs: { 17: jobs('Launcher builds (VPS fallback)', 'success', null) } });
  yes('a job that never reached the note does not', r.run === '');
  r = await ask({ artifacts: [art(18)], runs: { 18: run(18) }, jobs: { 18: jobs('Launcher builds (VPS fallback)', 'success', 'failure') } });
  yes('a job whose note step failed does not', r.run === '');
  r = await ask({ artifacts: [art(19)], runs: { 19: run(19) }, jobs: { 19: jobs('Some other job', 'success') } });
  yes('a green job of another name does not', r.run === '');
  r = await ask({ artifacts: [art(16), art(11)], runs: { 16: run(16), 11: run(11) }, jobs: { 16: jobs('Launcher builds (VPS fallback)', 'failure'), 11: good.jobs[11] } });
  yes('a failed build of the tree beside a green one: the green one counts', r.run.endsWith('/11'));
  r = await ask({ artifacts: [Object.assign(art(11), { name: T.PREFIX + TREE + 'x' })], runs: good.runs, jobs: good.jobs });
  yes('only the exact name counts', r.run === '');
  r = await T.find({ tree: 'HEAD', repo: REPO_NAME, get: github(good) });
  yes('a tree that is not a tree id is not asked about', r.run === '' && /no tree/.test(r.why));
  const g = github(good);
  r = await T.find({ tree: TREE, repo: '', get: g });
  yes('nor is a missing repository', r.run === '' && g.asked.length === 0);

  // GitHub that will not answer: main builds, and the script still ends 0.
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'tested-tree-'));
  const out = path.join(scratch, 'output');
  const logs = []; const log = console.log; console.log = s => logs.push(String(s));
  try {
    fs.writeFileSync(out, '');
    r = await T.main(['--tree', TREE, '--repo', REPO_NAME], { GITHUB_OUTPUT: out }, github({ down: true }));
    const down = fs.readFileSync(out, 'utf8');
    fs.writeFileSync(out, '');
    const r2 = await T.main(['--tree', TREE, '--repo', REPO_NAME], { GITHUB_OUTPUT: out }, github(good));
    const up = fs.readFileSync(out, 'utf8');
    console.log = log;
    yes('GitHub down: nothing is written, so main builds in full: ' + logs[0], r.run === '' && down === '' && /builds in full/.test(logs[0]));
    yes('a tree that passed writes run=<its address> for the jobs to read', r2.run !== '' && up === 'run=' + r2.run + '\n');
  } finally { console.log = log; fs.rmSync(scratch, { recursive: true, force: true }); }
  const src = read(path.join(REPO, 'scripts', 'dev', 'Tested-Tree.js'));
  yes('run as a command it always ends 0, so it can never fail main', /\.then\(\(\) => process\.exit\(0\), \(\) => process\.exit\(0\)\)/.test(src));

  // ---- 2. build.yml's wiring -------------------------------------------------
  const build = read(path.join(REPO, '.github', 'workflows', 'build.yml'));
  const pr = read(path.join(REPO, '.github', 'workflows', 'build-pr.yml'));
  const job = /\njobs:\n(?:  #.*\n)*  tested:\n([\s\S]*?)\n\n/.exec(build);
  const tj = job ? job[1] : '';
  yes('build.yml\'s first job is "tested"', !!job);
  yes('  on a push only, so a manual run always builds', /\n    if: \$\{\{ github\.event_name == 'push' \}\}\n/.test(tj));
  yes('  on any VPS runner, not a build one', /\n    runs-on: \[self-hosted, Windows, thornswood-vps\]\n/.test(tj));
  yes('  with only actions: read and contents: read', /\n    permissions:\n      actions: read\n      contents: read\n    outputs:/.test(tj));
  yes('  and no secrets', !/secrets\./.test(tj));
  yes('  its output is the script\'s', /\n      run: \$\{\{ steps\.look\.outputs\.run \}\}\n/.test(tj) && /id: look\n/.test(tj) &&
      /node scripts\\dev\\Tested-Tree\.js --tree \$tree --repo \$env:GITHUB_REPOSITORY\n/.test(tj) && /git rev-parse 'HEAD\^\{tree\}'/.test(tj));
  yes('the hosted job waits for it and builds only when it found nothing',
      /\n  launcher:\n    name: Launcher builds\n    needs: tested\n    if: \$\{\{ !cancelled\(\) && needs\.tested\.outputs\.run == '' && /.test(build));
  yes('so does the fallback', /\n  launcher-vps:\n    name: [^\n]*\n    needs: \[tested, launcher\]\n    if: \$\{\{ !cancelled\(\) && needs\.tested\.outputs\.run == '' && /.test(build));
  const checks = (/steps: &checks\n([\s\S]*?)\n\n  # The default:/.exec(build) || ['', ''])[1];
  const steps = checks.split(/\n(?=      - )/).filter(s => /^      - /.test(s));
  const last2 = steps.slice(-2).join('\n');
  yes('the note is the last two steps of the checks', /- name: Write down the tree these checks passed on\n/.test(steps[steps.length - 2] || '') &&
      (steps[steps.length - 1] || '').indexOf('- name: ' + T.STEP + '\n') >= 0);
  yes('  both on a pull request only', (last2.match(/\n        if: github\.event_name == 'pull_request'\n/g) || []).length === 2);
  yes('  under the name the script looks for', last2.indexOf('name: ' + T.PREFIX + '${{ steps.tree.outputs.tree }}') >= 0);
  yes('  writing the tree git gives for HEAD', /git rev-parse 'HEAD\^\{tree\}'/.test(last2));
  yes('  kept seven days, replaced on a rerun', /retention-days: 7\n/.test(last2) && /overwrite: true/.test(last2));
  yes('the pull request build has the same note steps', pr.indexOf(last2) >= 0);
  for (const n of T.JOBS) { yes('the script\'s job name "' + n + '" is a job in build-pr.yml', pr.indexOf('\n    name: ' + n + '\n') >= 0); }
  yes('the script\'s workflow is the pull request build', fs.existsSync(path.join(REPO, T.WORKFLOW)) && /\non:\n  pull_request:\n/.test(pr));

  // ---- 3. why the tree is enough ---------------------------------------------
  const checkout = steps[0] || '';
  yes('the checks check out one commit, with no history on either build', /^      - uses: actions\/checkout@[0-9a-f]{40} # v\d+\n/.test(checkout + '\n') && !/^\s+with:/m.test(checkout));
  const before = steps.slice(0, -2).join('\n').replace(/^\s*#.*$/gm, '');
  const EVENT = /github\.(event|ref|ref_name|sha|head_ref|base_ref|run_id|run_number|actor)\b|GITHUB_(EVENT_NAME|EVENT_PATH|REF|REF_NAME|REF_TYPE|SHA|HEAD_REF|BASE_REF|RUN_ID|RUN_NUMBER|ACTOR)\b/;
  yes('no check step reads the event, the ref or the commit', !EVENT.test(before));
  yes('no check step fetches more history', !/git(\.exe)?\s+fetch|fetch-depth/.test(before));
  // Every harness and every script: GitHub's event and ref variables are read
  // only where named here, each with why it is not a check of a build.
  const ALLOWED = {
    'scripts/release/Resolve-ReleaseTag.ps1': 'release.yml\'s tag step, which no check runs: tests/test-release-tag.ps1 gives it the values itself',
    'tests/test-release-tag.ps1': 'reads release.yml\'s text for those names; sets them for Resolve-ReleaseTag.ps1 in a scratch process'
  };
  const ENVREAD = /\b(GITHUB_(EVENT_NAME|EVENT_PATH|REF|REF_NAME|REF_TYPE|SHA|HEAD_REF|BASE_REF|RUN_ID|RUN_NUMBER|ACTOR))\b/;
  const found = [];
  const walk = d => {
    for (const e of fs.readdirSync(path.join(REPO, d), { withFileTypes: true })) {
      const rel = d + '/' + e.name;
      if (e.isDirectory()) { if (e.name !== 'node_modules') { walk(rel); } continue; }
      if (!/\.(js|ps1|psm1|py|sh|cmd|bat)$/.test(e.name) || rel === 'tests/test-3182-tested-tree.js') { continue; }
      if (ENVREAD.test(read(path.join(REPO, rel)))) { found.push(rel); }
    }
  };
  walk('tests'); walk('scripts');
  const loose = found.filter(f => !ALLOWED[f]);
  yes('no harness or script reads the event or ref but those named here (' + (loose.join(', ') || 'none') + ')', loose.length === 0);
  for (const f of Object.keys(ALLOWED)) { yes('  ' + f + ' is still one (' + ALLOWED[f] + ')', found.indexOf(f) >= 0); }

  console.log(pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
})().catch(e => { console.log('  FAIL ' + (e && e.stack || e)); process.exit(1); });
