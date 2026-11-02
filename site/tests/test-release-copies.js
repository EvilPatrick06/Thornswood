// test-release-copies.js
//
// Downloads come from this repository's Releases (#3686), while every
// launcher keeps asking thornswood.net/feed[-dev]/assets/<sha256>. The site
// answers an asset with a redirect to its GitHub Release copy once GitHub,
// asked without a token, says the Release of the feed's current release holds
// it under its sha256, with that sha256 as GitHub's own digest and the site's
// size. Until then, and for anything else, the site sends the bytes itself.
//
// The "release copies" block is lifted out of site/server.js by its markers
// and run with GitHub's answers stubbed, against a temp feed folder. Then the
// two routes that use it are checked for the redirect in front of the bytes.
//
// Read only. Writes to a temp folder and nowhere else.
const REPO_DIR = require('path').join(__dirname, '..', '..'); // this harness is in site\tests\, the repository is two folders up
const fs = require('fs');
const os = require('os');
const path = require('path');
const siteFiles = require('../../tests/site-files');

const CR = String.fromCharCode(13);
const server = siteFiles.source().split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const A = 'a'.repeat(64), B = 'b'.repeat(64), C = 'c'.repeat(64), I = 'd'.repeat(64);
const TAG = 'release/main/20261026-170000';
const DL = 'https://github.com/ThornswoodRP/Thornswood/releases/download/release/main/20261026-170000/';

const from = server.indexOf('/* ---- release copies (#3686) ----');
const to = server.indexOf('/* ---- end release copies ---- */');
yes('the release copies block is in server.js, between its markers', from >= 0 && to > from);
const block = from >= 0 && to > from ? server.slice(from, to) : '';

// The block, with its GitHub call replaced by what each test says GitHub
// answers, and feedFile pointed at a temp store.
function load(answer, feedDocs) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'ts-release-copies-'));
  const files = {};
  for (const ch of Object.keys(feedDocs)) {
    const f = path.join(tmp, ch + '-00000001.json');
    fs.writeFileSync(f, JSON.stringify(feedDocs[ch]));
    files[ch] = f;
  }
  const calls = [];
  const env = {
    https: null,
    feedFile: (ch) => files[ch] || null,
    readJsonQuiet: (f) => { try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch (e) { return null; } },
    calls
  };
  const make = new Function('env', 'Date', 'console',
    'const { https, feedFile, readJsonQuiet } = env;\n' + block + '\n' +
    'releaseGitHub = (p) => { env.calls.push(p); return Promise.resolve(env.answer(p)); };\n' +
    'return { releaseCopy, releaseInstallerCopy, releaseCopies, RELEASE_LOOK_MS, feedReleaseTag };');
  // releaseGitHub is a function declaration in the block, so it can be
  // replaced by assignment inside the same function body.
  env.answer = answer;
  const clock = { now: 1000 };
  const FakeDate = { now: () => clock.now };
  const quiet = { log: () => {}, error: () => {} };
  return { api: make(env, FakeDate, quiet), calls, clock, env };
}
const tick = () => new Promise((r) => setImmediate(r));

function releases(list) { return { status: 200, body: list }; }
function asset(name, digestSha, size, extra) {
  return Object.assign({ name, state: 'uploaded', size, digest: 'sha256:' + digestSha,
    browser_download_url: DL + name }, extra || {});
}

async function main() {
  if (!block) { console.log('\n' + pass + ' passed, ' + fail + ' failed'); process.exit(1); }
  const mainDoc = { launcherVersion: '1.2.7', release: { id: '20261026-170000', channel: 'main', tag: TAG } };

  // ---- 1. a private repository, or no Release yet: the site sends the bytes
  let t = load(() => ({ status: 404, why: 'GitHub answered 404' }), { feed: mainDoc });
  yes('the feed\'s release tag is read from its newest generation', t.api.feedReleaseTag('feed') === TAG);
  yes('while GitHub answers 404 (private, or no Release yet), no redirect', t.api.releaseCopy('feed', A, 10) === '');
  await tick(); await tick();
  yes('  and GitHub was asked once, for the Release list', t.calls.length === 1 && t.calls[0] === '/releases?per_page=30');
  t.api.releaseCopy('feed', A, 10); await tick();
  yes('  and not again inside the wait', t.calls.length === 1);
  t.clock.now += t.api.RELEASE_LOOK_MS;
  t.api.releaseCopy('feed', A, 10); await tick();
  yes('  but again once the wait is over', t.calls.length === 2);

  // ---- 2. the Release is there: the files GitHub vouches for redirect -----
  const assets = [
    asset(A, A, 10),                                        // good
    asset(B, C, 20),                                        // name is not GitHub's digest
    asset(C, C, 30, { state: 'starter' }),                  // not finished uploading
    asset('Thornswood-Setup.exe', I, 99),                   // the installer
    asset(B.slice(0, 63) + 'e', B.slice(0, 63) + 'e', 40,
      { browser_download_url: 'https://evil.example/' + B.slice(0, 63) + 'e' }) // not this repository
  ];
  t = load((p) => p.startsWith('/releases?') ? releases([
      { id: 7, tag_name: 'release/dev/20261026-160000-dev', draft: false },
      { id: 8, tag_name: TAG, draft: false }])
    : p === '/releases/8/assets?per_page=100&page=1' ? releases(assets) : { status: 404, why: 'GitHub answered 404' },
    { feed: mainDoc, 'feed-dev': { release: { tag: 'release/dev/20261026-160000-dev' } } });
  yes('the first ask for a Release is served from the site', t.api.releaseCopy('feed', A, 10) === '');
  await tick(); await tick(); await tick();
  yes('once GitHub holds it, the asset redirects to the Release copy', t.api.releaseCopy('feed', A, 10) === DL + A);
  yes('  never when the site\'s file is another size', t.api.releaseCopy('feed', A, 11) === '');
  yes('  never for an asset whose name is not GitHub\'s own sha256 of it', t.api.releaseCopy('feed', B, 20) === '');
  yes('  never for an upload GitHub has not finished', t.api.releaseCopy('feed', C, 30) === '');
  yes('  never for an address outside this repository\'s Releases', t.api.releaseCopy('feed', B.slice(0, 63) + 'e', 40) === '');
  yes('  and a file the Release does not hold is served from the site', t.api.releaseCopy('feed', 'f'.repeat(64), 5) === '');
  const asked = t.calls.length;
  t.clock.now += 10 * t.api.RELEASE_LOOK_MS;
  t.api.releaseCopy('feed', A, 10); await tick();
  yes('a Release once seen is never asked about again', t.calls.length === asked);
  yes('the installer redirects only when it is the file files.json lists', t.api.releaseInstallerCopy(I, 99) === DL + 'Thornswood-Setup.exe');
  yes('  not another build of it', t.api.releaseInstallerCopy(A, 99) === '' && t.api.releaseInstallerCopy(I, 98) === '');

  // ---- 3. a draft, a feed with no tag, a tag of another shape -------------
  t = load(() => releases([{ id: 9, tag_name: TAG, draft: true }]), { feed: mainDoc });
  t.api.releaseCopy('feed', A, 10); await tick(); await tick();
  yes('a draft Release is not used', t.api.releaseCopy('feed', A, 10) === '' && t.calls.length === 1);
  t = load(() => releases([]), { feed: { release: { tag: 'v1.2.7' } }, 'feed-dev': { launcherVersion: '1' } });
  yes('a feed whose release tag is not release/<channel>/<id> asks GitHub nothing',
      t.api.releaseCopy('feed', A, 10) === '' && t.api.releaseCopy('feed-dev', A, 10) === '' && t.calls.length === 0);

  // ---- 4. the routes ------------------------------------------------------
  const assetRoute = server.indexOf("const feedAsset = p.match(");
  const assetEnd = server.indexOf('return fs.createReadStream(file).pipe(res);', assetRoute);
  const assetBody = assetRoute >= 0 && assetEnd > assetRoute ? server.slice(assetRoute, assetEnd) : '';
  const redirectAt = assetBody.indexOf('releaseCopy(feedAsset[1], feedAsset[2], st.size)');
  yes('the feed asset route asks for the Release copy after it found its own file',
      redirectAt > assetBody.indexOf('fs.existsSync(file)') && redirectAt > assetBody.indexOf('const st = fs.statSync(file)'));
  yes('  and answers 302 to it before any byte is sent',
      /if \(copy\) \{\s*res\.writeHead\(302, \{ location: copy/.test(assetBody.slice(redirectAt)) &&
      redirectAt < assetBody.indexOf('rangeReply('));
  const fileRoute = server.indexOf('const dl = p.match(/^\\/file\\/');
  const fileBody = fileRoute >= 0 ? server.slice(fileRoute, server.indexOf('rangeReply(', fileRoute)) : '';
  yes('the installer download asks for the Release copy with the sha256 files.json lists',
      /releaseInstallerCopy\(String\(\(meta\[dl\[1\]\] \|\| \{\}\)\.sha256/.test(fileBody) && /res\.writeHead\(302, \{ location: copy/.test(fileBody));

  console.log('\n' + pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
}
main().catch((e) => { console.log('FAIL  ' + (e && e.stack)); process.exit(1); });
