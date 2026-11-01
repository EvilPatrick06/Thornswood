#!/usr/bin/env node
// scripts/ops/Sync-Board.js
//
// Puts an issue's card on the board where the facts GitHub has say it
// belongs (#5185, the redesign's part 5, approved by Patrick on 31 Oct 2026).
//
// WHY. Until November the board's Status and Order were set by hand, or by a
// board: or order: label that board-status.yml carried out, and the card
// could say In Progress for an issue nobody touched in weeks, or Todo for one
// with a pull request open, because nothing tied the card to what was really
// happening. 909 issues were open when #5185 was filed. The board was a
// Projects board of Patrick's own account, which no GitHub App can reach, so
// every move went through his personal token. Now the board belongs to the
// ThornswoodRP organization, and one workflow (.github/workflows/board.yml)
// runs this for every issue that changes, with the board App's own token.
// Nobody moves a card by hand, and nothing else writes the board.
//
// WHAT DECIDES THE STATUS, in this order:
//   Done         the issue is closed; or a merged pull request of this
//                repository carries its test task ("Test task for #N:"),
//                so its fix is on main and waits only for a main Ship
//                (Developer-Guide.md, the board), unless another pull
//                request naming it is open
//   In Progress  an open pull request of this repository names it (Closes,
//                Fixes, Resolves, Refs or Part of #N, or its test task), in
//                its title or body, draft or not; or it carries a claimed:
//                label, which is how a Bot or a person says they are on it
//                and how a waiting issue keeps its place (Developer-Guide.md)
//   Todo         anything else
// A pull request names an issue only in its own title and body. A mention in
// a comment, or a commit message, puts a cross-reference on the issue's
// timeline too, but says nothing about which work the pull request does.
//
// WHAT DECIDES THE PRIORITY. Its label, P0 (breaks the game or a release
// now), P1 (next), P2 (soon) or P3 (later). The board's Priority field shows
// it so the board can sort by it; an issue with none has none on the board,
// and scripts/ops/Check-Board.ps1 names it for the weekly review to give one.
// Two at once: the more urgent one, and Check-Board.ps1 names that too. The
// Order field this replaced is not read or written.
//
// WHAT DECIDES THE TYPE. An issue filed from a form gets its type from the
// form (.github/ISSUE_TEMPLATE). One with none gets Bug when it is labelled
// bug, Dev Findings or Main Findings, Feature when it is labelled Suggestion,
// and Task otherwise; a type somebody set is never changed.
//
// HOW IT IS RUN.
//   node scripts/ops/Sync-Board.js --issues 12,34       those issues
//   node scripts/ops/Sync-Board.js --pull 56             the issues pull request 56 names
//   node scripts/ops/Sync-Board.js --all                 every open issue (a closed one
//                                                        is put in Done by its closed event)
//   node scripts/ops/Sync-Board.js --setup               makes the Priority field when the
//                                                        board has none; changes nothing else
//   --dry-run with any of them reads and says, and writes nothing.
// It reads BOARD_TOKEN (the board App's installation token: the board, and
// the repository's issues and pull requests), GITHUB_REPOSITORY,
// BOARD_OWNER and BOARD_NUMBER. It prints one line per issue and exits 1 when
// any issue could not be put right, naming each, and 2 when it was not asked
// properly.
'use strict';

const API = 'https://api.github.com/';
const STATUSES = ['Todo', 'In Progress', 'Done'];
const PRIORITIES = ['P0', 'P1', 'P2', 'P3'];
const PRIORITY_SAYS = {
  P0: 'Breaks the game, a release or the servers now',
  P1: 'Next up',
  P2: 'Soon',
  P3: 'Later',
};
const PRIORITY_COLOR = { P0: 'RED', P1: 'ORANGE', P2: 'YELLOW', P3: 'GRAY' };

// ------------------------------------------------------------- the rules

// Every issue number of repo the text names as the work of a pull request:
// after Close(s/d), Fix(es/ed), Resolve(s/d), Ref(s) or "Part of", each #N of
// the list that follows ("Refs #1, #2 and #3"), and every "Test task for
// #N:". A bare #N is an issue of the pull request's own repository, so it
// counts only when the pull request is in repo (from); owner/name#N counts
// from anywhere when it names repo, which is how a pull request of the engine
// fork names an issue here.
function namedIn(text, repo, from) {
  const out = new Set();
  const t = String(text || '');
  const self = !repo || !from || String(repo).toLowerCase() === String(from).toLowerCase();
  const ref = '(?:[\\w.-]+\\/[\\w.-]+)?#\\d+';
  const kw = new RegExp('\\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?|refs?|part\\s+of)\\b[\\s:]*(' + ref + '(?:\\s*(?:,|and|&|\\/)?\\s*' + ref + ')*)', 'gi');
  let m;
  while ((m = kw.exec(t)) !== null) {
    for (const one of m[1].match(new RegExp(ref, 'g')) || []) {
      const at = one.indexOf('#');
      const where = one.slice(0, at);
      if (where ? (repo && where.toLowerCase() === String(repo).toLowerCase()) : self) { out.add(Number(one.slice(at + 1))); }
    }
  }
  if (self) { for (const n of tasksIn(t)) { out.add(n); } }
  return out;
}

// The issues a body carries a test task for, by done-on-merge.yml's own
// first-line pattern.
function tasksIn(text) {
  const out = new Set();
  const re = /^\s*Test task for #(\d+)\s*:\s*\S/gim;
  let m;
  while ((m = re.exec(String(text || ''))) !== null) { out.add(Number(m[1])); }
  return out;
}

/*
  statusFor(issue, pulls) -> { status, why }
  issue: { repo, number, state, labels: [names] }
  pulls: [{ repo, number, state: 'open'|'closed', merged: bool, title, body }],
         the pull requests of the organization on the issue's timeline
*/
function statusFor(issue, pulls) {
  const n = Number(issue.number);
  if (String(issue.state).toLowerCase() === 'closed') { return { status: 'Done', why: 'it is closed' }; }
  const naming = (pulls || []).filter(p => namedIn(String(p.title || '') + '\n' + String(p.body || ''), issue.repo, p.repo).has(n));
  const name = p => (p.repo && issue.repo && p.repo.toLowerCase() !== issue.repo.toLowerCase() ? p.repo : '') + '#' + p.number;
  const open = naming.filter(p => p.state === 'open');
  if (open.length) { return { status: 'In Progress', why: 'pull request ' + open.map(name).join(', ') + ' names it and is open' }; }
  const shipped = naming.filter(p => p.merged && (!p.repo || !issue.repo || p.repo.toLowerCase() === issue.repo.toLowerCase()) && tasksIn(p.body).has(n));
  if (shipped.length) { return { status: 'Done', why: 'pull request ' + name(shipped[0]) + ' merged with its test task, so it waits on a main Ship' }; }
  const claim = (issue.labels || []).find(l => /^claimed:/i.test(l));
  if (claim) { return { status: 'In Progress', why: 'it carries ' + claim }; }
  return { status: 'Todo', why: 'no open pull request names it and nobody has claimed it' };
}

// The priority its labels give, or null; and every one it carries.
function priorityFor(labels) {
  const have = PRIORITIES.filter(p => (labels || []).some(l => String(l).trim().toUpperCase() === p));
  return { priority: have.length ? have[0] : null, all: have };
}

// The type an issue with none gets, from its labels.
function typeFor(labels) {
  const has = name => (labels || []).some(l => String(l).toLowerCase() === name.toLowerCase());
  if (has('bug') || has('Dev Findings') || has('Main Findings')) { return 'Bug'; }
  if (has('Suggestion')) { return 'Feature'; }
  return 'Task';
}

// The pull requests on an issue's timeline from a repository of the same
// owner (Thornswood's own, and the engine fork's), one each.
function pullsOnTimeline(events, repo) {
  const seen = new Map();
  const owner = String(repo).split('/')[0].toLowerCase();
  for (const e of events || []) {
    if (!e || e.event !== 'cross-referenced' || !e.source || !e.source.issue) { continue; }
    const s = e.source.issue;
    if (!s.pull_request) { continue; }
    const from = String((s.repository && s.repository.full_name) || repo);
    if (from.split('/')[0].toLowerCase() !== owner) { continue; }
    seen.set(from.toLowerCase() + '#' + Number(s.number), {
      repo: from,
      number: Number(s.number),
      state: String(s.state || '').toLowerCase(),
      merged: !!(s.pull_request && s.pull_request.merged_at),
      title: String(s.title || ''),
      body: String(s.body || ''),
    });
  }
  return Array.from(seen.values());
}

// ---------------------------------------------------------- GitHub calls

function client(token, fetchImpl) {
  const f = fetchImpl || fetch;
  let calls = 0;
  async function call(method, path, body) {
    calls++;
    const res = await f(API + path, {
      method: method,
      headers: {
        Accept: 'application/vnd.github+json',
        Authorization: 'Bearer ' + token,
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'thornswood-board',
        'Content-Type': 'application/json',
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await res.text();
    let data = null;
    try { data = text ? JSON.parse(text) : null; } catch (e) { data = text; }
    if (!res.ok) {
      const said = data && typeof data === 'object' && data.message ? data.message : String(text).slice(0, 300);
      const err = new Error(method + ' ' + path.split('?')[0] + ' answered ' + res.status + ': ' + said);
      err.status = res.status;
      throw err;
    }
    return { data: data, link: res.headers && res.headers.get ? res.headers.get('link') || '' : '' };
  }
  async function all(path) {
    const out = [];
    let next = path + (path.indexOf('?') >= 0 ? '&' : '?') + 'per_page=100';
    while (next) {
      const r = await call('GET', next);
      for (const x of Array.isArray(r.data) ? r.data : []) { out.push(x); }
      const m = /<https:\/\/api\.github\.com\/([^>]+)>;\s*rel="next"/.exec(r.link);
      next = m ? m[1] : '';
    }
    return out;
  }
  return { call: call, all: all, count: () => calls };
}

function optionName(o) { return o && typeof o.name === 'object' && o.name ? String(o.name.raw || '') : String((o && o.name) || ''); }

// The board's Status and Priority fields, with each option's id by name.
async function readBoard(gh, owner, number) {
  const fields = await gh.all('orgs/' + owner + '/projectsV2/' + number + '/fields');
  const pick = name => fields.find(f => String(f.name).toLowerCase() === name.toLowerCase());
  const status = pick('Status');
  if (!status || String(status.data_type).toLowerCase() !== 'single_select') { throw new Error('the board has no single select field named Status'); }
  const so = {};
  for (const o of status.options || []) { so[optionName(o)] = o.id; }
  const missing = STATUSES.filter(s => !so[s]);
  if (missing.length) { throw new Error('the board\'s Status has no ' + missing.join(', ') + '; it has ' + Object.keys(so).join(', ') + ' (an option is never added from here: GitHub rewrites every option when one is added, which can clear every card\'s Status)'); }
  const priority = pick('Priority');
  let po = null;
  if (priority) {
    if (String(priority.data_type).toLowerCase() !== 'single_select') { throw new Error('the board\'s Priority field is not a single select'); }
    po = {};
    for (const o of priority.options || []) { po[optionName(o)] = o.id; }
    const lack = PRIORITIES.filter(p => !po[p]);
    if (lack.length) { throw new Error('the board\'s Priority has no ' + lack.join(', ') + '; it has ' + Object.keys(po).join(', ')); }
  }
  return { status: { id: status.id, options: so }, priority: priority ? { id: priority.id, options: po } : null };
}

async function setup(gh, owner, number, dry, say) {
  const fields = await gh.all('orgs/' + owner + '/projectsV2/' + number + '/fields');
  if (fields.some(f => String(f.name).toLowerCase() === 'priority')) { say('the board has a Priority field; nothing to make'); return; }
  if (dry) { say('would make the Priority field, ' + PRIORITIES.join(', ')); return; }
  await gh.call('POST', 'orgs/' + owner + '/projectsV2/' + number + '/fields', {
    name: 'Priority',
    data_type: 'single_select',
    single_select_options: PRIORITIES.map(p => ({ name: p, color: PRIORITY_COLOR[p], description: PRIORITY_SAYS[p] })),
  });
  say('made the Priority field, ' + PRIORITIES.join(', '));
}

// Puts one issue right: its type when it has none, its card, its Status and
// its Priority. Returns the line to print.
// fresh, when given, is the pull request this run is for, read just now: it
// stands in for its own entry on the timeline, which GitHub may not have
// written yet a few seconds after the pull request was opened.
async function syncIssue(gh, o, issue, board, fresh) {
  const n = Number(issue.number);
  const labels = (issue.labels || []).map(l => (typeof l === 'string' ? l : l.name));
  const events = await gh.all('repos/' + o.repo + '/issues/' + n + '/timeline');
  let pulls = pullsOnTimeline(events, o.repo);
  if (fresh) { pulls = pulls.filter(p => !(p.number === fresh.number && String(p.repo).toLowerCase() === String(fresh.repo).toLowerCase())).concat([fresh]); }
  const s = statusFor({ repo: o.repo, number: n, state: issue.state, labels: labels }, pulls);
  const p = priorityFor(labels);
  const typeNow = issue.type && issue.type.name ? String(issue.type.name) : '';
  const parts = ['#' + n + ': ' + s.status + ' (' + s.why + ')', 'priority ' + (p.priority || 'none') + (p.all.length > 1 ? ' (it carries ' + p.all.join(' and ') + ')' : '')];
  let typeSet = '';
  if (!typeNow) { typeSet = typeFor(labels); parts.push('type ' + typeSet + ' (it had none)'); }
  if (o.dry) { return parts.join(', ') + '; nothing written (dry run)'; }
  if (typeSet) { await gh.call('PATCH', 'repos/' + o.repo + '/issues/' + n, { type: typeSet }); }
  const added = await gh.call('POST', 'orgs/' + o.owner + '/projectsV2/' + o.number + '/items', { type: 'Issue', owner: o.repo.split('/')[0], repo: o.repo.split('/')[1], number: n });
  const item = added.data && added.data.id;
  if (!item) { throw new Error('the board gave back no card for #' + n); }
  const fields = [{ id: board.status.id, value: board.status.options[s.status] }];
  if (board.priority) { fields.push({ id: board.priority.id, value: p.priority ? board.priority.options[p.priority] : null }); }
  await gh.call('PATCH', 'orgs/' + o.owner + '/projectsV2/' + o.number + '/items/' + item, { fields: fields });
  return parts.join(', ');
}

async function run(argv, env, fetchImpl, say) {
  say = say || (s => console.log(s));
  const arg = name => { const i = argv.indexOf(name); return i >= 0 ? String(argv[i + 1] || '') : null; };
  const o = {
    repo: String(env.GITHUB_REPOSITORY || ''),
    owner: String(env.BOARD_OWNER || ''),
    number: String(env.BOARD_NUMBER || ''),
    dry: argv.indexOf('--dry-run') >= 0,
  };
  if (!/^[\w.-]+\/[\w.-]+$/.test(o.repo)) { say('GITHUB_REPOSITORY names no repository'); return 2; }
  if (!/^[\w.-]+$/.test(o.owner)) { say('BOARD_OWNER names no organization'); return 2; }
  if (!/^\d+$/.test(o.number)) { say('BOARD_NUMBER is not the board\'s number (the board environment\'s variable, #5185 says how it is set)'); return 2; }
  if (!env.BOARD_TOKEN) { say('BOARD_TOKEN is empty, so nothing can reach the board'); return 2; }
  const gh = client(env.BOARD_TOKEN, fetchImpl);
  if (argv.indexOf('--setup') >= 0) { await setup(gh, o.owner, o.number, o.dry, say); return 0; }

  let numbers = [];
  let fresh = null;
  const listed = new Map();
  const issues = arg('--issues');
  const pull = arg('--pull');
  if (issues !== null) {
    numbers = issues.split(/[\s,]+/).filter(Boolean).map(Number);
    if (!numbers.length || numbers.some(x => !Number.isInteger(x) || x <= 0)) { say('--issues takes issue numbers, by commas'); return 2; }
  } else if (pull !== null) {
    if (!/^\d+$/.test(pull)) { say('--pull takes one pull request number'); return 2; }
    const pr = (await gh.call('GET', 'repos/' + o.repo + '/pulls/' + pull)).data;
    fresh = { repo: o.repo, number: Number(pr.number), state: String(pr.state || '').toLowerCase(), merged: !!pr.merged_at, title: String(pr.title || ''), body: String(pr.body || '') };
    numbers = Array.from(namedIn(String(pr.title || '') + '\n' + String(pr.body || ''), o.repo, o.repo)).sort((a, b) => a - b);
    // An edit that took a name out: the names before the edit come from the
    // workflow (EARLIER_ISSUES), since GitHub keeps no old body to ask.
    for (const x of String(env.EARLIER_ISSUES || '').split(/[\s,]+/).filter(s => /^\d+$/.test(s)).map(Number)) {
      if (numbers.indexOf(x) < 0) { numbers.push(x); }
    }
    say('pull request #' + pull + ' names ' + (numbers.length ? numbers.map(x => '#' + x).join(', ') : 'no issue'));
  } else if (argv.indexOf('--all') >= 0) {
    for (const i of await gh.all('repos/' + o.repo + '/issues?state=open')) {
      if (!i.pull_request) { listed.set(Number(i.number), i); }
    }
    numbers = Array.from(listed.keys()).sort((a, b) => a - b);
    say(numbers.length + ' open issues');
  } else {
    say('say which issues: --issues, --pull, --all or --setup');
    return 2;
  }

  let board;
  try { board = await readBoard(gh, o.owner, o.number); } catch (e) { say('stopped, nothing written: ' + e.message); return 1; }
  if (!board.priority) { say('the board has no Priority field yet, so priorities are not shown (--setup makes it)'); }
  const failed = [];
  for (const n of numbers) {
    try {
      let issue = listed.get(n);
      if (!issue) { issue = (await gh.call('GET', 'repos/' + o.repo + '/issues/' + n)).data; }
      if (issue.pull_request) { say('#' + n + ' is a pull request; its card is GitHub\'s to keep'); continue; }
      say(await syncIssue(gh, o, issue, board, fresh));
    } catch (e) {
      failed.push(n);
      say('#' + n + ': not put right: ' + e.message);
    }
  }
  say(gh.count() + ' calls to GitHub');
  if (failed.length) { say('not put right: ' + failed.map(x => '#' + x).join(', ')); return 1; }
  return 0;
}

if (require.main === module) {
  run(process.argv.slice(2), process.env).then(code => process.exit(code), e => { console.log('stopped: ' + (e && e.message || e)); process.exit(1); });
}
module.exports = { namedIn, tasksIn, statusFor, priorityFor, typeFor, pullsOnTimeline, readBoard, syncIssue, run, client, STATUSES, PRIORITIES };
