'use strict';
/*
  test-site-headers.js

      node .\tests\test-site-headers.js

  Every answer the site gives says what a browser may do with it, and the
  policy it sends is no looser than the pages actually need (#1366).

  WHY THIS EXISTS. send() in site\server.js wrote Cache-Control and nosniff
  and nothing else, so an answer from thornswood.net said nothing about who
  may draw it inside a frame, where its address may be sent as a referrer, or
  where a script running on one of our pages may be fetched from. The last of
  those is not hypothetical here: an advertising tag reached every public
  page in September, and nothing in the site refused it. server.js now sends
  four headers on every answer (GUARD, next to send()), and this reads them
  off a running copy rather than off the source.

  Two halves.

  THE PAGES. The policy is read out of server.js and held against what
  public\*.html and the small pages server.js writes itself ask a browser to
  load. Anything loaded from another host fails this, because the policy
  allows none. 'unsafe-inline' is allowed to be in it only while the pages
  carry inline script or styling, which both do today: when that stops being
  true, this fails and the line to delete is in GUARD.

  THE ANSWERS. A copy of server.js is started in the temp folder, the way
  tests\test-site-local.js starts one, and asked for a page, an API answer, a
  redirect, a 404, a static file, a 304, a byte range and an address that
  cannot be read. All eight carry the four headers, once each. The 304, the
  range and the 400 never go through send(), which is why they are here: they
  write their own headers, and the one setHeader at the top of handle() is
  what covers them.

  Nothing here reads the checkout's own site\config.json, and nothing asks
  Discord: the sample config is checked for empty Discord settings before any
  copy that reads it is started.
*/
const REPO_DIR = require('path').join(__dirname, '..'); // the tests are in tests\, the repository is one folder up
const fs = require('fs');
const path = require('path');
const os = require('os');
const net = require('net');
const http = require('http');
const { spawn } = require('child_process');

const CR = String.fromCharCode(13);
const BS = String.fromCharCode(92);
const APP = path.join(REPO_DIR, 'site');
const PUBLIC = path.join(APP, 'public');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function read(rel) {
  try { return fs.readFileSync(path.join(REPO_DIR, rel), 'utf8').split(CR).join(''); }
  catch (e) { return null; }
}

const src = read('site/server.js') || '';

// ------------------------------------------------------- the headers sent --
// GUARD out of server.js itself, read as a value, so this harness cannot hold
// a copy of the policy that has drifted from the one that goes out.
function objectAfter(head) {
  const at = src.indexOf(head);
  if (at < 0) { return null; }
  const b = src.indexOf('{', at);
  let d = 0;
  for (let i = b; i < src.length; i++) {
    if (src[i] === '{') { d++; }
    else if (src[i] === '}') { d--; if (d === 0) { return src.slice(b, i + 1); } }
  }
  return null;
}
const guardSrc = objectAfter('const GUARD = {');
let GUARD = null;
try { GUARD = guardSrc ? eval('(' + guardSrc + ')') : null; } catch (e) { GUARD = null; }
yes('server.js has the guard headers in one place, GUARD next to send()', !!GUARD);
const G = GUARD || {};

const WANT = {
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
  'X-Frame-Options': 'SAMEORIGIN'
};
Object.keys(WANT).forEach(function (name) {
  yes('GUARD sends ' + name + ': ' + WANT[name], G[name] === WANT[name]);
});
const policy = String(G['Content-Security-Policy'] || '');
yes('GUARD sends a Content-Security-Policy', policy.length > 0);

// The policy as { directive: [source, source] }.
const CSP = {};
policy.split(';').forEach(function (part) {
  const words = part.trim().split(/\s+/).filter(Boolean);
  if (words.length) { CSP[words[0]] = words.slice(1); }
});
function allows(directive, source) {
  const list = CSP[directive] || CSP['default-src'] || [];
  return list.indexOf(source) >= 0;
}
yes("the policy falls back to this site: default-src 'self'",
    (CSP['default-src'] || []).join(' ') === "'self'");
yes("nothing may be framed but this site: frame-ancestors 'self'",
    (CSP['frame-ancestors'] || []).join(' ') === "'self'");
yes("no plugins and no rewritten base: object-src 'none', base-uri 'self'",
    (CSP['object-src'] || []).join(' ') === "'none'" &&
    (CSP['base-uri'] || []).join(' ') === "'self'");
yes("a form on a page here posts here: form-action 'self'",
    (CSP['form-action'] || []).join(' ') === "'self'");
yes("no script, style or fetch may come from another host: no http source in the policy",
    !/https?:/.test(policy) && policy.indexOf('*') < 0);

// send() writes them, and handle() sets them once for the answers that never
// go through send().
const sendBody = objectAfter('function send(res, code, payload, type, extra)') || '';
yes('send() puts GUARD on every answer it writes',
    sendBody.indexOf('GUARD') >= 0 && sendBody.indexOf("'Cache-Control': 'no-store'") >= 0);
yes('handle() sets them once as well, for the streamed answers that write their own headers',
    /res\.setHeader\(name, GUARD\[name\]\)/.test(src));

// ---------------------------------------------- what the pages ask browsers --
// Only the places a browser is told to load something. A link somebody clicks,
// an og:image a crawler reads and a line of prose naming an address are not
// loads, and no policy stops them.
const pages = ['index.html', 'home.html'].map(function (name) {
  return { name: name, text: (read('site/public/' + name) || '') };
});
const styles = (read('site/public/fonts.css') || '');
yes('both public pages and fonts.css are there to read',
    pages.every(function (p) { return p.text.length > 0; }) && styles.length > 0);

const loads = [];
pages.concat([{ name: 'fonts.css', text: styles }]).forEach(function (p) {
  const found = [];
  const add = (re) => {
    let m;
    while ((m = re.exec(p.text)) !== null) { found.push(m[1]); }
  };
  add(/<script[^>]+src=["']([^"']+)["']/g);
  add(/<link[^>]+href=["']([^"']+)["']/g);
  add(/<(?:img|video|audio|source|iframe|embed|object)[^>]+src=["']([^"']+)["']/g);
  add(/url\(["']?([^)"']+)/g);
  add(/fetch\(\s*["'`]([^"'`]+)/g);
  found.forEach(function (where) {
    if (/^https?:\/\//.test(where)) { loads.push(p.name + ': ' + where); }
  });
});
yes('no page loads anything from another host' + (loads.length ? ', but ' + loads.join('; ') : ''),
    loads.length === 0);

// data: and blob: pictures, which the policy names on purpose.
const dataPics = pages.some(function (p) { return /url\(["']?data:image\//.test(p.text); });
const blobPics = pages.some(function (p) { return /createObjectURL/.test(p.text) && /\.src = url/.test(p.text); });
yes('the backdrop is a data: picture, and img-src allows data:', dataPics && allows('img-src', 'data:'));
yes('the gallery form previews a picked file, and img-src allows blob:', blobPics && allows('img-src', 'blob:'));

// Inline script and styling are the one loose part, and only while they are
// there. The small pages server.js writes carry style attributes too.
const inlineScripts = pages.reduce(function (n, p) {
  return n + (p.text.match(/<script(?![^>]*\bsrc=)[^>]*>/g) || []).length;
}, 0);
const inlineStyles = pages.reduce(function (n, p) {
  return n + (p.text.match(/<style[^>]*>/g) || []).length + (p.text.match(/ style="/g) || []).length;
}, 0) + (src.match(/ style="/g) || []).length;
yes('the pages carry inline script (' + inlineScripts + ' blocks) and inline styling (' +
    inlineStyles + ' places), which is why the policy allows them',
    inlineScripts > 0 && inlineStyles > 0);
yes("script-src allows inline only while the pages need it, and allows no other host",
    allows('script-src', "'self'") &&
    allows('script-src', "'unsafe-inline'") === (inlineScripts > 0));
yes("style-src the same",
    allows('style-src', "'self'") &&
    allows('style-src', "'unsafe-inline'") === (inlineStyles > 0));
// 'unsafe-eval' is not in the policy, so nothing the pages run may build code
// from a string. marked, the one script file served, does not.
const scripts = fs.readdirSync(PUBLIC).filter(function (f) { return /\.js$/.test(f); })
  .map(function (f) { return { name: f, text: read('site/public/' + f) || '' }; });
const builds = pages.concat(scripts).filter(function (p) {
  return /\bnew Function\s*\(|[^.\w]eval\s*\(/.test(p.text);
}).map(function (p) { return p.name; });
yes('nothing served builds code from a string' + (builds.length ? ', but ' + builds.join(', ') : '') +
    ", so the policy needs no 'unsafe-eval'",
    builds.length === 0 && policy.indexOf('unsafe-eval') < 0);
yes('no page draws another page in a frame, so frame-ancestors costs nothing',
    pages.every(function (p) { return p.text.indexOf('<iframe') < 0; }));

// --------------------------------------------------------- a running copy --
const sampleText = String(read('site/config.example.json'));
const BOM = String.fromCharCode(65279);
let sample = null;
try { sample = JSON.parse(sampleText.charAt(0) === BOM ? sampleText.slice(1) : sampleText); } catch (e) { sample = null; }
const D = (sample || {}).discord || {};
const quiet = !!sample && ['clientId', 'clientSecret', 'botToken', 'guildId', 'invite'].every(function (k) {
  return D[k] === '';
}) && sample.botKey === '' && sample.secret === '';

function wait(ms) { return new Promise(function (ok) { setTimeout(ok, ms); }); }
async function until(cond, ms) {
  const end = Date.now() + ms;
  while (Date.now() < end) { if (cond()) { return true; } await wait(20); }
  return cond();
}
function freePort() {
  return new Promise(function (ok, no) {
    const s = net.createServer();
    s.on('error', no);
    s.listen(0, '127.0.0.1', function () {
      const p = s.address().port;
      s.close(function () { ok(p); });
    });
  });
}
function ask(port, route, headers) {
  return new Promise(function (ok) {
    const req = http.request({
      host: '127.0.0.1', port: port, method: 'GET', path: route, agent: false,
      headers: headers || {}
    }, function (res) {
      let buf = '';
      res.setEncoding('utf8');
      res.on('data', function (d) { buf += d; });
      res.on('end', function () {
        ok({ status: res.statusCode, headers: res.headers, raw: res.rawHeaders, body: buf });
      });
    });
    req.on('error', function (e) { ok({ status: 0, error: e.message, headers: {}, raw: [], body: '' }); });
    req.setTimeout(10000, function () { req.destroy(new Error('no answer in ten seconds')); });
    req.end();
  });
}
// Every guard header, with the value GUARD holds, written exactly once.
function guarded(what, r) {
  const missing = [];
  const twice = [];
  Object.keys(G).forEach(function (name) {
    const low = name.toLowerCase();
    if (String(r.headers[low] || '') !== String(G[name])) { missing.push(name); }
    let seen = 0;
    for (let i = 0; i < r.raw.length; i += 2) { if (String(r.raw[i]).toLowerCase() === low) { seen++; } }
    if (seen !== 1) { twice.push(name + ' x' + seen); }
  });
  yes(what + ' carries all four guard headers, once each' +
      (missing.length ? ', missing or wrong: ' + missing.join(', ') : '') +
      (twice.length ? ', not once: ' + twice.join(', ') : ''),
      missing.length === 0 && twice.length === 0);
}

const made = [];
function copy() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ts-headers-'));
  made.push(dir);
  fs.copyFileSync(path.join(APP, 'server.js'), path.join(dir, 'server.js'));
  fs.mkdirSync(path.join(dir, 'public'));
  ['home.html', 'robots.txt'].forEach(function (f) {
    fs.copyFileSync(path.join(PUBLIC, f), path.join(dir, 'public', f));
  });
  fs.copyFileSync(path.join(APP, 'config.example.json'), path.join(dir, 'config.json'));
  return dir;
}
async function start(dir) {
  const port = await freePort();
  const child = spawn(process.execPath, ['server.js'], {
    cwd: dir,
    env: Object.assign({}, process.env, {
      THORNSWOOD_DOCS_PORT: String(port),
      THORNSWOOD_DOCS_LOCAL: '1',
      THORNSWOOD_CHAT_DIR: path.join(dir, 'chat')
    })
  });
  const run = { child: child, port: port, out: '', exited: false };
  child.stdout.on('data', function (d) { run.out += d; });
  child.stderr.on('data', function (d) { run.out += d; });
  child.on('exit', function () { run.exited = true; });
  run.up = await until(function () { return run.out.indexOf('listening on ') >= 0 || run.exited; }, 10000) &&
           !run.exited;
  return run;
}
function stop(run) {
  return new Promise(function (ok) {
    if (!run || run.exited) { ok(); return; }
    run.child.once('exit', function () { ok(); });
    try { run.child.kill(); } catch (e) { ok(); }
    setTimeout(ok, 3000);
  });
}

(async function () {
  let run = null;
  try {
    if (!quiet) {
      console.log('SKIP  no copy was started: config.example.json is missing, or holds a Discord setting or a secret');
      yes('the sample is safe to start a copy on', false);
    } else {
      run = await start(copy());
      yes('a copy of server.js comes up on 127.0.0.1', run.up);
      if (!run.up) {
        console.log('      what the copy said:');
        run.out.split('\n').slice(-12).forEach(function (l) { if (l.trim()) { console.log('        ' + l.trim()); } });
      } else {
        const page = await ask(run.port, '/rules');
        yes('a public page answers 200 as HTML (' + page.status + ')',
            page.status === 200 && /text\/html/.test(String(page.headers['content-type'] || '')));
        guarded('a public page', page);
        yes('and keeps the Cache-Control send() has always written',
            String(page.headers['cache-control'] || '') === 'no-store');

        const api = await ask(run.port, '/api/public');
        yes('an API answer is 200 JSON (' + api.status + ')',
            api.status === 200 && /application\/json/.test(String(api.headers['content-type'] || '')));
        guarded('an API answer', api);

        const moved = await ask(run.port, '/download');
        yes('a redirect is 301 to /downloads (' + moved.status + ')',
            moved.status === 301 && String(moved.headers.location || '') === '/downloads');
        guarded('a redirect', moved);

        const gone = await ask(run.port, '/no-such-address', { accept: 'text/html' });
        yes('an address that is not there is 404 (' + gone.status + ')', gone.status === 404);
        guarded('a 404 page', gone);

        const asset = await ask(run.port, '/robots.txt');
        yes('a static file is 200 and cached (' + asset.status + ')',
            asset.status === 200 && /max-age/.test(String(asset.headers['cache-control'] || '')));
        guarded('a static file', asset);

        const etag = String(asset.headers.etag || '');
        const again = await ask(run.port, '/robots.txt', { 'if-none-match': etag });
        yes('the same file with its ETag is 304 (' + again.status + ')', !!etag && again.status === 304);
        guarded('a 304, which never goes through send()', again);

        const part = await ask(run.port, '/robots.txt', { range: 'bytes=0-3' });
        yes('a byte range is 206 with four bytes (' + part.status + ')',
            part.status === 206 && part.body.length === 4);
        guarded('a byte range, which writes its own headers', part);

        const bad = await ask(run.port, '/%zz');
        yes('an address that cannot be read is 400, never 500 (' + bad.status + ')', bad.status === 400);
        guarded('the 400 for a bad address', bad);

        // Nothing here runs over the certificate, so the one header that is
        // only for that must not go out on plain HTTP.
        yes('no Strict-Transport-Security on a plain HTTP answer, as before',
            !page.headers['strict-transport-security']);
      }
    }
  } catch (e) {
    yes('the run finished without throwing: ' + (e && e.stack ? e.stack : e), false);
  } finally {
    await stop(run);
    for (const d of made) {
      try { fs.rmSync(d, { recursive: true, force: true }); } catch (e) { }
    }
  }

  console.log('');
  console.log(pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
})();
