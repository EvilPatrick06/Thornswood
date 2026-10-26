#!/usr/bin/env node
// scripts/dev/Tested-Tree.js
//
// #3182: main's build ran every check again on the commit its pull request
// had just passed, 26 minutes of a build runner each time (run 39690135051
// for #3125 on 21 Oct 2026), and 905 box minutes that day. A squash merge of
// a pull request whose build ran against the main it lands on gives main the
// very tree that build checked, so build.yml's first job asks this script
// whether a green pull request build already checked HEAD's tree. When one
// did, main's build says which run and stops green; otherwise it builds in
// full, as before.
//
// WHAT A PULL REQUEST BUILD LEAVES. The last step of build-pr.yml's checks
// prints one line in its job's log, TESTED-TREE <tree> and the commit, the
// pull request and its head. It is the last step, so it is only there when
// every check before it passed, and it runs only when the gate step ran every
// gate harness (#3114: a pull request built on the VPS may run only those its
// change can reach, and then main builds in full and is traced). It was an
// artifact, tested-tree-<tree>, until #3399: a private repository's artifact
// storage is counted by the hour, this one used October's whole allowance by
// 23 Oct 2026 (Patrick's billing report, on #3399), and from then every
// upload failed and took every pull request's build red with it. A log costs
// no storage, and GitHub keeps it 90 days.
//
// HOW IT IS FOUND. Main's HEAD is the squash merge of a pull request, and
// GitHub answers which pull request a commit came from. That pull request's
// head is the commit its build-pr.yml runs were made for, so its runs are
// read newest first, and the log of the one whose Launcher builds job got
// through its last step is read for the line.
//
// WHAT COUNTS AS TESTED. A TESTED-TREE line naming this tree, in the log of a
// Launcher builds job that ended success with its "Write down the tree these
// checks passed on" step success, in a run of .github/workflows/build-pr.yml
// for a pull_request whose head is this repository (a fork's run could name
// any tree it liked, and a fork never reaches the box), for the head of a
// pull request merged as this commit. Anything less, or any answer from
// GitHub this cannot read, is "not tested", and main builds.
//
// WHY THE TREE IS ENOUGH. actions/checkout fetches one commit, so a check
// sees the same files and no history on both builds; what differs is the
// commit's own id, message and date, the branch name and the event, and no
// check reads those (tests/test-3182-tested-tree.js holds that, and #3114
// has the run of every gate harness on a pull request checkout and a main
// checkout of one tree). The nightly runs every harness on main each night.
//
//     node scripts/dev/Tested-Tree.js --tree <sha> --commit <sha> --repo <owner/name>
//
// reads GH_TOKEN and writes run=<url> to GITHUB_OUTPUT when the tree passed.
// It always exits 0: a question it cannot answer builds main, it never fails it.
'use strict';

const WORKFLOW = '.github/workflows/build-pr.yml';
const JOBS = ['Launcher builds', 'Launcher builds (VPS fallback)'];
const STEP = 'Write down the tree these checks passed on';
const MARK = 'TESTED-TREE';
const SHA = /^[0-9a-f]{40}$/;

// Every tree a job's log says its checks passed on: the lines that start,
// after GitHub's timestamp, with the mark and a tree id.
function treesInLog(text) {
  const out = [];
  const re = new RegExp('^(?:\\d{4}-\\d\\d-\\d\\dT[\\d:.]+Z )?' + MARK + ' ([0-9a-f]{40})(?: |$)');
  for (const line of String(text || '').split(/\r?\n/)) {
    const m = re.exec(line);
    if (m) { out.push(m[1]); }
  }
  return out;
}

/*
  find({ tree, commit, repo, get, getText }) -> { run, why }
  get(path) resolves to the parsed JSON of GET https://api.github.com/<path>,
  getText(path) to its body as text (a job's log), or each throws. run is the
  passing run's address, or '' with why saying what was missing.
*/
async function find(o) {
  if (!SHA.test(String(o.tree || ''))) { return { run: '', why: 'no tree was given' }; }
  if (!SHA.test(String(o.commit || ''))) { return { run: '', why: 'no commit was given' }; }
  if (!/^[\w.-]+\/[\w.-]+$/.test(String(o.repo || ''))) { return { run: '', why: 'no repository was given' }; }
  const prs = await o.get('repos/' + o.repo + '/commits/' + o.commit + '/pulls?per_page=100');
  const merged = (Array.isArray(prs) ? prs : []).filter(p => p && p.merged_at && p.head && SHA.test(String(p.head.sha || '')) &&
    p.head.repo && p.head.repo.full_name === o.repo);
  if (merged.length === 0) { return { run: '', why: 'no pull request of this repository was merged as ' + o.commit.slice(0, 12) }; }
  const whys = [];
  for (const p of merged) {
    const list = await o.get('repos/' + o.repo + '/actions/workflows/' + WORKFLOW.split('/').pop() + '/runs?event=pull_request&head_sha=' + p.head.sha + '&per_page=100');
    const runs = (list && Array.isArray(list.workflow_runs) ? list.workflow_runs : []).filter(r => r && r.head_sha === p.head.sha).sort((a, b) => b.id - a.id);
    if (runs.length === 0) { whys.push('pull request #' + p.number + ': no pull request build of its head ' + p.head.sha.slice(0, 12)); continue; }
    for (const r of runs) {
      const id = r.id;
      if (r.path !== WORKFLOW) { whys.push('run ' + id + ': not ' + WORKFLOW); continue; }
      if (r.event !== 'pull_request') { whys.push('run ' + id + ': not a pull request build'); continue; }
      if (!r.repository || r.repository.full_name !== o.repo || !r.head_repository || r.head_repository.full_name !== o.repo) {
        whys.push('run ' + id + ': its head is not this repository'); continue;
      }
      const j = await o.get('repos/' + o.repo + '/actions/runs/' + id + '/jobs?per_page=100');
      const job = (j && Array.isArray(j.jobs) ? j.jobs : []).find(x =>
        JOBS.indexOf(x.name) >= 0 && x.conclusion === 'success' &&
        (Array.isArray(x.steps) ? x.steps : []).some(s => s.name === STEP && s.conclusion === 'success'));
      if (!job) { whys.push('run ' + id + ': no Launcher builds job passed through to its last step'); continue; }
      const trees = treesInLog(await o.getText('repos/' + o.repo + '/actions/jobs/' + job.id + '/logs'));
      if (trees.indexOf(o.tree) >= 0) {
        return { run: String(r.html_url || ''), why: 'pull request #' + p.number + ' passed every check on this tree' };
      }
      whys.push('run ' + id + ': ' + (trees.length ? 'it passed on ' + trees.map(t => t.slice(0, 12)).join(', ') + ', another tree (main moved under it)' : 'its log has no ' + MARK + ' line'));
    }
  }
  return { run: '', why: whys.join('; ') };
}

// GET https://api.github.com/<path>, as text. A job's log answers with a
// redirect to where GitHub keeps it, which fetch follows; the token is not
// sent on to that other host.
function api(token) {
  return async function getText(path) {
    const res = await fetch('https://api.github.com/' + path, {
      headers: { 'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer ' + token, 'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'thornswood-tested-tree' }
    });
    if (!res.ok) { throw new Error('GET ' + path.split('?')[0] + ' answered ' + res.status); }
    return res.text();
  };
}

async function main(argv, env, get) {
  const arg = n => { const i = argv.indexOf(n); return i >= 0 ? String(argv[i + 1] || '') : ''; };
  let r;
  const getText = get || api(env.GH_TOKEN || '');
  const getJson = async p => { const t = await getText(p); return typeof t === 'string' ? JSON.parse(t) : t; };
  try { r = await find({ tree: arg('--tree'), commit: arg('--commit'), repo: arg('--repo'), get: getJson, getText: async p => String(await getText(p)) }); }
  catch (e) { r = { run: '', why: 'GitHub could not be asked: ' + e.message }; }
  if (r.run) {
    console.log('Already tested: ' + r.why + ', ' + r.run + '. Main builds nothing again.');
    if (env.GITHUB_OUTPUT) { require('fs').appendFileSync(env.GITHUB_OUTPUT, 'run=' + r.run + '\n'); }
  } else {
    console.log('Not tested yet (' + r.why + '), so main builds in full.');
  }
  return r;
}

if (require.main === module) { main(process.argv.slice(2), process.env).then(() => process.exit(0), () => process.exit(0)); }
module.exports = { find: find, main: main, treesInLog: treesInLog, WORKFLOW: WORKFLOW, JOBS: JOBS, STEP: STEP, MARK: MARK };
