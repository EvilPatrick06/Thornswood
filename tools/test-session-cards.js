/*
  test-session-cards.js

  The /sessions page groups by person, not by session.

  Asked for by Patrick on 22 September: one card a person, closed showing the
  Discord name, the id, total playtime and when they last played, and open
  showing every session they have had. The note column came off at the same
  time.

  The arithmetic on that closed card is the part worth a test, because it is
  the part that can be quietly wrong and still look right:

    - total playtime counts only the sessions that reported an END. A row with
      no end carries no minutes, so counting it would make the hours disagree
      with the session count on the same card. The same rule the week's totals
      already use, for the same reason.
    - the NEWEST name wins. Somebody who changed their Discord name should show
      the name they have now, not the one they had on their first session.
    - a row with no Discord id makes no card at all, rather than a card with an
      empty heading.

  This lifts the real functions out of the shipped page by text, so a rename
  fails loudly rather than testing a copy of the logic.

  Read only. It opens one file and runs no server.
*/
const fs = require('fs');
const path = require('path');

const PAGE = path.join(__dirname, 'docs-app', 'public', 'index.html');
const src = fs.readFileSync(PAGE, 'utf8');

function grab(name) {
  const at = src.indexOf('function ' + name);
  if (at < 0) throw new Error('docs-app/public/index.html has no function ' + name);
  const b = src.indexOf('{', at);
  let d = 0;
  for (let i = b; i < src.length; i++) {
    if (src[i] === '{') d++;
    else if (src[i] === '}') { d--; if (d === 0) return src.slice(at, i + 1); }
  }
  throw new Error('unbalanced braces reading ' + name);
}

eval([grab('forMins'), grab('sessionAt'), grab('sessionOpen'), grab('sessionPeople')].join('\n'));

let pass = 0, fail = 0;
const yes = (what, c) => {
  if (c) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
};

/* Newest first, which is the order drawSessions sorts into before it calls
   sessionPeople. The grouping relies on that for the name rule. */
const rows = [
  { who:'111', name:'Djinn',   start:5000, end:5000 + 60 * 60000, minutes:60, profile:7, version:'1.1.77', channel:'dev'  },
  { who:'222', name:'Patrick', start:4000, end:4000 + 30 * 60000, minutes:30, profile:9, version:'1.1.77', channel:'main' },
  { who:'111', name:'',        start:3000, end:0,                 minutes:0,  profile:7, version:'1.1.76', channel:'main' },
  { who:'111', name:'OldName', start:2000, end:2000 + 90 * 60000, minutes:90, profile:7, version:'1.1.75', channel:'main' },
  { who:'333', name:'Tester',  start:0,    end:1000,              minutes:15, profile:0, version:'',       channel:'main' }
].sort((a, b) => sessionAt(b) - sessionAt(a));

const people = sessionPeople(rows);

yes('one entry per person, not per session', people.length === 3);
yes('ordered by who played most recently', people[0].who === '111' && people[1].who === '222');

const d = people.find(p => p.who === '111');
yes('every one of that person\'s sessions is kept', d.rows.length === 3);
yes('total playtime adds only the ended sessions, 60 + 90', d.mins === 150);
yes('the open session is counted separately, not as zero minutes', d.open === 1);
yes('the newest name wins over the older one', d.name === 'Djinn');
yes('last played is the newest session', d.last === 5000);

const t = people.find(p => p.who === '333');
yes('a session with no start still dates the card from its end', t.last === 1000);
yes('a person with one session reads one session', t.rows.length === 1);

yes('a row with no Discord id makes no card',
    sessionPeople([{ who:'', name:'x', start:1, end:2, minutes:1 }]).length === 0);

yes('150 minutes reads as hours on the card', forMins(150) === '2.5 hours');
yes('under a minute says so', forMins(0.5) === 'under a minute');

/* The note column is gone, and the endpoint it used is no longer reachable
   from the page. If either comes back, this says so. */
yes('the page has no note column', src.indexOf('<th>Note</th>') < 0);
yes('the page never calls the note endpoint', src.indexOf('/api/session-note') < 0);

/* ---- what a session row says about where it got to ---------------------- */
/*
  A character is picked at the game's main menu, so a session with no
  character never reached either world. Saying "main" for one of those puts a
  session on the live server that was never on it, which is exactly what
  somebody would later be asked to account for.
*/
eval(grab('sessionTable'));
const esc = s => String(s == null ? '' : s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

const onMain  = sessionTable([{ who:'1', profile:7, version:'1.1.78', channel:'main', start:1, end:2, minutes:5, session:'aaaaaaaa' }]);
const onDev   = sessionTable([{ who:'1', profile:7, version:'1.1.78', channel:'dev',  start:1, end:2, minutes:5, session:'bbbbbbbb' }]);
const stuckM  = sessionTable([{ who:'1', profile:0, version:'1.1.78', channel:'main', start:1, end:2, minutes:1, session:'cccccccc' }]);
const stuckD  = sessionTable([{ who:'1', profile:0, version:'1.1.78', channel:'dev',  start:1, end:2, minutes:1, session:'dddddddd' }]);
const stuckU  = sessionTable([{ who:'1', profile:0, version:'', channel:'', start:1, end:2, minutes:1, session:'eeeeeeee' }]);

yes('a session with a character on main reads main', onMain.indexOf('>main<') >= 0);
yes('a session with a character on dev reads dev', onDev.indexOf('>dev<') >= 0);

/* The three that never reached a world, told apart as far as the row allows. */
yes('stuck on the main build reads Main Launcher', stuckM.indexOf('>Main Launcher<') >= 0);
yes('stuck on the dev build reads Dev Launcher', stuckD.indexOf('>Dev Launcher<') >= 0);
yes('stuck with no build reported reads plain Launcher', stuckU.indexOf('>Launcher<') >= 0);

yes('a stuck main session does NOT also claim the main world', stuckM.indexOf('>main<') < 0);
yes('a stuck dev session does NOT also claim the dev world', stuckD.indexOf('>dev<') < 0);
yes('a stuck session says which world it would have joined',
    stuckM.indexOf('never reached the main world') >= 0);
yes('and the unknown one says the build was not reported, rather than guessing',
    stuckU.indexOf('the build was not reported') >= 0);

/* ---- the logs button ---------------------------------------------------- */
yes('every session offers More details', onMain.indexOf('More details') >= 0);
yes('the button carries the session and the Discord id',
    onMain.indexOf('data-s="aaaaaaaa"') >= 0 && onMain.indexOf('data-w="1"') >= 0);
yes('the log row spans the whole table', onMain.indexOf('colspan="6"') >= 0);
yes('the page has a download control for a log', src.indexOf('class="dl"') >= 0);
yes('logs are fetched per session, not with the page', src.indexOf('/api/session-logs?session=') >= 0);

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
