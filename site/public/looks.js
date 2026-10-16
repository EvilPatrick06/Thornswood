/*
  Make the site yours (#515). The visitor picks a palette, a typeface and a
  weight once, and every page of thornswood.net remembers it: the front, the
  written pages, the hub and the plain door pages.

  WHY THIS IS A FILE IN <head> AND NOT PART OF home.js. The choice has to be
  on <html> before the first paint, or a Parchment reader sees a flash of
  Night on every page load. home.js and hub.js run at the end of <body>. The
  CSP is script-src 'self', so this cannot be an inline <script> either: it is
  a small same-origin file, loaded without defer, ahead of the stylesheets.

  WHAT IS STORED. One localStorage key, tw:look, holding
  {"palette":..,"font":..,"weight":..}. Nothing goes to the server and no
  cookie is set. Every value is checked against OPTIONS, so a hand-edited or
  stale value falls back to the default rather than putting an unknown string
  on <html>. Storage that throws (blocked, private mode) gives the default.

  The default of each choice is the first entry, and the default is written
  as NO attribute at all, so the site as designed is exactly the CSS with no
  looks.css rule matching. looks.css only redefines tokens.
*/
(function () {
  'use strict';
  var KEY = 'tw:look';
  var OPTIONS = {
    palette: [['night', 'Night'], ['parchment', 'Parchment'], ['contrast', 'High contrast']],
    font:    [['designed', 'As designed'], ['plain', 'Plain'], ['book', 'Book']],
    weight:  [['regular', 'Regular'], ['heavier', 'Heavier']]
  };
  var LABELS = { palette: 'Colours', font: 'Font', weight: 'Weight' };
  // The browser bar colour on phones, per palette (meta theme-color).
  var BAR = { night: '#0B0E0A', parchment: '#EFE9DA', contrast: '#000000' };

  function allowed(kind, v) {
    var list = OPTIONS[kind];
    for (var i = 0; i < list.length; i++) if (list[i][0] === v) return true;
    return false;
  }
  function clean(v) {
    var out = {};
    for (var kind in OPTIONS) {
      out[kind] = (v && typeof v === 'object' && allowed(kind, v[kind])) ? v[kind] : OPTIONS[kind][0][0];
    }
    return out;
  }
  function read() {
    var raw = null;
    try { raw = window.localStorage.getItem(KEY); } catch (e) { raw = null; }
    var v = null;
    try { v = raw ? JSON.parse(raw) : null; } catch (e) { v = null; }
    return clean(v);
  }
  function apply(look) {
    var root = document.documentElement;
    for (var kind in OPTIONS) {
      if (look[kind] === OPTIONS[kind][0][0]) root.removeAttribute('data-' + kind);
      else root.setAttribute('data-' + kind, look[kind]);
    }
    var bar = document.querySelector('meta[name="theme-color"]');
    if (bar) bar.setAttribute('content', BAR[look.palette]);
  }
  function save(look) {
    var c = clean(look);
    var isDefault = true;
    for (var kind in OPTIONS) if (c[kind] !== OPTIONS[kind][0][0]) isDefault = false;
    try {
      if (isDefault) window.localStorage.removeItem(KEY);
      else window.localStorage.setItem(KEY, JSON.stringify(c));
    } catch (e) { /* storage blocked: still applied for this page */ }
    apply(c);
    return c;
  }

  // The picker. Any element with data-look-picker gets the three choices and
  // a reset, built from OPTIONS so the menu and the allowlist cannot drift.
  function picker(box) {
    var now = read();
    var selects = {};
    box.textContent = '';
    for (var kind in OPTIONS) {
      var id = 'look-' + kind;
      var lab = document.createElement('label');
      lab.setAttribute('for', id);
      lab.textContent = LABELS[kind];
      var sel = document.createElement('select');
      sel.id = id;
      sel.setAttribute('data-look', kind);
      OPTIONS[kind].forEach(function (o) {
        var opt = document.createElement('option');
        opt.value = o[0];
        opt.textContent = o[1];
        sel.appendChild(opt);
      });
      sel.value = now[kind];
      sel.addEventListener('change', function () {
        var next = {};
        for (var k in selects) next[k] = selects[k].value;
        save(next);
      });
      selects[kind] = sel;
      lab.appendChild(sel);
      box.appendChild(lab);
    }
    var reset = document.createElement('button');
    reset.type = 'button';
    reset.className = 'look-reset';
    reset.textContent = 'Back to the default';
    reset.addEventListener('click', function () {
      var d = save({});
      for (var k in selects) selects[k].value = d[k];
    });
    box.appendChild(reset);
    return selects;
  }

  apply(read());

  // A change made in another tab follows into this one.
  window.addEventListener('storage', function (e) {
    if (e.key !== KEY && e.key !== null) return;
    var look = read();
    apply(look);
    var sels = document.querySelectorAll('select[data-look]');
    for (var i = 0; i < sels.length; i++) sels[i].value = look[sels[i].getAttribute('data-look')];
  });

  document.addEventListener('DOMContentLoaded', function () {
    var boxes = document.querySelectorAll('[data-look-picker]');
    for (var i = 0; i < boxes.length; i++) picker(boxes[i]);
  });

  window.twLook = { KEY: KEY, OPTIONS: OPTIONS, read: read, save: save, clean: clean };
})();
