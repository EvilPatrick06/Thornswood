'use strict';
/*
  Journals, behind J.

  Patrick, 22 September: "J for Journal... This would open the journal menu,
  which would allow you to have multiple journals with multiple pages, and
  share your journal or specific pages of your journal with friends."

  All four of those are here: more than one journal, pages inside each, sharing
  a whole journal, and sharing one page. Sharing is with a FRIEND and not with
  anybody, which is the server's rule and is refused there rather than hidden
  here, so the refusal says why.

  WHAT SHARING MEANS. It is not a copy. The page stays yours, and the person
  you shared it with reads what it says NOW: correct a page and they see the
  correction. That also means a shared page only shows up while its owner is
  online, which is a real limit and is written on the panel where somebody
  would look for it rather than left to be discovered.

  THE CONTRACT with thornswood-front.js:
    window.thornswoodJournal = { open, close, toggle, isOpen, setData }
    page -> plugin  'journal:ready' | 'journal:opened' | 'journal:closed'

  Everything it does goes out as the ordinary /journal command, the same lines
  a person could type. See the journalCommand note in gamemode.js.
*/
(function () {
  if (window.thornswoodJournal) { return; }

  var ID = 'ts-journal';
  var data = null;
  var shown = false;
  var root = null;
  var openBook = '';     // which journal is being read
  var openPage = '';     // which page inside it
  var editing = false;
  var readingShared = -1;

  function tell(what) {
    try { window.skyrimPlatform.sendMessage('thornswood-front', 'journal:' + what); }
    catch (e) { }
  }

  function net(line) {
    try {
      if (window.thornswoodNet && window.thornswoodNet.say) {
        window.thornswoodNet.say(line);
        return true;
      }
    } catch (e) { }
    return false;
  }

  var CSS = [
    '#' + ID + '{position:fixed;inset:0;z-index:2147483000;display:none;',
    '  background:rgba(6,7,9,.72);font-family:Georgia,serif;color:#e9e7e1}',
    '#' + ID + '.on{display:grid;place-items:center}',
    '#' + ID + ' .panel{width:1040px;max-width:calc(100vw - 48px);height:660px;',
    '  max-height:calc(100vh - 48px);display:grid;grid-template-rows:auto 1fr auto;',
    '  background:#1b1f26;border:2px solid #3a424e;border-radius:12px;',
    '  box-shadow:0 18px 60px rgba(0,0,0,.6);overflow:hidden}',
    '#' + ID + ' h2{margin:0;padding:18px 24px 14px;font-size:24px;font-weight:600;',
    '  border-bottom:1px solid #2b313a}',
    '#' + ID + ' .cols{display:grid;grid-template-columns:280px 1fr;overflow:hidden}',
    '#' + ID + ' .side{overflow:auto;border-right:1px solid #2b313a;padding:14px;',
    '  font-family:system-ui,sans-serif;font-size:13.5px}',
    '#' + ID + ' .main{overflow:auto;padding:16px 22px;font-family:system-ui,sans-serif;font-size:14px}',
    '#' + ID + ' .foot{padding:12px 24px;border-top:1px solid #2b313a;display:flex;gap:10px;',
    '  align-items:center;font-family:system-ui,sans-serif;font-size:13px;color:#98a2ae}',
    '#' + ID + ' h3{margin:14px 0 7px;font-size:11px;letter-spacing:.08em;text-transform:uppercase;',
    '  color:#79828f;font-weight:600}',
    '#' + ID + ' h3:first-child{margin-top:0}',
    '#' + ID + ' .item{display:block;width:100%;text-align:left;margin-bottom:5px;',
    '  padding:7px 9px;border:1px solid #2b313a;border-radius:7px;background:#212630;',
    '  color:#e9e7e1;font:inherit;cursor:pointer}',
    '#' + ID + ' .item:hover{border-color:#d9ab52}',
    '#' + ID + ' .item.sel{border-color:#d9ab52;color:#d9ab52}',
    '#' + ID + ' .item .c{float:right;color:#79828f;font-size:12px}',
    '#' + ID + ' button{font:inherit;cursor:pointer;border-radius:7px;border:1px solid #3a424e;',
    '  background:#1b1f26;color:#e9e7e1;padding:5px 11px;font-size:13px}',
    '#' + ID + ' button:hover{border-color:#d9ab52;color:#d9ab52}',
    '#' + ID + ' button.go{background:#d9ab52;border-color:#d9ab52;color:#1a1500;font-weight:600}',
    '#' + ID + ' input,#' + ID + ' textarea,#' + ID + ' select{font:inherit;color:#e9e7e1;',
    '  background:#13161b;border:1px solid #3a424e;border-radius:7px;padding:8px 10px;width:100%}',
    '#' + ID + ' textarea{min-height:300px;resize:vertical;line-height:1.55;font-family:Georgia,serif;font-size:15px}',
    '#' + ID + ' .bar{display:flex;gap:8px;align-items:center;margin-bottom:12px;flex-wrap:wrap}',
    '#' + ID + ' .bar .grow{flex:1}',
    '#' + ID + ' .none{color:#79828f;padding:8px 2px;line-height:1.55}',
    '#' + ID + ' .read{white-space:pre-wrap;line-height:1.6;font-family:Georgia,serif;font-size:15px}',
    '#' + ID + ' .from{color:#79828f;font-size:12.5px;margin-bottom:10px}'
  ].join('\n');

  function build() {
    if (root) { return root; }
    var style = document.createElement('style');
    style.textContent = CSS;
    document.head.appendChild(style);
    root = document.createElement('div');
    root.id = ID;
    root.innerHTML =
      '<div class="panel">' +
      '<h2>Journals</h2>' +
      '<div class="cols">' +
      '<div class="side" id="' + ID + '-side"></div>' +
      '<div class="main" id="' + ID + '-main"></div>' +
      '</div>' +
      '<div class="foot"><span id="' + ID + '-foot"></span><span style="flex:1"></span>' +
      '<button id="' + ID + '-close">Close</button></div>' +
      '</div>';
    document.body.appendChild(root);
    root.querySelector('#' + ID + '-close').onclick = close;
    // The page answers its own Escape; no plugin can see a key while the
    // browser holds the keyboard. See thornswood-bridge.js.
    document.addEventListener('keydown', function (ev) {
      if (!shown) { return; }
      if (ev.key === 'Escape') { ev.preventDefault(); close(); }
    });
    return root;
  }

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function books() { return (data && data.journals) || []; }
  function bookOf(id) {
    var b = books();
    for (var i = 0; i < b.length; i++) { if (b[i].id === id) { return b[i]; } }
    return null;
  }
  function pageOf(book, id) {
    var p = (book && book.pages) || [];
    for (var i = 0; i < p.length; i++) { if (p[i].id === id) { return p[i]; } }
    return null;
  }

  function drawSide() {
    var side = root.querySelector('#' + ID + '-side');
    var html = '<h3>Yours</h3>';
    var b = books();
    if (!b.length) {
      html += '<div class="none">Nothing yet.</div>';
    } else {
      for (var i = 0; i < b.length; i++) {
        html += '<button class="item' + (b[i].id === openBook && readingShared < 0 ? ' sel' : '') +
                '" data-book="' + esc(b[i].id) + '">' + esc(b[i].title) +
                '<span class="c">' + b[i].pages.length + '</span></button>';
      }
    }
    html += '<button class="item go" data-new="1" style="margin-top:8px">New journal</button>';

    var shared = (data && data.shared) || [];
    html += '<h3>Shared with you</h3>';
    if (!shared.length) {
      html += '<div class="none">Nothing. A page only shows here while the person who wrote it is online.</div>';
    } else {
      for (var j = 0; j < shared.length; j++) {
        html += '<button class="item' + (readingShared === j ? ' sel' : '') +
                '" data-shared="' + j + '">' + esc(shared[j].title) +
                '<span class="c">' + shared[j].pages.length + '</span>' +
                '<div style="color:#79828f;font-size:12px">from ' + esc(shared[j].from) + '</div></button>';
      }
    }
    side.innerHTML = html;

    var items = side.querySelectorAll('button[data-book],button[data-new],button[data-shared]');
    for (var k = 0; k < items.length; k++) {
      items[k].onclick = function () {
        if (this.getAttribute('data-new')) {
          /*
            No window.prompt. A browser modal inside the game is a dialog
            nothing can dismiss: the page owns the keyboard while it is up and
            no plugin can reach it. So a journal is made with a plain name and
            renamed on the panel, which is one more click and cannot strand
            anybody.
          */
          net('/journal new Journal');
          return;
        }
        if (this.getAttribute('data-shared') !== null) {
          readingShared = Number(this.getAttribute('data-shared'));
          openBook = ''; openPage = ''; editing = false;
          draw();
          return;
        }
        openBook = this.getAttribute('data-book');
        readingShared = -1;
        openPage = '';
        editing = false;
        draw();
      };
    }
  }

  function drawMain() {
    var main = root.querySelector('#' + ID + '-main');

    if (readingShared >= 0) {
      var sh = ((data && data.shared) || [])[readingShared];
      if (!sh) { main.innerHTML = '<div class="none">Gone.</div>'; return; }
      var out = '<div class="from">' + esc(sh.title) + ', from ' + esc(sh.from) +
                (sh.whole ? ' (the whole journal)' : ' (shared pages)') + '</div>';
      for (var i = 0; i < sh.pages.length; i++) {
        out += '<div style="margin-bottom:22px"><b>' + esc(sh.pages[i].title) + '</b>' +
               '<div class="read">' + esc(sh.pages[i].text) + '</div></div>';
      }
      main.innerHTML = out;
      return;
    }

    var book = bookOf(openBook);
    if (!book) {
      main.innerHTML = '<div class="none">Pick a journal on the left, or start one.</div>';
      return;
    }

    var friends = ((data && data.friends) || []).filter(function (f) { return true; });
    var pick = '<select id="' + ID + '-who"><option value="">a friend...</option>';
    for (var f = 0; f < friends.length; f++) {
      pick += '<option value="' + esc(friends[f].name) + '">' + esc(friends[f].name) + '</option>';
    }
    pick += '</select>';

    var html =
      '<div class="bar">' +
      '<input id="' + ID + '-title" value="' + esc(book.title) + '" style="max-width:280px">' +
      '<button data-do="rename">Rename</button>' +
      '<span class="grow"></span>' +
      '<span style="color:#79828f;font-size:12.5px">share</span>' +
      pick +
      '<button data-do="sharebook">Whole journal</button>' +
      '<button data-do="unsharebook">Stop</button>' +
      '<button data-do="dropbook">Throw away</button>' +
      '</div>';

    html += '<div class="bar">';
    for (var p = 0; p < book.pages.length; p++) {
      html += '<button data-page="' + esc(book.pages[p].id) + '"' +
              (book.pages[p].id === openPage ? ' class="go"' : '') + '>' +
              esc(book.pages[p].title) + '</button>';
    }
    html += '<button class="go" data-do="newpage">New page</button></div>';

    var page = pageOf(book, openPage);
    if (!page) {
      html += '<div class="none">' + (book.pages.length ? 'Pick a page.' : 'No pages yet.') + '</div>';
    } else {
      html +=
        '<div class="bar">' +
        '<input id="' + ID + '-ptitle" value="' + esc(page.title) + '" style="max-width:320px">' +
        '<span class="grow"></span>' +
        '<button data-do="sharepage">Share this page</button>' +
        '<button data-do="unsharepage">Stop sharing it</button>' +
        '<button class="go" data-do="save">Save</button>' +
        '</div>' +
        '<textarea id="' + ID + '-text">' + esc(page.text || '') + '</textarea>';
    }

    main.innerHTML = html;

    var pages = main.querySelectorAll('button[data-page]');
    for (var q = 0; q < pages.length; q++) {
      pages[q].onclick = function () {
        openPage = this.getAttribute('data-page');
        draw();
      };
    }
    var acts = main.querySelectorAll('button[data-do]');
    for (var r = 0; r < acts.length; r++) {
      acts[r].onclick = function () { act(this.getAttribute('data-do'), book); };
    }
  }

  function val(id) {
    var el = root.querySelector('#' + ID + '-' + id);
    return el ? String(el.value || '') : '';
  }

  function act(verb, book) {
    var who = val('who');
    if (verb === 'rename') {
      net('/journal title ' + book.id + ' ' + val('title'));
      return;
    }
    if (verb === 'newpage') {
      net('/journal page ' + book.id + ' - New page :: ');
      return;
    }
    if (verb === 'save') {
      /*
        NEWLINES ARE FLATTENED BECAUSE THE CHANNEL IS LINE BASED. The chat
        socket carries one line at a time, so a page with paragraphs in it
        would arrive as several commands and the second would be nonsense.
        They go over as \\n and the server never sees a raw newline.
      */
      var text = val('text').split('\n').join('\\n');
      net('/journal page ' + book.id + ' ' + (openPage || '-') + ' ' + val('ptitle') + ' :: ' + text);
      return;
    }
    if (verb === 'dropbook') { net('/journal drop ' + book.id); openBook = ''; return; }
    if (verb === 'sharebook') {
      if (!who) { return; }
      net('/journal share ' + book.id + ' - ' + who);
      return;
    }
    if (verb === 'unsharebook') { net('/journal unshare ' + book.id + ' -'); return; }
    if (verb === 'sharepage') {
      if (!who || !openPage) { return; }
      net('/journal share ' + book.id + ' ' + openPage + ' ' + who);
      return;
    }
    if (verb === 'unsharepage') {
      if (!openPage) { return; }
      net('/journal unshare ' + book.id + ' ' + openPage);
    }
  }

  function draw() {
    if (!root || !shown) { return; }
    drawSide();
    drawMain();
    var foot = root.querySelector('#' + ID + '-foot');
    foot.textContent = 'Escape or J closes this. Sharing needs them to be a friend.';
  }

  function open() {
    build();
    if (shown) { return; }
    shown = true;
    root.className = 'on';
    draw();
    tell('opened');
  }

  function close() {
    if (!shown) { return; }
    shown = false;
    if (root) { root.className = ''; }
    tell('closed');
  }

  function toggle() { if (shown) { close(); } else { open(); } }

  window.thornswoodJournal = {
    open: open,
    close: close,
    toggle: toggle,
    isOpen: function () { return shown; },
    setData: function (d) {
      data = d || null;
      /*
        Redrawn on every push, and that is a real cost: typing into a page and
        having a friend log in would otherwise rebuild the textarea under the
        cursor. So a draw that would replace the text box leaves it alone
        while it has focus.
      */
      if (!shown) { return; }
      var el = root && root.querySelector('#' + ID + '-text');
      if (el && document.activeElement === el) { drawSide(); return; }
      draw();
    }
  };

  build();
  tell('ready');
})();
