// tests/fixtures/known-page.js
//
// The Known Issues page as the site serves it (#2414). Its one copy is the
// "known" board in site/data/board.json, which the hub edits, and /known and
// /api/page/known are that board written out by knownMarkdown in
// site/server.js. A test that reads what the page says reads it through here,
// so it reads the same text a person sees, made by the same code.
//
//   const { knownPage } = require('./fixtures/known-page');
//   const md = knownPage();          // the page's markdown, or null
//   const md = knownPage(otherRoot);  // the same out of another checkout
//
// Read only.
'use strict';
const fs = require('fs');
const path = require('path');

const REPO = path.join(__dirname, '..', '..');
const MARK = /\/\/ ==== thornswood known board ====([\s\S]*?)\/\/ ==== end thornswood known board ====/;

// knownMarkdown out of server.js, between its markers, or null.
function knownWriter(serverSource) {
  const cut = MARK.exec(String(serverSource || ''));
  if (!cut) return null;
  return new Function(cut[1] + '\nreturn knownMarkdown;')();
}

// The page's markdown out of a checkout (this one by default), or null when
// server.js has no writer or board.json has no known board.
function knownPage(root) {
  const base = root || REPO;
  let src, board;
  try { src = fs.readFileSync(path.join(base, 'site', 'server.js'), 'utf8'); } catch (e) { return null; }
  try { board = JSON.parse(fs.readFileSync(path.join(base, 'site', 'data', 'board.json'), 'utf8')); } catch (e) { return null; }
  const write = knownWriter(src);
  if (!write || !board || !board.known) return null;
  return write('Known Issues', board.known);
}

module.exports = { knownPage, knownWriter, MARK };
