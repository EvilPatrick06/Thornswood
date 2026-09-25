// test-one-way.js
//
// You could hear them and they could not hear you.
//
// Patrick, 21 September, on the dev server: "for voice I could here Djinn on
// Dev server but he couldnt hear me, my indicator ashowed green but he coudnt
// hear me at all".
//
// THREE THINGS IN voice.js, all readable in the file rather than guessed at:
//
//  1. ONLY THE INITIATOR COULD EVER RENEGOTIATE. onnegotiationneeded was wired
//     inside `if (initiator)`, so the answering side's tracks went out in its
//     first answer or they never went out at all. Anything that changed after
//     that was permanent, silent, and in one direction only, which is the
//     exact shape of the report.
//
//  2. SIGNALLING FOR A PEER NOT YET OPENED WAS THROWN AWAY. onSdp and onIce
//     both began `const rec = conns.get(m.from); if (!rec) return;`, and a
//     connection is only opened by reconcile() off a 'peers' message. An offer
//     or a candidate that overtook that message was dropped in silence and
//     nothing ever retried it, because the sender had already fired its one
//     negotiation.
//
//  3. THE PAGE COULD NOT SHOW IT. The green dot's class comes from rec.dist,
//     so it means "standing near me", and the bar beside it is their level
//     coming IN. Nothing on the page ever said whether your own voice was
//     leaving the machine. The one fault nobody can self diagnose was also the
//     one the page would not show.
//
// This drives the shipped holding and signalling code, and checks the rest of
// the claims against the shipped file.
//
// Read only.
const fs = require('fs');
const path = require('path');
const SRC = process.env.VOICE ||
            path.join(__dirname, 'public', 'voice.js');
const CR = String.fromCharCode(13);
const src = fs.readFileSync(SRC, 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const a = src.indexOf('const pending = new Map();');
const b = a < 0 ? -1 : src.indexOf('\nasync function onIce(m) {', a);
const c = b < 0 ? -1 : src.indexOf('\n}\n', b);
const block = (a >= 0 && c >= 0) ? src.slice(a, c + 3) : null;

yes('the holding code is in the page', block !== null);

/** The real hold, replay, onSdp and onIce, over a pretend set of peers. */
function rig() {
  const conns = new Map();
  const sent = [];
  const applied = { sdp: [], ice: [] };
  const clock = { now: 1000000 };

  const fn = new Function(
    'conns', 'ws', 'Date', 'applied',
    block +
    '\nreturn { hold: hold, replay: replay, onSdp: onSdp, onIce: onIce, ' +
    'pending: pending };');

  const api = fn(
    conns,
    { readyState: 1, send: function (t) { sent.push(JSON.parse(t)); } },
    { now: function () { return clock.now; } },
    applied);
  api.conns = conns; api.sent = sent; api.applied = applied; api.clock = clock;
  return api;
}

/** A peer we have opened. Records what was actually applied to it. */
function peer(api, id, polite) {
  const rec = {
    polite: !!polite, making: false, ignoring: false,
    pc: {
      signalingState: 'stable',
      setRemoteDescription: function (d) {
        api.applied.sdp.push({ id: id, type: d.type }); return Promise.resolve();
      },
      setLocalDescription: function () {
        rec.pc.localDescription = { type: 'answer' }; return Promise.resolve();
      },
      addIceCandidate: function (cnd) {
        api.applied.ice.push({ id: id, c: cnd }); return Promise.resolve();
      },
      localDescription: { type: 'answer' }
    }
  };
  api.conns.set(id, rec);
  return rec;
}

if (block !== null) {
  const THEM = 7;

  // S1: THE CASE THAT HAPPENED. An offer overtakes the peers message.
  {
    const r = rig();
    r.onSdp({ t: 'sdp', from: THEM, sdp: { type: 'offer' } });
    yes('S1 an offer for a peer we have not opened is not thrown away',
        (r.pending.get(THEM) || []).length === 1);
    yes('S1 and nothing was applied yet', r.applied.sdp.length === 0);

    peer(r, THEM, true);
    r.replay(THEM);
    return Promise.resolve().then(function () { }).then(function () {
      yes('S1 and it is applied the moment that peer opens',
          r.applied.sdp.length === 1 && r.applied.sdp[0].type === 'offer');
      yes('S1 and the hold is emptied', !r.pending.get(THEM));
      more();
    });
  }
}

function more() {
  const THEM = 7;

  // S2: candidates are held the same way, in order.
  {
    const r = rig();
    r.onIce({ t: 'ice', from: THEM, candidate: { c: 1 } });
    r.onIce({ t: 'ice', from: THEM, candidate: { c: 2 } });
    yes('S2 candidates for an unopened peer are held', (r.pending.get(THEM) || []).length === 2);
    peer(r, THEM, true);
    r.replay(THEM);
    Promise.resolve().then(function () {
      yes('S2 and both are applied, in the order they arrived',
          r.applied.ice.length === 2 &&
          r.applied.ice[0].c.c === 1 && r.applied.ice[1].c.c === 2);

      // S3: a hold for somebody who has already gone is not replayed at them
      //     twenty seconds later.
      const q = rig();
      q.onSdp({ t: 'sdp', from: THEM, sdp: { type: 'offer' } });
      q.clock.now += 21000;
      peer(q, THEM, true);
      q.replay(THEM);
      Promise.resolve().then(function () {
        yes('S3 anything older than twenty seconds is dropped rather than replayed',
            q.applied.sdp.length === 0);

        // S4: glare. Two offers cross; exactly one side gives way.
        const g = rig();
        const polite = peer(g, THEM, true);
        polite.making = true;
        g.onSdp({ t: 'sdp', from: THEM, sdp: { type: 'offer' } });

        const h = rig();
        const rude = peer(h, THEM, false);
        rude.making = true;
        h.onSdp({ t: 'sdp', from: THEM, sdp: { type: 'offer' } });

        Promise.resolve().then(function () {
          yes('S4 the polite side takes the other offer', g.applied.sdp.length === 1);
          yes('S4 and the impolite side keeps its own', h.applied.sdp.length === 0);
          yes('S4 so exactly one of the pair gives way, which is what stops a collision',
              (g.applied.sdp.length === 1) !== (h.applied.sdp.length === 1));
          structure();
        });
      });
    });
  }
}

function structure() {
  const code = src.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/\/\/[^\n]*/g, ' ');

  yes('both sides can renegotiate, not only the initiator',
      /pc\.onnegotiationneeded/.test(code) &&
      !/if \(initiator\) \{\s*pc\.onnegotiationneeded/.test(code));
  yes('and the polite one is the side that was not the initiator',
      /rec\.polite = !initiator;/.test(code));
  yes('an offer is only ignored by the impolite side',
      /rec\.ignoring = !rec\.polite && offerCollision;/.test(code));
  yes('the page reads packetsSent, which is what the sender actually sent',
      /packetsSent/.test(code));
  yes('and it wants it CLIMBING, so a connection that stopped is not called healthy',
      /n > rec\.sent/.test(code));
  yes('the row says in words whether they can hear you',
      /CANNOT hear you/.test(code));
  yes('and the stats poll is stopped when the peer goes',
      /clearInterval\(rec\.poll\)/.test(code));

  console.log('');
  console.log(pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
}
