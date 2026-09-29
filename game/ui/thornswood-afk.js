'use strict';
/*
  Are you still here? The window, page side (#1142).

  Patrick, 29 Sep: "we also need an AFK kick in game after 15 mins idle with
  the opportunity for a menu to pop after that 15 minutes with the option to
  click I am still here, if they do click I'm still here it resets, if not it
  kicks them to the main menu where they can rechoose their character and
  they automatically rejoin the queue". The window counts down 60 seconds
  (agreed the same day).

  The clock is thornswood-front.js's, not this page's: the front puts this up
  after 15 minutes with nothing from the keyboard, the mouse or the character,
  holds the keyboard for it (the 'afk' claim, so the button can be clicked),
  and takes the game back to the character choice when its own minute is up.
  This only draws the question and the seconds, and says when the button is
  pressed. Enter or Space press it too.

  THE CONTRACT with thornswood-front.js:
    window.thornswoodAfk = { ask(secs), close(), isOpen(), left() }
    window.THORNSWOOD_AFK_ASK = secs  asks as soon as this file is in
    page -> plugin  'afk:shown' | 'afk:here'
*/
(function () {
  if (window.thornswoodAfk) { return; }

  var ID = 'ts-afk';
  var root = null, elLeft = null;
  var until = 0, timer = 0;

  function tell(what) {
    try { window.skyrimPlatform.sendMessage('thornswood-front', 'afk:' + what); } catch (e) { }
  }

  var css = [
    '#ts-afk{position:fixed;inset:0;z-index:2147483000;display:flex;align-items:center;justify-content:center;',
    'background:rgba(0,0,0,.55);font-family:"Palatino Linotype",Palatino,"Book Antiqua",Georgia,serif;color:#e4d9bf;',
    'user-select:none;pointer-events:auto}',
    '#ts-afk.gone{display:none}',
    '#ts-afk .box{width:560px;max-width:92vw;padding:30px 36px 28px;text-align:center;background:rgba(9,8,6,.96);',
    'border:2px solid rgba(198,170,109,.55);outline:1px solid rgba(198,170,109,.22);outline-offset:6px;',
    'box-shadow:0 30px 90px rgba(0,0,0,.8)}',
    '#ts-afk .eyebrow{font-size:13px;letter-spacing:.42em;text-transform:uppercase;color:#c6aa6d;margin-bottom:10px}',
    '#ts-afk .title{font-size:36px;color:#f6e9c8;line-height:1.1}',
    '#ts-afk .why{font-size:16px;line-height:1.55;color:rgba(228,217,191,.78);margin:14px 0 0}',
    '#ts-afk .left{font-size:18px;color:#e9d19b;margin:16px 0 0}',
    '#ts-afk .here{margin-top:22px;border:1px solid rgba(198,170,109,.6);padding:12px 30px;font-size:18px;',
    'letter-spacing:.2em;text-transform:uppercase;color:#f6e9c8;background:rgba(198,170,109,.14);font-family:inherit}'
  ].join('');

  function mount() {
    if (root) { return; }
    var style = document.createElement('style');
    style.id = 'ts-afk-css';
    style.textContent = css;
    document.head.appendChild(style);
    root = document.createElement('div');
    root.id = ID;
    root.className = 'gone';
    root.innerHTML =
      '<div class="box"><div class="eyebrow">Thornswood</div>' +
      '<div class="title">Are you still here?</div>' +
      '<div class="why">Nothing has come from your keyboard, mouse or character for 15 minutes. ' +
      'If nobody answers, you are taken back to the character choice so somebody waiting can have your seat, ' +
      'and you keep a place in line to come back in.</div>' +
      '<div class="left"></div>' +
      '<button class="here" type="button">I am still here</button></div>';
    document.body.appendChild(root);
    elLeft = root.querySelector('.left');
    root.querySelector('.here').addEventListener('click', here);
  }

  function secondsLeft() { return Math.max(0, Math.ceil((until - Date.now()) / 1000)); }

  function tick() {
    if (!elLeft) { return; }
    var left = secondsLeft();
    elLeft.textContent = left > 0
      ? 'Back to the character choice in ' + left + (left === 1 ? ' second.' : ' seconds.')
      : 'Taking you back to the character choice.';
  }

  function isOpen() { return !!root && root.className !== 'gone'; }

  function ask(secs) {
    mount();
    until = Date.now() + Math.max(1, Number(secs) || 60) * 1000;
    root.className = '';
    tick();
    if (!timer) { timer = setInterval(tick, 250); }
    tell('shown');
  }

  function close() {
    if (timer) { clearInterval(timer); timer = 0; }
    if (root) { root.className = 'gone'; }
  }

  function here() {
    if (!isOpen()) { return; }
    close();
    tell('here');
  }

  window.addEventListener('keydown', function (ev) {
    if (!isOpen()) { return; }
    var k = ev.key || '';
    if (k === 'Enter' || k === ' ' || k === 'Spacebar') {
      if (ev.preventDefault) { ev.preventDefault(); }
      here();
    }
  });

  window.thornswoodAfk = { ask: ask, close: close, isOpen: isOpen, left: secondsLeft };

  var asked = Number(window.THORNSWOOD_AFK_ASK) || 0;
  if (asked > 0) {
    window.THORNSWOOD_AFK_ASK = 0;
    ask(asked);
  }
})();
