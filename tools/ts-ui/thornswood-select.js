'use strict';
/*
  Who are you today. The character choice at the game's main menu.

  Asked for by Patrick on 20 September: pick your character in the game, the
  way the other servers do, and not in the launcher. The launcher writes the
  list of this install's characters to Data/Platform/thornswood-characters.json
  before Play; thornswood-front.js reads it at the main menu, puts it on
  window.THORNSWOOD_SELECT and fetches this file into the page.

  THE SLOTS, Patrick's spec the same evening: just the character slots, two
  by default, three for a Patreon tier or a Gamemaster (the site decides and
  the launcher passes "slots"). A taken slot is the character's name, big,
  and under it the last location, the hours played and the last time, with a
  delete icon. An empty slot prompts to make a new character.

  CLICK MEANS GO, Patrick later the same day: "if you click on one that's the
  one you go to and doesn't require a confirm button at the bottom". A click
  on a taken slot plays that character at once and a click on an empty slot
  makes a new one at once; there is no Play bar. The keys stay: up, down or
  a number lights a slot, Enter plays the lit one, Delete asks to forget it.
  The slots are fixed by number too, see slots() below.

  The pick is one message, to skymp5-client rather than to our plugin:

      window.skyrimPlatform.sendMessage('thornswood', 'select', profileId)

  The client (our fork, gameData.chooseAtMenu) has been waiting at the menu
  for exactly that and logs in as that profile. thornswood-front.js hears the
  same message and writes the choice to disk for the launcher, which fetches
  the voice token for it and keeps the books. A delete is a line to the
  plugin, 'select:forget <id>', which the launcher reads the same way and
  drops the character from its list; the character itself stays on the
  server, the way the old launcher's Delete worked.

  MUSIC: the launcher passes a file name when the build carries the theme,
  and the page plays it on a loop from the menu through the loading screen.
  The page is reloaded once the world is up, which is what stops it. This was
  dev only until 22 September, when the final track arrived and went to main.

  Same rule as every overlay: nothing calls loadUrl, this mounts itself and
  hides itself. Same look as the K panel next door.
*/

(function () {
  if (window.thornswoodSelect) return;

  var LIST = window.THORNSWOOD_SELECT;
  if (!LIST || !Array.isArray(LIST.characters)) return;

  var chars = LIST.characters.slice();
  var spare = Number(LIST.spare) || 0;
  var last = Number(LIST.last) || 0;
  var SLOTS = Math.max(1, Number(LIST.slots) || 2);
  var at = 0;
  var sent = false;
  var asking = 0;        // the profile id a delete is being confirmed for, or 0

  function tell(what) {
    try { window.skyrimPlatform.sendMessage('thornswood-front', 'select:' + what); } catch (e) { }
  }

  /* The page is laid out for a 1920x1080 screen and scaled up from there. */
  function scale() {
    var s = Math.min(window.innerWidth / 1920, window.innerHeight / 1080);
    if (!isFinite(s) || s < 1) s = 1;
    return Math.min(s, 2.4);
  }

  /*
    Kept plain on purpose. No cursor rules, no transitions, no hover styles:
    the first three cuts of this page died the moment the mouse moved over
    them, with the browser still up according to the plugin, and hover is
    the one thing a mouse move asks of a page. The lit slot is lit by a
    click or a key and nothing else.
  */
  var css = [
    '#ts-select{position:fixed;inset:0;z-index:2147483001;display:flex;align-items:center;justify-content:center;',
    'background:#0b0907;',
    'font-family:"Palatino Linotype",Palatino,"Book Antiqua",Georgia,serif;color:#e4d9bf;user-select:none;pointer-events:auto}',
    '#ts-select.gone{display:none}',
    '#ts-select *{box-sizing:border-box}',
    // the painting behind everything: the loop when it plays, the still under it
    '#ts-select .bg{position:absolute;inset:0;z-index:0;background:#0b0907 center/cover no-repeat}',
    '#ts-select .bg video{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}',
    '#ts-select .shade{position:absolute;inset:0;z-index:0;',
    'background:radial-gradient(ellipse at center,rgba(0,0,0,.40) 0%,rgba(0,0,0,.76) 100%)}',
    '#ts-select .panel{position:relative;z-index:1;width:960px;max-height:92vh;display:flex;flex-direction:column;transform-origin:center center;',
    'background:rgba(9,8,6,.96);border:2px solid rgba(198,170,109,.55);outline:1px solid rgba(198,170,109,.22);outline-offset:6px;',
    'box-shadow:0 30px 90px rgba(0,0,0,.8),inset 0 0 0 1px rgba(0,0,0,.6)}',
    '#ts-select .head{padding:32px 44px 20px;border-bottom:1px solid rgba(198,170,109,.3);display:flex;align-items:flex-end;justify-content:space-between}',
    '#ts-select .eyebrow{font-size:13px;letter-spacing:.42em;text-transform:uppercase;color:#c6aa6d;margin-bottom:10px}',
    '#ts-select .title{font-size:42px;color:#f6e9c8;line-height:1.05}',
    '#ts-select .count{font-size:14px;letter-spacing:.2em;text-transform:uppercase;color:rgba(198,170,109,.7);padding-bottom:8px}',
    '#ts-select .list{padding:22px 44px 8px;overflow:auto;display:grid;gap:14px}',
    /*
      Scrollbars, for this page and for the window it sits in. The browser's
      own is a white strip against a dark page, which reads as a fault rather
      than as a control. Written without a page in front of them on purpose:
      this page is up at the main menu before any other is loaded, and the K
      panel carries the same rules for the world.
    */
    '::-webkit-scrollbar{width:10px;height:10px}',
    '::-webkit-scrollbar-track{background:rgba(0,0,0,.25)}',
    '::-webkit-scrollbar-thumb{background:rgba(198,170,109,.35);border:2px solid transparent;',
    'background-clip:padding-box;border-radius:6px}',
    '::-webkit-scrollbar-thumb:active{background:rgba(233,209,155,.55);background-clip:padding-box}',
    '::-webkit-scrollbar-corner{background:transparent}',
    // a slot
    '#ts-select .slot{position:relative;border:1px solid rgba(198,170,109,.34);background:rgba(255,255,255,.025);padding:20px 26px 20px 30px;',
    'min-height:132px}',
    '#ts-select .slot::before{content:"";position:absolute;left:0;top:0;bottom:0;width:5px;background:transparent}',
    '#ts-select .slot.at{border-color:#e9d19b;background:rgba(120,94,44,.30)}',
    '#ts-select .slot.at::before{background:#e9d19b}',
    '#ts-select .slot.empty{border-style:dashed;background:rgba(0,0,0,.18)}',
    '#ts-select .slot.empty.at{background:rgba(120,94,44,.22)}',
    '#ts-select .slotno{font-size:12px;letter-spacing:.3em;text-transform:uppercase;color:rgba(198,170,109,.7);margin-bottom:8px;display:flex;gap:14px}',
    '#ts-select .slotno .tag{color:#e9d19b}',
    '#ts-select .name{font-size:32px;color:#f6e9c8;line-height:1.1;padding-right:56px}',
    '#ts-select .name.faint{color:rgba(246,233,200,.62);font-style:italic}',
    '#ts-select .stats{display:grid;grid-template-columns:1.4fr 1fr 1fr;gap:18px;margin-top:14px}',
    '#ts-select .stat .k{font-size:11px;letter-spacing:.26em;text-transform:uppercase;color:rgba(198,170,109,.65);margin-bottom:4px}',
    '#ts-select .stat .v{font-size:17px;color:#e4d9bf}',
    '#ts-select .stat .v.dim{color:rgba(228,217,191,.5)}',
    '#ts-select .make{font-size:26px;color:#e9d19b;margin-top:2px}',
    '#ts-select .sub{font-size:15px;line-height:1.5;color:rgba(228,217,191,.6);margin-top:8px;max-width:720px}',
    // the delete icon and the confirm strip
    '#ts-select .bin{position:absolute;right:16px;top:16px;width:48px;height:48px;display:grid;place-items:center;border:1px solid rgba(198,170,109,.25);',
    'color:rgba(228,217,191,.55)}',
    '#ts-select .bin svg{width:20px;height:20px;fill:none;stroke:currentColor;stroke-width:1.7;stroke-linecap:round;stroke-linejoin:round}',
    '#ts-select .confirm{position:absolute;inset:0;background:rgba(40,12,10,.96);display:flex;align-items:center;justify-content:space-between;gap:20px;padding:0 30px}',
    '#ts-select .confirm .q{font-size:18px;color:#f6e9c8;line-height:1.4}',
    '#ts-select .confirm .q small{display:block;font-size:13.5px;color:rgba(228,217,191,.6);margin-top:4px}',
    '#ts-select .confirm .b{display:flex;gap:10px}',
    '#ts-select .btn2{border:1px solid rgba(198,170,109,.6);padding:10px 22px;font-size:13px;letter-spacing:.2em;text-transform:uppercase;',
    'color:#e9d19b;background:rgba(0,0,0,.3);white-space:nowrap}',
    '#ts-select .btn2.danger{border-color:#e9a27a;color:#f6c9b0;background:rgba(120,40,30,.45)}',
    // the foot
    '#ts-select .foot{padding:16px 44px 30px}',
    '#ts-select .status{font-size:15px;color:rgba(228,217,191,.7);min-height:1.5em;margin-bottom:12px;text-align:center}',
    '#ts-select .hint{font-size:13px;color:rgba(228,217,191,.45);margin-top:4px;text-align:center;letter-spacing:.06em}',
    // Well below the hint and centred, so it is nowhere near the characters.
    '#ts-select .quitrow{display:flex;justify-content:center;margin-top:18px}',
    '#ts-select .quit{opacity:.72}',
    '#ts-select .quit:hover{opacity:1}'
  ].join('');
  var style = document.createElement('style');
  style.id = 'ts-select-css';
  style.textContent = css;
  document.head.appendChild(style);

  var root = document.createElement('div');
  root.id = 'ts-select';
  root.innerHTML =
    '<div class="bg"></div><div class="shade"></div>' +
    '<div class="panel">' +
      '<div class="head"><div><div class="eyebrow">Thornswood</div><div class="title">Who are you today?</div></div>' +
      '<div class="count"></div></div>' +
      '<div class="list"></div>' +
      '<div class="foot"><div class="status"></div>' +
      '<div class="hint">Click a character to play. Click an empty slot for a new character. Delete forgets the one that is lit.</div>' +
      /*
        A way out of this page that is not Task Manager.

        Patrick, 22 September: "add a close game button in the main menu with
        the chacrther selector". Until now the only way to leave was alt
        tabbing and killing Skyrim, which is also what people do when the page
        itself stops answering: Djinn's "Timed out" report ends "have to task
        out exit". A quit that the page offers is one they can reach while it
        is still drawing.

        It asks a second time before it goes, the way Forget does, because
        this is one click from Play and quitting by accident is a loading
        screen and a walk back to where you were.
      */
      '<div class="quitrow"><div class="btn2 quit">Close the game</div></div></div>' +
    '</div>';
  document.body.appendChild(root);
  var elPanel = root.querySelector('.panel');
  var elBg = root.querySelector('.bg');
  var elList = root.querySelector('.list');

  /*
    The painting. The still goes on as the background at once; the loop is
    laid over it and plays if this browser decodes it, and is taken away
    again if it cannot, so what is behind the panel is the painting either
    way and never a black box. Muted, because the music is its own element.
  */
  if (LIST.still) { try { elBg.style.backgroundImage = 'url("' + String(LIST.still) + '")'; } catch (e) { } }
  if (LIST.video) {
    try {
      var vid = document.createElement('video');
      vid.muted = true; vid.loop = true; vid.autoplay = true;
      vid.setAttribute('muted', ''); vid.setAttribute('playsinline', '');
      vid.preload = 'auto';
      vid.onerror = function () { try { vid.remove(); } catch (e) { } tell('painting: the loop would not play here, the still stays'); };
      vid.onplaying = function () { tell('painting: the loop is playing'); };
      vid.src = String(LIST.video);
      elBg.appendChild(vid);
      var vp = vid.play();
      if (vp && typeof vp.catch === 'function') { vp.catch(function () { }); }
    } catch (e) { tell('painting: ' + e); }
  }
  var elCount = root.querySelector('.count');
  var elStatus = root.querySelector('.status');

  /*
    Close the game. Asked twice, then sent to the front, which calls the
    engine's own quit: nothing in a browser can shut Skyrim.

    The second click is the confirm, on the same button, which is the lightest
    thing that cannot be done by accident. It gives up after five seconds so a
    stray first click does not leave a loaded gun sitting on the page.
  */
  var elQuit = root.querySelector('.quit');
  var quitArmed = 0;
  if (elQuit) {
    elQuit.onclick = function () {
      var now = Date.now();
      if (quitArmed && now - quitArmed < 5000) {
        quitArmed = 0;
        elQuit.textContent = 'Closing...';
        elQuit.className = 'btn2 quit';
        tell('quit');
        return;
      }
      quitArmed = now;
      elQuit.textContent = 'Click again to close';
      elQuit.className = 'btn2 quit danger';
      setTimeout(function () {
        if (!quitArmed) { return; }
        quitArmed = 0;
        elQuit.textContent = 'Close the game';
        elQuit.className = 'btn2 quit';
      }, 5000);
    };
  }

  function fit() {
    try { elPanel.style.transform = 'scale(' + scale().toFixed(3) + ')'; } catch (e) { }
  }

  function el(tag, cls, text) {
    var d = document.createElement(tag);
    if (cls) d.className = cls;
    if (text !== undefined && text !== null) d.textContent = text;
    return d;
  }
  var MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  var SHORT = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  function two(n) { return (n < 10 ? '0' : '') + n; }
  function when(iso) {
    var d = new Date(String(iso || ''));
    if (isNaN(d.getTime())) return '';
    return d.getDate() + ' ' + SHORT[d.getMonth()] + ', ' + two(d.getHours()) + ':' + two(d.getMinutes());
  }
  function hours(c) {
    var s = Number(c.seconds);
    if (!isFinite(s) || s < 0) {
      // An older launcher sends only the text, "1h 20m played".
      return String(c.played || '').replace(/\s*played$/, '');
    }
    if (s < 60) return 'Under a minute';
    var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
    if (h > 0) return h + 'h ' + m + 'm';
    return m + ' min';
  }

  /*
    The slots, fixed by the stored number. Slot n is the character the
    launcher numbered n; every number from 1 to the allowance with nobody in
    it is an empty card offering a new character; a character numbered past
    the allowance is drawn after them, in number order, because a character
    that exists is never hidden over a role change. Nothing is compacted or
    renumbered here.

    Patrick, 20 September: "when I deleted a character the slots moved, I
    want each slot to stay as is and so slot 1 and 3 could have things in
    them and slot 2 says make a new character". This page had switched to
    drawing 1 to n for the characters there are, in slot order, earlier the
    same day, because the stored numbers had climbed past the allowance (1
    empty, 2 empty, 3, 4, 5 on a three slot account) and the page was
    offering a fourth and a fifth. That is closed on the launcher side now:
    NextSlot hands out the lowest free number and Slots.Tidy moves a
    character down from above the allowance whenever a number under it is
    free, before this list is written. A character with no number, or one
    whose number another already holds, is drawn in the first empty slot
    rather than lost; the launcher has written a number since the day the
    file existed, so that is a hand edited file and nothing more.
  */
  function slots() {
    var held = {};
    var loose = [];
    chars.forEach(function (c) {
      var n = Number(c.slot) || 0;
      if (n >= 1 && !held[n]) held[n] = c;
      else loose.push(c);
    });
    var out = [];
    var n;
    for (n = 1; n <= SLOTS; n++) {
      var c = held[n] || loose.shift() || null;
      out.push({ n: n, id: c ? (Number(c.profileId) || 0) : spare, c: c });
    }
    var beyond = [];
    for (var k in held) { if (held.hasOwnProperty(k) && Number(k) > SLOTS) beyond.push(Number(k)); }
    beyond.sort(function (a, b) { return a - b; });
    beyond.forEach(function (m) { out.push({ n: m, id: Number(held[m].profileId) || 0, c: held[m] }); });
    loose.forEach(function (c) { out.push({ n: out.length + 1, id: Number(c.profileId) || 0, c: c }); });
    return out;
  }

  var BIN = '<svg viewBox="0 0 24 24"><path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/></svg>';

  /*
    What the click meant is decided by where the mouse went DOWN, not by what
    the click landed on.

    Stopping the click at the bin is not enough, and Patrick found that the
    hard way on 20 September: the delete icon stopped working and a press on
    it played the character instead. A browser fires click on the nearest
    common ancestor of what the mouse went down on and what it came up on, so
    a press that starts on the bin's icon and ends one pixel outside it fires
    the click on the slot, the bin's own handler never runs, and the slot
    plays. The icon is 36 pixels of a card the size of the panel, the cursor
    in the main menu is drawn by the game rather than by the page, and the
    browser only hears about the pointer when it moves, so a press that drifts
    is the normal case there rather than the odd one.

    So every press through the page records where it started, and the slot
    asks that question before it plays. Nothing here restyles on a mouse move,
    which is the rule this page keeps: it listens, it does not paint.
  */
  var downOn = '';       // 'bin', 'confirm' or ''
  var downSlot = -1;     // which slot the press started in

  function partOf(node, cls) {
    while (node && node !== root) {
      if (node.className && (' ' + node.className + ' ').indexOf(' ' + cls + ' ') >= 0) return true;
      node = node.parentNode;
    }
    return false;
  }

  function draw() {
    elList.textContent = '';
    var list = slots();
    if (at >= list.length) at = Math.max(0, list.length - 1);
    var taken = list.filter(function (e) { return !!e.c; }).length;
    elCount.textContent = taken + ' of ' + SLOTS + ' slots';
    list.forEach(function (e, i) {
      var card = el('div', 'slot' + (i === at ? ' at' : '') + (e.c ? '' : ' empty'));
      var no = el('div', 'slotno', 'Slot ' + e.n);
      if (e.c && e.id === last) no.appendChild(el('span', 'tag', 'last played'));
      if (!e.c) no.appendChild(el('span', '', 'empty'));
      card.appendChild(no);
      if (e.c) {
        var c = e.c;
        card.appendChild(el('div', 'name' + (c.name ? '' : ' faint'), c.name || 'Unnamed character'));
        var stats = el('div', 'stats');
        var s1 = el('div', 'stat'); s1.appendChild(el('div', 'k', 'Last location'));
        s1.appendChild(el('div', 'v' + (c.where ? '' : ' dim'), c.where || 'Not seen in the world yet'));
        var s2 = el('div', 'stat'); s2.appendChild(el('div', 'k', 'Hours played'));
        var hp = hours(c); s2.appendChild(el('div', 'v' + (hp ? '' : ' dim'), hp || 'None yet'));
        var s3 = el('div', 'stat'); s3.appendChild(el('div', 'k', 'Last played'));
        var w = when(c.lastPlayed); s3.appendChild(el('div', 'v' + (w ? '' : ' dim'), w || 'Never'));
        stats.appendChild(s1); stats.appendChild(s2); stats.appendChild(s3);
        card.appendChild(stats);
        var bin = el('div', 'bin');
        bin.title = 'Forget this character';
        bin.innerHTML = BIN;
        bin.onmousedown = function (ev) { downOn = 'bin'; downSlot = i; if (ev.stopPropagation) ev.stopPropagation(); };
        bin.onclick = function (ev) { if (ev.stopPropagation) ev.stopPropagation(); ask(i, e.id); };
        card.appendChild(bin);
        if (asking === e.id) {
          var strip = el('div', 'confirm');
          var q = el('div', 'q', 'Forget ' + (c.name || 'this character') + '?');
          q.appendChild(el('small', '', 'This launcher drops it from the list. The character itself stays on the server.'));
          strip.appendChild(q);
          var b = el('div', 'b');
          var yes = el('div', 'btn2 danger', 'Forget');
          yes.onmousedown = function (ev) { downOn = 'confirm'; downSlot = i; if (ev.stopPropagation) ev.stopPropagation(); };
          yes.onclick = function (ev) { if (ev.stopPropagation) ev.stopPropagation(); forget(e.id); };
          var no2 = el('div', 'btn2', 'Keep');
          no2.onmousedown = function (ev) { downOn = 'confirm'; downSlot = i; if (ev.stopPropagation) ev.stopPropagation(); };
          no2.onclick = function (ev) { if (ev.stopPropagation) ev.stopPropagation(); asking = 0; draw(); };
          b.appendChild(yes); b.appendChild(no2);
          strip.appendChild(b);
          strip.onmousedown = function (ev) { downOn = 'confirm'; downSlot = i; if (ev.stopPropagation) ev.stopPropagation(); };
          strip.onclick = function (ev) { if (ev.stopPropagation) ev.stopPropagation(); };
          card.appendChild(strip);
        }
      } else {
        card.appendChild(el('div', 'make', 'Make a new character'));
        card.appendChild(el('div', 'sub', e.id
          ? 'A fresh face. You will wake in the creation hall and choose your class, your profession and your home there.'
          : 'The launcher minted no id for a new character. Press Play in the launcher again.'));
      }
      /*
        The click is the choice, unless the press started on the bin or in
        the confirm strip. It can land here even then: see the note on
        downOn at the top of the file.
      */
      card.onmousedown = function () { if (downOn === '') downSlot = i; };
      card.onclick = function () {
        var was = downOn, wasSlot = downSlot;
        downOn = ''; downSlot = -1;
        if (was === 'confirm') { return; }
        if (was === 'bin') { ask(wasSlot < 0 ? i : wasSlot, null); return; }
        at = i; asking = 0; draw(); play();
      };
      elList.appendChild(card);
    });
    if (!sent) elStatus.textContent = '';
  }

  /* Put the confirm strip up on a slot, by index, and by id when it is known. */
  function ask(i, id) {
    var list = slots();
    if (i < 0 || i >= list.length) return;
    var e = list[i];
    if (!e || !e.c) return;
    at = i;
    asking = id === null || id === undefined ? Number(e.c.profileId) || 0 : id;
    draw();
  }

  function forget(id) {
    asking = 0;
    chars = chars.filter(function (c) { return Number(c.profileId) !== id; });
    if (last === id) last = 0;
    tell('forget ' + id);
    draw();
  }

  /*
    The pick goes to skymp5-client, and again every two seconds until the
    plugin says it heard. This page can be up long before any plugin runs
    (SkyrimPlatform loads the page at start and its plugins fifteen seconds
    later), so a pick made in that gap would otherwise be lost. The client
    ignores the repeats once it has one.
  */
  var acked = false;
  var picked = 0;
  function sendPick() {
    if (!picked || acked) return;
    try { window.skyrimPlatform.sendMessage('thornswood', 'select', picked); } catch (err) { }
  }
  function play() {
    if (sent) return;
    var list = slots();
    var e = list[at];
    if (!e || !e.id) return;
    sent = true;
    picked = e.id;
    elStatus.textContent = e.c ? 'Joining as ' + (e.c.name || 'your character') + '. The world is loading.' : 'Off to the creation hall. The world is loading.';
    draw();
    sendPick();
    tell('picked');
    var again = setInterval(function () {
      if (acked) { clearInterval(again); return; }
      sendPick();
    }, 2000);
  }
  function onAcked() {
    acked = true;
    setTimeout(function () { root.className = 'gone'; }, 1200);
  }

  function onKey(ev) {
    if (root.className === 'gone') return;
    var list = slots();
    var n = list.length;
    if (asking) {
      if (ev.key === 'Escape') { asking = 0; draw(); ev.preventDefault(); }
      else if (ev.key === 'Enter') { forget(asking); ev.preventDefault(); }
      return;
    }
    if (ev.key === 'ArrowDown') { at = n ? (at + 1) % n : 0; draw(); ev.preventDefault(); }
    else if (ev.key === 'ArrowUp') { at = n ? (at + n - 1) % n : 0; draw(); ev.preventDefault(); }
    else if (ev.key === 'Enter') { play(); ev.preventDefault(); }
    else if (ev.key === 'Delete') {
      var e = list[at];
      if (e && e.c) { asking = e.id; draw(); }
      ev.preventDefault();
    }
    else if (/^[1-9]$/.test(ev.key)) {
      var k = Number(ev.key) - 1;
      if (k < n) { at = k; draw(); ev.preventDefault(); }
    }
  }
  window.addEventListener('keydown', onKey, true);
  window.addEventListener('resize', fit);

  // ----------------------------------------------------------------- music --
  var audio = null;
  if (LIST.music) {
    try {
      audio = document.createElement('audio');
      audio.src = String(LIST.music);
      audio.loop = true;
      audio.volume = 0.55;
      audio.preload = 'auto';
      document.body.appendChild(audio);
      var p = audio.play();
      if (p && typeof p.then === 'function') {
        p.then(function () { tell('music playing'); },
               function (err) {
                 tell('music refused: ' + (err && err.message ? err.message : err) + ', trying on the first key or click');
                 var once = function () {
                   try { audio.play(); } catch (e) { }
                   window.removeEventListener('keydown', once, true);
                   window.removeEventListener('mousedown', once, true);
                 };
                 window.addEventListener('keydown', once, true);
                 window.addEventListener('mousedown', once, true);
               });
      }
    } catch (e) { tell('music failed: ' + e); }
  }

  // -------------------------------------------------------------- witness --
  function seen() {
    var out = [];
    try { out.push('vis=' + document.visibilityState); } catch (e) { }
    try {
      var cs = window.getComputedStyle(elPanel);
      out.push('panel=' + cs.display + '/' + cs.opacity + '/' + cs.visibility + (elPanel.isConnected ? '' : '/detached'));
      var r = elPanel.getBoundingClientRect();
      var top = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
      out.push('top=' + (top ? (top.tagName.toLowerCase() + (top.id ? '#' + top.id : '') + (top.className && typeof top.className === 'string' ? '.' + top.className.replace(/\s+/g, '.') : '')) : 'nothing'));
    } catch (e) { out.push('err=' + e); }
    out.push('size=' + window.innerWidth + 'x' + window.innerHeight + ' scale=' + scale().toFixed(2));
    return out.join(' ');
  }
  var moved = false;
  window.addEventListener('mousemove', function (ev) {
    if (moved) return;
    moved = true;
    tell('mouse first moved at ' + ev.clientX + ',' + ev.clientY + ' ' + seen());
  }, true);
  // Every two seconds while the choice is up. The plugin reloads the page
  // after six seconds without one, which is how a page that dies under the
  // mouse comes back instead of leaving a blank menu.
  var beat = setInterval(function () {
    if (sent || root.className === 'gone') { clearInterval(beat); return; }
    tell('alive ' + seen());
  }, 2000);

  window.thornswoodSelect = { play: play, acked: onAcked, close: function () { root.className = 'gone'; } };
  fit();
  draw();
  tell('ready ' + slots().length + ' slots ' + seen());
})();
