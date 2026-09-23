'use strict';
/*
  The party menu, behind P.

  Patrick, 22 September: "Friend/Party System & Journals - P for the Party
  menu. This menu would allow people to see who their friends are, if they are
  online, invite them to a party, see their name tag colour, see them on the
  map and compass, and get an experience boost for playing together."

  WHAT IS HERE AND WHAT IS NOT, said plainly rather than left to be discovered.
  Friends, who is online, inviting, the party, and the experience bonus are all
  here and all real. THE MAP AND THE COMPASS ARE NOT, and they are the one part
  of that list this server cannot do from a browser overlay: a compass marker
  is a Papyrus quest alias or a MapMarker reference, both of which live in the
  game rather than in a page, and putting a live marker on another person needs
  a plugin change that is worth doing on its own rather than half doing here.
  The panel says so where somebody would look for it, instead of quietly
  leaving it out.

  THE CONTRACT with thornswood-front.js, the same shape thornswood-skills.js
  uses and for the same reasons:

    window.thornswoodParty = { open, close, toggle, isOpen, setData }
    page -> plugin  'party:ready' | 'party:opened' | 'party:closed'

  Everything this panel DOES it does by sending the ordinary chat commands,
  through window.thornswoodNet.say: /friend, /party, /mute, /yes, /no. There is
  no second protocol. A person who would rather type has every button on this
  panel available to them, and the panel cannot do anything they could not.
*/
(function () {
  if (window.thornswoodParty) { return; }

  var ID = 'ts-party';
  var data = null;
  var shown = false;
  var root = null;

  function tell(what) {
    try { window.skyrimPlatform.sendMessage('thornswood-front', 'party:' + what); }
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

  /*
    The same frame, the same colours and the same 1920x1080 scaling as the
    skills panel, so the two read as one game rather than two pages. Kept
    inline rather than shared: a fourth file that all three panels depend on
    is a fourth thing that can fail to load, and these are small.
  */
  var CSS = [
    '#' + ID + '{position:fixed;inset:0;z-index:2147483000;display:none;',
    '  background:rgba(6,7,9,.72);font-family:Georgia,serif;color:#e9e7e1}',
    '#' + ID + '.on{display:grid;place-items:center}',
    '#' + ID + ' .panel{width:880px;max-width:calc(100vw - 48px);height:620px;',
    '  max-height:calc(100vh - 48px);display:grid;grid-template-rows:auto 1fr auto;',
    '  background:#1b1f26;border:2px solid #3a424e;border-radius:12px;',
    '  box-shadow:0 18px 60px rgba(0,0,0,.6);overflow:hidden}',
    '#' + ID + ' h2{margin:0;padding:18px 24px 14px;font-size:24px;font-weight:600;',
    '  border-bottom:1px solid #2b313a;display:flex;align-items:baseline;gap:14px}',
    '#' + ID + ' h2 .sub{font-size:14px;color:#98a2ae;font-family:system-ui,sans-serif}',
    '#' + ID + ' .body{overflow:auto;padding:16px 24px;display:grid;gap:18px;',
    '  align-content:start;font-family:system-ui,sans-serif;font-size:14px}',
    '#' + ID + ' .foot{padding:12px 24px;border-top:1px solid #2b313a;',
    '  display:flex;gap:10px;align-items:center;font-family:system-ui,sans-serif;font-size:13px;color:#98a2ae}',
    '#' + ID + ' h3{margin:0 0 8px;font-size:12px;letter-spacing:.08em;text-transform:uppercase;',
    '  color:#79828f;font-family:system-ui,sans-serif;font-weight:600}',
    '#' + ID + ' .row{display:flex;align-items:center;gap:10px;padding:8px 10px;',
    '  border:1px solid #2b313a;border-radius:8px;background:#212630;margin-bottom:6px}',
    '#' + ID + ' .row .nm{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}',
    '#' + ID + ' .dot{width:9px;height:9px;border-radius:50%;background:#4a515c;flex:none}',
    '#' + ID + ' .dot.on{background:#6fae7e}',
    '#' + ID + ' button{font:inherit;cursor:pointer;border-radius:7px;border:1px solid #3a424e;',
    '  background:#1b1f26;color:#e9e7e1;padding:5px 11px;font-size:13px}',
    '#' + ID + ' button:hover{border-color:#d9ab52;color:#d9ab52}',
    '#' + ID + ' button.go{background:#d9ab52;border-color:#d9ab52;color:#1a1500;font-weight:600}',
    '#' + ID + ' .none{color:#79828f;padding:6px 2px}',
    '#' + ID + ' .ask{border:1px solid #d9ab52;background:rgba(217,171,82,.1);',
    '  border-radius:9px;padding:12px 14px;display:flex;gap:10px;align-items:center}',
    '#' + ID + ' .ask .who{flex:1}',
    '#' + ID + ' .note{color:#79828f;font-size:12.5px;line-height:1.5}',
    '#' + ID + ' .tag{font-size:11px;border:1px solid #3a424e;border-radius:5px;',
    '  padding:1px 6px;color:#98a2ae}',
    '#' + ID + ' .tag.p{border-color:#8fb85e;color:#8fb85e}',
    '#' + ID + ' .tag.m{border-color:#e0645a;color:#e0645a}'
  ].join('\n');

  /*
    ------------------------------------------------------ THE PARTY STRIP

    Patrick asked to "see them on the map and compass". The map is the
    plugin's: one MapMarker per member, moved to wherever the server says they
    are. The COMPASS is this, and it is deliberately not Skyrim's.

    WHY NOT SKYRIM'S. That compass draws quest targets and map markers and
    nothing a plugin can add an arrow to. Putting a party on it properly needs
    a quest with one alias per member inside an esp, which is a Creation Kit
    change, a plugin rebuild and a new master for everybody. This is a strip of
    our own, under the game's compass, saying the same thing.

    AND IT IS FRESHER THAN THE SERVER'S OWN PARTY PUSH. Voice already receives
    everybody's position five times a second, because proximity voice needs it,
    and thornswood-voice.js hands that table out through who(). The server's
    party list is on a tick and a half. So membership comes from the server,
    where it belongs, and the POSITIONS come from the voice feed, which is
    fifteen times more often and costs nothing new.

    THE MATHS IS THE SAME AS THE VOICE PANNER'S and is written out there at
    length: Skyrim's facing is degrees clockwise from north, north is +Y, so
    forward is (sin, cos) and right is (cos, -sin). Getting it wrong only
    shows up once somebody turns away from north, which is why both places say
    so.
  */
  var where = [];            // the server's party list: who, and their form id
  var stripEl = null;
  var stripTimer = null;

  var STRIP_CSS =
    'position:fixed;left:50%;top:76px;transform:translateX(-50%);' +
    'z-index:2147483400;pointer-events:none;font-family:Georgia,serif;' +
    'font-size:15px;letter-spacing:.03em;color:#e9e7e1;' +
    'text-shadow:0 2px 4px rgba(0,0,0,.95);white-space:nowrap;display:none';

  function esc2(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  /*
    One member, as an arrow and a distance.

    The arrow is a character rather than a drawing: eight of them cover the
    compass rose closely enough to point at somebody, they need no file and no
    svg, and they are legible at this size on every machine.
  */
  var ARROWS = ['↑', '↗', '→', '↘',
                '↓', '↙', '←', '↖'];

  function arrowFor(bearing) {
    var at = Math.round(((bearing % 360) + 360) % 360 / 45) % 8;
    return ARROWS[at];
  }

  function drawStrip() {
    if (!stripEl) { return; }
    if (!where.length) { stripEl.style.display = 'none'; return; }

    var who = null;
    try {
      if (window.thornswoodVoice && window.thornswoodVoice.who) {
        who = window.thornswoodVoice.who();
      }
    } catch (e) { who = null; }

    var mine = null;
    var byProfile = who || {};
    try {
      if (data && data.me && byProfile[data.me]) { mine = byProfile[data.me]; }
    } catch (e) { mine = null; }

    var bits = [];
    for (var i = 0; i < where.length; i++) {
      var row = where[i];
      var name = esc2(row.n || 'somebody');

      /*
        Match the server's row to the voice feed's by NAME, because the two
        are keyed differently: the server's party list carries the form id the
        plugin needs for the map marker, and the voice feed is keyed by
        profile id. Names on this server are unique per character and the
        alternative is a third table nobody needs.

        Somebody the voice feed has not seen yet gets a name and no arrow,
        which is honest: it says they are in your party and does not pretend
        to know where.
      */
      var them = null;
      for (var pid in byProfile) {
        if (!Object.prototype.hasOwnProperty.call(byProfile, pid)) { continue; }
        if (String(byProfile[pid].name || '') === String(row.n || '')) {
          them = byProfile[pid];
          break;
        }
      }

      if (!them || !them.pos || !mine || !mine.pos) {
        bits.push('<span style="margin:0 14px;color:#98a2ae">' + name + '</span>');
        continue;
      }

      var dx = them.pos[0] - mine.pos[0];
      var dy = them.pos[1] - mine.pos[1];
      var dz = them.pos[2] - mine.pos[2];
      var metres = Math.sqrt(dx * dx + dy * dy + dz * dz) / UNITS_PER_METRE;

      // Their bearing from you, in degrees clockwise from north, minus the way
      // you are facing. Skyrim's north is +Y.
      var toThem = Math.atan2(dx, dy) * 180 / Math.PI;
      var facing = Number(mine.angleZ) || 0;
      var rel = toThem - facing;

      var far = metres >= 1000;
      var reads = far ? (Math.round(metres / 100) / 10) + ' km'
                      : Math.round(metres) + ' m';
      var sameRoom = String(them.cell) === String(mine.cell);

      bits.push(
        '<span style="margin:0 14px;color:' + (sameRoom ? '#8fb85e' : '#d9ab52') + '">' +
        '<span style="font-size:18px">' + arrowFor(rel) + '</span> ' +
        name + ' <span style="color:#98a2ae;font-size:13px">' + reads + '</span>' +
        '</span>');
    }

    stripEl.innerHTML = bits.join('');
    stripEl.style.display = '';
  }

  var UNITS_PER_METRE = 70;   // the same seventy the voice page uses

  function ensureStrip() {
    if (stripEl) { return; }
    stripEl = document.createElement('div');
    stripEl.id = 'ts-party-strip';
    stripEl.style.cssText = STRIP_CSS;
    document.body.appendChild(stripEl);
    /*
      Five a second, which is the rate the positions arrive at. Stopped
      entirely when there is no party, so somebody playing alone pays nothing
      at all for this.
    */
    stripTimer = setInterval(function () {
      try { if (where.length) { drawStrip(); } } catch (e) { }
    }, 200);
  }


  function build() {
    if (root) { return root; }
    var style = document.createElement('style');
    style.textContent = CSS;
    document.head.appendChild(style);

    root = document.createElement('div');
    root.id = ID;
    root.innerHTML =
      '<div class="panel">' +
      '<h2>Friends and party<span class="sub" id="' + ID + '-sub"></span></h2>' +
      '<div class="body" id="' + ID + '-body"></div>' +
      '<div class="foot"><span id="' + ID + '-foot"></span>' +
      '<span style="flex:1"></span>' +
      '<button id="' + ID + '-close">Close</button></div>' +
      '</div>';
    document.body.appendChild(root);
    root.querySelector('#' + ID + '-close').onclick = close;

    /*
      Escape closes it, and the page has to handle that itself.

      While the browser holds the keyboard no plugin can see a key: focus
      raises DInputHook::ChromeFocus and buttonEvent goes deaf. That is
      written out at length in thornswood-bridge.js and is the reason every
      panel on this server answers its own Escape.
    */
    document.addEventListener('keydown', function (ev) {
      if (!shown) { return; }
      if (ev.key === 'Escape') { ev.preventDefault(); close(); }
    });
    return root;
  }

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function draw() {
    if (!root) { return; }
    var body = root.querySelector('#' + ID + '-body');
    var sub = root.querySelector('#' + ID + '-sub');
    var foot = root.querySelector('#' + ID + '-foot');
    if (!data) {
      body.innerHTML = '<div class="none">Waiting for the server.</div>';
      sub.textContent = '';
      foot.textContent = '';
      return;
    }

    var html = '';

    // Anything standing gets answered first: it has a clock on it.
    if (data.offer) {
      var what = data.offer.kind === 'friend' ? 'wants to be friends'
        : (data.offer.kind === 'party' ? 'is asking you to join their party'
                                       : 'is offering to trade');
      html += '<div class="ask"><span class="who"><b>' + esc(data.offer.name) +
              '</b> ' + what + '</span>' +
              '<button class="go" data-do="yes">Yes</button>' +
              '<button data-do="no">No</button></div>';
    }

    html += '<div><h3>Your party</h3>';
    if (!data.party || !data.party.length) {
      html += '<div class="none">Not in a party. Look at somebody and press the party key, ' +
              'or use the Ask button on a friend below.</div>';
    } else {
      for (var i = 0; i < data.party.length; i++) {
        var m = data.party[i];
        html += '<div class="row"><span class="dot' + (m.on ? ' on' : '') + '"></span>' +
                '<span class="nm">' + esc(m.name) + (m.me ? ' (you)' : '') + '</span>' +
                (m.leader ? '<span class="tag p">leader</span>' : '') + '</div>';
      }
      html += '<div class="row" style="border:none;background:none;padding-left:2px">' +
              '<span class="nm">' + data.together +
              (data.together === 1 ? ' of them is here with you' : ' of them are here with you') +
              '. ' + (data.together ? ('Work counts ' + data.bonus + '% more.')
                                    : ('Be in the same place for ' + data.bonus + '% more from your work.')) +
              '</span><button data-do="leave">Leave</button></div>';
    }
    html += '</div>';

    html += '<div><h3>Friends</h3>';
    if (!data.friends || !data.friends.length) {
      html += '<div class="none">Nobody yet. Look at somebody and press the friend key.</div>';
    } else {
      for (var j = 0; j < data.friends.length; j++) {
        var f = data.friends[j];
        html += '<div class="row"><span class="dot' + (f.on ? ' on' : '') + '"></span>' +
                '<span class="nm">' + esc(f.name) + '</span>' +
                (f.party ? '<span class="tag p">party</span>' : '') +
                (f.muted ? '<span class="tag m">muted</span>' : '') +
                (f.on && !f.party ? '<button data-do="ask" data-who="' + esc(f.name) + '">Ask to party</button>' : '') +
                '<button data-do="mute" data-who="' + esc(f.name) + '">' + (f.muted ? 'Unmute' : 'Mute') + '</button>' +
                '<button data-do="drop" data-who="' + esc(f.name) + '">Remove</button>' +
                '</div>';
      }
    }
    html += '</div>';

    /*
      The two things that were asked for and are not here. Said on the panel
      rather than left out, because a missing feature nobody mentions reads as
      a broken one.
    */
    /*
      THE NOTE THAT USED TO SAY THESE WERE MISSING. They are not any more, and
      what is left of it is the one honest caveat: the strip is ours and not
      Skyrim's compass, and it is worth saying so rather than letting somebody
      wonder why the game's own compass never changed.
    */
    html += '<div><h3>Finding each other</h3><div class="note">' +
            'Everybody in your party has their name in green above their head, ' +
            'a marker on your map, and an arrow on the strip under your compass ' +
            'with how far away they are. Green on the strip means the same room ' +
            'as you, gold means somewhere else. ' +
            'The strip is ours rather than Skyrim\'s own compass: that one only ' +
            'draws quest targets and map markers, and putting people on it needs ' +
            'a change inside the game files rather than on this server.' +
            '</div></div>';

    body.innerHTML = html;
    sub.textContent = (data.friends ? data.friends.length : 0) + ' friend' +
                      ((data.friends && data.friends.length === 1) ? '' : 's');
    foot.textContent = 'Escape or P closes this.';

    var buttons = body.querySelectorAll('button[data-do]');
    for (var k = 0; k < buttons.length; k++) {
      buttons[k].onclick = function () {
        var verb = this.getAttribute('data-do');
        var who = this.getAttribute('data-who') || '';
        if (verb === 'yes') { net('/yes'); }
        else if (verb === 'no') { net('/no'); }
        else if (verb === 'leave') { net('/party leave'); }
        else if (verb === 'ask') { net('/party ' + who); }
        else if (verb === 'mute') { net('/mute ' + who); }
        else if (verb === 'drop') { net('/friend remove ' + who); }
      };
    }
  }

  function open() {
    build();
    if (shown) { return; }
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

  function toggle() { if (shown) { close(); } else { open(); } }

  window.thornswoodParty = {
    open: open,
    close: close,
    toggle: toggle,
    isOpen: function () { return shown; },
    setData: function (d) { data = d || null; if (shown) { draw(); } },

    /*
      Where your party is, handed over by thornswood-front.js.

      It comes from the plugin rather than from the server's own push to this
      page, because the plugin is already reading that property for the map
      markers and a page cannot read a plugin's variables. One source, two
      uses.
    */
    setWhere: function (list) {
      where = Array.isArray(list) ? list : [];
      ensureStrip();
      drawStrip();
      if (shown) { draw(); }
    },
    /* For anybody checking whether the strip is doing anything. */
    strip: function () { return where.length; }
  };

  build();
  tell('ready');
})();
