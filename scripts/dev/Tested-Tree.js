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
// keeps an artifact named tested-tree-<tree> holding the tree, the commit
// and the pull request. It is the last step, so it is only there when every
// check before it passed.
//
// WHAT COUNTS AS TESTED. An artifact of that name, not expired, from a run of
// .github/workflows/build-pr.yml for a pull_request whose head is this
// repository (a fork's run could name any tree it liked, and a fork never
// reaches the box), in which a Launcher builds job ended success with its
// "Keep the tree these checks passed on" step success. Anything less, or any
// answer from GitHub this cannot read, is "not tested", and main builds.
//
// WHY THE TREE IS ENOUGH. actions/checkout fetches one commit, so a check
// sees the same files and no history on both builds; what differs is the
// commit's own id, message and date, the branch name and the event, and no
// check reads those (tests/test-3182-tested-tree.js holds that, and #3114
// has the run of every gate harness on a pull request checkout and a main
// checkout of one tree). The nightly runs every harness on main each night.
//
//     node scripts/dev/Tested-Tree.js --tree <sha> --repo <owner/name>
//
// reads GH_TOKEN and writes run=<url> to GITHUB_OUTPUT when the tree passed.
// It always exits 0: a question it cannot answer builds main, it never fails it.
'use strict';

const WORKFLOW = '.github/workflows/build-pr.yml';
const JOBS = ['Launcher builds', 'Launcher builds (VPS fallback)'];
const STEP = 'Keep the tree these checks passed on';
const PREFIX = 'tested-tree-';

/*
  find({ tree, repo, get }) -> { run, why }
  get(path) resolves to the parsed JSON of GET https://api.github.com/<path>,
  or throws. run is the passing run's address, or '' with why saying what
  was missing.
*/
async function find(o) {
  if (!/^[0-9a-f]{40}$/.test(String(o.tree || ''))) { return { run: '', why: 'no tree was given' }; }
  if (!/^[\w.-]+\/[\w.-]+$/.test(String(o.repo || ''))) { return { run: '', why: 'no repository was given' }; }
  const name = PREFIX + o.tree;
  const list = await o.get('repos/' + o.repo + '/actions/artifacts?name=' + name + '&per_page=100');
  const arts = (list && Array.isArray(list.artifacts) ? list.artifacts : []).filter(a => a && a.name === name);
  if (arts.length === 0) { return { run: '', why: 'no pull request build kept this tree' }; }
  const whys = [];
  for (const a of arts) {
    const id = a.workflow_run && a.workflow_run.id;
    if (a.expired) { whys.push('run ' + id + ': its note has expired'); continue; }
    if (!Number.isInteger(id)) { whys.push('an artifact names no run'); continue; }
    const r = await o.get('repos/' + o.repo + '/actions/runs/' + id);
    if (!r || r.path !== WORKFLOW) { whys.push('run ' + id + ': not ' + WORKFLOW); continue; }
    if (r.event !== 'pull_request') { whys.push('run ' + id + ': not a pull request build'); continue; }
    if (!r.repository || r.repository.full_name !== o.repo || !r.head_repository || r.head_repository.full_name !== o.repo) {
      whys.push('run ' + id + ': its head is not this repository'); continue;
    }
    const j = await o.get('repos/' + o.repo + '/actions/runs/' + id + '/jobs?per_page=100');
    const ok = (j && Array.isArray(j.jobs) ? j.jobs : []).some(job =>
      JOBS.indexOf(job.name) >= 0 && job.conclusion === 'success' &&
      (Array.isArray(job.steps) ? job.steps : []).some(s => s.name === STEP && s.conclusion === 'success'));
    if (!ok) { whys.push('run ' + id + ': no Launcher builds job passed through to its last step'); continue; }
    const prs = (Array.isArray(r.pull_requests) ? r.pull_requests : []).map(p => '#' + p.number);
    return { run: String(r.html_url || ''), why: 'pull request ' + (prs.join(', ') || 'build') + ' passed every check on this tree' };
  }
  return { run: '', why: whys.join('; ') };
}

function api(token) {
  return async function get(path) {
    const res = await fetch('https://api.github.com/' + path, {
      headers: { 'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer ' + token, 'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'thornswood-tested-tree' }
    });
    if (!res.ok) { throw new Error('GET ' + path.split('?')[0] + ' answered ' + res.status); }
    return res.json();
  };
}

async function main(argv, env, get) {
  const arg = n => { const i = argv.indexOf(n); return i >= 0 ? String(argv[i + 1] || '') : ''; };
  let r;
  try { r = await find({ tree: arg('--tree'), repo: arg('--repo'), get: get || api(env.GH_TOKEN || '') }); }
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
module.exports = { find: find, main: main, WORKFLOW: WORKFLOW, JOBS: JOBS, STEP: STEP, PREFIX: PREFIX };
