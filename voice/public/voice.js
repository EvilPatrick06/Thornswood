'use strict';
/*
  Thornswood proximity voice, browser side.

  Audio goes peer to peer over WebRTC. The only thing that comes from the
  server is where everybody is standing, which it already knows, so nobody's
  voice depends on their own game telling the truth about their position.

  The distance model is the one the bench settled on: Skyrim is 70 units to
  the metre, full volume inside four metres, silence by thirty.
*/

const UNITS_PER_METRE = 70;
const REF_DISTANCE = 4;    // metres at full volume
const MAX_DISTANCE = 30;   // metres to silence

/*
  HOW LOUD SOMEBODY IS AT A GIVEN DISTANCE, worked out here rather than left to
  the panner.

  MAX_DISTANCE USED TO BE A LIE. It was handed to a panner whose distanceModel
  is 'inverse', and WebAudio's inverse model does not read maxDistance at all;
  only the linear model does. So there was no silence at thirty metres or at
  any other distance: a voice got quieter for ever and never stopped. The
  overlay this page is the plain browser twin of had the same defect and it is
  on the To Do List as "Whisper, local and yell all carry the same distance,
  because the page changes a number WebAudio does not read".

  So the panner does direction and nothing else, and this does the level: full
  strength to REF_DISTANCE, then a natural 1/d falloff scaled to reach exactly
  nothing at MAX_DISTANCE.

  WHAT THIS PAGE STILL DOES NOT HAVE is the three speaking modes. It is a
  second client with a smaller feature set, reachable by anybody who opens the
  address, and giving it modes means carrying the vmode protocol here too.
  That is its own piece of work; this is the half that was simply wrong.
*/
function levelFor(metres) {
  let d = Number(metres);
  if (!isFinite(d) || d < 0) { d = 0; }
  if (d >= MAX_DISTANCE) { return 0; }
  if (d <= REF_DISTANCE) { return 1; }
  return (REF_DISTANCE / d) * (1 - ((d - REF_DISTANCE) / (MAX_DISTANCE - REF_DISTANCE)));
}

/* Ramped rather than assigned: a gain that jumps clicks. */
function setGain(node, want) {
  try { node.gain.setTargetAtTime(want, ctx ? ctx.currentTime : 0, 0.04); }
  catch (e) { try { node.gain.value = want; } catch (e2) { } }
}

const qs = new URLSearchParams(location.search);
const MY_PROFILE = Number(qs.get('profile') || 1);
const MY_NAME = qs.get('name') || '';

const el = (id) => document.getElementById(id);
const state = el('state'), rows = el('rows');

let ws = null, ctx = null, mic = null, myPeer = 0;
/* Why the server last refused this page, '' when it has not. See onclose. */
let deniedWhy = '';
let muted = false;
let lastWho = {};
const conns = new Map();   // peerId -> {pc, panner, gain, el, profileId, name, analyser, data}

// ------------------------------------------------------------- connecting --
function say(t) { state.textContent = t; }

el('join').onclick = async () => {
  el('join').disabled = true;
  say('Asking for the microphone.');
  try {
    mic = await navigator.mediaDevices.getUserMedia({
      audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true }
    });
  } catch (e) {
    say('No microphone. ' + (e && e.message ? e.message : ''));
    el('join').disabled = false;
    return;
  }

  ctx = new (window.AudioContext || window.webkitAudioContext)();
  await ctx.resume();
  // Heads sit at the origin facing down -Z, and everyone else is placed
  // relative to that. Nothing is ever placed in absolute game coordinates,
  // because the listener would then have to move too and there is no reason
  // for both to.
  if (ctx.listener.forwardZ) {
    ctx.listener.forwardX.value = 0; ctx.listener.forwardY.value = 0; ctx.listener.forwardZ.value = -1;
    ctx.listener.upX.value = 0; ctx.listener.upY.value = 1; ctx.listener.upZ.value = 0;
  } else if (ctx.listener.setOrientation) {
    ctx.listener.setOrientation(0, 0, -1, 0, 1, 0);
  }

  el('mute').disabled = false;
  connect();
};

el('mute').onclick = () => {
  muted = !muted;
  if (mic) mic.getAudioTracks().forEach(t => { t.enabled = !muted; });
  el('mute').textContent = muted ? 'Unmute' : 'Mute';
};

function connect() {
  const proto = location.protocol === 'https:' ? 'wss' : 'ws';
  ws = new WebSocket(proto + '://' + location.host);

  ws.onopen = () => {
    say('Connected. Waiting for the server to say where everyone is.');
    ws.send(JSON.stringify({ t: 'join', profileId: MY_PROFILE, name: MY_NAME }));
  };

  ws.onclose = () => {
    for (const [id] of conns) drop(id);
    /*
      A REFUSAL IS NOT A DROPPED CONNECTION, AND THIS TREATED THEM THE SAME.

      Measured 22 September in the live voice log: 3,999 of its 4,000 lines are
      "REFUSED a join for profile ...: an expired token", for three profiles.
      The service was right to refuse and right to say so; it sends
      { t: 'denied', why } and closes. This page never handled that message, so
      the refusal fell through the switch in onmessage, the socket closed, this
      ran, and it reconnected five seconds later with the same dead token. Five
      seconds apart for hours, which is the whole log.

      Retrying a token the server has just called expired cannot work: the page
      holds one string and reconnecting does not fetch another. The plugin
      rewrites it on a five minute tick, so a minute is the right wait, and the
      person is told what is happening instead of watching a line that says the
      server keeps going away.
    */
    if (deniedWhy) {
      say('The voice server would not let this page in: ' + deniedWhy +
          '. Trying again in a minute with a fresh token.');
      setTimeout(connect, 60000);
      return;
    }
    say('Lost the voice server. Trying again in five seconds.');
    setTimeout(connect, 5000);
  };

  ws.onmessage = (ev) => {
    let m; try { m = JSON.parse(ev.data); } catch (e) { return; }
    /*
      The one message this page did not know about. See onclose.
      Cleared on a welcome, so a page that gets in after a bad spell goes back
      to the ordinary five second retry.
    */
    if (m.t === 'denied') { deniedWhy = String(m.why || 'it did not say why'); return; }
    if (m.t === 'welcome') { myPeer = m.peer; deniedWhy = ''; return; }
    if (m.t === 'peers') { reconcile(m.peers); return; }
    if (m.t === 'pos') { lastWho = m.who || {}; place(); return; }
    if (m.t === 'sdp') { onSdp(m); return; }
    if (m.t === 'ice') { onIce(m); return; }
  };
}

// ------------------------------------------------------------------ peers --
function reconcile(list) {
  const want = new Map();
  for (const p of list) if (p.peer !== myPeer) want.set(p.peer, p);

  for (const [id] of conns) if (!want.has(id)) drop(id);

  for (const [id, p] of want) {
    if (conns.has(id)) { conns.get(id).profileId = p.profileId; conns.get(id).name = p.name; continue; }
    // Only one side offers, or both would and the negotiation collides. The
    // lower peer id is the one that starts, which every pair agrees on without
    // having to be told.
    open(id, p, myPeer < id);
    // Anything that arrived for them before now. See hold().
    replay(id);
  }
  draw();
}

/*
Where to look for each other, asked for rather than typed in.

This was a Google STUN server written into three separate pages. STUN
alone only works when both ends can be reached once they know where to
look; behind a symmetric NAT, some mobile networks and a lot of corporate
ones, they cannot, and that pair of people never hear each other while
everybody else sounds fine. TURN fixes it and needs a relay, which cannot
be typed into a page, so the service hands the list out at /ice.

The old value stays here as the fallback, so a service that has not been
told about a relay, or one that cannot be reached for a moment, behaves
exactly as this did before.
*/
// Served by the voice service itself, so this one can just ask for /ice.
let ICE = [{ urls: 'stun:stun.l.google.com:19302' }];
fetch('/ice')
  .then((r) => r.json())
  .then((d) => { if (d && d.iceServers && d.iceServers.length) { ICE = d.iceServers; } })
  .catch(() => { });

function open(id, info, initiator) {
  const pc = new RTCPeerConnection({ iceServers: ICE });
  const gain = ctx.createGain();
  const panner = ctx.createPanner();
  panner.panningModel = 'HRTF';
  // Direction only: rolloffFactor 0 makes the inverse model return 1 at every
  // distance, and levelFor does the rest. See levelFor.
  panner.distanceModel = 'inverse';
  panner.refDistance = 1;
  panner.rolloffFactor = 0;
  panner.connect(gain).connect(ctx.destination);

  const analyser = ctx.createAnalyser();
  analyser.fftSize = 256;
  const data = new Uint8Array(analyser.frequencyBinCount);

  const rec = { pc, panner, gain, profileId: info.profileId, name: info.name, analyser, data, el: null };
  conns.set(id, rec);

  for (const track of mic.getAudioTracks()) pc.addTrack(track, mic);

  pc.onicecandidate = (e) => {
    if (e.candidate && ws && ws.readyState === 1) {
      ws.send(JSON.stringify({ t: 'ice', to: id, candidate: e.candidate }));
    }
  };

  /*
    IS ANYBODY ACTUALLY GETTING MY VOICE.

    Patrick, 21 September, on the dev server: "for voice I could here Djinn on
    Dev server but he couldnt hear me, my indicator ashowed green but he coudnt
    hear me at all".

    THE GREEN DOT HAS NEVER MEANT THAT. Read draw(): the dot's class comes from
    rec.dist, so green means "this person is standing near me in the world" and
    nothing else, and the bar beside it is THEIR level coming in. There was no
    indication anywhere on this page of whether your own voice was leaving the
    machine. So the one fault a proximity voice system can have that nobody can
    self diagnose was also the one the page could not show.

    outbound-rtp packetsSent is the ground truth: it is counted by the sender's
    own stack once media is actually going out on that connection. If it is
    climbing, they are receiving audio and the problem is at their end. If it
    is stuck, it is at ours, and which one it is is the whole diagnosis.
  */
  rec.sent = null;
  rec.sending = false;
  const poll = setInterval(() => {
    if (!conns.has(id)) { clearInterval(poll); return; }
    pc.getStats(null).then((report) => {
      report.forEach((r) => {
        if (r.type !== 'outbound-rtp' || r.kind !== 'audio') { return; }
        const n = Number(r.packetsSent) || 0;
        // Climbing, not merely non-zero. A connection that sent a little and
        // then stopped is the exact fault being looked for, and a raw count
        // would keep saying yes forever.
        rec.sending = (rec.sent !== null && n > rec.sent);
        rec.sent = n;
      });
      draw();
    }).catch(() => { });
  }, 2000);
  rec.poll = poll;

  pc.ontrack = (e) => {
    const src = ctx.createMediaStreamSource(e.streams[0]);
    src.connect(panner);
    src.connect(analyser);
    // Chrome will not run a WebRTC stream through WebAudio unless the stream
    // is also attached to a media element somewhere. It is muted: the audible
    // path is the panner.
    const a = new Audio();
    a.srcObject = e.streams[0];
    a.muted = true;
    a.play().catch(() => { });
    rec.el = a;
    draw();
  };

  /*
    BOTH SIDES CAN RENEGOTIATE, AND ONE OF THEM IS POLITE ABOUT IT.

    This block used to be wrapped in `if (initiator)`, so the answering side
    had NO renegotiation path at all, ever. Its tracks went out in the first
    answer or they never went out. Anything that changed its sending state
    after that, a track added a moment late, a device that came back, a
    connection that had to be rebuilt, was permanent and silent and in one
    direction only, which is exactly the shape Patrick reported.

    Wiring both sides means both can offer, and two offers crossing is a glare
    collision that breaks the connection outright. The standard answer is
    perfect negotiation: one side is polite and gives way, the other is not.
    The roles come from the same comparison that used to pick the initiator,
    so every pair still agrees without being told: the lower peer id is the
    impolite one and keeps its offer.
  */
  rec.polite = !initiator;
  rec.making = false;
  rec.ignoring = false;

  pc.onnegotiationneeded = async () => {
    try {
      rec.making = true;
      await pc.setLocalDescription();
      if (ws && ws.readyState === 1) {
        ws.send(JSON.stringify({ t: 'sdp', to: id, sdp: pc.localDescription }));
      }
    } catch (e) {
      // Older browsers want the offer made by hand. Same message either way.
      try {
        const offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        if (ws && ws.readyState === 1) {
          ws.send(JSON.stringify({ t: 'sdp', to: id, sdp: pc.localDescription }));
        }
      } catch (e2) { }
    } finally {
      rec.making = false;
    }
  };
}

/*
  SIGNALLING THAT ARRIVES BEFORE THE PEER IS KNOWN IS KEPT, NOT DROPPED.

  Both of these began `const rec = conns.get(m.from); if (!rec) return;`. A
  connection is only opened by reconcile(), off a 'peers' message, so an offer
  or a candidate that arrived before our own peer list caught up was thrown
  away in silence. Nothing ever retried it: the sender had already fired its
  one negotiation. The pair then had no media, or media one way only if some
  of the candidates landed and some did not.

  So anything for a peer we have not opened yet is held for twenty seconds and
  replayed the moment reconcile() opens them. Twenty seconds because a 'peers'
  message follows a join closely; anything older than that is for somebody who
  has already gone.
*/
const pending = new Map();   // peerId -> [{at, m}]

function hold(m) {
  const list = pending.get(m.from) || [];
  list.push({ at: Date.now(), m });
  pending.set(m.from, list);
}

function replay(id) {
  const list = pending.get(id);
  if (!list) { return; }
  pending.delete(id);
  const now = Date.now();
  for (const held of list) {
    if (now - held.at > 20000) { continue; }
    if (held.m.t === 'sdp') { onSdp(held.m); } else { onIce(held.m); }
  }
}

async function onSdp(m) {
  const rec = conns.get(m.from);
  if (!rec) { hold(m); return; }
  try {
    /*
      The polite half of perfect negotiation. See open(). If an offer arrives
      while we are making our own, the polite side rolls back and takes theirs
      and the impolite side ignores it, so the pair always settles on one.
    */
    const offerCollision = m.sdp.type === 'offer' &&
      (rec.making || rec.pc.signalingState !== 'stable');
    rec.ignoring = !rec.polite && offerCollision;
    if (rec.ignoring) { return; }

    await rec.pc.setRemoteDescription(m.sdp);
    if (m.sdp.type === 'offer') {
      await rec.pc.setLocalDescription();
      if (ws && ws.readyState === 1) {
        ws.send(JSON.stringify({ t: 'sdp', to: m.from, sdp: rec.pc.localDescription }));
      }
    }
  } catch (e) {
    // Older browsers want the answer made by hand.
    try {
      if (m.sdp.type === 'offer') {
        const answer = await rec.pc.createAnswer();
        await rec.pc.setLocalDescription(answer);
        if (ws && ws.readyState === 1) {
          ws.send(JSON.stringify({ t: 'sdp', to: m.from, sdp: rec.pc.localDescription }));
        }
      }
    } catch (e2) { }
  }
}

async function onIce(m) {
  const rec = conns.get(m.from);
  if (!rec) { hold(m); return; }
  try { await rec.pc.addIceCandidate(m.candidate); }
  catch (e) { if (!rec.ignoring) { /* a candidate for an offer we ignored */ } }
}

function drop(id) {
  const rec = conns.get(id);
  if (!rec) return;
  try { if (rec.poll) { clearInterval(rec.poll); } } catch (e) { }
  try { rec.pc.close(); } catch (e) { }
  try { if (rec.el) { rec.el.pause(); rec.el.srcObject = null; } } catch (e) { }
  conns.delete(id);
  draw();
}

// -------------------------------------------------------------- placement --
function place() {
  const me = lastWho[MY_PROFILE];
  if (!me || !ctx) { draw(); return; }

  // Skyrim's Z is up and the facing angle is degrees clockwise from north.
  // WebAudio has Y up and Z toward the listener, so the two axes swap and the
  // sign of Z flips. Getting this wrong puts everyone behind you.
  const yaw = (Number(me.angleZ) || 0) * Math.PI / 180;
  const cos = Math.cos(yaw), sin = Math.sin(yaw);

  for (const [, rec] of conns) {
    const them = lastWho[rec.profileId];
    if (!them || !them.pos || !me.pos) { setGain(rec.gain, 0); rec.dist = null; continue; }

    // A wall is not a distance. Different cell, no sound, whatever the maths says.
    if (String(them.cell) !== String(me.cell)) { setGain(rec.gain, 0); rec.dist = null; continue; }

    const dx = (them.pos[0] - me.pos[0]) / UNITS_PER_METRE;
    const dy = (them.pos[1] - me.pos[1]) / UNITS_PER_METRE;
    const dz = (them.pos[2] - me.pos[2]) / UNITS_PER_METRE;

    // Rotate into the listener's frame. Facing 0 is north, which is +Y, and
    // the angle grows clockwise, so forward is (sin, cos) and right is
    // (cos, -sin). Then map to WebAudio, where +X is the listener's right and
    // forward is -Z. Getting either half wrong only shows up once somebody
    // turns away from north, which is why it is worth writing out.
    const right = dx * cos - dy * sin;
    const forward = dx * sin + dy * cos;

    rec.dist = Math.sqrt(right * right + forward * forward + dz * dz);
    setGain(rec.gain, levelFor(rec.dist));
    setPos(rec.panner, right, dz, -forward);
  }
  draw();
}

function setPos(panner, x, y, z) {
  if (panner.positionX) {
    panner.positionX.value = x; panner.positionY.value = y; panner.positionZ.value = z;
  } else {
    panner.setPosition(x, y, z);
  }
}

// ------------------------------------------------------------------- draw --
function draw() {
  if (conns.size === 0) {
    rows.innerHTML = '<tr><td colspan="4" class="note" style="border-top:none">Nobody yet.</td></tr>';
    return;
  }
  const parts = [];
  for (const [id, rec] of conns) {
    let lvl = 0;
    if (rec.analyser) {
      rec.analyser.getByteFrequencyData(rec.data);
      let sum = 0;
      for (let i = 0; i < rec.data.length; i++) sum += rec.data[i];
      lvl = Math.min(100, Math.round((sum / rec.data.length) * 1.6));
    }
    const near = rec.dist != null && rec.dist <= MAX_DISTANCE;
    const cls = rec.dist == null ? '' : (near ? 'on' : 'far');
    const who = rec.name || ('profile ' + rec.profileId);
    const d = rec.dist == null ? 'elsewhere' : (rec.dist < 1 ? 'right here' : Math.round(rec.dist) + ' m');
    /*
      WHETHER THEY ARE GETTING YOUR VOICE, said in words.

      The dot is proximity and the bar is what is coming IN, and neither has
      ever said anything about what is going OUT. This column does, off
      packetsSent. 'starting' is the first couple of seconds before there are
      two samples to compare, and is not a fault.
    */
    const out = rec.sent === null ? 'starting'
              : (rec.sending ? 'hears you' : 'CANNOT hear you');
    const outCls = rec.sent === null ? '' : (rec.sending ? 'on' : 'far');
    parts.push('<tr><td><span class="dot ' + cls + '"></span>' + esc(who) + '</td>' +
               '<td class="n">' + d + '</td>' +
               '<td class="n"><span class="bar"><i style="width:' + lvl + '%"></i></span></td>' +
               '<td class="n"><span class="dot ' + outCls + '"></span>' + out + '</td></tr>');
  }
  rows.innerHTML = parts.join('');
}

function esc(s) {
  return String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
}

setInterval(() => { if (conns.size) draw(); }, 250);

if (!navigator.mediaDevices || !window.RTCPeerConnection) {
  say('This browser has no microphone or WebRTC support.');
  el('join').disabled = true;
}
