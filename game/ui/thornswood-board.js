'use strict';
/*
  The notice board, opened by clicking it while you are standing at it.

  THE CONTRACT with thornswood-front.js, the same shape the party panel uses:

    window.thornswoodBoard = { open, close, toggle, isOpen, setData }
    page -> plugin  'board:ready' | 'board:opened' | 'board:closed'
                    'board:near x y z here'

  Everything this panel DOES it does by sending the ordinary lines, through
  window.thornswoodNet.say. There is no second protocol. The labels are
  words. The lines are how the panel talks to the server.

  setData never opens the panel. The click does. A later setData redraws
  what is already open, and the plugin closes it once you walk away.
*/
(function () {
  if (window.thornswoodBoard) { return; }

  var ID = 'ts-board';
  var data = null;
  var shown = false;
  var root = null;

  function tell(what) {
    try { window.skyrimPlatform.sendMessage('thornswood-front', 'board:' + what); }
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

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  /*
    THE LOOK IS THE PARTY PANEL'S, which is the K panel's. Every colour
    below is one that panel already uses. No :hover and no transitions.
  */
  var CSS = [
    '#' + ID + '{position:fixed;inset:0;z-index:2147483000;display:none;',
    '  background:radial-gradient(ellipse at center,rgba(0,0,0,.50) 0%,rgba(0,0,0,.72) 100%);',
    '  font-family:"Palatino Linotype",Palatino,Georgia,serif;color:#d9cfb4}',
    '#' + ID + '.on{display:grid;place-items:center}',
    '#' + ID + ' .panel{width:720px;max-width:calc(100vw - 48px);height:640px;',
    '  max-height:calc(100vh - 48px);display:grid;grid-template-rows:auto 1fr auto;',
    '  background:rgba(11,10,8,.94);border:1px solid rgba(198,170,109,.42);',
    '  outline:1px solid rgba(198,170,109,.14);outline-offset:4px;',
    '  box-shadow:0 24px 80px rgba(0,0,0,.7);overflow:hidden}',
    '#' + ID + ' h2{margin:0;padding:18px 24px 14px;font-size:26px;font-weight:normal;line-height:1.1;',
    '  color:#f6e9c8;border-bottom:1px solid rgba(198,170,109,.22);display:flex;align-items:baseline;gap:14px}',
    '#' + ID + ' h2 .sub{font-size:14px;color:rgba(217,207,180,.6);font-style:italic}',
    '#' + ID + ' .body{overflow:auto;padding:16px 24px;display:block;',
    '  font-size:16px}',
    '#' + ID + ' .foot{padding:12px 24px;border-top:1px solid rgba(198,170,109,.22);',
    '  display:flex;gap:10px;align-items:center;justify-content:flex-end}',
    '#' + ID + ' h3{margin:16px 0 8px;padding-bottom:6px;font-size:11.5px;letter-spacing:.24em;text-transform:uppercase;',
    '  color:rgba(198,170,109,.85);font-weight:normal;border-bottom:1px solid rgba(198,170,109,.22)}',
    '#' + ID + ' h3:first-child{margin-top:0}',
    '#' + ID + ' .row{display:flex;align-items:center;gap:10px;padding:10px 12px;flex-wrap:wrap;',
    '  border:1px solid rgba(198,170,109,.30);background:rgba(0,0,0,.20);margin-bottom:8px}',
    '#' + ID + ' .row .nm{flex:1;min-width:160px;font-size:16px;line-height:1.35}',
    '#' + ID + ' .tools{display:flex;align-items:center;gap:8px;flex-wrap:wrap;justify-content:flex-end}',
    '#' + ID + ' button{font-family:inherit;font-style:normal;font-weight:normal;cursor:pointer;',
    '  border:1px solid rgba(198,170,109,.55);background:rgba(0,0,0,.25);color:#e9d19b;',
    '  padding:6px 12px;font-size:15px;line-height:20px;letter-spacing:.14em;text-transform:uppercase;white-space:nowrap}',
    '#' + ID + ' button.go{background:#c6aa6d;border-color:#e9d19b;color:#1b1205}',
    '#' + ID + ' .none{color:rgba(217,207,180,.6);font-style:italic;padding:6px 2px}',
    '#' + ID + ' .note{color:rgba(217,207,180,.7);font-size:12.5px;line-height:1.5;margin-top:8px}',
    '#' + ID + ' .line{display:flex;gap:8px;align-items:center;margin-bottom:8px}',
    '#' + ID + ' input{font-family:inherit;font-size:16px;color:#d9cfb4;background:rgba(0,0,0,.25);',
    '  border:1px solid rgba(198,170,109,.42);padding:8px 10px;width:100%;box-sizing:border-box}',
    '#' + ID + ' ::-webkit-scrollbar{width:10px;height:10px}',
    '#' + ID + ' ::-webkit-scrollbar-track{background:rgba(0,0,0,.25)}',
    '#' + ID + ' ::-webkit-scrollbar-thumb{background:rgba(198,170,109,.35);border:2px solid transparent;',
    '  background-clip:padding-box;border-radius:6px}',
    '#' + ID + ' ::-webkit-scrollbar-thumb:active{background:rgba(233,209,155,.55);background-clip:padding-box}',
    '#' + ID + ' ::-webkit-scrollbar-corner{background:transparent}'
  ].join('\n');

  function build() {
    if (root) { return; }
    var style = document.createElement('style');
    style.textContent = CSS;
    document.head.appendChild(style);
    root = document.createElement('div');
    root.id = ID;
    root.innerHTML =
      '<div class="panel"><h2>Notice board</h2><div class="body"></div>' +
      '<div class="foot"><button data-do="close">Close</button></div></div>';
    document.body.appendChild(root);
    root.addEventListener('click', function (e) {
      if (e.target === root) { close(); }
    });
  }

  function field(id) {
    var el = document.getElementById(id);
    return el ? String(el.value || '').trim() : '';
  }

  function draw() {
    if (!root) { return; }
    var keptNotice = field(ID + '-notice');
    var keptJob = field(ID + '-job');
    var title = root.querySelector('h2');
    var body = root.querySelector('.body');
    var b = data && data.board;
    if (!b || !b.here) {
      title.innerHTML = 'Notice board';
      body.innerHTML = '<div class="none">Step up to the board.</div>';
      return;
    }
    title.innerHTML = esc(b.where || 'Notice board') +
      ' <span class="sub">' + esc(String(b.paid || 0)) + ' gold paid in</span>';
    var out = '<h3>On the board</h3>';
    var wall = b.wall || [];
    if (!wall.length) { out += '<div class="none">Nothing on it.</div>'; }
    for (var i = 0; i < wall.length; i++) {
      var row = wall[i];
      var kind = row.letter ? 'Letter' : (row.job ? 'Job' : 'Notice');
      var who = row.taken ? ', taken by ' + esc(row.taken) : '';
      out += '<div class="row"><span class="nm"><b>' + esc(row.n) + '.</b> ' + kind +
        ', ' + esc(row.name) + who + '<br>' + esc(row.text) + '</span><span class="tools">';
      if (row.job && !row.taken && !row.mine) {
        out += '<button class="go" data-do="take" data-n="' + esc(row.n) + '">Take</button>';
      }
      if (row.mine && !(row.job && row.taken)) {
        out += '<button data-do="unpin" data-n="' + esc(row.n) + '">Take down</button>';
      }
      if (row.held) {
        out += '<button data-do="drop" data-n="' + esc(row.n) + '">Put it back</button>';
      }
      out += '</span></div>';
    }
    var jobs = b.jobs || [];
    var elsewhere = [];
    for (var j = 0; j < jobs.length; j++) {
      if (jobs[j].hold !== b.hold) { elsewhere.push(jobs[j]); }
    }
    if (elsewhere.length) {
      out += '<div class="note">Hand these back at the board you took them from.</div>';
      for (var e = 0; e < elsewhere.length; e++) {
        out += '<div class="none">' + esc(elsewhere[e].hold) + ': ' + esc(elsewhere[e].text) + '</div>';
      }
    }
    out += '<h3>Put something up</h3>';
    out += '<div class="line"><input id="' + ID + '-notice" placeholder="the notice">' +
      '<button class="go" data-do="notice">Post a notice</button></div>';
    out += '<div class="line"><input id="' + ID + '-job" placeholder="the job">' +
      '<button class="go" data-do="job">Post a job</button></div>';
    out += '<div class="note">A notice is 20 gold. A job is 30 gold. The gold stays with the hold.</div>';
    out += '<h3>Leave a price list</h3>';
    var lists = b.submit || [];
    if (!lists.length) { out += '<div class="none">No list you can leave.</div>'; }
    for (var s = 0; s < lists.length; s++) {
      out += '<div class="row"><span class="nm">' + esc(lists[s].name) +
        '</span><span class="tools"><button class="go" data-do="submit" data-id="' +
        esc(lists[s].id) + '">Leave the list</button></span></div>';
    }
    body.innerHTML = out;
    var noticeBox = document.getElementById(ID + '-notice');
    var jobBox = document.getElementById(ID + '-job');
    if (noticeBox && keptNotice) { noticeBox.value = keptNotice; }
    if (jobBox && keptJob) { jobBox.value = keptJob; }
    var buttons = body.querySelectorAll('button[data-do]');
    for (var k = 0; k < buttons.length; k++) { buttons[k].onclick = onDo; }
  }

  function onDo() {
    var verb = this.getAttribute('data-do');
    var n = this.getAttribute('data-n');
    if (verb === 'notice') {
      var notice = field(ID + '-notice');
      if (notice) { net('/notice ' + notice); }
      return;
    }
    if (verb === 'job') {
      var job = field(ID + '-job');
      if (job) { net('/job ' + job); }
      return;
    }
    if (verb === 'take' && n) { net('/take ' + n); return; }
    if (verb === 'unpin' && n) { net('/unpin ' + n); return; }
    if (verb === 'drop' && n) { net('/dropjob ' + n); return; }
    if (verb === 'submit') {
      var id = this.getAttribute('data-id');
      if (id) { net('/book submit ' + id); }
    }
  }

  function open() {
    build();
    if (shown) { draw(); return; }
    shown = true;
    root.className = 'on';
    draw();
    tell('opened');
  }

  function close() {
    if (!shown) { return; }
    shown = false;
    if (root) { root.className = ''; }
    tell('closed');
  }

  document.addEventListener('keydown', function (ev) {
    if (!shown) { return; }
    if (ev.key === 'Escape') { close(); }
  });

  var foot = null;
  function wireFoot() {
    build();
    if (foot) { return; }
    foot = root.querySelector('.foot button');
    if (foot) { foot.onclick = function () { close(); }; }
  }

  window.thornswoodBoard = {
    open: function () { wireFoot(); open(); },
    close: close,
    toggle: function () { if (shown) { close(); } else { open(); } },
    isOpen: function () { return shown; },
    setData: function (d) {
      data = d || null;
      var b = data && data.board;
      if (b && isFinite(Number(b.x)) && isFinite(Number(b.y)) && isFinite(Number(b.z))) {
        tell('near ' + String(b.hold || 'board') + ' ' + Number(b.x) + ' ' + Number(b.y) + ' ' + Number(b.z));
      } else {
        tell('near none');
      }
      wireFoot();
      if (shown) { draw(); }
    }
  };

  tell('ready');
})();
