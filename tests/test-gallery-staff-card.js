/*
  test-gallery-staff-card.js

      node .\tests\test-gallery-staff-card.js

  The staff half of the Play page's gallery card (#731): the queue, Approve,
  Reject and taking the picture on the card off the gallery, all four over this
  copy's own signed ticket.

  WHY THIS EXISTS. Report shipped first (#739) because /api/gallery/report
  already read a launcher ticket out of the query, while the six staff doors
  read who(req), the twa cookie a browser gets at /auth/discord/callback, and
  the launcher holds no cookie. tests\test-gallery-report.js held those six to
  cookie only so that the day one grew a ticket path somebody would notice.

  The site's #743 is that day: one gate, galleryStaff, in front of all six,
  which takes the cookie OR a ticket whose Discord account holds a staff role
  (st.dev). This harness is the launcher end of that gate.

  IT PASSES ON A CHECKOUT WITHOUT #743 TOO, AND SAYS SO. The launcher change
  and the site change are two lanes and two pull requests, so this reads
  site\server.js, works out which of the two shapes it is on, and checks the
  card against that shape:

    - with galleryStaff: every door the card uses goes through it, the gate
      reads the ticket out of the query and asks st.dev of it, and it answers
      the refusals the card's own words are written against;
    - without it: the doors are still cookie only, and what is checked is that
      the card tells the truth about that. A site older than the gate answers
      403 {"error":"staff only"} with no why in it, and Gallery.Trouble names
      that one shape as an old site rather than blaming the account.

  So a Dev Ship of this card wants #743 on the live site (and Deploy-Docs run)
  before the staff buttons do anything but say that. The checks below are what
  hold the launcher to the API either way.

  The launcher cannot be started from here (CLAUDE.md), so this reads the
  source, the window and site\server.js. Read only.
*/
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const APP = path.join(ROOT, 'launcher', 'app');
const GALLERY = fs.readFileSync(path.join(APP, 'Gallery.cs'), 'utf8');
const DISCORD = fs.readFileSync(path.join(APP, 'Discord.cs'), 'utf8');
const SHELL = fs.readFileSync(path.join(APP, 'Shell.cs'), 'utf8');
const XAML = fs.readFileSync(path.join(ROOT, 'launcher', 'ui.xaml'), 'utf8');
const SERVER = fs.readFileSync(path.join(ROOT, 'site', 'server.js'), 'utf8');

let pass = 0, fail = 0;
const yes = (w, c) => {
  if (c) { pass++; console.log('PASS  ' + w); }
  else { fail++; console.log('FAIL  ' + w); }
};
const note = (m) => console.log('NOTE  ' + m);

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

/* One door out of site\server.js, from its route line to the next route. */
function door(needle) {
  const at = SERVER.indexOf(needle);
  if (at < 0) return '';
  const next = SERVER.indexOf("\n  if (p === '", at + needle.length);
  return SERVER.slice(at, next < 0 ? at + 1200 : next);
}

// ---- which shape the site is on ---------------------------------------------
const ticketed = /async function galleryStaff\(/.test(SERVER);
note(ticketed
  ? 'site\\server.js has galleryStaff (#743): the staff doors take a launcher ticket'
  : 'site\\server.js has no galleryStaff yet: the staff doors are cookie only until #743 is on main, and the card says so');

// ---- the doors the card uses, whichever shape they are on -------------------
const doors = [
  ["p === '/api/gallery/pending' && req.method === 'GET'", '/api/gallery/pending', 'GET'],
  ["p === '/api/gallery/approve' && req.method === 'POST'", '/api/gallery/approve', 'POST'],
  ["p === '/api/gallery/reject' && req.method === 'POST'", '/api/gallery/reject', 'POST'],
  ["p === '/api/gallery/approved' && req.method === 'DELETE'", '/api/gallery/approved', 'DELETE']
];
for (const [needle, name, method] of doors) {
  const d = door(needle);
  yes('the site serves ' + method + ' ' + name, d.length > 0);
  yes(name + ' is staff only, ' + (ticketed ? 'through galleryStaff' : 'by the cookie who(req) reads'),
      ticketed
        ? /const gs = await galleryStaff\(url, w\);/.test(d)
        : /if \(!w\.dev\) return sendJson\(res, 403, \{ error: 'staff only' \}\);/.test(d));
}
yes('the queue door hands back a pending list',
    /return sendJson\(res, 200, \{ pending: jsonFile\(GPENDING, \[\]\) \}\);/.test(door(doors[0][0])));
for (const [needle, name] of doors.slice(1)) {
  yes(name + ' reads the name out of the body', /const name = String\(o\.name \|\| ''\);/.test(door(needle)));
}
yes('reject and the delete of an approved shot only touch the file when asked to',
    /if \(o\.deleteFile\)/.test(door(doors[2][0])) && /if \(o\.deleteFile\)/.test(door(doors[3][0])));
yes('the delete of an approved shot drops the reports against that name too',
    /const kept = reports\.filter\(\(r\) => String\(r\.name\) !== name\);/.test(door(doors[3][0])));
yes('a queue entry carries the name, who by, the note, when and where it came from',
    /const entry = \{ name: name, by: by, note: note, at: Date\.now\(\), from: from \};/.test(SERVER));

if (ticketed) {
  const gate = body(SERVER, 'async function galleryStaff(url, w) {');
  yes('galleryStaff takes the hub cookie as one way in', /if \(w\.dev\) return \{ ok: true/.test(gate));
  yes('galleryStaff reads a launcher ticket out of the query as the other',
      /readTicket\(url\.searchParams\.get\('ticket'\)\)/.test(gate));
  yes('it asks st.dev of that ticket, not st.play', /if \(!st\.dev\)/.test(gate) && !/st\.play/.test(gate));
  yes('it names why on every refusal it means',
      /why: 'role'/.test(gate) && /why: 'guild'/.test(gate) && /why: 'banned'/.test(gate));
  yes('a Discord it could not ask is 503, not a refusal', /return \{ ok: false, code: 503/.test(gate));
  yes('neither cookie nor ticket is still the flat staff only, with no why in it',
      /if \(!t\) return \{ ok: false, code: 403, body: \{ error: 'staff only' \} \};/.test(gate));
} else {
  note('galleryStaff checks skipped: they are in tests\\test-hub-staff-gallery.js on the site branch');
  yes('the card is written against that: Gallery.Trouble names the flat staff only as an old site',
      /code == 403 && Str\(reply, "why"\)\.Length == 0/.test(GALLERY) &&
      /Str\(reply, "error"\) == "staff only"/.test(GALLERY));
}

// ---- the picture still waiting cannot be shown from here --------------------
// The card says so out loud, so this checks the claim is true rather than
// letting it rot into a lie: /up is the only door that serves a shot that is
// not approved yet, and it takes the hub member cookie.
yes('the only door that serves a waiting picture takes the hub member cookie',
    /const up = p\.match\(\/\^\\\/up\\\/\(\[A-Za-z0-9\._ -\]\+\)\$\/\);[\s\S]{0,200}?if \(!w\.member\)/.test(SERVER));

// ---- what the launcher sends ------------------------------------------------
const queue = body(GALLERY, 'public static List<Pending> Queue(out string bad)');
yes('Gallery.Queue is there', queue.length > 0);
yes('it asks /api/gallery/pending with GET', /Ask\("GET", "\/api\/gallery\/pending", null, out reply\)/.test(queue));
yes('a copy that is not linked is told to connect rather than asking with no ticket',
    /if \(!Discord\.Linked\)/.test(queue));
yes('only the pending array is read, not any name elsewhere in the document',
    /ArrayField\(reply, "pending"\)/.test(queue));
yes('each entry keeps the name, who by, the note, where from and when',
    /p\.Name = Str\(body, "name"\)/.test(queue) && /p\.By = Str\(body, "by"\)/.test(queue) &&
    /p\.Note = Str\(body, "note"\)/.test(queue) && /p\.From = Str\(body, "from"\)/.test(queue) &&
    /p\.When = Moment\(Num\(body, "at"\)\)/.test(queue));
yes('an entry with no name is skipped rather than shown as a blank row',
    /if \(p\.Name\.Length == 0\) continue;/.test(queue));
yes('a site that would not answer is a sentence to show, not an empty queue pretending nothing is waiting',
    /bad = Trouble\(code, reply, "read the gallery queue"\)/.test(queue));

const calls = [
  ['Approve', 'public static string Approve(string name)', 'POST', '/api/gallery/approve'],
  ['Reject', 'public static string Reject(string name)', 'POST', '/api/gallery/reject'],
  ['TakeDown', 'public static string TakeDown(string name)', 'DELETE', '/api/gallery/approved']
];
for (const [name, sig, method, url] of calls) {
  const m = body(GALLERY, sig);
  yes('Gallery.' + name + ' is there', m.length > 0);
  yes('Gallery.' + name + ' calls ' + method + ' ' + url,
      new RegExp('Staff\\("' + method + '", "' + url.replace(/\//g, '\\/') + '"').test(m));
}

const staffSend = body(GALLERY, 'static string Staff(string method, string door, string name, string what)');
yes('one sender for all three, so they cannot drift apart', staffSend.length > 0);
yes('the body is the name and nothing else, escaped for JSON',
    /"\{\\"name\\":\\"" \+ Discord\.Escape\(name\.Trim\(\)\) \+ "\\"\}"/.test(staffSend));
yes('nothing here sends deleteFile, so no file is deleted from a card button',
    !/\\"deleteFile/.test(GALLERY));
yes('a 200 is the only success, and "" is what it returns', /if \(code == 200\) return "";/.test(staffSend));
yes('a copy that is not linked never sends', /if \(!Discord\.Linked\) return NotLinked;/.test(staffSend));

const ask = body(GALLERY, 'static int Ask(string method, string door, string body, out string reply)');
yes('the ticket rides in the query, escaped, the way Report sends its own',
    /Uri\.EscapeDataString\(Discord\.Ticket\)/.test(ask));
yes('it goes through Discord.Send, the one sender in the launcher',
    /Discord\.Send\(method, url, body, out reply\)/.test(ask));
yes('a throw on the way out is written down, not swallowed', /Swallow\.Note\("Gallery\.Ask/.test(ask));

const send = body(DISCORD, 'public static int Send(string method, string url, string json, out string reply)');
yes('Discord.Send is there and takes the method', send.length > 0 && /req\.Method = method;/.test(send));
yes('a call with no body sends none, so the GET is a plain GET', /if \(json != null\)/.test(send));
yes('a refusal is read as an answer, with whatever the site said in it',
    /catch \(WebException we\)/.test(send) && /return \(int\)res\.StatusCode;/.test(send));
yes('PostJson is the same sender, so Report and the staff tools cannot drift apart',
    /return Send\("POST", url, json, out reply\);/.test(body(DISCORD, 'public static int PostJson(string url, string json, out string reply)')));

const trouble = body(GALLERY, 'static string Trouble(int code, string reply, string what)');
yes('a site that could not be reached says so rather than blaming the account',
    /if \(code == 0\) return "Could not reach thornswood\.net to " \+ what/.test(trouble));
yes('a site older than the gate is named as an old site, not as a refusal',
    /does not take staff work from the launcher yet/.test(trouble));
yes('every other refusal shows the site\'s own words first',
    /Str\(reply, "error"\)/.test(trouble) && /Str\(reply, "message"\)/.test(trouble));

// ---- the card ---------------------------------------------------------------
for (const name of ['BtnGalleryQueue', 'BtnGalleryTakeDown', 'GalleryQueueRow', 'TxtGalleryQueue',
                    'BtnGalleryApprove', 'BtnGalleryReject', 'BtnGalleryQueueNext',
                    'BtnGalleryQueueClose', 'GalleryTakeDownRow', 'BtnGalleryTakeDownYes',
                    'BtnGalleryTakeDownNo']) {
  yes('ui.xaml has ' + name, XAML.indexOf('x:Name="' + name + '"') > 0);
  yes('Shell.cs looks up ' + name, SHELL.indexOf('"' + name + '"') > 0);
}
yes('the staff buttons start hidden, so nobody else ever sees them flash',
    /x:Name="BtnGalleryQueue"[\s\S]{0,320}?Visibility="Collapsed"/.test(XAML) &&
    /x:Name="BtnGalleryTakeDown"[\s\S]{0,320}?Visibility="Collapsed"/.test(XAML));
yes('both staff rows start hidden too',
    /x:Name="GalleryQueueRow"[\s\S]{0,200}?Visibility="Collapsed"/.test(XAML) &&
    /x:Name="GalleryTakeDownRow"[\s\S]{0,200}?Visibility="Collapsed"/.test(XAML));
yes('Report and the way to the site are still on the card',
    XAML.indexOf('x:Name="BtnGalleryReport"') > 0 && XAML.indexOf('x:Name="BtnGalleryManage"') > 0);

yes('Queue opens the queue', /btnGalleryQueue\.Click \+= delegate \{ OpenGalleryQueue\(\); \}/.test(SHELL));
yes('Approve and Reject answer the one the row is on',
    /btnGalleryApprove\.Click \+= delegate \{ AnswerGalleryQueue\(true\); \}/.test(SHELL) &&
    /btnGalleryReject\.Click \+= delegate \{ AnswerGalleryQueue\(false\); \}/.test(SHELL));
yes('Next turns to the next one waiting', /btnGalleryQueueNext\.Click \+= delegate \{ NextInGalleryQueue\(\); \}/.test(SHELL));
yes('Close shuts the queue', /btnGalleryQueueClose\.Click \+= delegate \{ CloseGalleryQueue\(\); \}/.test(SHELL));
yes('Take this down asks first', /btnGalleryTakeDown\.Click \+= delegate \{ OpenGalleryTakeDown\(\); \}/.test(SHELL));
yes('and only the second button does it',
    /btnGalleryTakeDownYes\.Click \+= delegate \{ TakeGalleryShotDown\(\); \}/.test(SHELL) &&
    /btnGalleryTakeDownNo\.Click \+= delegate \{ CloseGalleryTakeDown\(\); \}/.test(SHELL));
yes('On the site still opens the site page', /Open\(Gallery\.StaffPage\)/.test(SHELL));

const paint = body(SHELL, 'static void PaintGalleryTools()');
yes('the staff buttons are staff only', /bool staff = doors && GalleryStaff\(\);/.test(paint));
yes('Queue is staff and nothing else', /btnGalleryQueue\.Visibility = \(staff && quiet\)/.test(paint));
yes('Take this down wants a picture on the card as well as staff',
    /btnGalleryTakeDown\.Visibility = \(staff && named && quiet\)/.test(paint));
yes('every button goes while a row is open, so the card asks one thing at a time',
    /bool quiet = !GalleryReportOpen && !GalleryQueueOpen && !GalleryTakeDownOpen;/.test(paint));

const open = body(SHELL, 'static void OpenGalleryQueue()');
yes('the queue is not opened by anybody the site would refuse', /if \(!GalleryStaff\(\)\) return;/.test(open));
yes('opening the queue closes the other two rows',
    /CloseGalleryReport\(\);/.test(open) && /CloseGalleryTakeDown\(\);/.test(open));
yes('the site is asked off the UI thread', /ThreadPool\.QueueUserWorkItem/.test(open));
yes('a queue closed while the site was being asked drops the answer',
    /if \(!GalleryQueueOpen\) return;/.test(open));
yes('an empty queue says nothing is waiting rather than showing a blank row',
    /Nothing is waiting for the gallery/.test(open));

const answer = body(SHELL, 'static void AnswerGalleryQueue(bool approve)');
yes('Approve and Reject go off the UI thread too', /ThreadPool\.QueueUserWorkItem/.test(answer));
yes('a second press while one is in the air does nothing',
    /if \(one == null \|\| galleryQueueBusy\) return;/.test(answer));
yes('it answers the one the row was on, not whatever the queue holds by then',
    /string name = one\.Name;/.test(answer));
yes('a refusal leaves it in the queue and says why',
    /if \(bad\.Length > 0\) \{ SayGallery\(bad\); PaintGalleryQueue\(\); return; \}/.test(answer));
yes('what the site took is off the queue and off the number on the button',
    /DropFromQueue\(name\);/.test(answer));
yes('an approved picture is what the card turns to, so staff see what went up',
    /ReloadGalleryShots\(name\);/.test(answer));

const takeOpen = body(SHELL, 'static void OpenGalleryTakeDown()');
yes('the take down is staff only as well', /if \(!GalleryStaff\(\)\) return;/.test(takeOpen));
yes('the question names the picture it is about', /SayGallery\("Take " \+ shot\.Name/.test(takeOpen));
const take = body(SHELL, 'static void TakeGalleryShotDown()');
yes('it takes down the picture the question was asked about, not whatever is up now',
    /Gallery\.Shot shot = galleryTakingDown;/.test(take));
yes('the take down goes off the UI thread', /ThreadPool\.QueueUserWorkItem/.test(take));
yes('a refusal leaves the picture on the card and says why',
    /if \(bad\.Length > 0\) \{ SayGallery\(bad\); return; \}/.test(take));
yes('what the site took down leaves the rotation without asking the feed again',
    /DropShot\(name\);/.test(take));

const drop = body(SHELL, 'static void DropShot(string name)');
yes('the card turns to the next one after a take down', /ShowNextShot\(\);/.test(drop));
yes('with none left the card goes back to hidden', /ShowEmptyGallery\(\);/.test(drop));

const decide = body(SHELL, 'static void GalleryDecide()');
yes('the rotation stands still while the queue or the question is open',
    /!GalleryReportOpen && !GalleryQueueOpen && !GalleryTakeDownOpen/.test(decide));

const start = body(SHELL, 'static void StartGallery()');
yes('the queue is counted at start up for staff only', /if \(GalleryStaff\(\)\)/.test(start));
yes('a site that will not answer that leaves the button saying Queue and nothing said',
    /if \(bad\.Length == 0\) waiting = queue\.Count;/.test(start));
const count = body(SHELL, 'static void PaintQueueCount()');
yes('the number waiting is on the button itself', /"Queue \(" \+ galleryQueueCount \+ "\)"/.test(count));

const empty = body(SHELL, 'static void ShowEmptyGallery()');
yes('an empty gallery still gives staff the card when something is waiting for it',
    /bool show = galleryQueueCount > 0 && GalleryStaff\(\);/.test(empty));

// ---- the words ---------------------------------------------------------------
const cardWords = literals(open) + '\n' + literals(answer) + '\n' + literals(take) + '\n' +
                  literals(takeOpen) + '\n' + literals(body(SHELL, 'static void PaintGalleryQueue()')) + '\n' +
                  literals(empty) + '\n' + literals(trouble) + '\n' + literals(staffSend) + '\n' +
                  literals(queue);
yes('no "player" in anything the staff tools say', !/\bplayers?\b/i.test(cardWords));
yes('no em or en dash in anything the staff tools say', !/[\u2013\u2014]/.test(cardWords));
yes('no em or en dash in the new source or the card',
    !/[\u2013\u2014]/.test(GALLERY) && !/[\u2013\u2014]/.test(XAML));
yes('Thornswood is spelt Thornswood', !/ThornsWood/.test(GALLERY + SHELL + XAML));
yes('the card says the waiting picture is looked at on the site rather than pretending to show it',
    /The picture itself opens on the site/.test(literals(body(SHELL, 'static void PaintGalleryQueue()'))));

// ---- C# 5 ---------------------------------------------------------------------
for (const [name, src] of [['Gallery.Queue', queue], ['Gallery.Staff', staffSend],
                           ['Gallery.Ask', ask], ['Gallery.Trouble', trouble],
                           ['Discord.Send', send], ['OpenGalleryQueue', open],
                           ['AnswerGalleryQueue', answer], ['TakeGalleryShotDown', take],
                           ['DropShot', drop], ['PaintGalleryTools', paint]]) {
  yes(name + ' is C# 5: no interpolated strings', src.length > 0 && !/\$"/.test(src));
  yes(name + ' is C# 5: no ?. and no ?? on a call', !/\?\./.test(src));
  yes(name + ' is C# 5: no nameof, no out var, no expression body',
      !/\bnameof\s*\(/.test(src) && !/\bout var\b/.test(src) && !/\)\s*=>\s*[^{]/.test(src.split('\n')[0]));
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
