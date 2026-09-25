'use strict';
/*
  Trading, the panel.

  Patrick, 22 September: "Currently the looking at people doesnt have the trade
  menu and when it did you had to use youyr cursor and a bunch of other bs I
  just want to press a key while looking at them."

  So the key does the asking and this only ever appears once both people are in
  a trade. Nobody has to find it, and it opens and closes itself: there is no
  trade key that opens an empty trade window.

  THE PILES BELONG TO THE SERVER. Everything on this panel is drawn from what
  the server says the two piles are, and every button sends an ordinary
  /trade line. This page cannot move an item; it can only ask. That is what
  makes it safe to let a page draw a trade at all.

  THE RULE THAT MATTERS, and it is worth knowing before you press Agree:
  ANY change to either pile takes BOTH agreements back. What you agreed to is
  what you get, or nothing happens.

  THE CONTRACT with thornswood-front.js:
    window.thornswoodTrade = { open, close, toggle, isOpen, setData }
    page -> plugin  'trade:ready' | 'trade:opened' | 'trade:closed'
*/
(function () {
  if (window.thornswoodTrade) { return; }

  var ID = 'ts-trade';
  var data = null;
  var shown = false;
  var root = null;
  var filter = '';

  function tell(what) {
    try { window.skyrimPlatform.sendMessage('thornswood-front', 'trade:' + what); }
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
    THE LOOK IS THE K PANEL'S, as the journal's and the party panel's are.
    Patrick, 23 September, about the journal: "the journal menu works but is
    ugly asf and doesn't match the theme we use with our other menus". This
    window was drawn from the same old template: system-ui sans serif, a
    rounded 12px panel, flat grey #1b1f26 and #212630 and a brass #d9ab52.
    It now carries thornswood-skills.js's values, the way the head of
    thornswood-party.js describes, and tools/test-party-trade-theme.js fails
    on a colour here that the K panel does not use.

    THIS IS WHERE ITEMS CHANGE HANDS, so no control got smaller. Every button
    keeps the font size and padding it had, Agree and Walk away keep their
    larger ones, and the buttons and the two boxes carry the line height the
    old type gave them, so each is the height it was whichever font of the
    stack the machine has. Uppercase and spaced, every button is wider than
    it was. Measured in Edge at 1920 by 1080 under the front's reset on
    24 September: the row buttons 24px tall as before, Agree and Walk away
    35px, the find and gold boxes 32px, and all of them inside their rows.
    Agree, once you have agreed, is drawn at the same opacity it was.

    No :hover, for the reason the K panel has none (see the head of
    thornswood-skills.js). The front's stylesheet in this same document sets
    margin, padding, border and background to nothing on every element, so
    each rule sets what it needs.
  */
  var CSS = [
    '#' + ID + '{position:fixed;inset:0;z-index:2147483100;display:none;',
    '  background:radial-gradient(ellipse at center,rgba(0,0,0,.50) 0%,rgba(0,0,0,.72) 100%);',
    '  font-family:"Palatino Linotype",Palatino,Georgia,serif;color:#d9cfb4}',
    '#' + ID + '.on{display:grid;place-items:center}',
    '#' + ID + ' .panel{width:1020px;max-width:calc(100vw - 48px);height:640px;',
    '  max-height:calc(100vh - 48px);display:grid;grid-template-rows:auto 1fr auto;',
    '  background:rgba(11,10,8,.94);border:1px solid rgba(198,170,109,.42);',
    '  outline:1px solid rgba(198,170,109,.14);outline-offset:4px;',
    '  box-shadow:0 24px 80px rgba(0,0,0,.7);overflow:hidden}',
    '#' + ID + ' h2{margin:0;padding:18px 24px 14px;font-size:26px;font-weight:normal;line-height:1.1;',
    '  color:#f6e9c8;border-bottom:1px solid rgba(198,170,109,.22)}',
    '#' + ID + ' .cols{display:grid;grid-template-columns:1fr 1fr 1fr;overflow:hidden}',
    '#' + ID + ' .col{overflow:auto;padding:14px 16px;border-right:1px solid rgba(198,170,109,.22);',
    '  font-size:13.5px}',
    '#' + ID + ' .col:last-child{border-right:none}',
    '#' + ID + ' h3{margin:0 0 9px;padding-bottom:6px;font-size:11.5px;letter-spacing:.24em;text-transform:uppercase;',
    '  color:rgba(198,170,109,.85);font-weight:normal;border-bottom:1px solid rgba(198,170,109,.22)}',
    '#' + ID + ' .line{display:flex;align-items:center;gap:8px;padding:6px 8px;',
    '  border:1px solid rgba(198,170,109,.30);background:rgba(0,0,0,.20);margin-bottom:5px}',
    '#' + ID + ' .line .nm{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}',
    '#' + ID + ' .line .c{color:rgba(217,207,180,.66);font-variant-numeric:tabular-nums}',
    '#' + ID + ' button{font-family:inherit;font-style:normal;font-weight:normal;cursor:pointer;',
    '  border:1px solid rgba(198,170,109,.55);background:rgba(0,0,0,.25);color:#e9d19b;',
    '  padding:3px 9px;font-size:12.5px;line-height:16px;letter-spacing:.14em;text-transform:uppercase;white-space:nowrap}',
    '#' + ID + ' .foot button{padding:7px 16px;font-size:14px;line-height:19px}',
    '#' + ID + ' button.go{background:#c6aa6d;border-color:#e9d19b;color:#1b1205}',
    '#' + ID + ' button.off{opacity:.55}',
    '#' + ID + ' input{font:inherit;line-height:18px;color:#f6e9c8;background:rgba(0,0,0,.35);',
    '  border:1px solid rgba(198,170,109,.30);padding:6px 9px;width:100%;margin-bottom:9px}',
    '#' + ID + ' input:focus{border-color:rgba(198,170,109,.55)}',
    '#' + ID + ' .none{color:rgba(217,207,180,.6);font-style:italic;padding:6px 2px;line-height:1.5}',
    '#' + ID + ' .gold{display:flex;gap:8px;align-items:center;margin-top:10px}',
    '#' + ID + ' .gold input{width:110px;margin:0}',
    '#' + ID + ' .ok{color:#9fcf92}',
    '#' + ID + ' .wait{color:rgba(217,207,180,.6)}',
    '#' + ID + ' .foot{padding:12px 20px;border-top:1px solid rgba(198,170,109,.22);display:flex;gap:12px;',
    '  align-items:center;font-size:13.5px;font-style:italic;color:rgba(217,207,180,.7)}',
    // The K panel's scrollbars, the same rules scoped to this window, so it
    // has them whether or not the K panel's page loaded first.
    '#' + ID + ' ::-webkit-scrollbar{width:10px;height:10px}',
    '#' + ID + ' ::-webkit-scrollbar-track{background:rgba(0,0,0,.25)}',
    '#' + ID + ' ::-webkit-scrollbar-thumb{background:rgba(198,170,109,.35);border:2px solid transparent;',
    '  background-clip:padding-box;border-radius:6px}',
    '#' + ID + ' ::-webkit-scrollbar-thumb:active{background:rgba(233,209,155,.55);background-clip:padding-box}',
    '#' + ID + ' ::-webkit-scrollbar-corner{background:transparent}'
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
      '<h2 id="' + ID + '-title">Trade</h2>' +
      '<div class="cols">' +
      '<div class="col" id="' + ID + '-pack"></div>' +
      '<div class="col" id="' + ID + '-mine"></div>' +
      '<div class="col" id="' + ID + '-theirs"></div>' +
      '</div>' +
      '<div class="foot"><span id="' + ID + '-state"></span><span style="flex:1"></span>' +
      '<button id="' + ID + '-cancel">Walk away</button>' +
      '<button class="go" id="' + ID + '-ok">Agree</button></div>' +
      '</div>';
    document.body.appendChild(root);
    root.querySelector('#' + ID + '-cancel').onclick = function () { net('/trade cancel'); };
    root.querySelector('#' + ID + '-ok').onclick = function () { net('/trade ok'); };
    /*
      Escape WALKS AWAY rather than hiding the panel, and that is deliberate.
      A trade you cannot see is a trade you have forgotten you are in, holding
      somebody else standing there waiting.
    */
    document.addEventListener('keydown', function (ev) {
      if (!shown) { return; }
      if (ev.key === 'Escape') { ev.preventDefault(); net('/trade cancel'); }
    });
    return root;
  }

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function draw() {
    if (!root || !data) { return; }
    root.querySelector('#' + ID + '-title').textContent = 'Trading with ' + (data.them || 'somebody');

    // What you are carrying, with a box to narrow it down: a pack of two
    // hundred things is not a list anybody reads.
    var pack = root.querySelector('#' + ID + '-pack');
    var low = filter.toLowerCase();
    var ph = '<h3>Your pack</h3>' +
             '<input id="' + ID + '-find" placeholder="find" value="' + esc(filter) + '">';
    var items = (data.pack || []).filter(function (it) {
      return !low || it.n.toLowerCase().indexOf(low) !== -1;
    });
    if (!items.length) {
      ph += '<div class="none">' + (low ? 'Nothing by that name.' : 'You are carrying nothing.') + '</div>';
    } else {
      for (var i = 0; i < items.length && i < 200; i++) {
        ph += '<div class="line"><span class="nm">' + esc(items[i].n) + '</span>' +
              '<span class="c">' + items[i].c + '</span>' +
              '<button data-add="' + esc(items[i].n) + '" data-n="1">+1</button>' +
              (items[i].c > 1 ? '<button data-add="' + esc(items[i].n) + '" data-n="' + items[i].c + '">all</button>' : '') +
              '</div>';
      }
    }
    pack.innerHTML = ph;

    var mine = root.querySelector('#' + ID + '-mine');
    var mh = '<h3>You are offering ' + (data.iAgreed ? '<span class="ok">&#10003; agreed</span>' : '') + '</h3>';
    if (!(data.mine || []).length) { mh += '<div class="none">Nothing yet.</div>'; }
    for (var j = 0; j < (data.mine || []).length; j++) {
      mh += '<div class="line"><span class="nm">' + esc(data.mine[j].n) + '</span>' +
            '<span class="c">' + data.mine[j].c + '</span>' +
            '<button data-rem="' + esc(data.mine[j].n) + '">take back</button></div>';
    }
    mh += '<div class="gold"><span>gold</span>' +
          '<input id="' + ID + '-gold" value="' + (data.myGold || 0) + '">' +
          '<button data-do="gold">Set</button></div>';
    mine.innerHTML = mh;

    var theirs = root.querySelector('#' + ID + '-theirs');
    var th = '<h3>' + esc(data.them) + ' is offering ' +
             (data.theyAgreed ? '<span class="ok">&#10003; agreed</span>' : '<span class="wait">still deciding</span>') + '</h3>';
    if (!(data.theirs || []).length && !data.theirGold) { th += '<div class="none">Nothing yet.</div>'; }
    for (var k = 0; k < (data.theirs || []).length; k++) {
      th += '<div class="line"><span class="nm">' + esc(data.theirs[k].n) + '</span>' +
            '<span class="c">' + data.theirs[k].c + '</span></div>';
    }
    if (data.theirGold) {
      th += '<div class="line"><span class="nm">gold</span><span class="c">' + data.theirGold + '</span></div>';
    }
    theirs.innerHTML = th;

    root.querySelector('#' + ID + '-state').textContent =
      data.iAgreed && data.theyAgreed ? 'Swapping...'
      : (data.iAgreed ? 'Waiting for ' + data.them + '.'
                      : 'Changing either side takes both agreements back.');
    var okBtn = root.querySelector('#' + ID + '-ok');
    okBtn.className = data.iAgreed ? 'off' : 'go';
    okBtn.textContent = data.iAgreed ? 'Agreed' : 'Agree';

    var find = root.querySelector('#' + ID + '-find');
    if (find) {
      find.oninput = function () { filter = this.value; draw(); this.focus(); };
    }
    wire(pack); wire(mine);
  }

  function wire(where) {
    var b = where.querySelectorAll('button[data-add],button[data-rem],button[data-do]');
    for (var i = 0; i < b.length; i++) {
      b[i].onclick = function () {
        var addWhat = this.getAttribute('data-add');
        var remWhat = this.getAttribute('data-rem');
        if (addWhat) { net('/trade add ' + addWhat + ' ' + (this.getAttribute('data-n') || '1')); return; }
        if (remWhat) { net('/trade remove ' + remWhat); return; }
        if (this.getAttribute('data-do') === 'gold') {
          var g = root.querySelector('#' + ID + '-gold');
          net('/trade gold ' + (g ? g.value : '0'));
        }
      };
    }
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
    filter = '';
    if (root) { root.className = ''; }
    tell('closed');
  }

  window.thornswoodTrade = {
    open: open,
    close: close,
    toggle: function () { if (shown) { net('/trade cancel'); } },
    isOpen: function () { return shown; },
    /*
      THE PANEL FOLLOWS THE TRADE RATHER THAN A KEY. The server sends
      open:false when the trade ends, whichever way it ended, so the window
      cannot be left up over a trade that is over.
    */
    setData: function (d) {
      data = d || null;
      if (!data || !data.open) { close(); return; }
      if (!shown) { open(); } else { draw(); }
    }
  };

  build();
  tell('ready');
})();
