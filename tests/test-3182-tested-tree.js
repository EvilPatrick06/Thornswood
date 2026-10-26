// #3182: main's build stops green when a pull request build of this
// repository already passed HEAD's tree, and builds in full otherwise.
// Offline: scripts/dev/Tested-Tree.js against stand-in GitHub answers, and
// build.yml's wiring read from the file. Nothing reaches GitHub.
//
// What is held here:
//   1. only the TESTED-TREE line of this tree, in the log of a green
//      build-pr.yml run's Launcher builds job that reached its last step,
//      for the head of a pull request of this repository merged as HEAD,
//      counts; another tree in the line, a log with no line, a fork, a push
//      run, a failed job, a job that stopped before the note, a pull request
//      not merged or from a fork, a question GitHub will not answer: main
//      builds. Since #3399 the note is a line of the log, not an artifact,
//      so this asks no artifact anything.
//   2. build.yml asks first, on push only, on a light runner, with nothing
//      but actions, contents and pull-requests read; both launcher jobs wait
//      for it and build when it found nothing; the note is the last step of
//      the checks, pull request only, under the name the script looks for,
//      and no step of either build uploads an artifact.
//   3. why the tree is enough. One commit is checked out on both builds, so
//      a check sees the same files and no history either way. What differs
//      is the event, the ref, the commit's id: no check step and no harness
//      or script reads GitHub's event or ref variables, which is what would
//      make one tree pass on a pull request and fail on main. The lint
//      (#3185) does, and only reports: it cannot fail a build. (A check that
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

const COMMIT = 'c'.repeat(40);
const HEAD = 'd'.repeat(40);

/* A stand-in GitHub: the pull requests of COMMIT, the runs of each head,
   jobs by run id and logs by job id. */
function github(o) {
  const asked = [];
  const get = async p => {
    asked.push(p);
    if (o.down) { throw new Error('GET answered 502'); }
    let m = /^repos\/[^/]+\/[^/]+\/commits\/([0-9a-f]{40})\/pulls\?per_page=100$/.exec(p);
    if (m) { return m[1] === COMMIT ? (o.pulls || []) : []; }
    m = /^repos\/[^/]+\/[^/]+\/actions\/workflows\/build-pr\.yml\/runs\?event=pull_request&head_sha=([0-9a-f]{40})&per_page=100$/.exec(p);
    if (m) { return { workflow_runs: (o.runs || []).filter(r => r.head_sha === m[1]) }; }
    m = /^repos\/[^/]+\/[^/]+\/actions\/runs\/(\d+)\/jobs\?per_page=100$/.exec(p);
    if (m) { return { jobs: (o.jobs || {})[m[1]] || [] }; }
    m = /^repos\/[^/]+\/[^/]+\/actions\/jobs\/(\d+)\/logs$/.exec(p);
    if (m) { if (!(o.logs || {})[m[1]]) { throw new Error('GET answered 404'); } return o.logs[m[1]]; }
    throw new Error('the stand-in was asked ' + p);
  };
  get.asked = asked;
  return get;
}
function pull(extra) { return Object.assign({ number: 3190, merged_at: '2026-10-26T17:00:00Z', head: { sha: HEAD, repo: { full_name: REPO_NAME } } }, extra || {}); }
function run(id, extra) {
  return Object.assign({ id: id, path: T.WORKFLOW, event: 'pull_request', head_sha: HEAD, html_url: 'https://github.com/' + REPO_NAME + '/actions/runs/' + id,
    repository: { full_name: REPO_NAME }, head_repository: { full_name: REPO_NAME } }, extra || {});
}
// The jobs of run <id>: the hosted one skipped, and <name> with job id
// <id>0, its last step the note unless stepConclusion is null.
function jobs(id, name, conclusion, stepConclusion) {
  const steps = [{ name: 'Run the gate harnesses', conclusion: 'success' }];
  if (stepConclusion !== null) { steps.push({ name: T.STEP, conclusion: stepConclusion || 'success' }); }
  return [{ id: 1, name: 'Launcher builds', conclusion: 'skipped', steps: [] }, { id: id * 10, name: name, conclusion: conclusion, steps: steps }];
}
// A job's log as GitHub hands it over: timestamps, the step's echo of its
// own script (which must not count), and the line itself.
function jobLog(tree) {
  return ['2026-10-26T16:59:01.0000000Z ##[group]Run $tree = (git rev-parse \'HEAD^{tree}\' | Out-String).Trim()',
          '2026-10-26T16:59:01.0000001Z \u001b[36;1mWrite-Host (\'' + T.MARK + ' {0} commit {1}\' -f $tree)\u001b[0m',
          '2026-10-26T16:59:02.1234567Z ' + T.MARK + ' ' + tree + ' commit ' + 'e'.repeat(40) + ' pull request 3190 head ' + HEAD,
          '2026-10-26T16:59:02.2000000Z ##[endgroup]'].join('\r\n');
}
function world(id, name, extra) {
  return Object.assign({ pulls: [pull()], runs: [run(id)], jobs: { [id]: jobs(id, name || 'Launcher builds (VPS fallback)', 'success') }, logs: { [id * 10]: jobLog(TREE) } }, extra || {});
}
async function ask(o, tree) { const g = github(o); return T.find({ tree: tree || TREE, commit: COMMIT, repo: REPO_NAME, get: g, getText: g }); }

(async () => {
  // ---- 1. what counts --------------------------------------------------------
  const good = world(11);
  let r = await ask(good);
  yes('a green fallback build of this tree, for the head of the pull request merged as HEAD, counts, and names its run: ' + r.why,
      r.run === 'https://github.com/' + REPO_NAME + '/actions/runs/11' && /#3190/.test(r.why));
  r = await ask(world(12, 'Launcher builds'));
  yes('so does a green hosted build', r.run.endsWith('/12'));
  r = await ask(good, OTHER);
  yes('another tree does not: ' + r.why, r.run === '' && /another tree/.test(r.why));
  r = await ask(world(11, null, { logs: { 110: '2026-10-26T16:59:02Z the gate passed\n' } }));
  yes('a log with no note line does not: ' + r.why, r.run === '' && /no TESTED-TREE line/.test(r.why));
  r = await ask(world(11, null, { logs: { 110: jobLog(TREE).replace(/\r\n2026-10-26T16:59:02\.1234567Z [^\r]*/, '') } }));
  yes('the step\'s echo of its own script is not the line', r.run === '');
  r = await ask(world(13, null, { runs: [run(13, { head_repository: { full_name: 'someone/Thornswood' } })] }));
  yes('a fork\'s pull request build does not, whatever tree it names: ' + r.why, r.run === '' && /not this repository/.test(r.why));
  r = await ask(world(13, null, { pulls: [pull({ head: { sha: HEAD, repo: { full_name: 'someone/Thornswood' } } })] }));
  yes('nor does a pull request whose head is a fork: ' + r.why, r.run === '' && /no pull request of this repository was merged/.test(r.why));
  r = await ask(world(13, null, { pulls: [pull({ merged_at: null })] }));
  yes('nor one that was never merged', r.run === '');
  r = await ask(world(13, null, { pulls: [] }));
  yes('a commit no pull request was merged as builds in full: ' + r.why, r.run === '' && /no pull request/.test(r.why));
  r = await ask(world(14, null, { runs: [run(14, { event: 'push', path: '.github/workflows/build.yml' })] }));
  yes('a run of another workflow does not: ' + r.why, r.run === '' && /not \.github\/workflows\/build-pr\.yml/.test(r.why));
  r = await ask(world(15, null, { runs: [run(15, { event: 'workflow_dispatch' })] }));
  yes('a build-pr.yml run that is not a pull request does not', r.run === '' && /not a pull request build/.test(r.why));
  r = await ask(world(15, null, { runs: [run(15, { head_sha: 'f'.repeat(40) })] }));
  yes('a run of another head does not, whatever the query gave: ' + r.why, r.run === '' && /no pull request build of its head/.test(r.why));
  r = await ask(world(16, null, { jobs: { 16: jobs(16, 'Launcher builds (VPS fallback)', 'failure') } }));
  yes('a build whose job failed does not: ' + r.why, r.run === '' && /no Launcher builds job passed/.test(r.why));
  r = await ask(world(17, null, { jobs: { 17: jobs(17, 'Launcher builds (VPS fallback)', 'success', null) } }));
  yes('a job that never reached the note does not', r.run === '');
  r = await ask(world(18, null, { jobs: { 18: jobs(18, 'Launcher builds (VPS fallback)', 'success', 'failure') } }));
  yes('a job whose note step failed does not', r.run === '');
  r = await ask(world(19, 'Some other job'));
  yes('a green job of another name does not', r.run === '');
  r = await ask({ pulls: [pull()], runs: [run(16), run(11)], jobs: { 16: jobs(16, 'Launcher builds (VPS fallback)', 'failure'), 11: good.jobs[11] }, logs: good.logs });
  yes('a failed build of the head beside a green one: the green one counts', r.run.endsWith('/11'));
  r = await ask({ pulls: [pull()], runs: [run(11), run(20)], jobs: { 11: good.jobs[11], 20: jobs(20, 'Launcher builds (VPS fallback)', 'success') }, logs: { 110: jobLog(TREE), 200: jobLog(OTHER) } });
  yes('the newest run is read first, and an older one of this tree still counts: ' + r.why, r.run.endsWith('/11') && /#3190/.test(r.why));
  r = await ask(world(11, null, { logs: { 110: jobLog(TREE).replace(T.MARK + ' ' + TREE, T.MARK + ' ' + TREE + 'x') } }));
  yes('only a whole tree id counts', r.run === '');
  r = await T.find({ tree: 'HEAD', commit: COMMIT, repo: REPO_NAME, get: github(good), getText: github(good) });
  yes('a tree that is not a tree id is not asked about', r.run === '' && /no tree/.test(r.why));
  r = await T.find({ tree: TREE, commit: '', repo: REPO_NAME, get: github(good), getText: github(good) });
  yes('nor is a missing commit', r.run === '' && /no commit/.test(r.why));
  const g = github(good);
  r = await T.find({ tree: TREE, commit: COMMIT, repo: '', get: g, getText: g });
  yes('nor is a missing repository', r.run === '' && g.asked.length === 0);
  const g2 = github(good);
  await T.find({ tree: TREE, commit: COMMIT, repo: REPO_NAME, get: g2, getText: g2 });
  yes('no artifact is asked about any more (#3399)', g2.asked.every(p => !/artifacts/.test(p)));

  // GitHub that will not answer: main builds, and the script still ends 0.
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'tested-tree-'));
  const out = path.join(scratch, 'output');
  const logs = []; const log = console.log; console.log = s => logs.push(String(s));
  try {
    fs.writeFileSync(out, '');
    r = await T.main(['--tree', TREE, '--commit', COMMIT, '--repo', REPO_NAME], { GITHUB_OUTPUT: out }, github({ down: true }));
    const down = fs.readFileSync(out, 'utf8');
    fs.writeFileSync(out, '');
    const r2 = await T.main(['--tree', TREE, '--commit', COMMIT, '--repo', REPO_NAME], { GITHUB_OUTPUT: out }, github(good));
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
  yes('  with only actions, contents and pull-requests read', /\n    permissions:\n      actions: read\n      contents: read\n      pull-requests: read\n    outputs:/.test(tj));
  yes('  and no secrets', !/secrets\./.test(tj));
  yes('  its output is the script\'s', /\n      run: \$\{\{ steps\.look\.outputs\.run \}\}\n/.test(tj) && /id: look\n/.test(tj) &&
      /node scripts\\dev\\Tested-Tree\.js --tree \$tree --commit \$env:GITHUB_SHA --repo \$env:GITHUB_REPOSITORY\n/.test(tj) && /git rev-parse 'HEAD\^\{tree\}'/.test(tj));
  yes('the hosted job waits for it and builds only when it found nothing',
      /\n  launcher:\n    name: Launcher builds\n    needs: tested\n    if: \$\{\{ !cancelled\(\) && needs\.tested\.outputs\.run == '' && /.test(build));
  yes('so does the fallback', /\n  launcher-vps:\n    name: [^\n]*\n    needs: \[tested, launcher\]\n    if: \$\{\{ !cancelled\(\) && needs\.tested\.outputs\.run == '' && /.test(build));
  const checks = (/steps: &checks\n([\s\S]*?)\n\n  # The default:/.exec(build) || ['', ''])[1];
  const steps = checks.split(/\n(?=      - )/).filter(s => /^      - /.test(s));
  const note = steps[steps.length - 1] || '';
  yes('the note is the last step of the checks, under the name the script looks for', note.indexOf('- name: ' + T.STEP + '\n') === 6);
  yes('  on a pull request only, and only when its gate step ran the whole gate (#3114)',
      /\n        if: github\.event_name == 'pull_request' && steps\.gate\.outputs\.whole == 'true'\n/.test(note));
  // #3114: a pull request built on the VPS may run only the gate harnesses
  // its change can reach. Its tree is then not tested in full, so it keeps
  // no note and main builds it in full (and is traced). Run-Gate.ps1 says
  // whole=true only when it ran every gate harness.
  const gateStep = steps.find(x => /^      - name: Run the gate harnesses\n/.test(x)) || '';
  const rg = read(path.join(REPO, 'scripts', 'dev', 'Run-Gate.ps1'));
  yes('the gate step is "gate", and runs Run-Gate.ps1', /\n        id: gate\n/.test(gateStep) && /\.\\scripts\\dev\\Run-Gate\.ps1 /.test(gateStep));
  yes('  which says whole=true only when it ran every gate harness',
      (rg.match(/Set-StepOutput 'whole'/g) || []).length === 1 && /\nif \(\$whole\) \{ Set-StepOutput 'whole' 'true' \}\n/.test(rg) &&
      /\n\$run = \$gate\n\$whole = \$true\n/.test(rg) && (rg.match(/\$whole = \$false/g) || []).length === 1 &&
      /\{ \$run = \$picked; \$whole = \$false \}/.test(rg) && /if \(\$picked\.Count -ge \$gate\.Count\) \{ return \$null \}/.test(rg));
  yes('  writing the tree git gives for HEAD, in the line the script reads', /git rev-parse 'HEAD\^\{tree\}'/.test(note) &&
      note.indexOf("Write-Host ('" + T.MARK + " {0} commit {1} pull request {2} head {3}' -f $tree, $env:GITHUB_SHA, $env:PR_NUMBER, $env:PR_HEAD)") >= 0);
  yes('  the pull request number and head through env, never pasted into the script', /\n          PR_NUMBER: \$\{\{ github\.event\.pull_request\.number \}\}\n          PR_HEAD: \$\{\{ github\.event\.pull_request\.head\.sha \}\}\n/.test(note) &&
      !/\$\{\{/.test(note.split('        run: |')[1] || ''));
  yes('the pull request build has the same note step', pr.indexOf(note) >= 0);
  yes('no step of either build uploads an artifact (#3399)', !/actions\/upload-artifact@/.test(build.replace(/^\s*#.*$/gm, '')) && !/actions\/upload-artifact@/.test(pr.replace(/^\s*#.*$/gm, '')));
  for (const n of T.JOBS) { yes('the script\'s job name "' + n + '" is a job in build-pr.yml', pr.indexOf('\n    name: ' + n + '\n') >= 0); }
  yes('the script\'s workflow is the pull request build', fs.existsSync(path.join(REPO, T.WORKFLOW)) && /\non:\n  pull_request:\n/.test(pr));

  // ---- 3. why the tree is enough ---------------------------------------------
  const checkout = steps[0] || '';
  yes('the checks check out one commit, with no history on either build', /^      - uses: actions\/checkout@[0-9a-f]{40} # v\d+\n/.test(checkout + '\n') && !/^\s+with:/m.test(checkout));
  // The lint step is the one step that reads the event and fetches the
  // base (#3185): it reports warnings and cannot fail a build, and it is the
  // last before the note, so no check runs after its fetch.
  const lint = steps[steps.length - 2] || '';
  yes('the step before the note is the lint, which cannot fail a build', /^      - name: Lint \(warnings only\)\n/.test(lint) &&
      /\n        continue-on-error: true\n/.test(lint) && /\n          \.\\scripts\\dev\\Lint\.ps1 -All\n          exit 0\n/.test(lint) &&
      /\nexit 0\s*$/.test(read(path.join(REPO, 'scripts', 'dev', 'Lint.ps1'))));
  const before = steps.slice(0, -2).join('\n').replace(/^\s*#.*$/gm, '');
  const EVENT = /github\.(event|ref|ref_name|sha|head_ref|base_ref|run_id|run_number|actor)\b|GITHUB_(EVENT_NAME|EVENT_PATH|REF|REF_NAME|REF_TYPE|SHA|HEAD_REF|BASE_REF|RUN_ID|RUN_NUMBER|ACTOR)\b/;
  yes('no check step reads the event, the ref or the commit', !EVENT.test(before));
  yes('no check step fetches more history', !/git(\.exe)?\s+fetch|fetch-depth/.test(before));
  // Every harness and every script: GitHub's event and ref variables are read
  // only where named here, each with why it is not a check of a build.
  const ALLOWED = {
    'scripts/release/Resolve-ReleaseTag.ps1': 'release.yml\'s tag step, which no check runs: tests/test-release-tag.ps1 gives it the values itself',
    'tests/test-release-tag.ps1': 'reads release.yml\'s text for those names; sets them for Resolve-ReleaseTag.ps1 in a scratch process',
    'scripts/dev/Run-Gate.ps1': 'the gate step: the event chooses only how much of the gate runs (#3114), and a build that ran less than all of it keeps no note, held above',
    'tests/test-3114-run-gate.ps1': 'sets those names for Run-Gate.ps1 in scratch processes, to hold what it does on each event'
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
