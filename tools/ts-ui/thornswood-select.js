'use strict';
/*
  Who are you today. The character choice at the game's main menu.

  Asked for by Patrick on 20 September: pick your character in the game, the
  way the other servers do, and not in the launcher. The launcher writes the
  list of this install's characters to Data/Platform/thornswood-characters.json
  before Play; thornswood-front.js reads it at the main menu, puts it on
  window.THORNSWOOD_SELECT and fetches this file into the page. One card per
  character, one more for a new one, and Play.

  The pick is one message, to skymp5-client rather than to our plugin:

      window.skyrimPlatform.sendMessage('thornswood', 'select', profileId)

  The client (our fork, gameData.chooseAtMenu) has been waiting at the menu
  for exactly that and logs in as that profile. thornswood-front.js hears the
  same message and writes the choice to disk for the launcher, which fetches
  the voice token for it and keeps the books.

  THE SECOND LOOK, 20 September, after Patrick saw the first: a 760px panel
  on a 3440x1440 screen was a postage stamp, the Play button was clipped,
  and both cards read "A character with no name yet, 1m played played". So
  the panel scales with the screen, the type is big, a character with no
  name from the roster is named by when it was last played, and Play is a
  bar across the bottom that cannot be clipped.

  ALSO FROM THAT LOOK: the panel vanished the moment the mouse moved, and no
  log said why. The page now reports what it can see, through the plugin's
  log: a heartbeat every two seconds with the panel's computed display and
  whatever element is on top at its centre, and a line on the first mouse
  move. Not a fix, a witness.

  MUSIC, dev only: the plugin passes a file name when the dev build carries
  one, and the page plays it on a loop from the menu through the loading
  screen. The page is reloaded once the world is up, which is what stops it.

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
  var at = 0;
  var sent = false;

  // The last played character first, then the rest in the launcher's order,
  // then the new one.
  chars.sort(function (a, b) {
    if (Number(a.profileId) === last) return -1;
    if (Number(b.profileId) === last) return 1;
    return 0;
  });

  function tell(what) {
    try { window.skyrimPlatform.sendMessage('thornswood-front', 'select:' + what); } catch (e) { }
  }

  /* The page is laid out for a 1920x1080 screen and scaled up from there. */
  function scale() {
    var s = Math.min(window.innerWidth / 1920, window.innerHeight / 1080);
    if (!isFinite(s) || s < 1) s = 1;
    return Math.min(s, 2.4);
  }

  var css = [
    '#ts-select{position:fixed;inset:0;z-index:2147483001;display:flex;align-items:center;justify-content:center;',
    'background:radial-gradient(ellipse at center,rgba(0,0,0,.42) 0%,rgba(0,0,0,.78) 100%);',
    'font-family:"Palatino Linotype",Palatino,"Book Antiqua",Georgia,serif;color:#e4d9bf;user-select:none;pointer-events:auto}',
    '#ts-select.gone{display:none}',
    '#ts-select *{box-sizing:border-box}',
    '#ts-select .panel{width:920px;max-height:92vh;display:flex;flex-direction:column;transform-origin:center center;',
    'background:rgba(9,8,6,.96);border:2px solid rgba(198,170,109,.55);outline:1px solid rgba(198,170,109,.22);outline-offset:6px;',
    'box-shadow:0 30px 90px rgba(0,0,0,.8),inset 0 0 0 1px rgba(0,0,0,.6)}',
    '#ts-select .head{padding:34px 44px 22px;border-bottom:1px solid rgba(198,170,109,.3)}',
    '#ts-select .eyebrow{font-size:13px;letter-spacing:.42em;text-transform:uppercase;color:#c6aa6d;margin-bottom:10px}',
    '#ts-select .title{font-size:42px;color:#f6e9c8;line-height:1.05;letter-spacing:.01em}',
    '#ts-select .lead{font-size:16px;line-height:1.5;color:rgba(228,217,191,.72);margin-top:12px;max-width:760px}',
    '#ts-select .list{padding:22px 44px 10px;overflow:auto;display:grid;gap:12px}',
    '#ts-select .card{position:relative;border:1px solid rgba(198,170,109,.34);background:rgba(255,255,255,.025);padding:20px 26px 18px 30px;',
    'cursor:pointer;transition:background 80ms linear,border-color 80ms linear}',
    '#ts-select .card::before{content:"";position:absolute;left:0;top:0;bottom:0;width:5px;background:transparent}',
    '#ts-select .card:hover{border-color:rgba(233,209,155,.7);background:rgba(120,94,44,.16)}',
    '#ts-select .card.at{border-color:#e9d19b;background:rgba(120,94,44,.30)}',
    '#ts-select .card.at::before{background:#e9d19b}',
    '#ts-select .name{font-size:24px;color:#f6e9c8;display:flex;align-items:baseline;gap:14px}',
    '#ts-select .name .key{font-size:13px;color:rgba(198,170,109,.7);letter-spacing:.1em;min-width:16px}',
    '#ts-select .tag{margin-left:auto;font-size:12px;letter-spacing:.24em;text-transform:uppercase;color:#e9d19b;white-space:nowrap}',
    '#ts-select .desc{font-size:16px;line-height:1.5;color:rgba(228,217,191,.85);margin-top:6px}',
    '#ts-select .dim{font-size:14px;color:rgba(228,217,191,.55);margin-top:3px}',
    '#ts-select .foot{padding:16px 44px 30px}',
    '#ts-select .status{font-size:15px;color:rgba(228,217,191,.7);min-height:1.5em;margin-bottom:12px}',
    '#ts-select .btn{display:block;width:100%;border:2px solid #e9d19b;padding:18px 20px;text-align:center;font-family:inherit;',
    'font-size:20px;letter-spacing:.3em;text-transform:uppercase;cursor:pointer;background:#c6aa6d;color:#1b1205;',
    'white-space:nowrap;transition:background 80ms linear}',
    '#ts-select .btn:hover{background:#e9d19b}',
    '#ts-select .btn.off{opacity:.35;pointer-events:none}',
    '#ts-select .hint{font-size:13px;color:rgba(228,217,191,.45);margin-top:14px;text-align:center;letter-spacing:.06em}'
  ].join('');
  var style = document.createElement('style');
  style.id = 'ts-select-css';
  style.textContent = css;
  document.head.appendChild(style);

  var root = document.createElement('div');
  root.id = 'ts-select';
  root.innerHTML =
    '<div class="panel">' +
      '<div class="head"><div class="eyebrow">Thornswood</div><div class="title">Who are you today?</div>' +
      '<div class="lead">Pick a character, or begin a new one. A new character wakes in the creation hall and chooses a class, a profession and a home there.</div></div>' +
      '<div class="list"></div>' +
      '<div class="foot"><div class="status"></div><div class="btn">Play</div>' +
      '<div class="hint">Up and down, or a number, then Enter. Or click.</div></div>' +
    '</div>';
  document.body.appendChild(root);
  var elPanel = root.querySelector('.panel');
  var elList = root.querySelector('.list');
  var elStatus = root.querySelector('.status');
  var elPlay = root.querySelector('.btn');

  function fit() {
    try { elPanel.style.transform = 'scale(' + scale().toFixed(3) + ')'; } catch (e) { }
  }

  function el(tag, cls, text) {
    var d = document.createElement(tag);
    if (cls) d.className = cls;
    if (text !== undefined && text !== null) d.textContent = text;
    return d;
  }
  function cap(s) { s = String(s || ''); return s ? s.charAt(0).toUpperCase() + s.slice(1) : ''; }
  var MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  function when(iso) {
    var d = new Date(String(iso || ''));
    if (isNaN(d.getTime())) return '';
    return d.getDate() + ' ' + MONTHS[d.getMonth()];
  }

  function entries() {
    var out = chars.map(function (c) { return { id: Number(c.profileId) || 0, c: c }; });
    if (spare > 0) out.push({ id: spare, c: null });
    return out;
  }

  function draw() {
    elList.textContent = '';
    var list = entries();
    list.forEach(function (e, i) {
      var card = el('div', 'card' + (i === at ? ' at' : ''));
      var name = el('div', 'name');
      name.appendChild(el('span', 'key', String(i + 1)));
      if (e.c) {
        var c = e.c;
        var d = when(c.lastPlayed);
        // The roster names a character once it has been seen in the world; a
        // character the roster does not know yet is named by its last day.
        name.appendChild(el('span', '', c.name || (d ? 'Your character from ' + d : 'Your character')));
        if (e.id === last) name.appendChild(el('span', 'tag', 'last played'));
        card.appendChild(name);
        var bits = [];
        if (c.race) bits.push(c.race);
        if (c.trade) bits.push(cap(c.trade));
        if (c.town) bits.push('of ' + cap(c.town));
        card.appendChild(el('div', 'desc', bits.length ? bits.join(', ') : 'Class, profession and home show here once the server has seen this character.'));
        var dim = [];
        if (c.where) dim.push('last seen ' + c.where);
        if (d) dim.push('last played ' + d);
        if (c.played) dim.push(c.played);
        if (dim.length) card.appendChild(el('div', 'dim', dim.join(' · ')));
      } else {
        name.appendChild(el('span', '', 'A new character'));
        name.appendChild(el('span', 'tag', 'begin'));
        card.appendChild(name);
        card.appendChild(el('div', 'desc', 'A fresh face. You will wake in the creation hall and choose your class, your profession and your home there.'));
      }
      card.onclick = function () { at = i; draw(); };
      card.ondblclick = function () { at = i; play(); };
      elList.appendChild(card);
    });
    var e2 = list[at];
    elPlay.textContent = !e2 ? 'Play' : (e2.c ? 'Play as ' + (e2.c.name || 'this character') : 'Begin a new character');
    elPlay.className = 'btn' + (sent || !list.length ? ' off' : '');
    if (!sent) elStatus.textContent = list.length ? '' : 'The launcher listed no characters and minted no new one. Press Play in the launcher again.';
  }

  function play() {
    if (sent) return;
    var list = entries();
    var e = list[at];
    if (!e || !e.id) return;
    sent = true;
    elStatus.textContent = e.c ? 'Joining as ' + (e.c.name || 'your character') + '. The world is loading.' : 'Off to the creation hall. The world is loading.';
    draw();
    try { window.skyrimPlatform.sendMessage('thornswood', 'select', e.id); } catch (err) { }
    tell('picked');
    setTimeout(function () { root.className = 'gone'; }, 1500);
  }

  function onKey(ev) {
    if (root.className === 'gone') return;
    var n = entries().length;
    if (ev.key === 'ArrowDown') { at = n ? (at + 1) % n : 0; draw(); ev.preventDefault(); }
    else if (ev.key === 'ArrowUp') { at = n ? (at + n - 1) % n : 0; draw(); ev.preventDefault(); }
    else if (ev.key === 'Enter') { play(); ev.preventDefault(); }
    else if (/^[1-9]$/.test(ev.key)) {
      var k = Number(ev.key) - 1;
      if (k < n) { at = k; draw(); ev.preventDefault(); }
    }
  }
  window.addEventListener('keydown', onKey, true);
  window.addEventListener('resize', fit);
  elPlay.onclick = play;

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
  /*
    What the page can see about itself, for the log, because the first time
    this ran the panel vanished on a mouse move and nothing recorded why.
  */
  function seen() {
    var out = [];
    try { out.push('vis=' + document.visibilityState); } catch (e) { }
    try {
      var cs = window.getComputedStyle(elPanel);
      out.push('panel=' + cs.display + '/' + cs.opacity + '/' + cs.visibility + (elPanel.isConnected ? '' : '/detached'));
      var r = elPanel.getBoundingClientRect();
      out.push('rect=' + Math.round(r.left) + ',' + Math.round(r.top) + ',' + Math.round(r.width) + 'x' + Math.round(r.height));
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
    setTimeout(function () { tell('half a second after the mouse moved ' + seen()); }, 500);
  }, true);
  var beats = 0;
  var beat = setInterval(function () {
    if (sent || root.className === 'gone' || beats++ > 60) { clearInterval(beat); return; }
    tell('alive ' + seen());
  }, 2000);

  window.thornswoodSelect = { play: play, close: function () { root.className = 'gone'; } };
  fit();
  draw();
  tell('ready ' + entries().length + ' ' + seen());
})();
