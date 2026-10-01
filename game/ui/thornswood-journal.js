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

  /*
    THE LOOK IS THE K PANEL'S. Patrick, 23 September, playing on dev: "Also
    the journal menu works but is ugly asf and doesn't match the theme we use
    with our other menus". It had been drawn from another template: system-ui
    sans serif, rounded 12px and 7px corners, flat grey #1b1f26 and a brass
    #d9ab52, which is the To Do List web page's palette and not the game's.
    Every colour below is one thornswood-skills.js already uses, and the rest
    follows it too: the Palatino stack (fonts on the machine, never one off
    the network, because this is the game's own browser), parchment text,
    gold hairlines, square corners, the dark vignette behind the panel,
    uppercase gold buttons with one gold primary, and gold scrollbars.
    tools/test-journal-theme.js fails on a colour here that the K panel does
    not use.

    Only the look changed. The grid, the sizes, the ids and classes the
    script reads and every line it sends are as they were.

    No :hover and no transitions, for the reason the K panel has none (see
    the head of thornswood-skills.js). The journal and page you picked are
    lit by the click, and the cursor still turns into a hand.

    The front's own stylesheet, in this same document, sets margin, padding,
    border and background to nothing on every element (measured in its
    build.js on 24 September), so each rule sets what it needs rather than
    leaning on the browser's defaults.
  */
  var CSS = [
    '#' + ID + '{position:fixed;inset:0;z-index:2147483000;display:none;',
    '  background:radial-gradient(ellipse at center,rgba(0,0,0,.50) 0%,rgba(0,0,0,.72) 100%);',
    '  font-family:"Palatino Linotype",Palatino,Georgia,serif;color:#d9cfb4}',
    '#' + ID + '.on{display:grid;place-items:center}',
    '#' + ID + ' .panel{width:1040px;max-width:calc(100vw - 48px);height:660px;',
    '  max-height:calc(100vh - 48px);display:grid;grid-template-rows:auto 1fr auto;',
    '  background:rgba(11,10,8,.94);border:1px solid rgba(198,170,109,.42);',
    '  outline:1px solid rgba(198,170,109,.14);outline-offset:4px;',
    '  box-shadow:0 24px 80px rgba(0,0,0,.7);overflow:hidden}',
    '#' + ID + ' h2{margin:0;padding:18px 24px 14px;font-size:26px;font-weight:normal;line-height:1.1;',
    '  color:#f6e9c8;border-bottom:1px solid rgba(198,170,109,.22)}',
    '#' + ID + ' .cols{display:grid;grid-template-columns:280px 1fr;overflow:hidden}',
    '#' + ID + ' .side{overflow:auto;border-right:1px solid rgba(198,170,109,.22);padding:16px 14px;',
    '  font-size:15px}',
    '#' + ID + ' .main{overflow:auto;padding:18px 24px;font-size:17px}',
    '#' + ID + ' .foot{padding:12px 24px;border-top:1px solid rgba(198,170,109,.22);display:flex;gap:10px;',
    '  align-items:center;font-size:13.5px;font-style:italic;color:rgba(217,207,180,.7)}',
    '#' + ID + ' h3{margin:14px 0 7px;padding-bottom:6px;font-size:11.5px;letter-spacing:.24em;text-transform:uppercase;',
    '  color:rgba(198,170,109,.85);font-weight:normal;border-bottom:1px solid rgba(198,170,109,.22)}',
    '#' + ID + ' h3:first-child{margin-top:0}',
    // The K panel's button at 11px rather than its 13px. Uppercase and spaced
    // is wider than the old buttons were, and at 12px Save no longer fit on
    // the line with the page's title and went onto one of its own, pushing
    // the text box down (measured in Edge at 1920 by 1080, 24 September).
    '#' + ID + ' button{font-family:inherit;font-style:normal;font-weight:normal;cursor:pointer;',
    '  border:1px solid rgba(198,170,109,.55);background:rgba(0,0,0,.25);color:#e9d19b;',
    '  padding:6px 12px;font-size:14px;line-height:18px;letter-spacing:.14em;text-transform:uppercase;white-space:nowrap}',
    '#' + ID + ' button.go{background:#c6aa6d;border-color:#e9d19b;color:#1b1205}',
    // A journal in the list and a page tab are names rather than actions, so
    // they read as the K panel's cards and choices do, not as its buttons.
    '#' + ID + ' .item{display:block;width:100%;text-align:left;margin-bottom:6px;',
    '  padding:9px 12px;border:1px solid rgba(198,170,109,.30);background:rgba(0,0,0,.20);',
    '  color:#f6e9c8;font-size:15px;letter-spacing:.02em;text-transform:none;white-space:normal}',
    '#' + ID + ' .item.sel{border-color:rgba(198,170,109,.55);background:rgba(120,94,44,.24);',
    '  box-shadow:inset 3px 0 0 0 #c6aa6d}',
    '#' + ID + ' .item.go{text-align:center;font-size:11px;letter-spacing:.14em;text-transform:uppercase;',
    '  background:#c6aa6d;border-color:#e9d19b;color:#1b1205}',
    '#' + ID + ' .item .c{float:right;color:rgba(217,207,180,.5);font-size:12px;font-style:italic}',
    '#' + ID + ' button[data-page]{font-size:13.5px;letter-spacing:.02em;text-transform:none;color:#d9cfb4;',
    '  border-color:rgba(198,170,109,.30);background:rgba(0,0,0,.20)}',
    '#' + ID + ' button[data-page].go{border-color:#e9d19b;background:rgba(201,162,75,.20);color:#f6e9c8}',
    '#' + ID + ' input,#' + ID + ' textarea,#' + ID + ' select{font-family:inherit;font-size:16px;color:#f6e9c8;',
    '  background:rgba(0,0,0,.35);border:1px solid rgba(198,170,109,.30);padding:8px 10px;width:100%}',
    '#' + ID + ' input:focus,#' + ID + ' textarea:focus,#' + ID + ' select:focus{border-color:rgba(198,170,109,.55)}',
    // the list the select drops down is drawn on its own, so it gets a solid
    // colour rather than a see-through one
    '#' + ID + ' option{background:#1b1205;color:#d9cfb4}',
    '#' + ID + ' textarea{min-height:300px;resize:vertical;line-height:1.55;font-size:15px}',
    '#' + ID + ' .bar{display:flex;gap:8px;align-items:center;margin-bottom:12px;flex-wrap:wrap}',
    '#' + ID + ' .bar .grow{flex:1}',
    '#' + ID + ' .none{color:rgba(217,207,180,.6);font-style:italic;padding:8px 2px;line-height:1.55}',
    '#' + ID + ' .read{white-space:pre-wrap;line-height:1.65;font-size:17px;color:#d9cfb4}',
    '#' + ID + ' .from{color:rgba(217,207,180,.6);font-style:italic;font-size:12.5px;margin-bottom:10px}',
    '#' + ID + ' .main b{font-weight:normal;font-size:16.5px;color:#f6e9c8}',
    // The K panel's scrollbars, the same rules scoped to this panel, so the
    // journal has them whether or not the K panel's page loaded first.
    '#' + ID + ' ::-webkit-scrollbar{width:10px;height:10px}',
    '#' + ID + ' ::-webkit-scrollbar-track{background:rgba(0,0,0,.25)}',
    '#' + ID + ' ::-webkit-scrollbar-thumb{background:rgba(198,170,109,.35);border:2px solid transparent;',
    '  background-clip:padding-box;border-radius:6px}',
    '#' + ID + ' ::-webkit-scrollbar-thumb:active{background:rgba(233,209,155,.55);background-clip:padding-box}',
    '#' + ID + ' ::-webkit-scrollbar-corner{background:transparent}'
  ].join('\n');

  /*
    SCALED TO THE SCREEN, THE K PANEL'S WAY. Issue 958.

    Patrick on dev, 28 September: "it doesn't scale the menu size for bigger
    screens or is just too small". The panel is a fixed 1040 by 660 box in
    CSS pixels, and the game's browser is the size of the screen, so at his
    3440 by 1440 it filled under a third of the width, and at 3840 by 2160 a
    quarter. It is laid out for 1920 by 1080 and scaled up from there by the
    smaller of the two ratios, exactly as fit() in thornswood-skills.js does:
    1920 by 1080 draws it as is, 2560 by 1440 at 1.333, 3440 by 1440 at
    1.333, 3840 by 2160 at 2. Never below 1, where max-width and max-height
    already keep it on a smaller screen, and never above 2.4.
    tests/test-journal-scale.js holds it at those sizes.
  */
  var BASE_W = 1920, BASE_H = 1080, MAX_SCALE = 2.4;

  function scaleFor(w, h) {
    var s = Math.min(w / BASE_W, h / BASE_H);
    if (!isFinite(s) || s < 1) { s = 1; }
    return Math.min(s, MAX_SCALE);
  }

  function fit() {
    try {
      var panel = root && root.querySelector('.panel');
      if (!panel) { return; }
      panel.style.transformOrigin = 'center center';
      panel.style.transform = 'scale(' + scaleFor(window.innerWidth, window.innerHeight).toFixed(3) + ')';
    } catch (e) { }
  }

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
    fit();
    window.addEventListener('resize', fit);
    // The page answers its own Escape, and its own J; no plugin can see a key
    // while the browser holds the keyboard. See thornswood-bridge.js. The
    // footer has said "Escape or J closes this" since #288, and J reached
    // neither the game nor the plugin while this panel held the keyboard, so
    // it did nothing (#530). J closes only when the caret is not in a title
    // or a page, where it is a letter somebody is writing.
    document.addEventListener('keydown', function (ev) {
      if (!shown) { return; }
      if (ev.key === 'Escape') { ev.preventDefault(); close(); return; }
      if ((ev.key === 'j' || ev.key === 'J') && !ev.ctrlKey && !ev.altKey && !ev.metaKey && !typing(ev.target)) {
        ev.preventDefault(); close();
      }
    });
    return root;
  }

  // True when a key would go into a title, a page or any other text field.
  function typing(el) {
    if (!el || !el.tagName) { return false; }
    var t = String(el.tagName).toUpperCase();
    return t === 'INPUT' || t === 'TEXTAREA' || t === 'SELECT' || !!el.isContentEditable;
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
                '<div style="color:rgba(217,207,180,.6);font-size:12px;font-style:italic">from ' + esc(shared[j].from) + '</div></button>';
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
      var whoId = friends[f].p != null && friends[f].p !== '' ? String(friends[f].p) : friends[f].name;
      pick += '<option value="' + esc(whoId) + '">' + esc(friends[f].name) + '</option>';
    }
    pick += '</select>';

    var html =
      '<div class="bar">' +
      '<input id="' + ID + '-title" value="' + esc(book.title) + '" style="max-width:360px">' +
      '<button data-do="rename">Rename</button>' +
      '<span class="grow"></span>' +
      '<button data-do="dropbook">Throw away</button>' +
      '</div>' +
      '<div class="bar">' +
      '<span style="color:rgba(198,170,109,.85);font-size:13px;letter-spacing:.18em;text-transform:uppercase">Share with</span>' +
      pick +
      '<button data-do="sharebook">Whole journal</button>' +
      '<button data-do="unsharebook">Stop sharing</button>' +
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

  function sayNeedFriend() {
    var foot = root && root.querySelector('#' + ID + '-foot');
    if (foot) { foot.textContent = 'Pick a friend first. Sharing only works with somebody on your list.'; }
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
      if (!who) { sayNeedFriend(); return; }
      net('/journal share ' + book.id + ' - ' + who);
      return;
    }
    if (verb === 'unsharebook') { net('/journal unshare ' + book.id + ' -'); return; }
    if (verb === 'sharepage') {
      if (!openPage) { return; }
      if (!who) { sayNeedFriend(); return; }
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
    fit();
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
    scaleFor: scaleFor,
    setData: function (d) {
      data = d || null;
      /*
        Redrawn on every push, and that is a real cost: typing into a page and
        having a friend log in would otherwise rebuild the textarea under the
        cursor. So a draw that would replace the text box leaves it alone
        while it has focus.
      */
      if (!shown) { return; }
      var el = document.activeElement;
      if (el && root && root.contains && root.contains(el) && typing(el)) { return; }
      draw();
    }
  };

  build();
  // Owner updates can precede this asynchronously loaded script (#1275).
  if (window.thornswoodSocialView) {
    window.thornswoodJournal.setData(window.thornswoodSocialView);
  }
  tell('ready');
})();
