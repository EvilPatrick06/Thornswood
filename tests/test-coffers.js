// test-coffers.js
//
// The drop box, rent and the notice boards. One system, because the box is
// where the rent and the fees land.
//
// THE BOX IS MEASURED AND NOT INVENTED. mp.onPutItem(containerRefrId, actorId,
// baseId, count) exists in the fork and PutItemEvent::OnFireSuccess is the
// thing that removes the items, so returning false REFUSES the put and the
// gold stays in the hand. That is what makes a treasury possible without a new
// record, a client change or a release.
//
// Patrick's design, 21 September: twenty gold for a notice which is read only,
// thirty for a job which goes on the taker's list, the fee routes into the drop
// box which is the hold's money, and the same box takes rent. Rent is handed to
// a steward in person or put in the box; the server counts and does not seize,
// even though it owns everybody's pack and could.
//
// Read only.
const REPO_DIR = require('path').join(__dirname, '..'); // the tests are in tests\, the repository is one folder up
const fs = require('fs');
const path = require('path');
const SRC = process.env.GM || path.join(REPO_DIR, 'game', 'gamemode.js');
const CR = String.fromCharCode(13);
const src = fs.readFileSync(SRC, 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

function lift(from, to) {
  const a = src.indexOf(from);
  if (a < 0) { return null; }
  const b = src.indexOf(to, a);
  return b < 0 ? null : src.slice(a, b + to.length);
}

const putBlock = lift('  function putIn(containerRefrId, actorId, baseId, count) {', '\n  }\n');
const postBlock = lift('  function post(parts, actorId, profileId, toProfile, isJob) {', '\n  }\n');

yes('the drop box answer is in the gamemode', putBlock !== null);
yes('and posting to a board is too', postBlock !== null);

const GOLD = 0x0000000F;
const SWORD = 0x12eb7;
const BOX = 0xaaaa;
const ALICE = 101;

/** Drive putIn with a hold that owns BOX. */
function put(opts) {
  const said = [];
  const claims = opts.claims || {};
  const funds = opts.funds || { whiterun: 0 };
  const fn = new Function(
    'containerRefrId', 'actorId', 'baseId', 'count',
    'holdOfBox', 'claims', 'funds', 'rentOwedBy', 'save', 'plog',
    'notify', 'say', 'mp', 'Number', 'GOLD_ID',
    putBlock + '\nreturn putIn;');
  const call = fn(
    null, null, null, null,
    function (id) { return id === BOX ? 'whiterun' : null; },
    claims, funds,
    function (pid) {
      const out = [];
      for (const b in claims) {
        const c = claims[b];
        if (c.by === pid && c.rent && c.rent.owed > 0) { out.push(b); }
      }
      return out;
    },
    function () { }, function () { },
    function (id, m) { said.push(m); },
    function (id, m) { said.push(m); },
    { get: function () { return ALICE; } },
    Number, GOLD);
  const out = call(opts.into === undefined ? BOX : opts.into,
                   0xff000058, opts.baseId, opts.count);
  return { refused: out === false, said: said, claims: claims, funds: funds };
}

if (putBlock !== null) {
  // S1: gold in the hold's box is money to the hold.
  {
    const r = put({ baseId: GOLD, count: 40 });
    yes('S1 gold in the box is accepted', !r.refused);
    yes('S1 and the hold is forty richer', r.funds.whiterun === 40);
    // Twice, because every message in this file goes to both notify and say:
    // the corner of the screen and the chat log. One of them is missed.
    yes('S1 and the person is told, on screen and in chat',
        r.said.length === 2 && r.said[0] === r.said[1] &&
        r.said[0].indexOf('40 gold') !== -1);
  }

  // S2: ONLY COIN. A box that takes a sword is a box somebody loses a sword
  //     in: the server has no way to give it back and no rule saying whose it
  //     became. Refusing costs them nothing, which is what the event is for.
  {
    const r = put({ baseId: SWORD, count: 1 });
    yes('S2 anything that is not coin is refused', r.refused);
    yes('S2 and the reason names losing it',
        r.said[0].indexOf('lost in there') !== -1);
    yes('S2 and the hold gains nothing', r.funds.whiterun === 0);
  }

  // S3: EVERY OTHER CHEST IN SKYRIM IS UNTOUCHED. This is the check that keeps
  //     one feature from changing the whole world.
  {
    const r = put({ baseId: SWORD, count: 1, into: 0xbbbb });
    yes('S3 a container that is not a box says nothing at all',
        !r.refused && r.said.length === 0);
  }

  // S4: gold pays down what the payer owes first, because that is what putting
  //     coin in the city's box almost always means.
  {
    const claims = {
      breezehome: { by: ALICE, name: 'Alice', at: 1,
                    rent: { amount: 50, everyDays: 7, owed: 50, since: 1 } }
    };
    const r = put({ baseId: GOLD, count: 30, claims: claims });
    yes('S4 rent is paid down first', claims.breezehome.rent.owed === 20);
    yes('S4 and the person is told how much went to it',
        r.said[0].indexOf('30 of it goes against your rent') !== -1);
  }

  // S5: and paying it off clears it rather than going negative.
  {
    const claims = {
      breezehome: { by: ALICE, name: 'Alice', at: 1,
                    rent: { amount: 50, everyDays: 7, owed: 20, since: 1 } }
    };
    put({ baseId: GOLD, count: 100, claims: claims });
    yes('S5 overpaying clears the debt and does not go below nothing',
        claims.breezehome.rent.owed === 0);
  }
}

if (postBlock !== null) {
  /** Drive post with a pack and a hold that has a box. */
  function posting(opts) {
    const told = [];
    const notices = opts.notices || {};
    const funds = { whiterun: 0 };
    const boxes = opts.noBox ? {} : { whiterun: BOX };
    const took = { n: 0 };
    const fn = new Function(
      'parts', 'actorId', 'profileId', 'toProfile', 'isJob',
      'boxes', 'notices', 'funds', 'takeGold', 'save', 'plog', 'mp',
      'NOTICE_FEE', 'JOB_FEE', 'Number', 'boardHere',
      postBlock + '\nreturn post;');
    const call = fn(
      null, null, null, null, null,
      boxes, notices, funds,
      function (id, amount) {
        if (opts.broke) { return false; }
        took.n += amount;
        return true;
      },
      function () { }, function () { },
      { get: function () { return { name: 'Alice' }; } },
      20, 30, Number,
      // Standing at Whiterun's board unless the test says otherwise. The
      // board is what makes /notice a board rather than a command.
      function () { return opts.noBoard ? null : 'whiterun'; });
    call(opts.parts, 0xff000058, ALICE,
         function (pid, m) { told.push(m); }, !!opts.isJob);
    return { told: told, notices: notices, funds: funds, took: took.n };
  }

  // S6: a notice costs twenty and lands on the board.
  {
    const r = posting({ parts: ['/notice', 'Room', 'to', 'let'] });
    yes('S6 a notice costs twenty gold', r.took === 20);
    yes('S6 and it is on the board', r.notices.whiterun.length === 1);
    yes('S6 with the words that were said',
        r.notices.whiterun[0].text === 'Room to let');
    yes('S6 and the fee goes to the hold', r.funds.whiterun === 20);
  }

  // S7: a job costs thirty and is marked as one, because a job goes on the
  //     taker's list and a notice is read only.
  {
    const r = posting({ parts: ['/job', 'Clear', 'the', 'cellar'], isJob: true });
    yes('S7 a job costs thirty gold', r.took === 30);
    yes('S7 and is marked as a job', r.notices.whiterun[0].job === true);
  }

  // S8: no gold, no notice. Nothing is posted on credit.
  {
    const r = posting({ parts: ['/notice', 'Room'], broke: true });
    yes('S8 somebody who cannot pay posts nothing',
        !r.notices.whiterun || r.notices.whiterun.length === 0);
    yes('S8 and is told the price', r.told[0].indexOf('20 gold') !== -1);
  }

  // S9: AWAY FROM A BOARD NOTHING IS POSTED AND NOTHING IS CHARGED. This is
  //     what makes it a board rather than a command you can say anywhere.
  {
    const r = posting({ parts: ['/notice', 'Room'], noBoard: true });
    yes('S9 away from a board the fee is not taken', r.took === 0);
    yes('S9 and it says to stand at one',
        r.told[0].indexOf('notice board') !== -1);
  }

  // S10: an empty notice is not a twenty gold blank.
  {
    const r = posting({ parts: ['/notice'] });
    yes('S10 an empty notice costs nothing', r.took === 0);
  }
}

// ------------------------------------------------------ the taker's list
//
// Patrick: thirty gold for a job, "which goes on the taker's list". A job is
// the one thing on a board with a second half. The server records who took
// what and takes it off the open board so two people do not both go and do it.
// It does NOT pay anybody and there is no /done: the poster paid to put it up,
// and whether it was done is between the two of them, the same way rent is
// handed to a steward in person. A server that judged whether a job was
// finished would be refereeing roleplay.
{
  const takeBlock = lift('  function take(parts, actorId, profileId, toProfile) {', '\n  }\n');
  yes('the taker\'s list is in the gamemode', takeBlock !== null);

  function taking(opts) {
    const told = [];
    const notices = { whiterun: opts.list };
    const fn = new Function(
      'parts', 'actorId', 'profileId', 'toProfile',
      'boardHere', 'notices', 'save', 'plog', 'mp', 'Number',
      takeBlock + '\nreturn take;');
    const call = fn(
      null, null, null, null,
      function () { return opts.noBoard ? null : 'whiterun'; },
      notices, function () { }, function () { },
      { get: function () { return { name: opts.who || 'Bob' }; } },
      Number);
    call(opts.parts, 0xff000058, opts.by,
         function (pid, m) { told.push(m); });
    return { told: told, list: notices.whiterun };
  }

  if (takeBlock !== null) {
    const job = () => ({ by: ALICE, name: 'Alice', text: 'Clear the cellar',
                         at: 1, job: true, taken: 0 });
    const notice = () => ({ by: ALICE, name: 'Alice', text: 'Room to let',
                            at: 1, job: false, taken: 0 });

    // S11: taking a job puts your name on it.
    {
      const r = taking({ by: 202, parts: ['/take', '1'], list: [job()] });
      yes('S11 a job can be taken', r.list[0].taken === 202);
      yes('S11 and the taker is named on it', r.list[0].takenName === 'Bob');
      yes('S11 and is sent to the person who posted it',
          r.told[0].indexOf('Alice') !== -1);
    }

    // S12: and only one person gets it.
    {
      const held = job(); held.taken = 303; held.takenName = 'Cyrus';
      const r = taking({ by: 202, parts: ['/take', '1'], list: [held] });
      yes('S12 a job somebody already has cannot be taken again',
          r.list[0].taken === 303);
      yes('S12 and says who has it', r.told[0].indexOf('Cyrus') !== -1);
    }

    // S13: a notice is not a job.
    {
      const r = taking({ by: 202, parts: ['/take', '1'], list: [notice()] });
      yes('S13 a notice cannot be taken', r.list[0].taken === 0);
      yes('S13 and says so', r.told[0].indexOf('not a job') !== -1);
    }

    // S14: and you cannot take your own.
    {
      const r = taking({ by: ALICE, parts: ['/take', '1'], list: [job()] });
      yes('S14 your own job is not takeable', r.list[0].taken === 0);
    }

    // S15: away from the board, nothing.
    {
      const r = taking({ by: 202, parts: ['/take', '1'], list: [job()],
                         noBoard: true });
      yes('S15 a job cannot be taken from across Skyrim', r.list[0].taken === 0);
    }
  }
}

// ---------------------------------------------------------------- structure
{
  const code = src
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/\/\/[^\n]*/g, ' ');
  yes('the put hook is registered with the engine',
      /mp\.onPutItem = guard\('onPutItem'/.test(code));
  yes('and it hands straight to the property block',
      /return prop\.putIn\(containerRefrId, actorId, baseId, count\)/.test(code));
  yes('all five words are in the one list',
      /'\/box', '\/rent',/.test(code) && /'\/notice', '\/job', '\/board',/.test(code));
  yes('and the dispatcher routes them',
      /word === '\/box' \|\|/.test(code) && /word === '\/board'\)/.test(code));
  yes('the container somebody opened is only remembered for containers',
      /prop\.touchedBox && kindIsContainer\(baseDesc\)/.test(code));
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
