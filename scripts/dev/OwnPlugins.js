// OwnPlugins.js
//
// Where a builder reads a plugin of the load order from (#2923).
//
// Thornswood's own plugins (Thornswood-Content.esp, Thornswood-Last.esp,
// Thornswood-WoodworkerTrail.esp, and any other file in game/content) are made
// and shipped from this repository's game/content. A game folder holds
// whichever release last reached it: on 20 Oct One's held a Content plugin
// from 12 Oct, 146,941 bytes against the repository's 117,274 the day before
// #2911 changed it. A table read from there describes a plugin nobody ships,
// and a content change could only be built by making a Data folder of links
// to the repository's copy.
//
// So every plugin whose name is a file in game/content is read from there,
// and every other plugin from the game's Data folder. The same rule is
// OwnPlugins.ps1 for the PowerShell builders and own_plugins.py for the
// Python ones; tests/test-2923-own-plugins.js holds the three to it.
//
//   const { pluginPath } = require('./OwnPlugins.js');
//   const file = pluginPath(DATA, 'Thornswood-Content.esp');
'use strict';
const fs = require('fs');
const path = require('path');

const OWN_DIR = path.join(__dirname, '..', '..', 'game', 'content');

function isOwn(name) {
  return fs.existsSync(path.join(OWN_DIR, name));
}

function pluginPath(dataDir, name) {
  return isOwn(name) ? path.join(OWN_DIR, name) : path.join(dataDir, name);
}

module.exports = { OWN_DIR, isOwn, pluginPath };
