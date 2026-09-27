/*
  test-gallery-report.js

      node .\tests\test-gallery-report.js

  The launcher's end of the gallery: Report on the Play page, and the site
  still being the shape Report was written against.

  WHY THIS EXISTS. Issue #731 asked for the launcher to report a picture and
  for staff to approve, reject and take one down from the same card. Report
  came first (#739), because /api/gallery/report and /api/gallery/submit read
  the launcher's signed ticket out of the query and check it the way
  /api/play/join does, while the six staff doors read who(req), the twa Discord
  cookie a browser gets at /auth/discord/callback, and the launcher holds no
  cookie. So this harness held those six to cookie only, on purpose, so that
  the day one grew a ticket path somebody would notice.

  The site's #743 is that day: one gate, galleryStaff, in front of all six,
  taking either the cookie or a staff ticket. The staff half of the card that
  uses it, and every check on it, is in tests\test-gallery-staff-card.js. This
  file keeps Report and the card around it, and the staff-door block below now
  reads whichever of the two shapes site\server.js is on and says which, so it
  is honest on a checkout with that change and on one without it.

  The launcher cannot be started from here (CLAUDE.md), so this reads the
  source, the window and site\server.js and checks the shape:

    - Gallery.Report posts to /api/gallery/report with the ticket in the
      query and the name and the reason in the body;
    - the reports inbox and dismissing a report stay at the site: nothing in
      the launcher calls either;
    - the card asks /api/gallery/who and hides Report until it has answered,
      so an older site leaves the page as it was;
    - the public rotation still reads /api/public;
    - the buttons exist in ui.xaml, Shell wires them, and the rotation stands
      still while a report is being written;
    - the doors named here are the doors site\server.js actually serves, and
      the report door really does take the ticket, so this fails if either
      side moves;
    - the words follow the house rules and the C# is C# 5.

  Read only. It reads launcher\app\*.cs, launcher\ui.xaml and site\server.js.
*/
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const APP = path.join(ROOT, 'launcher', 'app');
const GALLERY = fs.readFileSync(path.join(APP, 'Gallery.cs'), 'utf8');
const SHELL = fs.readFileSync(path.join(APP, 'Shell.cs'), 'utf8');
const XAML = fs.readFileSync(path.join(ROOT, 'launcher', 'ui.xaml'), 'utf8');
const SERVER = fs.readFileSync(path.join(ROOT, 'site', 'server.js'), 'utf8');

let pass = 0, fail = 0;
const yes = (w, c) => {
  if (c) { pass++; console.log('PASS  ' + w); }
  else { fail++; console.log('FAIL  ' + w); }
};

/* A method's body: from its signature to the closing brace at the same indent. */
function body(src, signature) {
  const at = src.indexOf(signature);
  if (at < 0) return '';
  const lineStart = src.lastIndexOf('\n', at) + 1;
  const indent = src.slice(lineStart, at);
  const end = src.indexOf('\n' + indent + '}', at);
  return end < 0 ? '' : src.slice(at, end + indent.length + 2);
}

/* Every C# string literal in a piece of source, joined. */
function literals(src) {
  const out = [];
  const re = /"((?:[^"\\]|\\.)*)"/g;
  let m;
  while ((m = re.exec(src))) out.push(m[1].replace(/\\n/g, '\n').replace(/\\"/g, '"'));
  return out.join('\n');
}

// ---- the site is still the shape the launcher was written against ----------
yes('the site serves POST /api/gallery/report',
    /p === '\/api\/gallery\/report' && req\.method === 'POST'/.test(SERVER));
const reportDoor = SERVER.slice(SERVER.indexOf("p === '/api/gallery/report' && req.method === 'POST'"),
                                SERVER.indexOf("p === '/api/gallery/reports'"));
yes('the report door reads a launcher ticket out of the query',
    /readTicket\(url\.searchParams\.get\('ticket'\)\)/.test(reportDoor));
yes('the report door reads the name and the reason out of the body',
    /o\.name/.test(reportDoor) && /o\.why/.test(reportDoor));
yes('the report door refuses an unknown name with 404',
    /not on the gallery/.test(reportDoor));
yes('the site serves GET /api/gallery/who and answers it to anybody',
    /p === '\/api\/gallery\/who' && req\.method === 'GET'/.test(SERVER));
yes('who hands back signed, canSubmit, staff, admin and name',
    /signed: !!\(w\.id \|\| w\.member\)/.test(SERVER) && /staff: !!w\.dev/.test(SERVER));

// Every staff door, and which of the two gates it is on. Before the site's
// #743 each one read the cookie and nothing else; after it, all six go through
// galleryStaff, which takes the cookie or a staff ticket. Either is a shape
// this repository has really been in, so both pass here and the run says which
// one it read. A door on neither is a door that moved without anybody saying
// so, and that is the failure worth having.
const staffDoors = [
  ["p === '/api/gallery/pending' && req.method === 'GET'", '/api/gallery/pending'],
  ["p === '/api/gallery/approve' && req.method === 'POST'", '/api/gallery/approve'],
  ["p === '/api/gallery/reject' && req.method === 'POST'", '/api/gallery/reject'],
  ["p === '/api/gallery/approved' && req.method === 'DELETE'", '/api/gallery/approved'],
  ["p === '/api/gallery/reports' && req.method === 'GET'", '/api/gallery/reports'],
  ["p === '/api/gallery/report/dismiss' && req.method === 'POST'", '/api/gallery/report/dismiss']
];
const ticketed = /async function galleryStaff\(/.test(SERVER);
console.log('NOTE  site\\server.js has ' + (ticketed
  ? 'galleryStaff, so the staff doors take a launcher ticket (#743)'
  : 'no galleryStaff: the staff doors are still cookie only, so the card\'s staff tools wait on #743'));
for (const [needle, name] of staffDoors) {
  const at = SERVER.indexOf(needle);
  const door = at < 0 ? '' : SERVER.slice(at, at + 400);
  yes(name + ' is there and is staff only, ' +
      (ticketed ? 'through the one galleryStaff gate' : 'by the cookie who(req) reads'),
      at > 0 && (ticketed
        ? /const gs = await galleryStaff\(url, w\);\s*\n\s*if \(!gs\.ok\) return sendJson\(res, gs\.code, gs\.body\);/.test(door)
        : /if \(!w\.dev\) return sendJson\(res, 403/.test(door) &&
          !/searchParams\.get\('ticket'\)/.test(door)));
}
yes('who(req) is the twa cookie, so a browser is one way past that gate and not the launcher\'s way',
    /const ADMIN\s+= 'twa';/.test(SERVER) &&
    /function identity\(req\) \{\s*\n\s*const raw = cookies\(req\)\[ADMIN\] \|\| '';/.test(SERVER));

// ---- what the launcher asks for ---------------------------------------------
const report = body(GALLERY, 'public static string Report(string name, string why)');
yes('Gallery.Report is there', report.length > 0);
yes('it posts to /api/gallery/report', /"\/api\/gallery\/report\?ticket="/.test(report));
yes('the ticket rides in the query, escaped, the way the site reads it',
    /Uri\.EscapeDataString\(Discord\.Ticket\)/.test(report));
yes('the body carries the name and the reason, both escaped for JSON',
    /Discord\.Escape\(name\.Trim\(\)\)/.test(report) && /Discord\.Escape\(reason\)/.test(report));
yes('it goes through Discord.PostJson, the same sender the door uses',
    /Discord\.PostJson\(url, body, out reply\)/.test(report));
yes('a copy that is not linked is told to connect rather than sending nothing',
    /if \(!Discord\.Linked\)/.test(report));
yes('the reason is cut at the 500 the site keeps', /Substring\(0, 500\)/.test(report));
yes('a 200 is the only success, and "" is what it returns', /if \(code == 200\) return "";/.test(report));
yes('the site\'s own words are shown when it refuses',
    /Str\(reply, "error"\)/.test(report) && /Str\(reply, "message"\)/.test(report));
yes('a site that could not be reached says so rather than blaming the person',
    /code == 0/.test(report) && /Could not reach thornswood\.net/.test(report));

const who = body(GALLERY, 'public static Who AskWho()');
yes('Gallery.AskWho asks /api/gallery/who', /"\/api\/gallery\/who"/.test(who));
yes('a site with no such door leaves the answer unanswered',
    /if \(text\.IndexOf\("\\"signed\\"", StringComparison\.Ordinal\) < 0\) return w;/.test(who));

yes('the rotation still reads the public feed and nothing else',
    /Discord\.Site \+ "\/api\/public"/.test(GALLERY));
yes('Manage on the site points at the site page, not at a door',
    /public static string StaffPage \{ get \{ return Discord\.Site \+ "\/uploads"; \} \}/.test(GALLERY));

// ---- the two staff doors the card does not use ------------------------------
// The reports inbox and dismissing a report are staff work about REPORTS, not
// about a picture on the card, and there is nothing on the Play page to show
// them on. They stay at the site; the card's own staff tools are the queue,
// approve, reject and the take down, and tests\test-gallery-staff-card.js is
// where those are checked.
const csFiles = fs.readdirSync(APP).filter(f => f.endsWith('.cs'));
for (const door of ['/api/gallery/reports', '/api/gallery/report/dismiss']) {
  let hits = 0;
  for (const f of csFiles) {
    const src = fs.readFileSync(path.join(APP, f), 'utf8');
    // The report door's own address starts with /api/gallery/report, so the
    // dismiss one is looked for whole and the other is plain.
    hits += (src.split('"' + door).length - 1);
  }
  yes('nothing in the launcher calls ' + door, hits === 0);
}

// ---- the card --------------------------------------------------------------
for (const name of ['BtnGalleryReport', 'BtnGalleryManage', 'GalleryReportRow',
                    'BoxGalleryWhy', 'BtnGalleryReportSend', 'BtnGalleryReportCancel',
                    'TxtGallerySaid']) {
  yes('ui.xaml has ' + name, XAML.indexOf('x:Name="' + name + '"') > 0);
  yes('Shell.cs looks up ' + name, SHELL.indexOf('"' + name + '"') > 0);
}
yes('both buttons start hidden, so a site with no gallery leaves the card as it was',
    /x:Name="BtnGalleryReport"[\s\S]{0,320}?Visibility="Collapsed"/.test(XAML) &&
    /x:Name="BtnGalleryManage"[\s\S]{0,320}?Visibility="Collapsed"/.test(XAML));
yes('the reason box starts hidden too',
    /x:Name="GalleryReportRow"[\s\S]{0,160}?Visibility="Collapsed"/.test(XAML));

yes('Report opens the reason box', /btnGalleryReport\.Click \+= delegate \{ OpenGalleryReport\(\); \}/.test(SHELL));
yes('Send sends it', /btnGalleryReportSend\.Click \+= delegate \{ SendGalleryReport\(\); \}/.test(SHELL));
yes('Cancel closes it', /btnGalleryReportCancel\.Click \+= delegate \{ CloseGalleryReport\(\); \}/.test(SHELL));
yes('Manage on the site opens the site page', /Open\(Gallery\.StaffPage\)/.test(SHELL));

const paint = body(SHELL, 'static void PaintGalleryTools()');
yes('Report shows only once the site has answered and the copy is linked',
    /doors && named && Discord\.Linked/.test(paint));
yes('Manage on the site shows only for staff', /doors && GalleryStaff\(\)/.test(paint));
const staff = body(SHELL, 'static bool GalleryStaff()');
yes('staff is the site\'s word, off the door answer, not decided here',
    /Door\.Last != null && Door\.Last\.Dev/.test(staff) && /Discord\.DevAllowed/.test(staff));
yes('an unlinked copy is never staff', /if \(!Discord\.Linked\) return false;/.test(staff));

const decide = body(SHELL, 'static void GalleryDecide()');
yes('the rotation stands still while a report is being written',
    /!GalleryReportOpen/.test(decide));
const send = body(SHELL, 'static void SendGalleryReport()');
yes('the report is sent off the UI thread', /ThreadPool\.QueueUserWorkItem/.test(send));
yes('it reports the picture the box was opened on, not whatever is up now',
    /Gallery\.Shot shot = galleryReporting;/.test(send));

// ---- the words --------------------------------------------------------------
const words = literals(report) + '\n' + literals(paint) + '\n' + literals(send) + '\n' +
              literals(body(SHELL, 'static void OpenGalleryReport()'));
yes('no "player" in anything the card says', !/\bplayers?\b/i.test(words));
yes('no em or en dash in anything the card says', !/[\u2013\u2014]/.test(words));
yes('Thornswood is spelt Thornswood', !/ThornsWood/.test(words + GALLERY + XAML));
yes('the answer after a report says the picture stays up',
    /the picture stays up until one of them takes it down/.test(literals(send)));

// ---- C# 5 --------------------------------------------------------------------
for (const [name, src] of [['Gallery.Report', report], ['Gallery.AskWho', who],
                           ['PaintGalleryTools', paint], ['SendGalleryReport', send],
                           ['GalleryStaff', staff]]) {
  yes(name + ' is C# 5: no interpolated strings', src.length > 0 && !/\$"/.test(src));
  yes(name + ' is C# 5: no ?.', !/\?\./.test(src));
  yes(name + ' is C# 5: no nameof, no out var', !/\bnameof\s*\(/.test(src) && !/\bout var\b/.test(src));
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
