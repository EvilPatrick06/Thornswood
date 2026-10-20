// test-2483-kept-npcs.js
//
//     node tests/test-2483-kept-npcs.js
//
// #2483: a kept NPC stood twice for a moment. Each game spawned the server's
// copy with placeAtMe and left the plugin's placed copy standing until the
// world cleaner picked it at random. The fix is in the fork
// (engine/skymp/skymp5-client/src/view/formView.ts): the view takes the placed
// reference (refrId - 0x100000000) instead of spawning a second one.
//
// This runs the fork's own harness, skymp5-client/test-kept-npc-adopt.js,
// against the pinned engine/skymp. It needs the submodule checked out
// (git submodule update --init engine/skymp). The pull request gate does not
// check it out, so this is listed in tests/gate-excluded.txt.
'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const harness = path.join(__dirname, '..', 'engine', 'skymp', 'skymp5-client', 'test-kept-npc-adopt.js');
if (!fs.existsSync(harness)) {
  console.log('FAIL  engine/skymp is not checked out, or its pin is older than the #2483 fix: ' + harness);
  process.exit(1);
}
const r = spawnSync(process.execPath, [harness], { stdio: 'inherit' });
process.exit(r.status === null ? 1 : r.status);