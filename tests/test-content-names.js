// test-content-names.js
//
// Issue #400. Thornswood-Content.esp came from another server, and that
// server's name (Kzl, kzolivar) was on 33 editor ids and one script. The
// editor ids were renamed by scripts\mods\Rename-ContentRecords.ps1. The
// script is KzlChop, attached by a VMAD to FURN 0x05DF7B34, the headsman's
// block placed once in Solitude. KzlChop.pex never shipped, so it never ran;
// scripts\mods\Add-ContentRecords.py now takes the attachment off.
//
// This reads the plugin with its own reader, not the tool's, and proves:
//   1. the committed plugin has no editor id beginning Kzl or kzolivar,
//      compressed records included;
//   2. the tool, run over a copy, leaves the other server's name nowhere in
//      the file, takes off only the block's VMAD, keeps every form id, type
//      and flag in the same order, leaves every other record byte for byte,
//      keeps the placed block, and writes the true record count;
//   3. a second run changes nothing.
//
// The copy is written to a temporary folder (TEST_TMP if set) and removed.
// Nothing in the repo is written.
const fs = require('fs');
const os = require('os');
const path = require('path');
const zlib = require('zlib');
const { spawnSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const ESP = path.join(ROOT, 'game', 'content', 'Thornswood-Content.esp');
const TOOL = path.join(ROOT, 'scripts', 'mods', 'Add-ContentRecords.py');

const BLOCK = 0x5DF7B34;        // FURN ThornswoodExecutionerChoppingBlock
const BLOCK_REF = 0x5DFCC75;    // its one placed reference, in Solitude
const COMPRESSED = 0x00040000;

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

// ------------------------------------------------------------ the reader --
function readPlugin(buf) {
  const headerSize = buf.readUInt32LE(4);
  const head = buf.subarray(0, 24 + headerSize);
  const records = [];
  let ends = true;
  function walk(start, end) {
    let p = start;
    while (p + 24 <= end) {
      const tag = buf.toString('latin1', p, p + 4);
      const size = buf.readUInt32LE(p + 4);
      if (tag === 'GRUP') { walk(p + 24, p + size); p += size; continue; }
      const flags = buf.readUInt32LE(p + 8);
      const fid = buf.readUInt32LE(p + 12);
      const raw = buf.subarray(p + 24, p + 24 + size);
      records.push({ tag, flags, fid, raw, bytes: buf.subarray(p, p + 24 + size) });
      p += 24 + size;
    }
    if (p !== end) { ends = false; }
  }
  walk(24 + headerSize, buf.length);
  return { head, records, ends };
}

function subs(rec) {
  let d = rec.raw;
  if (rec.flags & COMPRESSED) { d = zlib.inflateSync(d.subarray(4)); }
  const out = [];
  let i = 0;
  while (i + 6 <= d.length) {
    const tag = d.toString('latin1', i, i + 4);
    const size = d.readUInt16LE(i + 4);
    if (i + 6 + size > d.length) { break; }
    out.push({ tag, body: d.subarray(i + 6, i + 6 + size) });
    i += 6 + size;
  }
  return out;
}

const OTHER = /^(kzl|kzolivar)/i;
function edid(rec) {
  const e = subs(rec).find(s => s.tag === 'EDID');
  return e ? e.body.toString('latin1').replace(/\0+$/, '') : '';
}
function otherServer(rec) {
  const found = [];
  for (const s of subs(rec)) {
    const text = s.body.toString('latin1');
    if (s.tag === 'EDID' && OTHER.test(text)) { found.push('editor id ' + text.replace(/\0+$/, '')); }
    if (s.tag === 'VMAD' && /kzl|kzolivar/i.test(text)) { found.push('script ' + text.replace(/[^ -~]+/g, ' ').trim()); }
  }
  return found;
}
function hedrCount(head) {
  const at = head.indexOf('HEDR', 0, 'latin1');
  return at < 0 ? null : head.readInt32LE(at + 6 + 4);
}

// ------------------------------------------------------ 1. the committed --
const shipped = fs.readFileSync(ESP);
const before = readPlugin(shipped);
yes('the committed plugin reads to its last byte (' + before.records.length + ' records)',
    before.ends && before.records.length > 300);
const badIds = before.records.filter(r => OTHER.test(edid(r)));
yes('no editor id in the committed plugin begins Kzl or kzolivar (' + before.records.length + ' read, compressed included)',
    badIds.length === 0);
for (const r of badIds) { console.log('      ' + r.tag + ' 0x' + r.fid.toString(16) + ' ' + edid(r)); }
const block = before.records.find(r => r.fid === BLOCK);
yes('the Execution Block is FURN 0x05DF7B34', block && block.tag === 'FURN' &&
    edid(block) === 'ThornswoodExecutionerChoppingBlock');
const ref = before.records.find(r => r.fid === BLOCK_REF);
yes('it is placed once, REFR 0x05DFCC75 names it', ref && ref.tag === 'REFR' &&
    subs(ref).some(s => s.tag === 'NAME' && s.body.readUInt32LE(0) === BLOCK));
const stillScripted = block && subs(block).some(s => s.tag === 'VMAD');
if (stillScripted) {
  console.log('NOTE  the committed plugin still attaches ' + otherServer(block).join(', ') +
              '. It is rebuilt by the tool and committed with the collection upload, not before,');
  console.log('      because the deploy scripts send this file to the servers and the launcher');
  console.log('      refuses Play until everybody has the same one.');
}

// ------------------------------------------------------- 2. the tool run --
function python(args) {
  for (const exe of ['python', 'py']) {
    const r = spawnSync(exe, args, { encoding: 'utf8' });
    if (!r.error) { return r; }
  }
  return null;
}
const tmpRoot = process.env.TEST_TMP || os.tmpdir();
fs.mkdirSync(tmpRoot, { recursive: true });
const dir = fs.mkdtempSync(path.join(tmpRoot, 'ts-content-names-'));
const copy = path.join(dir, 'Thornswood-Content.esp');
fs.writeFileSync(copy, shipped);
try {
  const check = python([TOOL, '--data', dir, '--check']);
  yes('python is on this machine', check !== null);
  if (check) {
    yes('--check exits 0', check.status === 0);
    if (check.status !== 0) { console.log(check.stdout + check.stderr); }
    yes('--check writes nothing', fs.readFileSync(copy).equals(shipped));
    if (stillScripted) {
      yes('--check says the block loses its script', /0x5DF7B34 ThornswoodExecutionerChoppingBlock loses the script/.test(check.stdout));
    }

    const run = python([TOOL, '--data', dir]);
    yes('the tool exits 0', run.status === 0);
    if (run.status !== 0) { console.log(run.stdout + run.stderr); }
    const outBuf = fs.readFileSync(copy);
    const after = readPlugin(outBuf);
    yes('the result reads to its last byte', after.ends);

    const left = [];
    for (const r of after.records) { for (const w of otherServer(r)) { left.push(r.tag + ' 0x' + r.fid.toString(16) + ' ' + w); } }
    yes('the other server\'s name is on no editor id and no script in the result', left.length === 0);
    for (const l of left) { console.log('      ' + l); }
    let inflatedText = '';
    for (const r of after.records) {
      inflatedText += (r.flags & COMPRESSED) ? zlib.inflateSync(r.raw.subarray(4)).toString('latin1') : r.raw.toString('latin1');
    }
    yes('and "Kzl" is nowhere in any record\'s bytes', inflatedText.indexOf('Kzl') < 0);

    const same = after.records.length === before.records.length &&
      before.records.every((r, i) => after.records[i].fid === r.fid && after.records[i].tag === r.tag &&
                                     after.records[i].flags === r.flags);
    yes('the same ' + before.records.length + ' records, same form ids, types and flags, same order', same);

    const nb = after.records.find(r => r.fid === BLOCK);
    const want = subs(block).filter(s => s.tag !== 'VMAD');
    const got = nb ? subs(nb) : [];
    yes('the block has no script attached', nb && !got.some(s => s.tag === 'VMAD'));
    yes('and every other subrecord of it is as it was (' + want.length + ')',
        got.length === want.length && want.every((s, i) => got[i].tag === s.tag && got[i].body.equals(s.body)));
    yes('it is still called Execution Block', got.some(s => s.tag === 'FULL' && s.body.toString('latin1') === 'Execution Block\0'));

    let untouched = 0;
    for (let i = 0; i < before.records.length && same; i++) {
      const r = before.records[i];
      if (r.fid === BLOCK) { continue; }
      if (after.records[i].bytes.equals(r.bytes)) { untouched++; }
    }
    const others = before.records.length - 1;
    yes('every other record is byte for byte what it was (' + untouched + ' of ' + others + ')', untouched === others);
    yes('the placed block in Solitude is still there', after.records.some(r => r.fid === BLOCK_REF && r.tag === 'REFR'));
    yes('the header\'s record count is what is in the file (' + hedrCount(after.head) + ')',
        hedrCount(after.head) === after.records.length);
    const mast = h => h.toString('latin1').split('MAST').slice(1).map(s => s.slice(2).split('\0')[0]);
    yes('the masters are the same (' + mast(before.head).join(', ') + ')',
        mast(before.head).length > 0 && JSON.stringify(mast(after.head)) === JSON.stringify(mast(before.head)));

    // ------------------------------------------------------ 3. again -----
    const again = python([TOOL, '--data', dir]);
    yes('a second run exits 0', again.status === 0);
    yes('and changes nothing', fs.readFileSync(copy).equals(outBuf));
  }
} finally {
  fs.rmSync(dir, { recursive: true, force: true });
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
