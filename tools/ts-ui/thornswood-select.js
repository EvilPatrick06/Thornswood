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
  delete icon. An empty slot prompts to make a new character. Then Play.

  The pick is one message, to skymp5-client rather than to our plugin:

      window.skyrimPlatform.sendMessage('thornswood', 'select', profileId)

  The client (our fork, gameData.chooseAtMenu) has been waiting at the menu
  for exactly that and logs in as that profile. thornswood-front.js hears the
  same message and writes the choice to disk for the launcher, which fetches
  the voice token for it and keeps the books. A delete is a line to the
  plugin, 'select:forget <id>', which the launcher reads the same way and
  drops the character from its list; the character itself stays on the
  server, the way the old launcher's Delete worked.

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

  var css = [
    '#ts-select{position:fixed;inset:0;z-index:2147483001;display:flex;align-items:center;justify-content:center;',
    'background:radial-gradient(ellipse at center,rgba(0,0,0,.42) 0%,rgba(0,0,0,.78) 100%);',
    'font-family:"Palatino Linotype",Palatino,"Book Antiqua",Georgia,serif;color:#e4d9bf;user-select:none;pointer-events:auto}',
    '#ts-select.gone{display:none}',
    '#ts-select *{box-sizing:border-box}',
    '#ts-select .panel{width:960px;max-height:92vh;display:flex;flex-direction:column;transform-origin:center center;',
    'background:rgba(9,8,6,.96);border:2px solid rgba(198,170,109,.55);outline:1px solid rgba(198,170,109,.22);outline-offset:6px;',
    'box-shadow:0 30px 90px rgba(0,0,0,.8),inset 0 0 0 1px rgba(0,0,0,.6)}',
    '#ts-select .head{padding:32px 44px 20px;border-bottom:1px solid rgba(198,170,109,.3);display:flex;align-items:flex-end;justify-content:space-between}',
    '#ts-select .eyebrow{font-size:13px;letter-spacing:.42em;text-transform:uppercase;color:#c6aa6d;margin-bottom:10px}',
    '#ts-select .title{font-size:42px;color:#f6e9c8;line-height:1.05}',
    '#ts-select .count{font-size:14px;letter-spacing:.2em;text-transform:uppercase;color:rgba(198,170,109,.7);padding-bottom:8px}',
    '#ts-select .list{padding:22px 44px 8px;overflow:auto;display:grid;gap:14px}',
    // a slot
    '#ts-select .slot{position:relative;border:1px solid rgba(198,170,109,.34);background:rgba(255,255,255,.025);padding:20px 26px 20px 30px;',
    'cursor:pointer;transition:background 80ms linear,border-color 80ms linear;min-height:132px}',
    '#ts-select .slot::before{content:"";position:absolute;left:0;top:0;bottom:0;width:5px;background:transparent}',
    '#ts-select .slot:hover{border-color:rgba(233,209,155,.7);background:rgba(120,94,44,.16)}',
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
    '#ts-select .bin{position:absolute;right:20px;top:20px;width:36px;height:36px;display:grid;place-items:center;border:1px solid transparent;',
    'color:rgba(228,217,191,.45);cursor:pointer;transition:all 80ms linear}',
    '#ts-select .bin:hover{color:#e9a27a;border-color:rgba(233,162,122,.6);background:rgba(120,44,44,.25)}',
    '#ts-select .bin svg{width:20px;height:20px;fill:none;stroke:currentColor;stroke-width:1.7;stroke-linecap:round;stroke-linejoin:round}',
    '#ts-select .confirm{position:absolute;inset:0;background:rgba(40,12,10,.96);display:flex;align-items:center;justify-content:space-between;gap:20px;padding:0 30px}',
    '#ts-select .confirm .q{font-size:18px;color:#f6e9c8;line-height:1.4}',
    '#ts-select .confirm .q small{display:block;font-size:13.5px;color:rgba(228,217,191,.6);margin-top:4px}',
    '#ts-select .confirm .b{display:flex;gap:10px}',
    '#ts-select .btn2{border:1px solid rgba(198,170,109,.6);padding:10px 22px;font-size:13px;letter-spacing:.2em;text-transform:uppercase;',
    'cursor:pointer;color:#e9d19b;background:rgba(0,0,0,.3);white-space:nowrap}',
    '#ts-select .btn2:hover{background:rgba(120,94,44,.5);color:#f6e9c8}',
    '#ts-select .btn2.danger{border-color:#e9a27a;color:#f6c9b0}',
    '#ts-select .btn2.danger:hover{background:rgba(160,50,40,.6)}',
    // the foot
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
      '<div class="head"><div><div class="eyebrow">Thornswood</div><div class="title">Who are you today?</div></div>' +
      '<div class="count"></div></div>' +
      '<div class="list"></div>' +
      '<div class="foot"><div class="status"></div><div class="btn">Play</div>' +
      '<div class="hint">Up and down, or a number, then Enter. Delete forgets the one that is lit.</div></div>' +
    '</div>';
  document.body.appendChild(root);
  var elPanel = root.querySelector('.panel');
  var elList = root.querySelector('.list');
  var elCount = root.querySelector('.count');
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
    The slots, in order. A character sits in the slot the launcher numbered
    it with; anything past the allowance still shows, because a character
    that exists is not hidden over a role change. Empty slots up to the
    allowance offer a new character.
  */
  function slots() {
    var out = [];
    var byslot = {};
    var extra = [];
    chars.forEach(function (c) {
      var s = Number(c.slot) || 0;
      if (s > 0 && !byslot[s]) byslot[s] = c; else extra.push(c);
    });
    // A launcher that numbered nothing (before 20 September) or two rows
    // on one number: the rest take the lowest free slots, in order.
    var unplaced = extra; extra = [];
    unplaced.forEach(function (c) {
      var free = 0;
      for (var j = 1; j <= SLOTS && !free; j++) if (!byslot[j]) free = j;
      if (free) byslot[free] = c; else extra.push(c);
    });
    var top = SLOTS;
    for (var k in byslot) if (Number(k) > top) top = Number(k);
    for (var i = 1; i <= top; i++) {
      if (byslot[i]) out.push({ n: i, id: Number(byslot[i].profileId) || 0, c: byslot[i] });
      else if (i <= SLOTS) out.push({ n: i, id: spare, c: null });
    }
    extra.forEach(function (c) { out.push({ n: out.length + 1, id: Number(c.profileId) || 0, c: c }); });
    return out;
  }

  var BIN = '<svg viewBox="0 0 24 24"><path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/></svg>';

  function draw() {
    elList.textContent = '';
    var list = slots();
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
        bin.onclick = function (ev) { ev.stopPropagation(); at = i; asking = e.id; draw(); };
        card.appendChild(bin);
        if (asking === e.id) {
          var strip = el('div', 'confirm');
          var q = el('div', 'q', 'Forget ' + (c.name || 'this character') + '?');
          q.appendChild(el('small', '', 'This launcher drops it from the list. The character itself stays on the server.'));
          strip.appendChild(q);
          var b = el('div', 'b');
          var yes = el('div', 'btn2 danger', 'Forget');
          yes.onclick = function (ev) { ev.stopPropagation(); forget(e.id); };
          var no2 = el('div', 'btn2', 'Keep');
          no2.onclick = function (ev) { ev.stopPropagation(); asking = 0; draw(); };
          b.appendChild(yes); b.appendChild(no2);
          strip.appendChild(b);
          strip.onclick = function (ev) { ev.stopPropagation(); };
          card.appendChild(strip);
        }
      } else {
        card.appendChild(el('div', 'make', 'Make a new character'));
        card.appendChild(el('div', 'sub', e.id
          ? 'A fresh face. You will wake in the creation hall and choose your class, your profession and your home there.'
          : 'The launcher minted no id for a new character. Press Play in the launcher again.'));
      }
      card.onclick = function () { at = i; asking = 0; draw(); };
      card.ondblclick = function () { at = i; play(); };
      elList.appendChild(card);
    });
    var e2 = list[at];
    if (!e2) elPlay.textContent = 'Play';
    else if (e2.c) elPlay.textContent = 'Play as ' + (e2.c.name || 'this character');
    else elPlay.textContent = 'Make a new character';
    elPlay.className = 'btn' + (sent || !e2 || !e2.id ? ' off' : '');
    if (!sent) elStatus.textContent = '';
  }

  function forget(id) {
    asking = 0;
    chars = chars.filter(function (c) { return Number(c.profileId) !== id; });
    if (last === id) last = 0;
    tell('forget ' + id);
    draw();
  }

  function play() {
    if (sent) return;
    var list = slots();
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
  var beats = 0;
  var beat = setInterval(function () {
    if (sent || root.className === 'gone' || beats++ > 30) { clearInterval(beat); return; }
    tell('alive ' + seen());
  }, 4000);

  window.thornswoodSelect = { play: play, close: function () { root.className = 'gone'; } };
  fit();
  draw();
  tell('ready ' + slots().length + ' slots ' + seen());
})();
