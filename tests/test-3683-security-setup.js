/*
  test-3683-security-setup.js

      node .\tests\test-3683-security-setup.js

  #3683 (part of #3721, getting the repository ready to go public), with
  #3642, #3650 and #2759. Holds the parts of GitHub's security setup that
  live in files, so none of them can drift from the others:

    A. CodeQL (.github/workflows/codeql.yml) reads the four languages here
       from source, on GitHub's runners only, and only when the event says
       the repository is not private. Code scanning results cannot be
       uploaded from a private personal repository without paid Advanced
       Security, so until the flip each run is skipped rather than red. It
       runs pull request code, so it must never ask for a self-hosted runner,
       which is the VPS (#3685). A schedule trigger carries no repository in
       its event, so the gate would read nothing there; it has none.
    B. The issue chooser's "A security hole" link opens SECURITY.md, never
       GitHub's advisory form, which a private repository cannot use (#3650).
    C. SECURITY.md gives the three routes security.txt and it share (the
       Security tab's button, a Discord message to the owner, the site's
       report page; Patrick, 26 Oct, q-3683-report-route A), a reply time, and
       no head count that goes stale (#3642). tests\test-3216-site-security.js
       holds security.txt's half.
    D. Dependabot watches every manifest this repository has, and only those:
       every entry's directory holds the manifest its ecosystem reads, and a
       package.json anywhere means an npm entry is owed. The npm lockfiles
       that ship are the engine's, watched in the fork (#2759).

  The same readers are then driven over planted text, so a reader that finds
  nothing wrong anywhere cannot pass by accident.

  Read only. Nothing here reaches GitHub or the network.
*/
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const CR = String.fromCharCode(13);
const read = (rel) => fs.readFileSync(path.join(ROOT, rel), 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

// ---- A. the CodeQL workflow -------------------------------------------------
const LANGS = ['actions', 'csharp', 'javascript-typescript', 'python'];
// The workflow without its comments, which talk about what it must not do.
const code = (t) => t.split('\n').filter((l) => !/^\s*#/.test(l)).join('\n');
function codeqlFaults(text) {
  const t = code(text);
  const bad = [];
  const on = (/\non:\n([\s\S]*?)\n(?=[a-z])/.exec(t) || [])[1] || '';
  if (/^\s*schedule:/m.test(on)) { bad.push('has a schedule trigger, whose event carries no repository to gate on'); }
  if (!/^\s*pull_request:/m.test(on)) { bad.push('does not scan pull requests'); }
  if (/self-hosted|thornswood-vps/.test(t)) { bad.push('asks for a self-hosted runner'); }
  const runsOn = t.match(/^\s*runs-on:.*$/gm) || [];
  if (!runsOn.length || runsOn.some((l) => !/runs-on:\s*ubuntu-latest\s*$/.test(l))) { bad.push('runs on something other than ubuntu-latest'); }
  if (!/\n    if: \$\{\{ github\.event\.repository\.private == false \}\}\n/.test(t)) { bad.push('is not gated on the repository being public'); }
  if (!/security-events: write/.test(t)) { bad.push('cannot upload its results'); }
  if (/\$\{\{\s*secrets\./.test(t)) { bad.push('reads a secret'); }
  const langs = ((/language:\s*\[([^\]]*)\]/.exec(t) || [])[1] || '').split(',').map((s) => s.trim()).filter(Boolean);
  for (const l of LANGS) { if (langs.indexOf(l) < 0) { bad.push('does not read ' + l); } }
  if (!/build-mode: none/.test(t)) { bad.push('builds before it reads'); }
  return bad;
}
const WF = '.github/workflows/codeql.yml';
const cq = fs.existsSync(path.join(ROOT, WF)) ? read(WF) : '';
yes('A  ' + WF + ' is there', !!cq);
const cqBad = codeqlFaults(cq);
yes('A  it reads ' + LANGS.join(', ') + ' from source, on GitHub\'s runners, only while public' +
    (cqBad.length ? ' (' + cqBad.join('; ') + ')' : ''), !!cq && cqBad.length === 0);
yes('A  and the reader fails a scheduled one on the VPS with no gate',
    codeqlFaults('on:\n  schedule:\n    - cron: x\njobs:\n  a:\n    runs-on: [self-hosted, Windows, thornswood-vps]\n').length >= 4);
// The other workflows that run a pull request: none of them is CodeQL's job.
yes('A  CodeQL runs from this one workflow only',
    fs.readdirSync(path.join(ROOT, '.github', 'workflows')).filter((f) => f !== 'codeql.yml' && /\.ya?ml$/.test(f))
      .every((f) => !/github\/codeql-action\//.test(read('.github/workflows/' + f))));

// ---- B. the issue chooser --------------------------------------------------
function chooserFaults(t) {
  const bad = [];
  if (/\/security\/advisories\//.test(t)) { bad.push('links to the advisory form'); }
  const hole = /- name: A security hole\n\s*url: (\S+)/.exec(t);
  if (!hole) { bad.push('has no security link'); }
  else if (!/\/blob\/main\/SECURITY\.md$/.test(hole[1])) { bad.push('its security link is not SECURITY.md (' + hole[1] + ')'); }
  return bad;
}
const chooser = read('.github/ISSUE_TEMPLATE/config.yml');
const chBad = chooserFaults(chooser);
yes('B  the issue chooser\'s security link opens SECURITY.md' + (chBad.length ? ' (' + chBad.join('; ') + ')' : ''), chBad.length === 0);
yes('B  and the reader fails the advisory form it used to open',
    chooserFaults('  - name: A security hole\n    url: https://github.com/x/y/security/advisories/new\n').length === 2);

// ---- C. SECURITY.md ---------------------------------------------------------
function securityFaults(t) {
  const bad = [];
  if (!/Report a vulnerability/.test(t) || !/Security tab/.test(t)) { bad.push('does not name the Security tab\'s button'); }
  if (!/public\s+repositories only/.test(t)) { bad.push('does not say the button is there only on a public repository'); }
  if (!/direct message to the owner/.test(t)) { bad.push('does not give the Discord route'); }
  if (!/\(https:\/\/thornswood\.net\/report\)/.test(t)) { bad.push('does not give the report page, which security.txt names first'); }
  if (!/\*\*72 hours\*\*/.test(t)) { bad.push('gives no reply time'); }
  if (/\b(two|three|four) person\b/i.test(t)) { bad.push('counts the people, which goes stale'); }
  if (/repository is private/i.test(t)) { bad.push('says the repository is private, which stops being true at the flip'); }
  return bad;
}
const sec = read('SECURITY.md');
const secBad = securityFaults(sec);
yes('C  SECURITY.md gives the three routes and a reply time, and no head count' + (secBad.length ? ' (' + secBad.join('; ') + ')' : ''), secBad.length === 0);
yes('C  and the reader fails the text it replaced',
    securityFaults('The repository is private, so the Security tab is there only for people with access. This is a two person project.').length >= 4);

// ---- D. Dependabot ----------------------------------------------------------
// The manifest each ecosystem reads, by the names this repository could have.
const MANIFEST = { 'github-actions': null, pip: /^requirements[^/]*\.txt$|^pyproject\.toml$/, npm: /^package\.json$/ };
function entries(t) {
  const out = [];
  const re = /- package-ecosystem: "?([a-z-]+)"?\n\s*directory: "?([^"\n]+)"?/g;
  let m;
  while ((m = re.exec(t))) { out.push({ eco: m[1], dir: m[2].trim() }); }
  return out;
}
function dependabotFaults(list, files) {
  const bad = [];
  for (const e of list) {
    const dir = e.dir.replace(/^\/+|\/+$/g, '');
    if (!(e.eco in MANIFEST)) { bad.push(e.eco + ' is an ecosystem this reader does not know'); continue; }
    if (e.eco === 'github-actions') {
      if (!files.some((f) => /^\.github\/workflows\/[^/]+\.ya?ml$/.test(f))) { bad.push('github-actions has no workflows to watch'); }
      continue;
    }
    const here = files.filter((f) => path.posix.dirname(f) === (dir || '.') && MANIFEST[e.eco].test(path.posix.basename(f)));
    if (!here.length) { bad.push(e.eco + ' ' + e.dir + ' holds no manifest'); }
  }
  for (const f of files.filter((x) => /(^|\/)package\.json$/.test(x) && !/(^|\/)node_modules\//.test(x))) {
    const d = '/' + path.posix.dirname(f).replace(/^\.$/, '');
    if (!list.some((e) => e.eco === 'npm' && e.dir.replace(/\/+$/, '') === d.replace(/\/+$/, ''))) { bad.push(f + ' has no npm entry'); }
  }
  return bad;
}
let tracked = [];
try {
  tracked = execFileSync('git', ['ls-files'], { cwd: ROOT, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }).split('\n').filter(Boolean);
} catch (e) { console.log('  git ls-files: ' + e.message); }
// The submodule's own files are the fork's, watched there.
tracked = tracked.filter((f) => !/^engine\//.test(f));
yes('D  git lists the tracked files (' + tracked.length + ')', tracked.length > 100);
const dep = entries(read('.github/dependabot.yml'));
yes('D  dependabot.yml has entries to read (' + dep.map((e) => e.eco + ' ' + e.dir).join(', ') + ')', dep.length >= 2);
const depBad = dependabotFaults(dep, tracked);
yes('D  every entry watches a manifest that is here, and every package.json is watched' + (depBad.length ? ' (' + depBad.join('; ') + ')' : ''), depBad.length === 0);
yes('D  and the reader fails an npm entry with no package.json and a package.json with no entry',
    dependabotFaults([{ eco: 'npm', dir: '/site' }], ['site/server.js', 'voice/package.json']).length === 2);
yes('D  the npm lockfiles that ship are named as watched in the fork',
    ['skymp5-server', 'skymp5-client', 'skymp5-front', 'thornswood/engine-changes'].every((w) => read('.github/dependabot.yml').indexOf(w) >= 0));

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
