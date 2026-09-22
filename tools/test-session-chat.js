/*
  test-session-chat.js

      node .\tools\test-session-chat.js

  What people said used to be a page of its own: the whole chat log, a day at a
  time, for everybody at once. Patrick on 22 September: put it under each
  person on /sessions, split per session. chatSlice in docs-app\server.js does
  the splitting and /api/session-logs hands the lines back with the rest of
  that session.

  THE SPLIT IS THE WHOLE THING AND IT IS THE PART THAT CAN BE SILENTLY WRONG.
  A slice that is too wide puts somebody else's words, or last night's words,
  under this session and into a report about behaviour. A slice that is too
  narrow drops what was actually said. Neither looks like a fault on the page:
  both render as a tidy list. So these check the boundaries, one at a time.

  It reads the real function out of docs-app\server.js rather than a copy.
*/
const fs = require('fs');
const path = require('path');
const os = require('os');

const SRC = path.join(__dirname, 'docs-app', 'server.js');
const src = fs.readFileSync(SRC, 'utf8');

function grab(name) {
  const at = src.indexOf('function ' + name);
  if (at < 0) throw new Error('docs-app/server.js has no function ' + name);
  const b = src.indexOf('{', at);
  let d = 0;
  for (let i = b; i < src.length; i++) {
    if (src[i] === '{') d++;
    else if (src[i] === '}') { d--; if (d === 0) return src.slice(at, i + 1); }
  }
  throw new Error('unbalanced braces reading ' + name);
}

const CHAT_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'thornswood-slice-'));
eval(grab('chatSlice'));

/* The voice service's own day naming, local time, so a line written at
   23:59 and one written at 00:01 land in different files. */
function dayOf(at) {
  const d = new Date(at);
  const p = (n) => (n < 10 ? '0' : '') + n;
  return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate());
}
function write(at, profileId, text, extra) {
  const line = Object.assign({ at: at, kind: 'say', peer: 1, profileId: profileId,
                               name: 'p' + profileId, proven: true, mode: 'local', text: text }, extra || {});
  fs.appendFileSync(path.join(CHAT_DIR, dayOf(at) + '.jsonl'), JSON.stringify(line) + '\n');
}

let pass = 0, fail = 0;
const yes = (w, c) => {
  if (c) { pass++; console.log('PASS  ' + w); }
  else { fail++; console.log('FAIL  ' + w); }
};

// A session at a fixed local time, well away from midnight.
const T = new Date(2026, 8, 22, 14, 0, 0).getTime();
const START = T, END = T + 30 * 60000;

write(START - 5000,  7, 'before the session');
write(START + 1000,  7, 'first thing');
write(START + 60000, 7, '/tp somewhere', { kind: 'command' });
write(START + 90000, 8, 'somebody else entirely');
write(START + 120000, 7, 'unproven line', { proven: false });
write(END - 1000,    7, 'last thing');
write(END + 5000,    7, 'after the session');

const got = chatSlice(7, START, END);

yes('only this profile and this window come back', got.lines.length === 4);
yes('nothing from before the session', !got.lines.some((l) => l.text === 'before the session'));
yes('nothing from after the session', !got.lines.some((l) => l.text === 'after the session'));
yes('nobody else in the room', !got.lines.some((l) => l.text === 'somebody else entirely'));
yes('slash commands are kept', got.lines.some((l) => l.kind === 'command'));
yes('and marked as commands', got.lines.filter((l) => l.kind === 'command').length === 1);
yes('an unproven line is kept', got.lines.some((l) => l.text === 'unproven line'));
yes('and marked unproven', got.lines.filter((l) => l.proven === false).length === 1);
yes('oldest first, the way it was said', got.lines[0].text === 'first thing' &&
    got.lines[got.lines.length - 1].text === 'last thing');
yes('the reason is empty when a log was actually read', got.why === '');

// ---- the edges of the window, one at a time --------------------------------
yes('a line exactly on the start is in', chatSlice(7, START + 1000, END).lines.some((l) => l.text === 'first thing'));
yes('a line exactly on the end is in', chatSlice(7, START, END - 1000).lines.some((l) => l.text === 'last thing'));
yes('a millisecond before the start is out', !chatSlice(7, START + 1001, END).lines.some((l) => l.text === 'first thing'));
yes('a millisecond after the end is out', !chatSlice(7, START, END - 1001).lines.some((l) => l.text === 'last thing'));

// ---- a session that runs over midnight -------------------------------------
const LATE = new Date(2026, 8, 23, 23, 50, 0).getTime();
write(LATE + 60000, 9, 'said before midnight');
write(LATE + 25 * 60000, 9, 'said after midnight');
const over = chatSlice(9, LATE, LATE + 40 * 60000);
yes('a session over midnight reads both days', over.lines.length === 2);
yes('and puts them in order across the boundary',
    over.lines[0].text === 'said before midnight' && over.lines[1].text === 'said after midnight');

// ---- nothing to read -------------------------------------------------------
yes('a profile that said nothing comes back empty', chatSlice(404, START, END).lines.length === 0);
yes('and says nothing was wrong', chatSlice(404, START, END).why === '');

const far = new Date(2019, 0, 1, 12, 0, 0).getTime();
const none = chatSlice(7, far, far + 60000);
yes('a day with no file at all says so', none.lines.length === 0 && none.why.indexOf('no chat log') >= 0);

/* A session with no profile number never reached a world, so there is nobody
   to match on. Asking for profile 0 would otherwise match every line whose
   profileId is missing. */
const zero = chatSlice(0, START, END);
yes('a session with no profile matches nothing', zero.lines.length === 0);

// ---- a truncated last line ------------------------------------------------
// An append-only log killed mid-write has one by design, and one bad line
// must not cost the rest.
fs.appendFileSync(path.join(CHAT_DIR, dayOf(START) + '.jsonl'), '{"at":' + (START + 2000) + ',"prof');
const after = chatSlice(7, START, END);
yes('a half written last line is skipped, not thrown', after.lines.length === 4);

try { fs.rmSync(CHAT_DIR, { recursive: true, force: true }); } catch (e) { }
console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
