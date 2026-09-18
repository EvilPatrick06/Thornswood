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
const ROLLOFF = 1.4;

const qs = new URLSearchParams(location.search);
const MY_PROFILE = Number(qs.get('profile') || 1);
const MY_NAME = qs.get('name') || '';

const el = (id) => document.getElementById(id);
const state = el('state'), rows = el('rows');

let ws = null, ctx = null, mic = null, myPeer = 0;
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
    say('Lost the voice server. Trying again in five seconds.');
    for (const [id] of conns) drop(id);
    setTimeout(connect, 5000);
  };

  ws.onmessage = (ev) => {
    let m; try { m = JSON.parse(ev.data); } catch (e) { return; }
    if (m.t === 'welcome') { myPeer = m.peer; return; }
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
  panner.distanceModel = 'inverse';
  panner.refDistance = REF_DISTANCE;
  panner.maxDistance = MAX_DISTANCE;
  panner.rolloffFactor = ROLLOFF;
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

  if (initiator) {
    pc.onnegotiationneeded = async () => {
      try {
        const offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        ws.send(JSON.stringify({ t: 'sdp', to: id, sdp: pc.localDescription }));
      } catch (e) { }
    };
  }
}

async function onSdp(m) {
  const rec = conns.get(m.from);
  if (!rec) return;
  try {
    await rec.pc.setRemoteDescription(m.sdp);
    if (m.sdp.type === 'offer') {
      const answer = await rec.pc.createAnswer();
      await rec.pc.setLocalDescription(answer);
      ws.send(JSON.stringify({ t: 'sdp', to: m.from, sdp: rec.pc.localDescription }));
    }
  } catch (e) { }
}

async function onIce(m) {
  const rec = conns.get(m.from);
  if (!rec) return;
  try { await rec.pc.addIceCandidate(m.candidate); } catch (e) { }
}

function drop(id) {
  const rec = conns.get(id);
  if (!rec) return;
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
    if (!them || !them.pos || !me.pos) { rec.gain.gain.value = 0; rec.dist = null; continue; }

    // A wall is not a distance. Different cell, no sound, whatever the maths says.
    if (String(them.cell) !== String(me.cell)) { rec.gain.gain.value = 0; rec.dist = null; continue; }

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

    rec.gain.gain.value = 1;
    setPos(rec.panner, right, dz, -forward);
    rec.dist = Math.sqrt(right * right + forward * forward + dz * dz);
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
    rows.innerHTML = '<tr><td colspan="3" class="note" style="border-top:none">Nobody yet.</td></tr>';
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
    parts.push('<tr><td><span class="dot ' + cls + '"></span>' + esc(who) + '</td>' +
               '<td class="n">' + d + '</td>' +
               '<td class="n"><span class="bar"><i style="width:' + lvl + '%"></i></span></td></tr>');
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
