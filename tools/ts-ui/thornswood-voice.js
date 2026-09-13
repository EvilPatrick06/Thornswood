'use strict';
/*
  Thornswood proximity voice, in the game's own browser.

  The earlier build opened Chrome in a window beside the game. That could never
  have worked, for a reason that has nothing to do with the bugs in it: it was
  served from http://<address>:7778, and Chromium exposes the microphone only
  on https or on localhost. On a plain http remote address
  navigator.mediaDevices is not merely blocked, it is undefined. No flag passed
  on the command line changes that, because it is an origin rule, not a
  permission.

  A page loaded from file:// inside the game is a trustworthy origin by
  Chromium's own rule, so the microphone API exists here. Whether CEF hands
  over an actual device is a separate question, answered by the probe.

  Everything this file needs comes from the plugin, never from the page's own
  address, because file:// has no host to read a server out of, and never from
  the keyboard, because the game's browser does not hold focus while you play.
  Push to talk is a game key that the plugin forwards.

  The socket belongs to thornswood-chat.js. This file used to open a second one
  to the same service, which is worse than wasteful: the service hands out a
  peer id per connection, so one person showed up in the room twice, negotiated
  with themselves, and saw every line of chat written out twice. So chat owns
  the connection and this subscribes to it.
*/

(function () {
  if (window.thornswoodVoice) return;   // injected twice, which is harmless

  var UNITS_PER_METRE = 70;
  var REF_DISTANCE = 4;
  var MAX_DISTANCE = 30;
  var ROLLOFF = 1.4;

  var cfg = { host: '', port: 7778, profileId: 0, name: '', pushToTalk: true,
              microphone: true };

  var ctx = null, mic = null, myPeer = 0;
  var talking = false, joined = false, wired = false;
  var micError = '';
  var lastWho = {};
  var conns = new Map();
  var waiting = null;

  /** The chat's socket, or null until that file has run. */
  function net() {
    var n = window.thornswoodNet;
    return (n && typeof n.post === 'function') ? n : null;
  }

  function post(obj) {
    var n = net();
    return n ? n.post(obj) : false;
  }

  // ------------------------------------------------------------- reporting --
  var lastReport = '';
  function report(stage, detail) {
    var line = stage + ' | ' + detail;
    if (line === lastReport) return;
    lastReport = line;
    try { window.skyrimPlatform.sendMessage('thornswood-voice', line); } catch (e) { }
    try { console.log('[voice] ' + line); } catch (e) { }
  }

  // --------------------------------------------------------------- overlay --
  // Small, top right, no pointer events. It is a debug read-out, not a panel:
  // nothing here is clickable, because nothing in the game's browser can be
  // clicked without taking the mouse away from the game.
  var box = null;
  function overlay() {
    if (box) return box;
    try {
      box = document.createElement('div');
      box.id = 'thornswood-voice';
      box.setAttribute('style', [
        'position:fixed', 'top:12px', 'right:12px', 'z-index:2147483647',
        'pointer-events:none', 'font:12px/1.5 "Segoe UI",system-ui,sans-serif',
        'color:#e8e3d8', 'background:rgba(20,18,15,.72)', 'border:1px solid #2b2721',
        'border-radius:8px', 'padding:8px 11px', 'min-width:150px',
        'text-shadow:0 1px 2px rgba(0,0,0,.8)'
      ].join(';'));
      document.body.appendChild(box);
    } catch (e) { box = null; }
    return box;
  }

  function esc(s) {
    return String(s).replace(/[&<>"]/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c];
    });
  }

  function draw() {
    var b = overlay();
    if (!b) return;
    var head = micError === 'off in Thornswood.ini'
                 ? 'Listening only, microphone off'
             : micError === 'NotAllowedError'
                 ? 'Listening only, no microphone'
             : micError ? ('No microphone: ' + micError)
             : !mic ? 'Voice starting'
             : (cfg.pushToTalk ? (talking ? 'Talking' : 'Voice ready') : 'Voice open');
    var dot = micError ? '#a86a6a' : (talking && mic ? '#7ea86a' : '#6b6458');
    var parts = ['<div style="display:flex;align-items:center;gap:7px;margin-bottom:' +
                 (conns.size ? '6px' : '0') + '">' +
                 '<span style="width:7px;height:7px;border-radius:50%;background:' + dot + '"></span>' +
                 '<span>' + head + '</span></div>'];
    conns.forEach(function (rec) {
      var who = rec.name || ('profile ' + rec.profileId);
      var d = rec.dist == null ? 'elsewhere'
            : (rec.dist < 1 ? 'here' : Math.round(rec.dist) + ' m');
      var near = rec.dist != null && rec.dist <= MAX_DISTANCE;
      parts.push('<div style="display:flex;justify-content:space-between;gap:12px;opacity:' +
                 (near ? '1' : '.45') + '"><span>' + esc(who) +
                 '</span><span style="color:#9a9284">' + d + '</span></div>');
    });
    b.innerHTML = parts.join('');
  }

  // ------------------------------------------------------------- the mic ----
  function applyMic() {
    if (!mic) return;
    var live = cfg.pushToTalk ? talking : true;
    mic.getAudioTracks().forEach(function (t) { t.enabled = live; });
    draw();
  }

  /**
   * Listening and talking are two different things, and only one of them needs
   * a microphone.
   *
   * The earlier version gave up entirely the moment CEF refused the mic, which
   * meant one refusal took the whole room's audio with it. So the audio
   * context and the mesh are set up first and the microphone is asked for
   * afterwards: if it is refused you still hear everybody, the overlay says
   * why, and the only thing missing is your own voice.
   */
  function start() {
    if (joined) return;
    joined = true;

    var AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) {
      micError = 'this browser has no Web Audio';
      report('audio', 'no AudioContext in this build, voice cannot run');
      draw();
      return;
    }

    try { ctx = new AC(); }
    catch (e) {
      micError = 'audio would not start';
      report('audio', 'AudioContext threw: ' + e);
      draw();
      return;
    }

    // Heads sit at the origin facing -Z and everybody else is placed
    // relative to that, so the listener never has to move.
    try {
      if (ctx.listener.forwardZ) {
        ctx.listener.forwardX.value = 0; ctx.listener.forwardY.value = 0; ctx.listener.forwardZ.value = -1;
        ctx.listener.upX.value = 0; ctx.listener.upY.value = 1; ctx.listener.upZ.value = 0;
      } else if (ctx.listener.setOrientation) {
        ctx.listener.setOrientation(0, 0, -1, 0, 1, 0);
      }
    } catch (e) { }

    resume();
    draw();

    // Turned off on purpose, in Thornswood.ini. Nothing is opened, so no
    // capture device is touched at all: the difference between this and the
    // on case is exactly one live microphone, which is what makes it a usable
    // test rather than a guess.
    if (!cfg.microphone) {
      micError = 'off in Thornswood.ini';
      report('mic', 'not asking, [Voice] Microphone is 0');
      connect();
      draw();
      return;
    }

    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      micError = 'this page has no getUserMedia';
      report('mic', 'this page has no getUserMedia at all, so you can hear but not talk');
      connect();
      draw();
      return;
    }

    report('mic', 'asking');
    navigator.mediaDevices.getUserMedia({
      audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true }
    }).then(function (str) {
      mic = str;
      micError = '';
      var t = str.getAudioTracks()[0];
      report('mic', 'granted, ' + (t ? (t.label || '(no label)') : 'no track'));
      // The room is joined only now, and deliberately.
      //
      // A peer connection carries the tracks it had when it was created.
      // Joining first and asking for the microphone afterwards meant the
      // first person already in the room got a receive-only connection, and
      // adding a track to it later only renegotiates from the side that
      // offered. Half the pairs would have been one way, silently, and which
      // half depended on who loaded faster.
      applyMic();
      connect();
      // And for anything that did get in first, tell it.
      conns.forEach(function (rec) {
        try { mic.getAudioTracks().forEach(function (tr) { rec.pc.addTrack(tr, mic); }); }
        catch (e) { }
      });
      draw();
    }).catch(function (err) {
      micError = (err && err.name ? err.name : 'refused');
      // NotAllowedError here is not a setting anybody can change. The game's
      // CEF is built without a permission handler, so every media request is
      // refused before it reaches Windows, and there is no prompt to accept.
      // The command line switch that bypasses it, --use-fake-ui-for-media-
      // stream, was tried on the launcher's play button and hung the game on
      // the loading screen every time. So this is the end of that road until
      // SkyrimPlatform is rebuilt: you can hear, you cannot talk.
      report('mic', 'refused ' + micError + ': ' +
                    (err && err.message ? err.message : err));
      // Still joined. Being unable to talk is not a reason to be unable to
      // hear, and the peer list is what the overlay draws.
      connect();
      draw();
    });
  }

  // An AudioContext may start suspended when nobody has clicked anything, and
  // in the game's browser nobody ever will. Ask on every opportunity rather
  // than once, and say so when it stays shut, because silent voice with a
  // healthy peer list looks identical to a broken mesh from the outside.
  function resume() {
    if (!ctx) return;
    if (ctx.state === 'running') { report('audio', 'running'); return; }
    try {
      ctx.resume().then(function () {
        report('audio', ctx.state);
      }).catch(function (e) {
        report('audio', 'suspended, resume refused: ' + e);
      });
    } catch (e) {
      report('audio', 'suspended, resume threw: ' + e);
    }
  }

  // ---------------------------------------------------------- the server ----
  // Nothing is opened here. thornswood-chat.js holds the one socket; this
  // listens on it and posts through it. Both files are fetched by the front in
  // the same pass and neither can rely on running first, so this waits rather
  // than assuming.
  function connect() {
    if (wired) { return; }
    var n = net();
    if (!n) {
      if (!waiting) {
        waiting = setInterval(function () {
          if (net()) { clearInterval(waiting); waiting = null; connect(); }
        }, 500);
        report('server', 'waiting for the chat socket');
      }
      return;
    }
    wired = true;
    report('server', 'sharing the chat socket to ' + cfg.host + ':' + cfg.port);

    myPeer = n.peer();

    n.on(function (m) {
      if (!m || !m.t) { return; }
      if (m.t === 'welcome') { myPeer = Number(m.peer) || 0; return; }
      if (m.t === 'peers') { reconcile(m.peers); return; }
      if (m.t === 'pos') { lastWho = m.who || {}; place(); return; }
      if (m.t === 'sdp') { onSdp(m); return; }
      if (m.t === 'ice') { onIce(m); return; }
      if (m.t === '__closed') {
        report('server', 'the chat socket went down, dropping the mesh');
        conns.forEach(function (_, id) { drop(id); });
        return;
      }
    });
  }

  function reconcile(list) {
    var want = new Map();
    list.forEach(function (p) { if (p.peer !== myPeer) want.set(p.peer, p); });
    conns.forEach(function (_, id) { if (!want.has(id)) drop(id); });
    want.forEach(function (p, id) {
      if (conns.has(id)) {
        conns.get(id).profileId = p.profileId;
        conns.get(id).name = p.name;
        return;
      }
      // Only the lower peer id offers, or both would and the negotiations
      // collide. Every pair agrees on that without being told.
      open(id, p, myPeer < id);
    });
    report('peers', conns.size + ' connected');
    draw();
  }

  function open(id, info, initiator) {
    var pc = new RTCPeerConnection({ iceServers: [{ urls: 'stun:stun.l.google.com:19302' }] });
    var gain = ctx.createGain();
    var panner = ctx.createPanner();
    panner.panningModel = 'HRTF';
    panner.distanceModel = 'inverse';
    panner.refDistance = REF_DISTANCE;
    panner.maxDistance = MAX_DISTANCE;
    panner.rolloffFactor = ROLLOFF;
    panner.connect(gain).connect(ctx.destination);

    var rec = { pc: pc, panner: panner, gain: gain, profileId: info.profileId,
                name: info.name, el: null, dist: null };
    conns.set(id, rec);

    if (mic) {
      mic.getAudioTracks().forEach(function (track) { pc.addTrack(track, mic); });
    } else {
      // No microphone yet, or none at all. Ask for a one way connection rather
      // than none, so the rest of the room is still audible.
      try { pc.addTransceiver('audio', { direction: 'recvonly' }); } catch (e) { }
    }

    pc.onicecandidate = function (e) {
      if (e.candidate) { post({ t: 'ice', to: id, candidate: e.candidate }); }
    };

    pc.ontrack = function (e) {
      var src = ctx.createMediaStreamSource(e.streams[0]);
      src.connect(panner);
      // Chromium will not pump a WebRTC stream through WebAudio unless the
      // stream is also attached to a media element. It is muted: the audible
      // path is the panner.
      var a = new Audio();
      a.srcObject = e.streams[0];
      a.muted = true;
      a.play().catch(function () { });
      rec.el = a;
      resume();
      draw();
    };

    if (initiator) {
      pc.onnegotiationneeded = function () {
        pc.createOffer().then(function (offer) {
          return pc.setLocalDescription(offer);
        }).then(function () {
          post({ t: 'sdp', to: id, sdp: pc.localDescription });
        }).catch(function () { });
      };
    }
  }

  function onSdp(m) {
    var rec = conns.get(m.from);
    if (!rec) return;
    rec.pc.setRemoteDescription(m.sdp).then(function () {
      if (m.sdp.type !== 'offer') return null;
      return rec.pc.createAnswer().then(function (answer) {
        return rec.pc.setLocalDescription(answer);
      }).then(function () {
        post({ t: 'sdp', to: m.from, sdp: rec.pc.localDescription });
      });
    }).catch(function () { });
  }

  function onIce(m) {
    var rec = conns.get(m.from);
    if (!rec) return;
    try { rec.pc.addIceCandidate(m.candidate); } catch (e) { }
  }

  function drop(id) {
    var rec = conns.get(id);
    if (!rec) return;
    try { rec.pc.close(); } catch (e) { }
    try { if (rec.el) { rec.el.pause(); rec.el.srcObject = null; } } catch (e) { }
    conns.delete(id);
    draw();
  }

  // The chat used to live here too, which meant two files rendering the same
  // line. thornswood-chat.js owns it now: it reads the socket, it writes into
  // the front's widget, and it handles /roll. Nothing about chat is left here.

  // ---------------------------------------------------------- placement -----
  function place() {
    var me = lastWho[cfg.profileId];
    if (!me || !ctx) { draw(); return; }

    // Skyrim's Z is up and the facing angle is degrees clockwise from north.
    // WebAudio has Y up and Z toward the listener, so the axes swap and the
    // sign of Z flips. Getting this wrong puts everyone behind you, and only
    // shows up once somebody turns away from north.
    var yaw = (Number(me.angleZ) || 0) * Math.PI / 180;
    var cos = Math.cos(yaw), sin = Math.sin(yaw);

    conns.forEach(function (rec) {
      var them = lastWho[rec.profileId];
      if (!them || !them.pos || !me.pos) { rec.gain.gain.value = 0; rec.dist = null; return; }

      // A wall is not a distance. Different cell, no sound.
      if (String(them.cell) !== String(me.cell)) { rec.gain.gain.value = 0; rec.dist = null; return; }

      var dx = (them.pos[0] - me.pos[0]) / UNITS_PER_METRE;
      var dy = (them.pos[1] - me.pos[1]) / UNITS_PER_METRE;
      var dz = (them.pos[2] - me.pos[2]) / UNITS_PER_METRE;

      var right = dx * cos - dy * sin;
      var forward = dx * sin + dy * cos;

      rec.gain.gain.value = 1;
      setPos(rec.panner, right, dz, -forward);
      rec.dist = Math.sqrt(right * right + forward * forward + dz * dz);
    });
    draw();
  }

  function setPos(panner, x, y, z) {
    if (panner.positionX) {
      panner.positionX.value = x; panner.positionY.value = y; panner.positionZ.value = z;
    } else {
      panner.setPosition(x, y, z);
    }
  }

  // ------------------------------------------------------------- the api ----
  window.thornswoodVoice = {
    configure: function (o) {
      o = o || {};
      if (o.host != null) cfg.host = String(o.host);
      if (o.port != null) cfg.port = Number(o.port) || 7778;
      if (o.profileId != null) cfg.profileId = Number(o.profileId) || 0;
      if (o.name != null) cfg.name = String(o.name);
      if (o.pushToTalk != null) cfg.pushToTalk = !!o.pushToTalk;
      if (o.microphone != null) cfg.microphone = !!o.microphone;
      report('config', cfg.host + ':' + cfg.port + ' as profile ' + cfg.profileId +
                       (cfg.pushToTalk ? ', push to talk' : ', always open'));
      start();
      connect();
    },
    setTalking: function (v) {
      v = !!v;
      if (v === talking) return;
      talking = v;
      resume();
      applyMic();
    },
    // There is no mute. Push to talk already means the microphone is shut
    // unless a key is held, so a second control for "shut" was answering a
    // question nobody asked.
    nudge: function () { resume(); if (!joined) start(); else connect(); },
    state: function () {
      return {
        mic: !!mic, audio: ctx ? ctx.state : 'none',
        socket: net() && net().isUp() ? 'up' : 'down', peers: conns.size,
        talking: talking
      };
    }
  };

  setInterval(function () { if (conns.size) draw(); }, 300);

  // Said once, at load, because when voice does not work these five lines are
  // the difference between knowing why and guessing. A page loaded from file://
  // should report secure=true and mediaDevices=true; if it does not, no amount
  // of fixing the mesh will help.
  try {
    report('where', location.href);
    report('secure', String(window.isSecureContext));
    report('mediaDevices', String(!!navigator.mediaDevices) +
           ', getUserMedia ' + String(!!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia)));
    report('webrtc', typeof window.RTCPeerConnection);
    report('webaudio', typeof (window.AudioContext || window.webkitAudioContext));
  } catch (e) { }

  report('loaded', 'waiting for the plugin to say who we are');
})();
