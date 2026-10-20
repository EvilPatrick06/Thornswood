'use strict';
/*
  The trade ships' panel (#2700, split from #511): the dock, and the staff
  side that keeps the ports and routes.

  E on a port's crate opens the dock side; Ports and routes on the Office page
  of K opens the staff side. The server answers on thornswoodShipView, and
  setData with open draws this panel; open false closes it.

  THE CONTRACT with thornswood-front.js, the same shape the box panel uses:

    window.thornswoodShip = { open, close, isOpen, setData }
    page -> plugin  'ship:ready' | 'ship:opened' | 'ship:closed'
    page -> server  '/ship load|sail|collect|return|close ...' at a dock and
                    '/ship draft|confirm|add|staff ...' for staff, through
                    window.thornswoodNet.say; nobody is told to type them
                    (Patrick, 4 Oct: no chat commands for what people do).

  WHAT IT SHOWS IS WHAT THE SERVER SENT. The server decides who may load or
  sail (the Trading Company's charter), which lines a person sees, and what a
  staff draft would change. This page draws the rows it is given and never
  works out who may do what. Nothing here moves a piece or a coin.
*/
(function () {
  if (window.thornswoodShip) { return; }

  var ID = 'ts-ship';
  var data = null;
  var shown = false;
  var root = null;

  function tell(what) {
    try { window.skyrimPlatform.sendMessage('thornswood-front', 'ship:' + what); }
    catch (e) { }
  }
  function net(line) {
    try {
      if (window.thornswoodNet && window.thornswoodNet.say) { window.thornswoodNet.say(line); return true; }
    } catch (e) { }
    return false;
  }
  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function plain(s) { return String(s == null ? '' : s).replace(/\s+/g, ' ').trim(); }

  var CSS = [
    '#' + ID + '{position:fixed;inset:0;z-index:2147483000;display:none;',
    '  background:radial-gradient(ellipse at center,rgba(0,0,0,.50) 0%,rgba(0,0,0,.72) 100%);',
    '  font-family:"Palatino Linotype",Palatino,Georgia,serif;color:#d9cfb4}',
    '#' + ID + '.on{display:grid;place-items:center}',
    '#' + ID + ' .panel{width:760px;max-width:calc(100vw - 48px);max-height:calc(100vh - 48px);',
    '  display:grid;grid-template-rows:auto 1fr auto;background:rgba(11,10,8,.94);',
    '  border:1px solid rgba(198,170,109,.42);outline:1px solid rgba(198,170,109,.14);',
    '  outline-offset:-6px;box-shadow:0 24px 80px rgba(0,0,0,.7);overflow:hidden}',
    '#' + ID + ' h2{margin:0;padding:18px 24px 14px;font-size:26px;font-weight:normal;',
    '  color:#f6e9c8;border-bottom:1px solid rgba(198,170,109,.22)}',
    '#' + ID + ' h3{font-size:19px;font-weight:normal;color:#f6e9c8;margin:16px 0 8px}',
    '#' + ID + ' .body{overflow:auto;padding:12px 20px;font-size:16px}',
    '#' + ID + ' .note{color:rgba(217,207,180,.8);font-style:italic;margin:0 0 10px}',
    '#' + ID + ' .line{display:flex;gap:8px;align-items:center;flex-wrap:wrap;padding:8px 10px;',
    '  border:1px solid rgba(198,170,109,.30);background:rgba(0,0,0,.20);margin-bottom:6px}',
    '#' + ID + ' .nm{flex:1;min-width:160px}',
    '#' + ID + ' select,#' + ID + ' input{font:inherit;color:#f6e9c8;background:#17140f;border:1px solid #ac9564;padding:5px}',
    '#' + ID + ' input[type=number]{width:5em}',
    '#' + ID + ' button{font-family:inherit;cursor:pointer;border:1px solid rgba(198,170,109,.55);',
    '  background:rgba(0,0,0,.25);color:#e9d19b;padding:5px 10px;font-size:14px;letter-spacing:.12em;text-transform:uppercase}',
    '#' + ID + ' .foot{padding:12px 20px;border-top:1px solid rgba(198,170,109,.22);display:flex;gap:12px;justify-content:flex-end}'
  ].join('\n');

  function build() {
    if (root) { return root; }
    var style = document.createElement('style');
    style.textContent = CSS;
    document.head.appendChild(style);
    root = document.createElement('div');
    root.id = ID;
    root.innerHTML = '<div class="panel" role="dialog" aria-modal="true" aria-labelledby="' + ID + '-title">' +
      '<h2 id="' + ID + '-title">Ship</h2><div class="body" id="' + ID + '-body"></div>' +
      '<div class="foot"><button id="' + ID + '-close">Step back</button></div></div>';
    document.body.appendChild(root);
    root.querySelector('#' + ID + '-close').onclick = function () { net('/ship close'); close(); };
    root.addEventListener('click', onClick);
    return root;
  }

  function val(id) { var el = document.getElementById(id); return el ? plain(el.value) : ''; }
  function count(id) {
    var el = document.getElementById(id);
    var n = el ? Number(el.value) : 0;
    if (!Number.isInteger(n) || n < 1 || (el.max && n > Number(el.max))) {
      if (el && el.setCustomValidity) { el.setCustomValidity('Choose a whole count from 1 to ' + (el.max || 'any') + '.'); el.reportValidity(); }
      return 0;
    }
    if (el.setCustomValidity) { el.setCustomValidity(''); }
    return n;
  }

  /* Every button carries what it sends; a button that needs a box reads it here. */
  function onClick(ev) {
    var el = ev.target;
    while (el && el !== root && !(el.getAttribute && el.getAttribute('data-act'))) { el = el.parentNode; }
    if (!el || el === root) { return; }
    var a = el.getAttribute('data-act'), h = el.getAttribute('data-hold') || '', k = el.getAttribute('data-key') || '';
    var n;
    if (a === 'say') { net(el.getAttribute('data-line')); return; }
    if (a === 'collect' || a === 'return') {
      n = count(el.getAttribute('data-count'));
      if (n) { net('/ship ' + a + ' ' + h + ' ' + el.getAttribute('data-line') + ' ' + n); }
      return;
    }
    if (a === 'load') {
      var piece = val(ID + '-piece-' + h).split(':'), to = val(ID + '-for-' + h);
      n = count(ID + '-count-' + h);
      if (piece.length === 2 && to && n) { net('/ship load ' + h + ' ' + piece[0] + ' ' + piece[1] + ' ' + n + ' ' + to); }
      return;
    }
    if (a === 'port') {
      var key = val(ID + '-pkey').toLowerCase(), hold = val(ID + '-phold'), name = val(ID + '-pname');
      if (key && hold && name) { net('/ship draft port ' + key + ' ' + hold + ' ' + name); }
      return;
    }
    if (a === 'route') {
      var m = count(ID + '-rmin');
      if (m) { net('/ship draft route ' + val(ID + '-rfrom') + ' ' + val(ID + '-rto') + ' ' + m); }
      return;
    }
    if (a === 'minutes') {
      var mm = count(el.getAttribute('data-count'));
      if (mm) { net('/ship draft route ' + k + ' ' + mm); }
    }
  }

  function line(inner) { return '<div class="line">' + inner + '</div>'; }
  function btn(text, attrs) { return '<button ' + attrs + '>' + esc(text) + '</button>'; }
  function say(text, l) { return btn(text, 'data-act="say" data-line="' + esc(l) + '"'); }
  function options(list, valueOf, textOf) {
    return list.map(function (x) { return '<option value="' + esc(valueOf(x)) + '">' + esc(textOf(x)) + '</option>'; }).join('');
  }

  function drawDock() {
    var b = '';
    if (data.note) { b += '<p class="note" role="status">' + esc(data.note) + '</p>'; }
    if (data.charter && !data.charter.may) { b += '<p class="note">' + esc(data.charter.why) + '</p>'; }
    var holds = data.holds || [];
    if (!holds.length) { b += '<p class="note">No ship is at this dock.</p>'; }
    holds.forEach(function (h) {
      var hid = esc(h.id);
      b += '<h3>' + hid + ', ' + esc(h.used) + ' of ' + esc(h.max) + ' lines</h3>';
      (h.lines || []).forEach(function (l) {
        var cid = ID + '-c-' + hid + '-' + l.line;
        var out = '<span class="nm">' + esc(l.count) + ' ' + esc(l.item) + ', for ' + esc(l.forName) + '</span>';
        if (l.canCollect || l.canReturn) {
          out += '<input id="' + cid + '" type="number" min="1" max="' + esc(l.count) + '" step="1" value="' + esc(l.count) + '" aria-label="Count">';
          out += btn(l.canCollect ? 'Collect' : 'Take back', 'data-act="' + (l.canCollect ? 'collect' : 'return') +
            '" data-hold="' + hid + '" data-line="' + esc(l.line) + '" data-count="' + cid + '"');
        }
        b += line(out);
      });
      if (h.others) { b += '<p class="note">' + esc(h.others) + ' more line(s) aboard for other people.</p>'; }
      if (h.canLoad && (data.pack || []).length && (data.people || []).length) {
        b += line('<select id="' + ID + '-piece-' + hid + '" aria-label="What to load">' +
          options(data.pack, function (p) { return p.base + ':' + p.nth; }, function (p) { return p.name + ' (' + p.count + ')'; }) + '</select>' +
          '<input id="' + ID + '-count-' + hid + '" type="number" min="1" step="1" value="1" aria-label="Count">' +
          '<label>for</label><select id="' + ID + '-for-' + hid + '" aria-label="Who it is for">' +
          options(data.people, function (p) { return p.actor; }, function (p) { return p.name; }) + '</select>' +
          btn('Load', 'data-act="load" data-hold="' + hid + '"'));
      }
      (h.sail || []).forEach(function (s) {
        b += line('<span class="nm">To ' + esc(s.name) + ', ' + esc(s.minutes) + ' minutes at sea</span>' +
          say('Sail', '/ship sail ' + h.id + ' ' + s.to));
      });
    });
    var inc = data.incoming || [];
    if (inc.length) {
      b += '<h3>Bound here</h3>';
      inc.forEach(function (s) { b += line('<span class="nm">' + esc(s.id) + ' from ' + esc(s.from) + ', due in ' + esc(s.dueIn) + ' minutes</span>'); });
    }
    return b;
  }

  function drawStaff() {
    var b = '';
    if (data.note) { b += '<p class="note" role="status">' + esc(data.note) + '</p>'; }
    var inForce = data.inForce || { ports: [], routes: [] }, draft = data.draft || { ports: [], routes: [] };
    b += '<h3>In force</h3>';
    if (!inForce.ports.length) { b += '<p class="note">No ports. A world with no ships.</p>'; }
    inForce.ports.forEach(function (p) {
      b += line('<span class="nm">' + esc(p.name) + ' (' + esc(p.key) + ', ' + esc(p.hold) + ')' + (p.crate ? '' : ', no crate yet') +
        ', ' + (p.ships || []).length + ' ship(s)</span>' + say('Put a ship here', '/ship add ' + p.key));
    });
    inForce.routes.forEach(function (r) {
      b += line('<span class="nm">' + esc(r.from) + ' to ' + esc(r.to) + ', ' + esc(r.minutes) + ' minutes, crew of ' + esc(r.crew) + '</span>');
    });
    b += '<h3>Your draft</h3>';
    if (data.crate && data.crate.here) {
      b += data.crate.dockOf
        ? '<p class="note">The container you just opened is the dock of ' + esc(data.crate.dockOf) + '.</p>'
        : line('<span class="nm">The container you just opened, as a new port:</span>' +
          '<input id="' + ID + '-pkey" type="text" maxlength="64" placeholder="key" aria-label="Port key">' +
          '<select id="' + ID + '-phold" aria-label="Hold">' + options(data.holdKeys || [], function (x) { return x; }, function (x) { return x; }) + '</select>' +
          '<input id="' + ID + '-pname" type="text" maxlength="64" placeholder="name people read" aria-label="Port name">' +
          btn('Add port', 'data-act="port"'));
    } else {
      b += '<p class="note">Open a crate at a dock, then this page within a minute, to make it a port or move a port\'s crate.</p>';
    }
    draft.ports.forEach(function (p) {
      b += line('<span class="nm">' + esc(p.name) + ' (' + esc(p.key) + ')</span>' +
        (data.crate && data.crate.here && !data.crate.dockOf ? say('Its crate is the one I opened', '/ship draft crate ' + p.key) : '') +
        say('Remove', '/ship draft unport ' + p.key));
    });
    draft.routes.forEach(function (r, i) {
      var cid = ID + '-m-' + i;
      b += line('<span class="nm">' + esc(r.from) + ' to ' + esc(r.to) + '</span>' +
        '<input id="' + cid + '" type="number" min="1" max="10080" step="1" value="' + esc(r.minutes) + '" aria-label="Minutes">' +
        btn('Set minutes', 'data-act="minutes" data-key="' + esc(r.from + ' ' + r.to) + '" data-count="' + cid + '"') +
        say('Remove', '/ship draft unroute ' + r.from + ' ' + r.to));
    });
    if (draft.ports.length > 1) {
      var keys = draft.ports.map(function (p) { return p.key; });
      b += line('<span class="nm">A new route</span>' +
        '<select id="' + ID + '-rfrom" aria-label="From">' + options(keys, function (x) { return x; }, function (x) { return x; }) + '</select>' +
        '<select id="' + ID + '-rto" aria-label="To">' + options(keys, function (x) { return x; }, function (x) { return x; }) + '</select>' +
        '<input id="' + ID + '-rmin" type="number" min="1" max="10080" step="1" value="60" aria-label="Minutes">' +
        btn('Add route', 'data-act="route"'));
    }
    b += '<h3>If you confirm</h3>';
    var ch = data.changes || [], st = data.strands || [];
    if (!ch.length) { b += '<p class="note">The draft is the list in force.</p>'; }
    ch.forEach(function (c) { b += line('<span class="nm">' + esc(c) + '</span>'); });
    st.forEach(function (s) { b += line('<span class="nm">Refused: ' + esc(s) + '</span>'); });
    b += line((data.canConfirm ? say('Confirm', '/ship confirm ' + data.base) : '') + say('Back to the list in force', '/ship draft reset'));
    return b;
  }

  function draw() {
    build();
    if (!data || data.open !== true) { close(); return; }
    root.className = 'on';
    var was = shown;
    shown = true;
    root.querySelector('#' + ID + '-title').textContent = data.mode === 'staff' ? 'Ports and routes' :
      ((data.port && data.port.name) || 'The dock');
    root.querySelector('#' + ID + '-body').innerHTML = data.mode === 'staff' ? drawStaff() : drawDock();
    if (!was) { tell('opened'); }
  }

  function open() { draw(); }
  function close() {
    if (root) { root.className = ''; }
    if (shown) { tell('closed'); }
    shown = false;
  }
  function setData(next) {
    data = next || null;
    if (!data || data.open !== true) { close(); } else { draw(); }
  }

  document.addEventListener('keydown', function (ev) {
    if (!shown) { return; }
    if (ev.key === 'Escape') { ev.preventDefault(); net('/ship close'); close(); }
  });

  window.thornswoodShip = {
    open: open, close: close, setData: setData,
    isOpen: function () { return shown; }
  };
  tell('ready');
})();
