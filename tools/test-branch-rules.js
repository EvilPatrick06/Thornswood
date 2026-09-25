// test-branch-rules.js
//
// The three files that say how work reaches main say what GitHub and the
// scripts actually do.
//
// WHY THIS EXISTS. Entry 232 on the To Do List, first opened as "the review
// routine both documents describe has never happened, and the settings exempt
// the only person it would bind". Branch protection on main changed twice on
// 22 September, and each time the documents were a step behind. Read off GitHub
// on 23 September: enforce_admins on, one required check "Launcher builds",
// required approving reviews 0, code owner review off. CLAUDE.md was corrected
// in #196. SECOND-DEVELOPER.md still said a main Ship commits and pushes the
// source when the release is out, and that the other person reads every pull
// request. .github/CODEOWNERS still said Patrick's own work goes straight to
// main and never becomes a pull request. CLAUDE.md itself still said a main
// Ship commits and pushes the source, one bullet above the paragraph saying
// Ship writes nothing to the repository. With enforce_admins on, a push
// straight to main is refused, so all of those described something the
// tooling will not allow.
//
// So this checks two things. First, the facts the documents lean on, read off
// the files that decide them: build.yml has one job and it is "Launcher
// builds"; Ship.ps1 never writes to the source repository; Bump-Version.ps1
// commits Updater.cs and nothing else; CODEOWNERS names files that exist and
// covers the six shared ones CLAUDE.md lists. Then the documents: each states
// the four settings, names the required check exactly as build.yml does, gives
// the command that reads the live settings, and says none of the things that
// stopped being true.
//
//     node tools/test-branch-rules.js           the files only, no network
//     node tools/test-branch-rules.js --live    also reads branch protection
//                                               off GitHub with gh and checks
//                                               the documents against it
//
// The --live read is a GET and changes nothing. CI does not pass it: the
// token a workflow gets cannot read branch protection.
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const LIVE = process.argv.indexOf('--live') !== -1;

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function read(rel) { return fs.readFileSync(path.join(ROOT, rel), 'utf8'); }

// Prose wraps anywhere and CODEOWNERS is all comment lines, so every document
// is compared as one line: comment marks off, Markdown emphasis and code
// marks off, whitespace collapsed.
function flat(text, comments) {
  let t = text.charCodeAt(0) === 0xFEFF ? text.slice(1) : text;
  if (comments) t = t.replace(/^[ \t]*#[ \t]?/gm, '');
  return t.replace(/[*`]/g, '').replace(/\s+/g, ' ');
}

// ------------------------------------------------------------ build.yml
// A required status check is matched by the job's name. Branch protection
// names one, so build.yml has to have exactly one job, and it has to be
// called what the documents and the setting call it.
const yml = read('.github/workflows/build.yml').split(/\r?\n/);
const jobs = [];
let inJobs = false;
yml.forEach(function (l) {
  if (/^jobs:\s*$/.test(l)) { inJobs = true; return; }
  if (!inJobs) return;
  if (/^\S/.test(l) && !/^#/.test(l)) { inJobs = false; return; }
  const job = /^  ([A-Za-z0-9_-]+):\s*$/.exec(l);
  if (job) { jobs.push({ id: job[1], name: null }); return; }
  const nm = /^    name:\s*["']?(.+?)["']?\s*$/.exec(l);
  if (nm && jobs.length && jobs[jobs.length - 1].name === null) jobs[jobs.length - 1].name = nm[1];
});
yes('build.yml has exactly one job, so one required check covers all of it (found ' + jobs.length + ')', jobs.length === 1);
const CHECK = jobs.length ? jobs[0].name : null;
yes('that job is named "Launcher builds" (found "' + CHECK + '")', CHECK === 'Launcher builds');

// ------------------------------------------------------------ Ship.ps1
// Every git call in a PowerShell script, with the repository it acts on. A
// call with -C names its own; a call without one acts on wherever the script
// is standing, which is the source repository unless a Push-Location says
// otherwise.
const WRITES = /^(add|commit|push|reset|checkout|switch|merge|rebase|tag|rm|mv|stash|cherry-pick|revert|apply|am|restore)$/;
function gitCalls(src) {
  const out = [];
  let here = null;
  let block = false;
  src.split(/\r?\n/).forEach(function (l, i) {
    if (block) { if (/#>/.test(l)) block = false; return; }
    if (/^\s*<#/.test(l)) { if (!/#>/.test(l)) block = true; return; }
    if (/^\s*#/.test(l)) return;
    const pl = /Push-Location\s+(\$\w+)/.exec(l);
    if (pl) here = pl[1];
    const re = /&\s*git\s+(?:-C\s+(\$\w+)\s+)?([a-z-]+)(.*)/g;
    let m;
    while ((m = re.exec(l))) {
      out.push({ line: i + 1, repo: m[1] || here || '$RepoDir', sub: m[2], rest: m[3], text: l.trim() });
    }
    if (/Pop-Location/.test(l)) here = null;
  });
  return out;
}
function sourceWrites(calls) {
  return calls.filter(function (c) {
    return WRITES.test(c.sub) && (c.repo === '$RepoDir' || c.repo === '$Here');
  });
}

// The parser has to catch the thing it is here for, so it is shown the lines
// Ship used to end with before it is trusted with the real file.
const oldShip = [
  '& git -C $RepoDir add -A 2>&1 | Out-Null',
  '& git -C $RepoDir commit -m $Notes 2>&1 | Out-Null',
  'Push-Location $RepoDir',
  '& git push 2>&1 | Out-Null',
  'Pop-Location',
  'Push-Location $devRel',
  '& git push -u origin HEAD 2>&1 | Out-Null',
  'Pop-Location'
].join('\n');
yes('the check flags the three source writes Ship used to end with, and not the dev feed push',
    sourceWrites(gitCalls(oldShip)).length === 3);

const shipSrc = read('tools/Ship.ps1');
const ship = gitCalls(shipSrc);
const shipReads = ship.filter(function (c) { return c.repo === '$RepoDir' && !WRITES.test(c.sub); });
const shipFeed = ship.filter(function (c) { return WRITES.test(c.sub) && c.repo === '$devRel'; });
yes('Ship.ps1 reads the source repository before a main release (' + shipReads.length + ' git calls: branch, status, fetch, ahead and behind)',
    shipReads.length >= 4);
yes('Ship.ps1 still writes the dev feed in the releases clone, so the check can see a write when there is one (' + shipFeed.length + ')',
    shipFeed.length >= 3);
const shipBad = sourceWrites(ship);
shipBad.forEach(function (c) { console.log('      Ship.ps1:' + c.line + '  ' + c.text); });
yes('Ship.ps1 never adds, commits, pushes or moves a branch in the source repository', shipBad.length === 0);
yes('Ship.ps1 has no git add -A anywhere', !/&\s*git\s+(?:-C\s+\$\w+\s+)?add\s+-A/.test(shipSrc));
yes('Ship.ps1 refuses a main release with anything uncommitted', /uncommitted change\(s\)\. A release ships what is on GitHub/.test(shipSrc));
// The ahead refusal used to say "Run git push first". main refuses that push
// from everybody, so since #253 it sends people through a pull request, and
// the documents say so.
yes('Ship.ps1 refuses a main release that is ahead of origin/main, and sends it through a pull request rather than a push',
    // origin/$branch since the hotfix path (24 September): the same refusal,
    // naming whichever branch is shipping, main or hotfix/...
    /ahead of origin\/(main|\$branch)\. A release has to be buildable[\s\S]{0,300}?through a pull request/.test(shipSrc) &&
    !/ahead of origin\/(main|\$branch)\. Run git push first/.test(shipSrc));
yes('Ship.ps1 refuses a main release with a file under tools that git does not know, which both documents now name',
    /file\(s\) under tools that git does not know about/.test(shipSrc));

// ------------------------------------------------------------ Bump-Version.ps1
const bump = gitCalls(read('tools/Bump-Version.ps1'));
const bumpAdds = bump.filter(function (c) { return c.sub === 'add'; });
yes('Bump-Version.ps1 stages one path, tools/app/Updater.cs, and nothing else',
    bumpAdds.length === 1 && /^\s+--\s+'tools\/app\/Updater\.cs'\s/.test(bumpAdds[0].rest + ' '));
yes('Bump-Version.ps1 commits', bump.some(function (c) { return c.sub === 'commit'; }));
yes('Bump-Version.ps1 pushes nothing itself; it prints the push for a person to run',
    !bump.some(function (c) { return c.sub === 'push'; }));

// ------------------------------------------------------------ CODEOWNERS
const coRaw = read('.github/CODEOWNERS');
const claudeRaw = read('CONTRIBUTING.md');
// The team, from the table in CONTRIBUTING.md: the GitHub column, as handles.
const TEAM = [];
((claudeRaw || '').split(/\r?\n/)).forEach(function (l) {
  const m = /^\|\s*[^|]+\|\s*([A-Za-z0-9-]+)\s*\|/.exec(l);
  if (m && m[1] !== 'GitHub' && !/^-+$/.test(m[1])) TEAM.push('@' + m[1]);
});
yes('CONTRIBUTING.md has a team table with GitHub handles (' + TEAM.join(' ') + ')', TEAM.length >= 3);
const rules = coRaw.split(/\r?\n/).filter(function (l) { return l.trim() && !/^\s*#/.test(l); })
  .map(function (l) { const p = l.trim().split(/\s+/); return { path: p[0], owners: p.slice(1) }; });
yes('CODEOWNERS has rules to read (' + rules.length + ')', rules.length >= 6);
const missing = rules.filter(function (r) {
  return !fs.existsSync(path.join(ROOT, r.path.replace(/^\//, '').replace(/\/$/, '')));
});
missing.forEach(function (r) { console.log('      no such path: ' + r.path); });
yes('every path CODEOWNERS names exists, since GitHub ignores a wrong one in silence', missing.length === 0);
const badOwner = [];
rules.forEach(function (r) {
  if (!r.owners.length) badOwner.push(r.path + ' has no owner');
  r.owners.forEach(function (o) { if (TEAM.indexOf(o) < 0) badOwner.push(r.path + ' ' + o); });
});
badOwner.forEach(function (b) { console.log('      ' + b); });
yes('every owner is somebody in CONTRIBUTING.md\'s team table, by GitHub handle', badOwner.length === 0);

const shared = /Do not edit ([\s\S]*?) without a line in #dev/.exec(claudeRaw);
const sharedNames = shared ? shared[1].replace(/\s+/g, ' ').split(/,\s*|\s+or\s+/).map(function (s) { return s.trim(); }).filter(Boolean) : [];
yes('CONTRIBUTING.md lists the six shared files (' + sharedNames.join(', ') + ')', sharedNames.length === 6);
const uncovered = sharedNames.filter(function (n) {
  return !rules.some(function (r) { return path.posix.basename(r.path) === n && TEAM.every(function (o) { return r.owners.indexOf(o) >= 0; }); });
});
uncovered.forEach(function (n) { console.log('      not in CODEOWNERS for the whole team: ' + n); });
yes('each of the six shared files has a CODEOWNERS line naming the whole team (' + TEAM.join(' ') + ')', sharedNames.length === 6 && uncovered.length === 0);

// ------------------------------------------------------------ the documents
const docs = [
  { name: 'CONTRIBUTING.md', text: flat(claudeRaw, false) },
  { name: 'SECOND-DEVELOPER.md', text: flat(read('SECOND-DEVELOPER.md'), false) },
  { name: '.github/CODEOWNERS', text: flat(coRaw, true) }
];
const PROTECTION = 'gh api repos/EvilPatrick06/Thornswood/branches/main/protection';

docs.forEach(function (d) {
  const t = d.text;
  yes(d.name + ' says enforce_admins is on', /enforce_admins is on\b/.test(t));
  const said = /required check is "?([^",;.]+?)"?[,;.]/.exec(t);
  yes(d.name + ' names the required check exactly as build.yml names the job (says "' + (said ? said[1] : '') + '")',
      !!said && said[1] === CHECK);
  yes(d.name + ' says required approving reviews is 0', /required approving reviews is (0|zero)\b/i.test(t));
  yes(d.name + ' says the code owner review is off', /code owner review is off|Require review from Code Owners is off/i.test(t));
  yes(d.name + ' gives the command that reads the live settings', t.indexOf(PROTECTION) !== -1);

  // What stopped being true. Ship writes nothing to the source repository,
  // nobody pushes straight to main, and nothing merges by itself because
  // auto-merge is off on the repository.
  yes(d.name + ' does not say a Ship commits and pushes the source',
      !/commits and pushes the source|commits the source and push/i.test(t));
  yes(d.name + ' does not describe work going straight to main', !/(goes|going) straight to main/i.test(t));
  yes(d.name + ' does not say a pull request merges itself', !/merges itself/i.test(t));
});

const sd = docs[1].text;
yes('SECOND-DEVELOPER.md does not say Ship bumps the version; Bump-Version.ps1 does, as its own commit',
    !/Ship bumps/i.test(sd) && /Bump-Version\.ps1/.test(sd));
yes('SECOND-DEVELOPER.md does not say Ship patches the client; it checks it with Sync-Client.ps1 -Check',
    !/patches the client/i.test(sd) && /Sync-Client\.ps1 -Check/.test(sd));
yes('SECOND-DEVELOPER.md does not say the other person reads every pull request, which nothing enforces',
    !/The other person reads the pull request/i.test(sd));
yes('SECOND-DEVELOPER.md says Patrick\'s own work goes through a pull request too',
    /Every change goes through a pull request, Patrick's included/.test(sd));
[docs[0], docs[1]].forEach(function (d) {
  yes(d.name + ' says a main release stops on a file under tools that git does not know, as Ship.ps1 does',
      /file under tools that git does not know/.test(d.text));
});

// ------------------------------------------------------------ --live
if (!LIVE) {
  console.log('SKIP  the live settings on GitHub; run with --live to read them with gh');
} else {
  let p = null;
  try {
    p = JSON.parse(execSync(PROTECTION, { cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'] }).toString('utf8'));
  } catch (e) {
    console.log('      ' + String(e.message).split('\n')[0]);
  }
  yes('gh read branch protection on main', !!p);
  if (p) {
    const checks = (p.required_status_checks && p.required_status_checks.contexts) || [];
    const reviews = p.required_pull_request_reviews || {};
    yes('live: enforce_admins is on, as the documents say', !!(p.enforce_admins && p.enforce_admins.enabled));
    yes('live: the one required check is "' + CHECK + '" (GitHub says ' + JSON.stringify(checks) + ')',
        checks.length === 1 && checks[0] === CHECK);
    yes('live: required approving reviews is 0 (GitHub says ' + reviews.required_approving_review_count + ')',
        (reviews.required_approving_review_count || 0) === 0);
    yes('live: the code owner review is off', !reviews.require_code_owner_reviews);
    yes('live: force pushes are refused', !(p.allow_force_pushes && p.allow_force_pushes.enabled));
  }
  let auto = null;
  try {
    auto = execSync('gh api repos/EvilPatrick06/Thornswood --jq .allow_auto_merge', { cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'] }).toString('utf8').trim();
  } catch (e) { }
  yes('live: auto-merge is off, so nothing merges by itself (GitHub says ' + auto + ')', auto === 'false');
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
