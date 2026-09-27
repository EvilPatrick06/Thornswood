// test-gallery-ux.js
//
// Public gallery themed like the site, home link + slideshow, staff queue on
// the hub Gallery page. Hub member upload/list/reports UI removed; public
// send form and per-image report stay on /gallery.
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..');
const HOME = path.join(ROOT, 'site', 'public', 'home.html');
const HUB = path.join(ROOT, 'site', 'public', 'index.html');
const CR = String.fromCharCode(13);

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const home = fs.readFileSync(HOME, 'utf8').split(CR).join('');
const hub = fs.readFileSync(HUB, 'utf8').split(CR).join('');

const barA = home.indexOf('<nav class="top" id="nav">');
const barB = home.indexOf('</nav>', barA);
const bar = home.slice(barA, barB);
yes('top bar links to /gallery', /href="\/gallery">Gallery</.test(bar));
yes('footer Community links to /gallery',
    /<h4>Community<\/h4>\s*<a href="\/gallery">Gallery<\/a>/.test(home));

yes('home has gallery slideshow shell', /id="galleryShow"/.test(home));
yes('home has See the gallery link', /See the gallery/.test(home));
yes('landing build starts a rotating slideshow',
    /setInterval\(function \(\) \{ go\(\(i \+ 1\) % shots\.length\); \}, 5000\)/.test(home));
yes('slideshow respects reduced motion',
    /prefers-reduced-motion: reduce/.test(home) &&
    /if \(!reduce && shots\.length > 1\)/.test(home));

yes('gal-box uses stone panel, not iron slab',
    /\.gal-box\{[^}]*background:var\(--stone\)/.test(home));
yes('gal-box heading is gold carve',
    /\.gal-box h2\{[^}]*color:var\(--gold\)/.test(home));

yes('public gallery keeps Send a picture for members',
    /id="galSubmit"/.test(home) && /Send a picture/.test(home));
yes('send form does not show Signed in as',
    !/Signed in as /.test((home.match(/id="galSubmit"[\s\S]{0,900}/) || [''])[0]));
yes('send form hides native file input and offers Choose pictures',
    /\.gal-box \.form input\[type=file\]\{[^}]*clip:rect\(0,0,0,0\)/.test(home) &&
    /id="galPick">Choose pictures</.test(home) &&
    /id="galFileName">No file chosen</.test(home));
yes('chosen list mounts under the drop zone',
    /id="galChosen"/.test(home) &&
    /class="gal-chosen"/.test(home));
yes('chosen list shows thumbnail, filename, size and Remove',
    /gal-chosen-thumb/.test(home) &&
    /gal-chosen-name/.test(home) &&
    /gal-chosen-size/.test(home) &&
    /createObjectURL/.test(home) &&
    /gal-chosen-x/.test(home) &&
    /textContent = 'Remove'/.test(home) &&
    /picked\.splice\(idx, 1\)/.test(home));
yes('chosen list themed charcoal gold',
    /\.gal-box \.form \.gal-chosen-item\{[^}]*background:var\(--iron\)/.test(home) &&
    /\.gal-box \.form \.btn\.gal-chosen-x\{[^}]*color:var\(--gold\)/.test(home));
yes('empty and multi-file labels stay in sync',
    /No file chosen/.test(home) &&
    /files chosen/.test(home) &&
    /picked\.length === 1/.test(home));
yes('send form has a visible dashed drop zone',
    /id="galDrop"/.test(home) &&
    /Drop pictures here or choose files/.test(home) &&
    /\.gal-box \.form \.gal-drop\{[^}]*dashed/.test(home) &&
    /\.gal-box \.form \.gal-drop\.drag\{/.test(home));
yes('Choose pictures button uses gold charcoal theme',
    /\.gal-box \.form \.btn\.gal-pick\{[^}]*border-color:var\(--gold\)/.test(home) &&
    /\.btn\.ghost\{[^}]*background:transparent/.test(home));
yes('file input allows multi-select', /\smultiple[>\s]/.test(
    (home.match(/id="galFile"[^>]*>/) || [''])[0]));
yes('Choose files button opens the hidden input',
    /getElementById\('galPick'\)/.test(home) && /f\.click\(\)/.test(home));
yes('send walks each chosen file in order',
    /picked\.length \? picked\.slice\(\)/.test(home) &&
    /\/api\/gallery\/submit\?name=/.test(home));
yes('submit box accepts drag-and-drop',
    /getElementById\('galDrop'\)/.test(home) &&
    /dataTransfer/.test(home) &&
    /\.gal-box \.form \.gal-drop\.drag\{/.test(home));
yes('By and Note stack as full-width gal-fields with labels above',
    /for="galBy">By</.test(home) &&
    /for="galNote">Note/.test(home) &&
    /\.gal-box \.form \.gal-field\{[^}]*flex-direction:column/.test(home) &&
    !/<label>By<input/.test(home) &&
    !/<label>Note<span class="hint">/.test(home));
yes('By and Note stay inside the themed .form grid',
    /id="galChosen"[\s\S]{0,200}gal-field[\s\S]{0,200}galBy[\s\S]{0,300}galNote[\s\S]{0,200}galSend/.test(home) &&
    !/'<\/div><\/div><\/div>' \+[\s\S]{0,40}<label>By/.test(home));
yes('By and Note inputs use charcoal iron night theme',
    /\.gal-box \.form input\[type=text\]\{[^}]*background:var\(--iron\)/.test(home) &&
    /\.gal-box \.form input\[type=text\]\{[^}]*color-scheme:dark/.test(home) &&
    /\.gal-box \.form input\[type=text\]:focus\{[^}]*border-color:var\(--gold\)/.test(home) &&
    /::placeholder\{[^}]*color:var\(--faint\)/.test(home) &&
    /placeholder="a name for the caption"/.test(home) &&
    /placeholder="a short note for staff"/.test(home));
yes('form gap keeps By Note off the drop zone and Send it',
    /\.gal-box \.form\{gap:22px\}/.test(home));

yes('public gallery keeps per-image Report',
    /data-galreport/.test(home));
yes('public gallery has no Waiting for approval queue',
    !/Waiting for approval/.test(home) && !/gal-pending/.test(home));
yes('public gallery has no Reports inbox',
    !/id="galReports"/.test(home) && !/gal-reports/.test(home));
yes('public gallery has no staff Delete on cards',
    !/data-galdel/.test(home));
yes('public gallery copy says staff tools are not here',
    /Staff queue, approve, reject and delete live on the hub Gallery page/.test(home));

yes('hub Gallery keeps staff queue mount only',
    /id="galqueue"/.test(hub) && !/id="galreports"/.test(hub));
yes('hub Gallery has no member upload drop or uploaded list',
    !/Drop files here/.test(hub) && !/Nothing uploaded yet/.test(hub) && !/function sendAll/.test(hub));
yes('hub Gallery has no open-reports empty state',
    !/No open reports/.test(hub) && !/loadGalleryReports/.test(hub));
yes('hub still calls gallery pending API',
    /\/api\/gallery\/pending/.test(hub));
yes('hub Gallery no longer loads gallery reports API on this page',
    !/\/api\/gallery\/reports/.test(hub));
yes('hub Gallery has no dashed empty-state to public gallery and Inbox',
    !/Approved pictures live on the public/.test(hub) &&
    !/Bug and idea reports go to/.test(hub));
yes('hub Gallery keeps staff approve intro',
    /Staff approve shots waiting for the public gallery/.test(hub));

yes('new gallery copy has no em dash', !/[\u2014\u2013]/.test(
  (home.match(/Send a picture[\s\S]{0,400}/) || [''])[0] +
  (home.match(/gal-show[\s\S]{0,200}/) || [''])[0]
));

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
