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

  Same rule as every overlay: nothing calls loadUrl, this mounts itself and
  hides itself. Same look as the K panel next door, because it is the first
  thing anybody sees.
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

  var css = [
    '#ts-select{position:fixed;inset:0;z-index:2147483001;display:flex;align-items:center;justify-content:center;',
    'background:radial-gradient(ellipse at center,rgba(0,0,0,.35) 0%,rgba(0,0,0,.7) 100%);',
    'font-family:"Palatino Linotype",Palatino,Georgia,serif;color:#d9cfb4;user-select:none;pointer-events:auto}',
    '#ts-select.gone{display:none}',
    '#ts-select *{box-sizing:border-box}',
    '#ts-select .panel{width:min(760px,92vw);max-height:88vh;display:flex;flex-direction:column;',
    'background:rgba(11,10,8,.94);border:1px solid rgba(198,170,109,.42);outline:1px solid rgba(198,170,109,.14);outline-offset:4px;',
    'box-shadow:0 24px 80px rgba(0,0,0,.7)}',
    '#ts-select .head{padding:24px 32px 16px;border-bottom:1px solid rgba(198,170,109,.22)}',
    '#ts-select .eyebrow{font-size:11px;letter-spacing:.3em;text-transform:uppercase;color:rgba(198,170,109,.75);margin-bottom:6px}',
    '#ts-select .title{font-size:26px;color:#f6e9c8;line-height:1.1}',
    '#ts-select .lead{font-size:13.5px;color:rgba(217,207,180,.66);font-style:italic;margin-top:8px}',
    '#ts-select .list{padding:16px 32px;overflow:auto;display:grid;gap:9px}',
    '#ts-select .card{border:1px solid rgba(198,170,109,.30);background:rgba(0,0,0,.20);padding:14px 18px 13px;cursor:pointer;transition:all 90ms linear}',
    '#ts-select .card:hover{border-color:rgba(233,209,155,.7);background:rgba(120,94,44,.16)}',
    '#ts-select .card.at{border-color:rgba(233,209,155,.95);background:rgba(120,94,44,.34)}',
    '#ts-select .name{font-size:18px;color:#f6e9c8;display:flex;align-items:baseline;gap:12px}',
    '#ts-select .tag{margin-left:auto;font-size:10.5px;letter-spacing:.2em;text-transform:uppercase;color:#e9d19b;white-space:nowrap}',
    '#ts-select .desc{font-size:13px;line-height:1.5;color:rgba(217,207,180,.78);margin-top:4px}',
    '#ts-select .dim{font-size:12.5px;color:rgba(217,207,180,.55);font-style:italic;margin-top:2px}',
    '#ts-select .foot{display:flex;align-items:center;justify-content:space-between;gap:20px;padding:14px 32px;border-top:1px solid rgba(198,170,109,.22)}',
    '#ts-select .status{font-size:13.5px;color:rgba(217,207,180,.7);font-style:italic}',
    '#ts-select .btn{border:1px solid #e9d19b;padding:11px 34px;font-size:13px;letter-spacing:.16em;text-transform:uppercase;cursor:pointer;',
    'background:#c6aa6d;color:#1b1205;transition:all 90ms linear}',
    '#ts-select .btn:hover{background:#e9d19b}',
    '#ts-select .btn.off{opacity:.35;pointer-events:none}'
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
      '<div class="foot"><div class="status"></div><div class="btn">Play</div></div>' +
    '</div>';
  document.body.appendChild(root);
  var elList = root.querySelector('.list');
  var elStatus = root.querySelector('.status');
  var elPlay = root.querySelector('.btn');

  function el(tag, cls, text) {
    var d = document.createElement(tag);
    if (cls) d.className = cls;
    if (text !== undefined && text !== null) d.textContent = text;
    return d;
  }
  function cap(s) { s = String(s || ''); return s ? s.charAt(0).toUpperCase() + s.slice(1) : ''; }

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
      if (e.c) {
        var c = e.c;
        var name = el('div', 'name', c.name || 'A character with no name yet');
        if (e.id === last) name.appendChild(el('span', 'tag', 'last played'));
        card.appendChild(name);
        var bits = [];
        if (c.race) bits.push(c.race);
        if (c.trade) bits.push(cap(c.trade));
        if (c.town) bits.push('of ' + cap(c.town));
        if (bits.length) card.appendChild(el('div', 'desc', bits.join(', ')));
        var dim = [];
        if (c.where) dim.push('last seen ' + c.where);
        if (c.played) dim.push(c.played + ' played');
        if (dim.length) card.appendChild(el('div', 'dim', dim.join(' · ')));
      } else {
        var n2 = el('div', 'name', 'A new character');
        n2.appendChild(el('span', 'tag', 'begin'));
        card.appendChild(n2);
        card.appendChild(el('div', 'desc', 'A fresh face. You will wake in the creation hall and choose your class, your profession and your home there.'));
      }
      card.onclick = function () { at = i; draw(); };
      card.ondblclick = function () { at = i; play(); };
      elList.appendChild(card);
    });
    elPlay.className = 'btn' + (sent || !list.length ? ' off' : '');
    if (!sent) elStatus.textContent = list.length ? '' : 'The launcher listed no characters and minted no new one. Press Play in the launcher again.';
  }

  function play() {
    if (sent) return;
    var list = entries();
    var e = list[at];
    if (!e || !e.id) return;
    sent = true;
    elStatus.textContent = e.c ? 'Joining as ' + (e.c.name || 'your character') + '.' : 'Off to the creation hall.';
    draw();
    try { window.skyrimPlatform.sendMessage('thornswood', 'select', e.id); } catch (err) { }
    setTimeout(function () { root.className = 'gone'; }, 1500);
  }

  function onKey(ev) {
    if (root.className === 'gone') return;
    var n = entries().length;
    if (ev.key === 'ArrowDown') { at = n ? (at + 1) % n : 0; draw(); ev.preventDefault(); }
    else if (ev.key === 'ArrowUp') { at = n ? (at + n - 1) % n : 0; draw(); ev.preventDefault(); }
    else if (ev.key === 'Enter') { play(); ev.preventDefault(); }
  }
  window.addEventListener('keydown', onKey, true);
  elPlay.onclick = play;

  window.thornswoodSelect = { play: play, close: function () { root.className = 'gone'; } };
  draw();
  try { window.skyrimPlatform.sendMessage('thornswood-front', 'select:ready ' + entries().length); } catch (e) { }
})();
