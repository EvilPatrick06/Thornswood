'use strict';
/*
  The emote wheel, as an overlay inside the front rather than a page of its own.

  It used to be thornswood-emotes.html, loaded with browser.loadUrl. There is
  only one browser, so that replaced whatever was already in it: the chat, the
  names above heads, the whole front. Last call to loadUrl won, and since the
  wheel opened later than the front started, the wheel always won. That is why
  the chat never appeared even once the files were installed.

  So nothing loads a page any more except thornswood-front.js. This mounts
  itself into whatever is already there, at the end of the body, where React
  is not looking.
*/

(function () {
  if (window.thornswoodSetRing) return;

  var R_IN = 62, R_OUT = 244, R_LABEL = 158;
  var items = [];

  // ------------------------------------------------------------------ css --
  var css = [
    '#thornswood-wheel{position:fixed;inset:0;z-index:2147483000;display:flex;',
    'align-items:center;justify-content:center;pointer-events:none;',
    'font-family:"Palatino Linotype",Palatino,Georgia,serif;user-select:none}',
    '#thornswood-wheel svg{overflow:visible;pointer-events:auto}',
    '#thornswood-wheel.gone{display:none}',
    '#thornswood-wheel .seg{fill:rgba(14,13,11,.72);stroke:rgba(198,170,109,.28);',
    'stroke-width:1;transition:fill 90ms linear}',
    '#thornswood-wheel .seg.hot{fill:rgba(120,94,44,.88);stroke:rgba(233,209,155,.9)}',
    '#thornswood-wheel .label{fill:#d9cfb4;font-size:13px;text-anchor:middle;',
    'dominant-baseline:middle;pointer-events:none}',
    '#thornswood-wheel .label.hot{fill:#f6e9c8}',
    '#thornswood-wheel .num{fill:rgba(198,170,109,.5);font-size:10px;text-anchor:middle;',
    'dominant-baseline:middle;pointer-events:none}',
    '#thornswood-hub{fill:rgba(14,13,11,.86);stroke:rgba(198,170,109,.45);',
    'stroke-width:1.5;transition:fill 90ms linear}',
    '#thornswood-hub.hot{fill:rgba(120,44,44,.9);stroke:rgba(233,170,155,.9)}',
    '#thornswood-hubtext{fill:#c6aa6d;font-size:15px;text-anchor:middle;',
    'dominant-baseline:middle;pointer-events:none;letter-spacing:.08em}',
    '#thornswood-ringname{fill:#c6aa6d;font-size:13px;text-anchor:middle;',
    'letter-spacing:.22em;text-transform:uppercase;pointer-events:none}',
    '#thornswood-hint{fill:rgba(217,207,180,.55);font-size:11.5px;text-anchor:middle;',
    'pointer-events:none;letter-spacing:.04em}'
  ].join('');

  var style = document.createElement('style');
  style.id = 'thornswood-wheel-css';
  style.textContent = css;
  (document.head || document.documentElement).appendChild(style);

  // The overlay composites straight over the game, so anything behind the
  // wheel has to be genuinely transparent rather than dark.
  try {
    document.documentElement.style.background = 'transparent';
    document.body.style.background = 'transparent';
  } catch (e) { }

  // ----------------------------------------------------------------- dom ---
  var SVGNS = 'http://www.w3.org/2000/svg';
  var host = document.createElement('div');
  host.id = 'thornswood-wheel';
  host.className = 'gone';
  host.innerHTML =
    '<svg width="520" height="560" viewBox="-260 -270 520 560" aria-label="Emote wheel">' +
    '<text id="thornswood-ringname" x="0" y="-238">ThornsWood</text>' +
    '<g id="thornswood-segments"></g>' +
    '<circle id="thornswood-hub" cx="0" cy="0" r="54"></circle>' +
    '<text id="thornswood-hubtext" x="0" y="0">STOP</text>' +
    '<text id="thornswood-hint" x="0" y="258">click, or press 1–9 and 0 · Tab for the next ring · Esc to close</text>' +
    '</svg>';
  document.body.appendChild(host);

  var segs = document.getElementById('thornswood-segments');
  var hub = document.getElementById('thornswood-hub');
  var ringName = document.getElementById('thornswood-ringname');
  var hubText = document.getElementById('thornswood-hubtext');
  var hintText = document.getElementById('thornswood-hint');

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

  function draw(list) {
    while (segs.firstChild) segs.removeChild(segs.firstChild);
    var n = list.length;
    if (!n) return;
    var step = 360 / n;

    for (var i = 0; i < n; i++) {
      (function (i) {
        var item = list[i];
        // The first wedge is centred on straight up, so the labels sit in the
        // order people read them.
        var from = i * step - step / 2;
        var to = from + step;

        var path = document.createElementNS(SVGNS, 'path');
        path.setAttribute('class', 'seg');
        path.setAttribute('d', wedge(from, to));

        var mid = polar(R_LABEL, from + step / 2);
        var label = document.createElementNS(SVGNS, 'text');
        label.setAttribute('class', 'label');
        label.setAttribute('x', mid[0]);
        label.setAttribute('y', mid[1]);
        label.textContent = item.name;

        // Under the label rather than further along the radius: on the
        // horizontal wedges a radial offset puts the digit beside the word and
        // the two read as one string.
        var num = document.createElementNS(SVGNS, 'text');
        num.setAttribute('class', 'num');
        num.setAttribute('x', mid[0]);
        num.setAttribute('y', mid[1] + 15);
        num.textContent = i < 9 ? String(i + 1) : (i === 9 ? '0' : '');

        function hot(on) {
          path.setAttribute('class', on ? 'seg hot' : 'seg');
          label.setAttribute('class', on ? 'label hot' : 'label');
        }
        path.addEventListener('mouseenter', function () { hot(true); });
        path.addEventListener('mouseleave', function () { hot(false); });
        path.addEventListener('click', function () {
          // The index, not the event.
          //
          // The wheel has two levels now, categories and then the emotes in
          // one, so a wedge is not always an animation: picking "Revelry" is
          // not something to play. The page draws whatever list it was handed
          // and says which one was chosen; deciding what that means belongs
          // with the plugin, which is the side that knows which level is up.
          say('__pick ' + i + ' ' + item.name);
        });

        segs.appendChild(path);
        segs.appendChild(label);
        segs.appendChild(num);
      })(i);
    }
  }

  hub.addEventListener('mouseenter', function () { hub.setAttribute('class', 'hot'); });
  hub.addEventListener('mouseleave', function () { hub.setAttribute('class', ''); });
  hub.addEventListener('click', function () { say('__hub'); });

  document.addEventListener('contextmenu', function (e) {
    if (host.className.indexOf('gone') !== -1) return;
    e.preventDefault();
    say('__back');
  });

  // ---------------------------------------------------------------- keys ---
  // The wheel's own keys have to be read here, not in the plugin.
  //
  // Opening the wheel raises browser focus, and raising focus makes
  // DInputHook withhold DirectInput from the game. SkyrimPlatform's
  // buttonEvent is built out of the game's input, so from the moment the wheel
  // is up the plugin is deaf: escape, tab, the digits and the key that opened
  // it all went nowhere. The only way out was the mouse, and if the mouse was
  // not landing either then the wheel was a thing you could open and not
  // close. CEF still gets keys, through a raw input hook that does not care
  // about focus, so they are read from the page instead.
  var closeChar = 'g';

  // When the wheel went up, so the key that put it there can be ignored.
  //
  // The same trap as the chat, and it is why the wheel looked like it never
  // opened at all. CEF is fed every keystroke whenever the browser is visible,
  // focused or not, so the G that the plugin reads as "open the wheel" also
  // arrives here a moment later, where it reads as "close the wheel". The log
  // proves it: the overlay came up and then said "the page asked to close",
  // twice, without anybody pressing anything else.
  /*
   * Whether the key that opened the wheel has been let go yet.
   *
   * This was a 400 millisecond timer and the timer was the bug. Holding G for
   * half a second is not a second press, but the browser sends autorepeat
   * keydowns the whole time it is held, and the first one past the deadline
   * closed the wheel. Worse, closing is a round trip through the plugin, so
   * every repeat after it sent another close while the wheel was still up:
   *
   *     [emotes] the page asked to close
   *     [emotes] the page asked to close
   *
   * From the chair that is a wheel that never appeared, a G that went to the
   * game instead and drew your fists, and a second or two with no keyboard
   * while focus went up and came back down.
   *
   * A release is not a guess. The wheel cannot be closed by the key that
   * opened it until that key has actually come up.
   */
  function open() { return host.className.indexOf('gone') === -1; }

  document.addEventListener('keydown', function (e) {
    if (!open()) return;
    // Autorepeat is one press being held, never a new one.
    if (e.repeat) { e.preventDefault(); return; }
    var k = e.key || '';

    // Back rather than close. On the emote list it steps up to the categories,
    // and only closes from there, so getting out of a category you opened by
    // mistake does not throw the whole wheel away.
    /*
      Swallowed here, decided by the plugin. Same rule as the close key below,
      and for the same reason.

      Both ends were acting on these. The page sent __back and the plugin also
      ran back() off its own buttonEvent, so one press of Escape inside a
      category stepped up to the categories and then closed the wheel. Tab
      turned the ring twice. A digit on the category ring opened the category
      and then played whatever emote sat at that index in it.

      preventDefault still matters: it stops the key reaching the game
      underneath. It is only the message that goes.
    */
    if (k === 'Escape' || e.keyCode === 27) { e.preventDefault(); return; }
    if (k === 'Tab' || e.keyCode === 9) { e.preventDefault(); return; }
    /*
      The close key is swallowed here and decided by the plugin.

      This page used to close the wheel itself, on the theory that raising
      browser focus stops the plugin hearing keys at all. That theory is wrong.
      DInputHook feeds plugins from the keyboard snapshot and only withholds
      the buffer from the game, so the plugin sees every press whether the
      wheel holds focus or not. The front log says so outright:

          input: 145 keys in 5s, browser focus yes, menu no

      With both ends acting on the same key they raced, and the page won. One
      tap opened the wheel and shut it again in the same frame:

          [emotes] opening the wheel
          [emotes] the page asked to close
          [emotes] closing the wheel

      Eleven times in one session, which from the chair is a wheel that never
      appears. One end owns the decision now, and it is the end that can see
      whether the wheel is already open.
    */
    if (closeChar && k.toLowerCase() === closeChar) {
      e.preventDefault();
      return;
    }

    // 1 to 9, then 0, matching the digit printed under each label. Swallowed
    // so the game does not also get them, and left to the plugin to act on.
    // A click on a wedge still sends __pick, which is the mouse and has no
    // second handler anywhere.
    if (k >= '0' && k <= '9') {
      var at = k === '0' ? 9 : (k.charCodeAt(0) - 49);
      if (items[at]) { e.preventDefault(); }
    }
  }, true);

  // Called by the plugin every time it shows the wheel or turns the ring.
  /**
   * Show a list.
   *
   * Everything about what the list means is decided by the plugin: the title
   * across the top, the word in the hub, the line along the bottom. This file
   * knows how to draw a ring and how to report a click, and deliberately
   * nothing else, so adding a third level or reordering the categories never
   * touches it.
   */
  window.thornswoodSetRing = function (list, title, hubWord, hint, closeKeyChar) {
    items = list || [];
    if (typeof closeKeyChar === 'string' && closeKeyChar) {
      closeChar = closeKeyChar.toLowerCase();
    }
    host.className = items.length ? '' : 'gone';
    ringName.textContent = title || 'Emotes';
    hubText.textContent = hubWord || 'STOP';
    hintText.textContent = hint || '';
    draw(items);
  };

  // Hiding is now a class on the overlay rather than a page being unloaded,
  // so the plugin needs a way to put it away without clearing the ring.
  window.thornswoodHideWheel = function () { host.className = 'gone'; };

  say('__ready');
})();
