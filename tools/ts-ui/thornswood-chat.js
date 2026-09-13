'use strict';
/*
  The chat's connection, page side.

  Where the messages actually travel, and why here rather than through the game
  server: the voice service already relays them. It has since it was written.
  Look at the socket handler in voice-server.js:

      if (msg.t === 'chat') {
        ...
        for (const [, p] of peers) p.ws.send(out);
      }

  Everyone with the game open already holds that socket, the service already
  knows who they are, and it is plain JavaScript on the VPS that can be changed
  without recompiling anything. Going through the game server instead would
  mean a new packet type in skymp5-client, and skymp5-client is compiled.

  It runs in the page rather than in a plugin because the browser is where a
  WebSocket exists. SkyrimPlatform's own HttpClient can only poll.

  The page is served from file:///, which Chromium treats as a trustworthy
  origin, so an outbound ws:// from here is allowed. That is the same rule that
  made the old separate voice window impossible: a page served over plain http
  from a remote address gets no microphone at all, whatever flags it is given.
*/

(function () {
  if (window.thornswoodNet) return;

  var CFG = window.THORNSWOOD || {};
  var HOST = String(CFG.host || '');
  var PORT = Number(CFG.port || 7778);
  var ME   = Number(CFG.profileId || 0);
  var NAME = String(CFG.name || 'Traveller');

  // Colours from the launcher's own palette so the chat looks like the rest of
  // the build rather than like a web page.
  var C_NAME = '#c6aa6d';
  var C_TEXT = '#e8e3d8';
  var C_SYS  = '#8f8a7d';
  var C_WARN = '#c98b6b';

  var ws = null;
  var tries = 0;
  var joined = false;
  var timer = null;
  var queue = [];

  // One socket, not two.
  //
  // Voice needs the same connection: the service hands out a peer id per
  // socket, and a second one from the same game would show up as a second
  // person in the room, get its own half of every WebRTC negotiation, and
  // double every line in the chat. So this file owns the connection and
  // anything else that wants it subscribes here.
  var listeners = [];
  var peerId = 0;

  function fanout(msg) {
    for (var i = 0; i < listeners.length; i++) {
      try { listeners[i](msg); } catch (e) {
        try { console.log('[chat] listener threw: ' + e); } catch (e2) { }
      }
    }
  }

  function chat() { return window.thornswoodChat; }

  function note(text, color) {
    var c = chat();
    if (c) c.add([{ text: text, color: color || C_SYS }], 'plain');
  }

  function url() {
    return 'ws://' + HOST + ':' + PORT + '/';
  }

  function connect() {
    if (!HOST) { note('No server address, so the chat is off.', C_WARN); return; }
    if (ws && (ws.readyState === 0 || ws.readyState === 1)) return;

    try {
      ws = new WebSocket(url());
    } catch (e) {
      retry();
      return;
    }

    ws.onopen = function () {
      tries = 0;
      joined = false;
      try {
        ws.send(JSON.stringify({ t: 'join', profileId: ME, name: NAME }));
      } catch (e) { }
    };

    ws.onmessage = function (ev) {
      var msg;
      try { msg = JSON.parse(ev.data); } catch (e) { return; }
      if (!msg || !msg.t) return;

      if (msg.t === 'welcome') {
        joined = true;
        peerId = Number(msg.peer) || 0;
        fanout(msg);
        note('Chat is on. Press enter to talk.', C_SYS);
        // Anything typed while the socket was down goes now rather than being
        // lost, which is what an unacknowledged send would have been.
        while (queue.length) {
          try { ws.send(JSON.stringify({ t: 'chat', text: queue.shift() })); }
          catch (e) { break; }
        }
        return;
      }

      if (msg.t !== 'chat') { fanout(msg); return; }

      if (msg.t === 'chat') {
        var who = String(msg.name || '').trim() || 'Someone';
        var mine = ME && Number(msg.profileId) === ME;
        var c = chat();
        if (!c) return;
        c.add([
          { text: who + ': ', color: mine ? '#d8c79a' : C_NAME },
          { text: String(msg.text || ''), color: C_TEXT }
        ], 'plain');
        return;
      }

      // 'peers' and 'pos' belong to voice. Ignored here on purpose rather than
      // logged: they arrive several times a second.
    };

    ws.onclose = function () {
      if (joined) note('Chat lost the server. Trying again.', C_WARN);
      joined = false;
      peerId = 0;
      fanout({ t: '__closed' });
      retry();
    };

    ws.onerror = function () {
      try { ws.close(); } catch (e) { }
    };
  }

  function retry() {
    if (timer) return;
    // Backs off to half a minute and stays there. Somebody who alt tabs out
    // for an hour should not come back to a thousand failed connections.
    var wait = Math.min(30000, 1000 * Math.pow(2, Math.min(tries, 5)));
    tries++;
    timer = setTimeout(function () { timer = null; connect(); }, wait);
  }

  // --------------------------------------------------------------- dice ---
  // /roll, because a shop full of haggling needs one and the front's own dice
  // pouch has been taken off the screen.
  //
  // The number is the number of sides. Not "d20", just 20, because nobody
  // wants to type a letter to roll a die and the d only ever meant something
  // to people who already play tabletop.
  //
  //   /roll          one 20
  //   /roll 20       one 20
  //   /roll 1000     one 1000
  //   /roll 6x3      three 6s, added up
  //
  // Sides: any whole number from 1 to 1000. Dice: up to 100 of them. Decimals
  // are refused rather than rounded, because a roll nobody can predict the
  // shape of is worse than no roll.
  //
  // Rolled here and sent as an ordinary line, so everybody sees the same words
  // and the relay needs no idea that dice exist. Among five friends that is the
  // right trade: making it uncheatable means changing the service and
  // redeploying it, to stop people cheating at a game they play for fun.
  var ROLL = /^\/(roll|r)\b\s*(.*)$/i;
  var SPEC = /^(\d+)(?:\s*[x*]\s*(\d+))?$/;

  var MAX_SIDES = 1000;
  var MAX_DICE = 100;
  var DEFAULT_SIDES = 20;

  function rollOf(spec) {
    spec = String(spec || '').trim().toLowerCase().replace(/\s+/g, '');
    // A leading d is not the syntax, but somebody who has rolled dice before
    // will type it on reflex, so it is dropped rather than refused.
    spec = spec.replace(/(^|[x*])d/g, '$1');
    if (!spec) spec = String(DEFAULT_SIDES);

    var m = SPEC.exec(spec);
    if (!m) return null;

    var sides = parseInt(m[1], 10);
    var count = m[2] ? parseInt(m[2], 10) : 1;

    if (!isFinite(sides) || sides < 1 || sides > MAX_SIDES) return null;
    if (!isFinite(count) || count < 1 || count > MAX_DICE) return null;

    var rolls = [];
    var total = 0;
    for (var i = 0; i < count; i++) {
      var v = 1 + Math.floor(Math.random() * sides);
      rolls.push(v);
      total += v;
    }

    if (count === 1) return 'rolls ' + sides + ': ' + total;
    // The breakdown, until there are so many that it is noise rather than
    // working out.
    if (count <= 12) return 'rolls ' + count + 'x' + sides + ': ' + rolls.join(' + ') + ' = ' + total;
    return 'rolls ' + count + 'x' + sides + ': ' + total;
  }

  window.thornswoodNet = {
    say: function (text) {
      text = String(text == null ? '' : text).trim();
      if (!text) return false;

      var dice = ROLL.exec(text);
      if (dice) {
        var line = rollOf(dice[2]);
        if (!line) {
          note('The number is the sides: /roll 20, /roll 1000, or /roll 6x3 for three of them. ' +
               'Whole numbers, 1 to ' + MAX_SIDES + ', up to ' + MAX_DICE + ' dice.', C_WARN);
          return false;
        }
        text = line;
      }
      if (ws && ws.readyState === 1 && joined) {
        try { ws.send(JSON.stringify({ t: 'chat', text: text })); return true; }
        catch (e) { }
      }
      // Held rather than dropped, and capped so a long outage does not grow
      // without limit.
      queue.push(text);
      while (queue.length > 20) queue.shift();
      note('Not connected yet, that is queued.', C_WARN);
      return false;
    },

    state: function () {
      return { host: HOST, port: PORT, joined: joined,
               ready: ws ? ws.readyState : -1, queued: queue.length };
    },

    /** Whoever else wants the socket. Voice is the only one so far. */
    on: function (fn) {
      if (typeof fn === 'function') { listeners.push(fn); }
    },

    /** Raw send, for message kinds this file has no opinion about. */
    post: function (obj) {
      if (!ws || ws.readyState !== 1 || !joined) { return false; }
      try { ws.send(JSON.stringify(obj)); return true; } catch (e) { return false; }
    },

    /** The service's id for this connection, 0 until the welcome arrives. */
    peer: function () { return peerId; },

    isUp: function () { return !!(ws && ws.readyState === 1 && joined); },

    /**
     * The name is only known once the character exists, so it can arrive late.
     *
     * Reconnects rather than sending a second join. The service hands out a new
     * peer id for every join and never removes the old one, so a second join on
     * a live socket leaves two entries pointing at the same connection and you
     * see every message twice. Closing first makes the service drop the old
     * entry properly, and costs one round trip nobody will notice.
     */
    setName: function (n) {
      n = String(n || '').trim();
      if (!n || n === NAME) return;
      NAME = n;
      if (ws && (ws.readyState === 0 || ws.readyState === 1)) {
        tries = 0;
        try { ws.close(); } catch (e) { }
      } else {
        connect();
      }
    }
  };

  connect();

  try { window.skyrimPlatform.sendMessage('thornswood-front', 'chat socket to ' + url()); }
  catch (e) { }
})();
