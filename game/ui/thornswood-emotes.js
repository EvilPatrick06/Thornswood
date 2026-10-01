'use strict';
/*
  The emote wheel, as an overlay inside the front rather than a page of its own.

  The middle of the wheel is eight quick slots. Click one to play it. The same
  eight are the number keys 1 to 8, and those play with the wheel shut. On the
  right is a search and every emote, in alphabetical order. Click a name to
  play it. Click a slot number under the search, then a name, to put that
  emote on the slot.

  The page draws and reports. Which animation a name means, and playing it,
  belong to the plugin.
*/

(function () {
  if (window.thornswoodSetWheel) return;

  var items = [];
  var slots = [];
  var pin = 0;
  var query = '';

  var css = [
    '#thornswood-wheel{position:fixed;inset:0;z-index:2147483000;display:flex;',
    'align-items:center;justify-content:center;pointer-events:auto;',
    'background:radial-gradient(ellipse at center,rgba(0,0,0,.28) 0%,rgba(0,0,0,.55) 100%);',
    'font-family:"Palatino Linotype",Palatino,Georgia,serif;color:#d9cfb4;user-select:none}',
    '#thornswood-wheel.gone{display:none}',
    '#thornswood-wheel .frame{display:flex;align-items:stretch;gap:0;',
    'background:rgba(11,10,8,.94);border:1px solid rgba(198,170,109,.42);',
    'outline:1px solid rgba(198,170,109,.14);outline-offset:4px;',
    'box-shadow:0 24px 80px rgba(0,0,0,.7);overflow:hidden}',
    '#thornswood-wheel .wheelwrap{width:520px;height:560px;display:flex;align-items:center;justify-content:center;',
    'border-right:1px solid rgba(198,170,109,.22)}',
    '#thornswood-wheel svg{overflow:visible}',
    '#thornswood-wheel .seg{fill:rgba(14,13,11,.72);stroke:rgba(198,170,109,.28);stroke-width:1}',
    '#thornswood-wheel .seg.hot{fill:rgba(120,94,44,.88);stroke:rgba(233,209,155,.9)}',
    '#thornswood-wheel .label{fill:#f6e9c8;font-size:15px;text-anchor:middle;',
    'dominant-baseline:middle;pointer-events:none}',
    '#thornswood-wheel .num{fill:rgba(198,170,109,.85);font-size:13px;text-anchor:middle;',
    'dominant-baseline:middle;pointer-events:none;letter-spacing:.12em}',
    '#thornswood-hub{fill:rgba(14,13,11,.86);stroke:rgba(198,170,109,.45);stroke-width:1.5}',
    '#thornswood-hub.hot{fill:rgba(120,44,44,.9);stroke:rgba(233,170,155,.9)}',
    '#thornswood-hubtext{fill:#c6aa6d;font-size:15px;text-anchor:middle;dominant-baseline:middle;',
    'pointer-events:none;letter-spacing:.12em}',
    '#thornswood-ringname{fill:#c6aa6d;font-size:13px;text-anchor:middle;letter-spacing:.22em;',
    'text-transform:uppercase;pointer-events:none}',
    '#thornswood-hint{fill:rgba(217,207,180,.7);font-size:13px;text-anchor:middle;pointer-events:none}',
    '#thornswood-wheel .side{width:360px;display:flex;flex-direction:column;padding:18px 18px 14px}',
    '#thornswood-wheel .side h2{margin:0 0 10px;font-size:26px;font-weight:normal;color:#f6e9c8}',
    '#thornswood-wheel .side input{font-family:inherit;font-size:16px;line-height:22px;color:#f6e9c8;',
    'background:rgba(0,0,0,.35);border:1px solid rgba(198,170,109,.30);padding:8px 10px;width:100%}',
    '#thornswood-wheel .side input:focus{border-color:rgba(198,170,109,.55)}',
    '#thornswood-wheel .mode{margin:10px 0;font-size:14px;font-style:italic;color:rgba(217,207,180,.7);',
    'min-height:20px}',
    '#thornswood-wheel .pins{display:flex;gap:6px;margin-bottom:10px;flex-wrap:wrap}',
    '#thornswood-wheel .pins button,#thornswood-wheel .row button{font-family:inherit;cursor:pointer;',
    'border:1px solid rgba(198,170,109,.55);background:rgba(0,0,0,.25);color:#e9d19b;',
    'padding:5px 8px;font-size:14px;letter-spacing:.08em;text-transform:uppercase}',
    '#thornswood-wheel .pins button.on,#thornswood-wheel button.go{background:#c6aa6d;border-color:#e9d19b;color:#1b1205}',
    '#thornswood-wheel .rows{overflow:auto;flex:1;border-top:1px solid rgba(198,170,109,.22);padding-top:8px}',
    '#thornswood-wheel .row{display:flex;align-items:center;gap:8px;margin-bottom:5px}',
    '#thornswood-wheel .row .nm{flex:1;text-align:left;font-size:16px;letter-spacing:.02em;',
    'text-transform:none;color:#f6e9c8;padding:7px 10px}',
    '#thornswood-wheel .none{color:rgba(217,207,180,.6);font-style:italic;padding:8px 2px}',
    '#thornswood-wheel ::-webkit-scrollbar{width:10px;height:10px}',
    '#thornswood-wheel ::-webkit-scrollbar-track{background:rgba(0,0,0,.25)}',
    '#thornswood-wheel ::-webkit-scrollbar-thumb{background:rgba(198,170,109,.35);border:2px solid transparent;',
    'background-clip:padding-box;border-radius:6px}'
  ].join('');

  var style = document.createElement('style');
  style.id = 'thornswood-wheel-css';
  style.textContent = css;
  (document.head || document.documentElement).appendChild(style);

  try {
    document.documentElement.style.background = 'transparent';
    document.body.style.background = 'transparent';
  } catch (e) { }

  var SVGNS = 'http://www.w3.org/2000/svg';
  var host = document.createElement('div');
  host.id = 'thornswood-wheel';
  host.className = 'gone';
  host.innerHTML =
    '<div class="frame">' +
    '<div class="wheelwrap">' +
    '<svg width="500" height="540" viewBox="-250 -270 500 540" aria-label="Emote wheel">' +
    '<text id="thornswood-ringname" x="0" y="-236">Quick slots</text>' +
    '<g id="thornswood-segments"></g>' +
    '<circle id="thornswood-hub" cx="0" cy="0" r="46"></circle>' +
    '<text id="thornswood-hubtext" x="0" y="1">STOP</text>' +
    '<text id="thornswood-hint" x="0" y="248">click a slot, or 1 to 8 with the wheel shut</text>' +
    '</svg></div>' +
    '<div class="side">' +
    '<h2>Emotes</h2>' +
    '<input id="thornswood-emote-find" placeholder="Search" autocomplete="off">' +
    '<div class="pins" id="thornswood-emote-pins"></div>' +
    '<div class="mode" id="thornswood-emote-mode"></div>' +
    '<div class="rows" id="thornswood-emote-rows"></div>' +
    '</div></div>';
  document.body.appendChild(host);

  var segs = document.getElementById('thornswood-segments');
  var hub = document.getElementById('thornswood-hub');
  var find = document.getElementById('thornswood-emote-find');
  var pins = document.getElementById('thornswood-emote-pins');
  var mode = document.getElementById('thornswood-emote-mode');
  var rows = document.getElementById('thornswood-emote-rows');

  var R_IN = 78, R_OUT = 210, R_LABEL = 148;

  function polar(r, deg) {
    var a = (deg - 90) * Math.PI / 180;
    return [r * Math.cos(a), r * Math.sin(a)];
  }

  function wedge(from, to) {
    var a = polar(R_OUT, from), b = polar(R_OUT, to);
    var c = polar(R_IN, to), d = polar(R_IN, from);
    var big = (to - from) > 180 ? 1 : 0;
    return 'M' + a[0] + ',' + a[1] +
           'A' + R_OUT + ',' + R_OUT + ' 0 ' + big + ' 1 ' + b[0] + ',' + b[1] +
           'L' + c[0] + ',' + c[1] +
           'A' + R_IN + ',' + R_IN + ' 0 ' + big + ' 0 ' + d[0] + ',' + d[1] + 'Z';
  }

  function say(what) {
    try { window.skyrimPlatform.sendMessage('thornswood-emote', what); }
    catch (e) { try { console.log('[emotes] sendMessage failed: ' + e); } catch (e2) { } }
  }

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function open() { return host.className.indexOf('gone') === -1; }

  function searching() {
    return document.activeElement === find;
  }

  function drawSlots() {
    while (segs.firstChild) segs.removeChild(segs.firstChild);
    var n = slots.length || 8;
    var step = 360 / n;
    for (var i = 0; i < n; i++) {
      (function (i) {
        var from = i * step - step / 2;
        var to = from + step;
        var path = document.createElementNS(SVGNS, 'path');
        path.setAttribute('class', 'seg');
        path.setAttribute('d', wedge(from, to));
        var mid = polar(R_LABEL, from + step / 2);
        var label = document.createElementNS(SVGNS, 'text');
        label.setAttribute('class', 'label');
        label.setAttribute('x', mid[0]);
        label.setAttribute('y', mid[1] - 8);
        var name = slots[i] || 'Empty';
        label.textContent = name.length > 14 ? name.slice(0, 13) + '.' : name;
        var num = document.createElementNS(SVGNS, 'text');
        num.setAttribute('class', 'num');
        num.setAttribute('x', mid[0]);
        num.setAttribute('y', mid[1] + 14);
        num.textContent = String(i + 1);
        function hot(on) { path.setAttribute('class', on ? 'seg hot' : 'seg'); }
        path.addEventListener('mouseenter', function () { hot(true); });
        path.addEventListener('mouseleave', function () { hot(false); });
        path.addEventListener('click', function () {
          if (slots[i]) { say('__slot ' + (i + 1)); }
        });
        segs.appendChild(path);
        segs.appendChild(label);
        segs.appendChild(num);
      })(i);
    }
  }

  function drawPins() {
    var html = '';
    for (var i = 0; i < (slots.length || 8); i++) {
      html += '<button data-pin="' + (i + 1) + '"' + (pin === i + 1 ? ' class="on"' : '') + '>' +
              (i + 1) + '</button>';
    }
    pins.innerHTML = html;
    var buttons = pins.querySelectorAll('button');
    for (var b = 0; b < buttons.length; b++) {
      buttons[b].onclick = function () {
        var n = Number(this.getAttribute('data-pin'));
        pin = pin === n ? 0 : n;
        drawPins();
        drawMode();
      };
    }
  }

  function drawMode() {
    if (!pin) {
      mode.textContent = 'Click a name to play it. Click a number to assign that slot.';
      return;
    }
    mode.textContent = 'Slot ' + pin + ' is ' + (slots[pin - 1] || 'empty') +
      '. Click a name to put it there.';
  }

  function drawRows() {
    var low = query.toLowerCase();
    var list = items.filter(function (it) {
      return !low || it.name.toLowerCase().indexOf(low) !== -1;
    });
    if (!list.length) {
      rows.innerHTML = '<div class="none">No emote by that name.</div>';
      return;
    }
    var html = '';
    for (var i = 0; i < list.length; i++) {
      html += '<div class="row"><button class="nm" data-play="' + esc(list[i].name) + '">' +
              esc(list[i].name) + '</button></div>';
    }
    rows.innerHTML = html;
    var buttons = rows.querySelectorAll('button[data-play]');
    for (var b = 0; b < buttons.length; b++) {
      buttons[b].onclick = function () {
        var name = this.getAttribute('data-play');
        if (pin) {
          slots[pin - 1] = name;
          say('__assign ' + pin + ' ' + name);
          drawSlots();
          drawMode();
          return;
        }
        say('__play ' + name);
      };
    }
  }

  find.oninput = function () { query = find.value; drawRows(); };
  find.addEventListener('mousedown', function (e) { e.stopPropagation(); });

  hub.addEventListener('mouseenter', function () { hub.setAttribute('class', 'hot'); });
  hub.addEventListener('mouseleave', function () { hub.setAttribute('class', ''); });
  hub.addEventListener('click', function () { say('__hub'); });

  host.addEventListener('mousedown', function (e) {
    if (e.target === host) { say('__close'); }
  });

  document.addEventListener('contextmenu', function (e) {
    if (!open()) return;
    e.preventDefault();
  });

  var closeChar = 'g';

  document.addEventListener('keydown', function (e) {
    if (!open()) return;
    if (e.repeat) { e.preventDefault(); return; }
    var k = e.key || '';
    if (searching() && k !== 'Escape' && k !== 'Tab') { return; }
    if (k === 'Escape' || e.keyCode === 27) { e.preventDefault(); return; }
    if (k === 'Tab' || e.keyCode === 9) {
      e.preventDefault();
      try { find.focus(); } catch (err) { }
      return;
    }
    if (closeChar && k.toLowerCase() === closeChar) {
      e.preventDefault();
      return;
    }
    if (k >= '1' && k <= '8') {
      e.preventDefault();
      say('__slot ' + k);
    }
  }, true);

  window.thornswoodSetWheel = function (list, slotNames, closeKeyChar) {
    items = (list || []).slice().sort(function (a, b) {
      return String(a.name).toLowerCase() < String(b.name).toLowerCase() ? -1 : 1;
    });
    slots = (slotNames || []).slice();
    while (slots.length < 8) { slots.push(''); }
    if (typeof closeKeyChar === 'string' && closeKeyChar) {
      closeChar = closeKeyChar.toLowerCase();
    }
    host.className = '';
    query = '';
    find.value = '';
    pin = 0;
    drawSlots();
    drawPins();
    drawMode();
    drawRows();
  };

  // Older callers. The wheel no longer has a second ring, so a list handed
  // this way is the emote list and the slots stay as they are.
  window.thornswoodSetRing = function (list, title, hubWord, hint, closeKeyChar) {
    window.thornswoodSetWheel(list, slots.length ? slots : [], closeKeyChar);
    if (title) {
      var ring = document.getElementById('thornswood-ringname');
      if (ring) { ring.textContent = title; }
    }
    if (hubWord) {
      var word = document.getElementById('thornswood-hubtext');
      if (word) { word.textContent = hubWord; }
    }
    if (hint) {
      var line = document.getElementById('thornswood-hint');
      if (line) { line.textContent = hint; }
    }
  };

  window.thornswoodHideWheel = function () {
    host.className = 'gone';
    pin = 0;
    try { find.blur(); } catch (e) { }
  };

  say('__ready');
})();
