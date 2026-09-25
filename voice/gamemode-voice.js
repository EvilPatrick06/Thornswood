// ----------------------------------------------------------------- voice ---
// Proximity voice, server side.
//
// The voice service runs beside this server and needs one thing from it:
// where everybody is, five times a second. It gets it from here rather than
// from anybody's game, which means voice does not care which client build a
// person runs, and nobody can move their own voice by editing a file.
//
// Everything below is deliberately best effort. A voice service that is down,
// slow or not installed must never be able to take the game server with it, so
// every call is wrapped and failures are counted rather than thrown.
(function () {
  var VOICE_PORT = 7778;
  var EVERY_MS = 200;
  var http = null;

  try { http = require('http'); } catch (e) { return; }
  if (!http) return;

  var failures = 0;
  var complained = false;
  var inFlight = false;

  function send(payload) {
    if (inFlight) return;           // never queue: a late position is worthless
    inFlight = true;

    var body = JSON.stringify(payload);
    var req = http.request({
      host: '127.0.0.1', port: VOICE_PORT, path: '/positions', method: 'POST',
      headers: { 'content-type': 'application/json', 'content-length': Buffer.byteLength(body) }
    }, function (res) {
      res.resume();
      res.on('end', function () { inFlight = false; failures = 0; complained = false; });
    });

    req.on('error', function () {
      inFlight = false;
      failures++;
      // Once, then quiet. Nobody needs this five times a second for an hour.
      if (failures === 25 && !complained) {
        complained = true;
        console.log('[thornswood] voice service is not answering on ' + VOICE_PORT +
                    '. Proximity voice is off; everything else is unaffected.');
      }
    });
    req.setTimeout(1000, function () { try { req.destroy(); } catch (e) { } });
    req.end(body);
  }

  setInterval(function () {
    var who = [];
    try {
      var online = mp.get(0, 'onlinePlayers') || [];
      for (var i = 0; i < online.length; i++) {
        var id = online[i];
        try {
          var pos = mp.get(id, 'pos');
          if (!pos) continue;
          var angle = mp.get(id, 'angle') || [0, 0, 0];
          who.push({
            profileId: mp.get(id, 'profileId'),
            pos: pos,
            angleZ: angle[2],
            // Two people in the same room share this string. Two people either
            // side of a loading door do not, which is exactly the line voice
            // should stop at.
            cell: String(mp.get(id, 'worldOrCellDesc') || ''),
            name: String(mp.get(id, 'appearance') && mp.get(id, 'appearance').name || '')
          });
        } catch (e) { }
      }
    } catch (e) { return; }

    if (who.length === 0) return;
    try { send({ who: who }); } catch (e) { }
  }, EVERY_MS);

  // ------------------------------------------------------------- online ---
  // How many people are awake, written where the launcher can read it.
  //
  // There is no way to ask a SkyMP server how busy it is: its networking has
  // no status packet, and the public list the old build used belongs to Skyrim
  // Together and this server never reports to it. But the server already
  // serves its resources folder over HTTP, so a small file dropped in there is
  // readable by every launcher without opening anything new or inventing a
  // protocol.
  try {
    var fs = require('fs');
    var path = require('path');
    var dataDir = 'data';
    try {
      var cfg = JSON.parse(fs.readFileSync('server-settings.json', 'utf8'));
      if (cfg && cfg.dataDir) dataDir = String(cfg.dataDir);
    } catch (e) { }

    var onlineFile = path.join(dataDir, 'online.json');
    var lastWritten = -1;

    setInterval(function () {
      var n = 0;
      try { n = (mp.get(0, 'onlinePlayers') || []).length; } catch (e) { return; }
      // Only when it moves. This file sits in a folder the server serves, and
      // rewriting it twice a second for no reason is churn nobody asked for.
      if (n === lastWritten) return;
      lastWritten = n;
      try {
        fs.writeFileSync(onlineFile, JSON.stringify({ now: n, at: Date.now() }));
      } catch (e) { }
    }, 2000);

    console.log('[thornswood] online count published at ' + onlineFile);
  } catch (e) { }

  console.log('[thornswood] voice position feed running, pushing to 127.0.0.1:' + VOICE_PORT);
})();
