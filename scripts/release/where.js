'use strict';
/**
 * where.js
 *
 *   const { where, resolveMove, repoRoot } = require('./where.js');
 *   where('Engine')
 *   resolveMove('bot')
 *
 * Same map as Where.ps1: reads layout.json at the repository root and prefers
 * the new place when it is present, then the old one. Issue #440 phase 0.
 *
 * Read only. Creates nothing.
 */

const fs = require('fs');
const path = require('path');

const here = __dirname;
const repo = path.resolve(here, '..', '..');
const layoutPath = path.join(repo, 'layout.json');

function loadLayout() {
  if (!fs.existsSync(layoutPath)) {
    throw new Error(
      'layout.json is not at ' + layoutPath +
      '. It is in the repository, so the path is wrong.'
    );
  }
  return JSON.parse(fs.readFileSync(layoutPath, 'utf8'));
}

function joinRepo(rel) {
  if (!rel) return repo;
  const parts = String(rel).split(/[\\/]+/).filter((p) => p && p !== '.');
  return path.join(repo, ...parts);
}

function joinUnder(root, rel) {
  if (!rel) return root;
  const parts = String(rel).split(/[\\/]+/).filter((p) => p && p !== '.');
  return path.join(root, ...parts);
}

function getEngine(layout, oldRoot) {
  const spec = layout.places.Engine;
  const neu = joinRepo(spec.new);
  const old = joinUnder(oldRoot, spec.oldUnderRoot);
  const probe = spec.presentWhen;
  if (probe && fs.existsSync(path.join(neu, probe))) return neu;
  if (fs.existsSync(old)) return old;
  return neu;
}

function getOut(layout, oldRoot) {
  const spec = layout.places.Out;
  const neu = joinRepo(spec.new);
  if (fs.existsSync(neu)) return neu;
  const any = spec.oldPresentWhenAny || [];
  for (const name of any) {
    if (fs.existsSync(path.join(oldRoot, name))) return oldRoot;
  }
  return neu;
}

function getPlace(layout, oldRoot, name) {
  if (name === 'Repo') return repo;
  if (name === 'Engine') return getEngine(layout, oldRoot);
  if (name === 'Out') return getOut(layout, oldRoot);
  // This machine's working copies of the feeds (Feed-Store.ps1, #907), not
  // clones of Thornswood-Releases beside the repository any more.
  if (name === 'Releases' || name === 'ReleasesDev') {
    return path.join(process.env.LOCALAPPDATA || '', 'Thornswood', 'feed', name === 'Releases' ? 'main' : 'dev');
  }
  if (layout.siblings && layout.siblings[name] != null) {
    return path.join(path.dirname(repo), layout.siblings[name]);
  }
  const der = layout.derived && layout.derived[name];
  if (der) {
    return joinUnder(getPlace(layout, oldRoot, der.from), der.join);
  }
  return null;
}

function getMove(layout, name) {
  const m = layout.moves && layout.moves[name];
  if (!m) return null;
  const neu = joinRepo(m.new);
  const old = joinRepo(m.old);
  if (fs.existsSync(neu)) return neu;
  if (fs.existsSync(old)) return old;
  return neu;
}

const PLACE_NAMES = [
  'Repo', 'Engine', 'ServerDist', 'ClientDist', 'ServerSettings', 'ChangeForms',
  'Out', 'Dist', 'Package', 'Payload', 'ServerZip', 'Releases', 'ReleasesDev'
];

/**
 * @param {string} what Place or move name from layout.json
 * @param {{ oldRoot?: string }} [opts]
 * @returns {string}
 */
function where(what, opts) {
  const layout = loadLayout();
  const oldRoot = (opts && opts.oldRoot) || layout.oldRootDefault || 'C:\\Thornswood-Dev';
  if (PLACE_NAMES.indexOf(what) >= 0) {
    const p = getPlace(layout, oldRoot, what);
    if (p == null) throw new Error('Where does not know place ' + what);
    return p;
  }
  const moveNames = Object.keys(layout.moves || {});
  if (moveNames.indexOf(what) >= 0) {
    return getMove(layout, what);
  }
  throw new Error(
    "where.js does not know '" + what + "'. Known: " +
    PLACE_NAMES.concat(moveNames).join(', ')
  );
}

/**
 * Resolve a reorganisation move key (bot, voice, site, ...). New folder first.
 * @param {string} name
 * @param {{ oldRoot?: string }} [opts]
 * @returns {string}
 */
function resolveMove(name, opts) {
  return where(name, opts);
}

function repoRoot() {
  return repo;
}

module.exports = {
  where,
  resolveMove,
  repoRoot,
  layoutPath,
  PLACE_NAMES
};

if (require.main === module) {
  const arg = process.argv[2];
  if (!arg) {
    process.stderr.write('Usage: node where.js <Place|Move>\n');
    process.exit(2);
  }
  process.stdout.write(where(arg) + '\n');
}
