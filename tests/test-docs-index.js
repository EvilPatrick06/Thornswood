// test-docs-index.js
//
// docs/README.md is the index of the pages in docs/. Every page outside
// archive/ must have a row there, so a new page cannot land without being
// findable from the index.
//
// WHY THIS EXISTS. Issue #1103: docs/COLLECTION-REBUILD-7ESSXF.md was in
// docs/ but not in the index, found while adding COLLECTION-REVISION-2.md
// for #476. The index says "Every page cites file and line for what it
// says" and lists every page but that one. Without a harness the next
// page will miss the table the same way.
//
// What it checks:
//   1. docs/README.md exists and has a markdown table;
//   2. every .md file directly under docs/ other than README.md itself
//      appears as a link target in that table (systems/ and archive/ are
//      covered by their own directory rows; nested pages stay under those);
//   3. COLLECTION-REBUILD-7ESSXF.md specifically has a row (#1103).
//
// Read only.
//
//     node tests/test-docs-index.js
const path = require('path');
const fs = require('fs');

const ROOT = path.join(__dirname, '..');
const DOCS = path.join(ROOT, 'docs');
const INDEX = path.join(DOCS, 'README.md');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

function read(p) {
  try { return fs.readFileSync(p, 'utf8').replace(/^\uFEFF/, ''); }
  catch (e) { return null; }
}

const index = read(INDEX);
yes('docs/README.md exists', index !== null);

const targets = new Set();
if (index !== null) {
  const linkRe = /\[([^\]]*)\]\(([^)]+)\)/g;
  let m;
  while ((m = linkRe.exec(index)) !== null) {
    targets.add(m[2].trim().replace(/^\.\//, ''));
  }
}
yes('docs/README.md has at least one markdown link (the index table)', targets.size > 0);

let topPages = [];
try {
  topPages = fs.readdirSync(DOCS).filter(function (name) {
    return /\.md$/i.test(name) && !/^README\.md$/i.test(name);
  }).sort();
} catch (e) {
  yes('docs/ can be listed', false);
}

topPages.forEach(function (name) {
  yes('docs/' + name + ' has a row (or link) in docs/README.md', targets.has(name));
});
yes('COLLECTION-REBUILD-7ESSXF.md is in the index (#1103)', targets.has('COLLECTION-REBUILD-7ESSXF.md'));
yes('docs/README.md has a systems/ row', targets.has('systems/') || targets.has('systems'));
yes('docs/README.md has an archive row', targets.has('archive') || targets.has('archive/'));

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail > 0 ? 1 : 0);
