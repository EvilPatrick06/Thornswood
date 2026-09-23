// test-social.js
//
// Friends, parties, mutes, journals and trading.
//
// Patrick, 22 September, in one message: "Friend/Party System & Journals - P
// for the Party menu... J for Journal... Add it so that when you look at
// someone, you are prompted to press buttons: one for friend, one for trade,
// and one for mute. Currently the looking at people doesnt have the trade menu
// and when it did you had to use youyr cursor and a bunch of other bs I just
// want to press a key while looking at them."
//
// THE TRADE MENU HE REMEMBERS WAS TradeTogether, a Skyrim Together mod that is
// not in this build: the launcher still carries six key bindings for it and
// writes them into a file that does not exist. So all of this is new, and the
// first thing checked here is the loop everything else rides on - the server
// publishing who is near you, the client matching the crosshair against it.
//
// It drives the REAL social and trade blocks out of gamemode.js over a fake mp
// and a fake clock, the way test-needs.js does.
//
// Read only.
const fs = require('fs');
const path = require('path');
const SRC = process.env.GM || path.join(__dirname, 'gamemode.js');
const CR = String.fromCharCode(13);
const src = fs.readFileSync(SRC, 'utf8').split(CR).join('');
const FRONT = fs.readFileSync(path.join(__dirname, 'ts-plugins', 'thornswood-front.js'), 'utf8');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

function lift(a, b) {
  const i = src.indexOf(a);
  const j = i < 0 ? -1 : src.indexOf(b, i);
  return (i >= 0 && j >= 0) ? src.slice(i, j) : null;
}
const social = lift('// ==== thornswood social:', '// ==== end thornswood social ====');
const trade = lift('// ==== thornswood trade ====', '// ==== end thornswood trade ====');
yes('the social block is in the gamemode', social !== null);
yes('the trade block is in the gamemode', trade !== null);

/*
  One world, two blocks.

  They are run over the SAME fake mp, because they talk to each other: a trade
  asks the social block for names, and accepting a trade offer is a social
  verb that calls into the trade block. Running them apart would test two
  things that never meet.
*/
function world() {
  const store = {};      // actorId -> { prop -> value }
  const clock = { now: 1700000000000 };
  const said = [];
  const timers = [];
  const kinds = {};
  const g = {};

  const mp = {
    makeProperty: function () { },
    get: function (id, key) {
      if (id === 0 && key === 'onlinePlayers') {
        return Object.keys(store).filter(k => store[k].here).map(Number);
      }
      const row = store[id];
      if (!row) { return undefined; }
      if (key === 'inventory') { return { entries: (row.inventory || []).slice() }; }
      return row[key];
    },
    set: function (id, key, v) {
      if (!store[id]) { store[id] = {}; }
      if (key === 'inventory') { store[id].inventory = (v && v.entries) || []; return; }
      store[id][key] = v;
    },
    lookupEspmRecordById: function (baseId) {
      const n = kinds[baseId];
      return n ? { record: { type: 'MISC', editorId: n, fields: [{ type: 'FULL', data: n }] } } : null;
    }
  };

  function run(block) {
    return new Function(
      'globalThis', 'mp', 'Date', 'console', 'setInterval', 'clearInterval',
      'guard', 'say', 'notify', 'Math', 'Number', 'String', 'Object', 'Array',
      'JSON', 'isFinite', 'parseInt',
      block)(
      g, mp, { now: function () { return clock.now; } },
      { log: function () { } },
      function (f) { timers.push(f); return timers.length; },
      function () { },
      function (n, f) { return f; },
      function (id, line) { said.push({ to: id, line: line }); },
      function (id, line) { said.push({ to: id, line: line }); },
      Math, Number, String, Object, Array, JSON, isFinite, parseInt);
  }

  run(social);
  run(trade);

  const api = {
    g: g,
    soc: g.__thornswoodSocial,
    trade: g.__thornswoodTrade,
    mp: mp,
    said: said,
    store: store,
    clock: clock,
    tick: function () { timers.forEach(f => f()); },
    /** Put somebody in the world. */
    person: function (id, name, profileId, cell, pos) {
      store[id] = {
        here: true, profileId: profileId, appearance: { name: name },
        worldOrCellDesc: cell || 'cell:X.esm', pos: pos || [0, 0, 0], inventory: []
      };
      return id;
    },
    moveTo: function (id, pos, cell) {
      store[id].pos = pos;
      if (cell) { store[id].worldOrCellDesc = cell; }
    },
    gone: function (id) { store[id].here = false; },
    give: function (id, baseId, count, label) {
      kinds[baseId] = label || ('thing' + baseId);
      store[id].inventory = (store[id].inventory || []).concat([{ baseId: baseId, count: count }]);
    },
    count: function (id, baseId) {
      let n = 0;
      (store[id].inventory || []).forEach(e => { if (e.baseId === baseId) { n += e.count || 1; } });
      return n;
    },
    near: function (id) {
      const v = store[id] && store[id].thornswoodNear;
      return (v && v.w) || {};
    },
    lines: function (id) {
      return said.filter(s => s.to === id).map(s => s.line);
    }
  };
  return api;
}

if (social && trade) {
  const GOLD = 0x0000000F;

  // --------------------------------------------- who is near, which is the loop
  {
    const w = world();
    const A = w.person(0xff000001, 'Bjorn', 101, 'town:X.esm', [0, 0, 0]);
    const B = w.person(0xff000002, 'Sera', 102, 'town:X.esm', [200, 0, 0]);
    const C = w.person(0xff000003, 'Far', 103, 'town:X.esm', [90000, 0, 0]);
    const D = w.person(0xff000004, 'Inside', 104, 'inn:X.esm', [0, 0, 0]);
    w.soc.nearTick();

    const mine = w.near(A);
    yes('somebody standing next to you is near', !!mine[B.toString(16)]);
    yes('and is named, so the prompt can say who it is', mine[B.toString(16)].n === 'Sera');
    yes('somebody across the hold is not', !mine[C.toString(16)]);
    yes('somebody through a door is not, whatever the coordinates say',
        !mine[D.toString(16)]);
    yes('and you are not near yourself', !mine[A.toString(16)]);

    /*
      THE OTHER HALF OF THE LOOP, in the plugin. The server can publish a
      perfect list and it is worth nothing unless the client asks the game
      what is under the crosshair, which nothing in this repo did before
      today.
    */
    yes('the client asks the game what is under the crosshair',
        /getCurrentCrosshairRef/.test(FRONT));
    yes('and matches it against what the server published',
        /globalThis\.thornswoodNear/.test(FRONT));
    yes('the three verbs are sent as ordinary commands',
        /lookVerb\('friend'\)/.test(FRONT) && /lookVerb\('trade'\)/.test(FRONT) &&
        /lookVerb\('mute'\)/.test(FRONT));
    yes('P and J open their panels', /thornswoodParty&&window\.thornswoodParty\.toggle/.test(FRONT) &&
        /thornswoodJournal&&window\.thornswoodJournal\.toggle/.test(FRONT));
    yes('and the three panels are actually loaded',
        /thornswood-party\.js/.test(FRONT) && /thornswood-journal\.js/.test(FRONT) &&
        /thornswood-trade\.js/.test(FRONT));
  }

  // --------------------------------------------------------------- friends
  {
    const w = world();
    const A = w.person(0xff000001, 'Bjorn', 101, 'town:X.esm', [0, 0, 0]);
    const B = w.person(0xff000002, 'Sera', 102, 'town:X.esm', [100, 0, 0]);

    yes('nobody starts with friends', w.soc.view(A).friends.length === 0);
    w.soc.offer('friend', A, B);
    yes('an offer stands for the person it was made to', !!w.soc.standingOffer(102));
    yes('and not for anybody else', !w.soc.standingOffer(101));

    // The accept path, the way the command does it.
    w.soc.addFriend(B, A);
    w.soc.addFriend(A, B);
    yes('saying yes makes it mutual, not a follower list',
        w.soc.isFriend(A, 102) && w.soc.isFriend(B, 101));

    w.soc.dropFriend(A, 102);
    yes('and removing is one sided, so you can drop somebody quietly',
        !w.soc.isFriend(A, 102) && w.soc.isFriend(B, 101));

    // An offer nobody answered goes away on its own.
    w.soc.offer('friend', A, B);
    w.clock.now += w.soc.SOCIAL.offerFor + 1000;
    yes('an offer nobody answers lapses', !w.soc.standingOffer(102));
  }

  // ----------------------------------------------------------------- mutes
  {
    const w = world();
    const A = w.person(0xff000001, 'Bjorn', 101, 'town:X.esm', [0, 0, 0]);
    const B = w.person(0xff000002, 'Sera', 102, 'town:X.esm', [100, 0, 0]);
    yes('muting says it turned on', w.soc.toggleMute(A, 102, 'Sera') === true);
    yes('and it is kept on the character', !!w.soc.stateOf(A).muted[102]);
    yes('and it is only yours', !w.soc.stateOf(B).muted[101]);
    yes('pressing again turns it off', w.soc.toggleMute(A, 102, 'Sera') === false);

    // The page is where the silence actually happens.
    const voice = fs.readFileSync(path.join(__dirname, 'ts-ui', 'thornswood-voice.js'), 'utf8');
    yes('the voice page takes a mute list', /setMuted: function/.test(voice));
    yes('and applies it to the gain node it already had',
        /muted\[rec\.profileId\] \? 0 : 1/.test(voice));
  }

  // --------------------------------------------------------------- parties
  {
    const w = world();
    const A = w.person(0xff000001, 'Bjorn', 101, 'town:X.esm', [0, 0, 0]);
    const B = w.person(0xff000002, 'Sera', 102, 'town:X.esm', [100, 0, 0]);
    const C = w.person(0xff000003, 'Thora', 103, 'town:X.esm', [200, 0, 0]);

    yes('nobody starts in a party', !w.soc.partyOf(101));
    yes('inviting makes one', w.soc.joinParty(101, 102) === '');
    const p = w.soc.partyOf(101);
    yes('with both of them in it', p && p.members.length === 2);
    yes('and the person who asked leads it', p.leader === 101);
    yes('the other one is in the same party', w.soc.partyOf(102) === p);

    w.soc.joinParty(101, 103);
    yes('a third joins the same one', w.soc.partyOf(103).members.length === 3);

    /*
      THE BONUS IS ON BEING TOGETHER. Patrick and Blade both asked for an
      experience bonus for playing together, and a bonus for being LISTED
      together is a checkbox everybody ticks once.
    */
    yes('standing with your party pays', w.soc.workBonus(A) > 1);
    w.moveTo(B, [100, 0, 0], 'far:X.esm');
    w.moveTo(C, [200, 0, 0], 'far:X.esm');
    yes('and being in the same list from two holds away does not',
        w.soc.workBonus(A) === 1);
    w.moveTo(B, [100, 0, 0], 'town:X.esm');
    yes('one of them coming back is enough', w.soc.workBonus(A) > 1);

    w.soc.leaveParty(102);
    w.soc.leaveParty(103);
    yes('a party of one is not a party', !w.soc.partyOf(101));

    // Logging out leaves it, which the tick does.
    const w2 = world();
    w2.person(0xff000001, 'Bjorn', 101, 'town:X.esm', [0, 0, 0]);
    w2.person(0xff000002, 'Sera', 102, 'town:X.esm', [100, 0, 0]);
    w2.soc.joinParty(101, 102);
    w2.gone(0xff000002);
    w2.soc.tick();
    yes('somebody who logs out leaves the party', !w2.soc.partyOf(102));
  }

  // -------------------------------------------------------------- journals
  {
    const w = world();
    const A = w.person(0xff000001, 'Bjorn', 101, 'town:X.esm', [0, 0, 0]);
    const B = w.person(0xff000002, 'Sera', 102, 'town:X.esm', [100, 0, 0]);

    const made = w.soc.newJournal(A, 'The Road North');
    yes('a journal can be started', !!made.journal && made.journal.title === 'The Road North');
    const jid = made.journal.id;
    const second = w.soc.newJournal(A, 'Recipes');
    yes('and more than one, which is what was asked for',
        !!second.journal && w.soc.stateOf(A).journals.length === 2);

    yes('a page can be written', w.soc.writePage(A, jid, '', 'Day one', 'It rained.') === '');
    const book = w.soc.findJournal(w.soc.stateOf(A), jid);
    yes('and it is in the journal', book.pages.length === 1 && book.pages[0].text === 'It rained.');
    const pid = book.pages[0].id;
    w.soc.writePage(A, jid, pid, 'Day one', 'It rained all week.');
    yes('writing the same page again edits it rather than adding one',
        w.soc.findJournal(w.soc.stateOf(A), jid).pages.length === 1);

    // Sharing is with a friend and nobody else.
    yes('you cannot share with somebody who is not a friend',
        w.soc.share(A, jid, '', 102) === 'You can only share with a friend.');
    w.soc.addFriend(A, B);
    yes('and you can with one', w.soc.share(A, jid, '', 102) === '');
    const mineB = w.soc.sharedWithMe(B);
    yes('it turns up on their side', mineB.length === 1 && mineB[0].from === 'Bjorn');
    yes('with the page in it', mineB[0].pages.length === 1);
    yes('and it is not a copy: they read what it says now',
        mineB[0].pages[0].text === 'It rained all week.');

    // One page rather than the whole book.
    const w2 = world();
    const X = w2.person(0xff000001, 'Bjorn', 101, 'town:X.esm', [0, 0, 0]);
    const Y = w2.person(0xff000002, 'Sera', 102, 'town:X.esm', [100, 0, 0]);
    const j2 = w2.soc.newJournal(X, 'Two pages').journal;
    w2.soc.writePage(X, j2.id, '', 'Open', 'anybody may read this');
    w2.soc.writePage(X, j2.id, '', 'Shut', 'nobody may');
    w2.soc.addFriend(X, Y);
    const open = w2.soc.findJournal(w2.soc.stateOf(X), j2.id).pages[0];
    w2.soc.share(X, j2.id, open.id, 102);
    const got = w2.soc.sharedWithMe(Y);
    yes('one page can be shared without the rest',
        got.length === 1 && got[0].pages.length === 1 && got[0].pages[0].title === 'Open');

    yes('and a journal can be thrown away', w2.soc.dropJournal(X, j2.id) &&
        w2.soc.stateOf(X).journals.length === 0);
  }

  // ---------------------------------------------------------------- trading
  {
    const w = world();
    const A = w.person(0xff000001, 'Bjorn', 101, 'town:X.esm', [0, 0, 0]);
    const B = w.person(0xff000002, 'Sera', 102, 'town:X.esm', [100, 0, 0]);
    w.give(A, 0x900, 3, 'Iron Sword');
    w.give(A, GOLD, 100, 'Gold');
    w.give(B, 0x901, 5, 'Leek');

    yes('a trade can be started', w.trade.begin(A, B) === '');
    yes('and both of them are in it', !!w.trade.tradeOf(A) && w.trade.tradeOf(B) === w.trade.tradeOf(A));
    yes('you cannot start a second one', w.trade.begin(A, B) !== '');

    yes('you can only offer what you are carrying',
        w.trade.add(A, 'Leek', 1) === 'You are not carrying that.');
    yes('and what you are', w.trade.add(A, 'Iron Sword', 2) === '');
    const t = w.trade.tradeOf(A);
    yes('it lands on your side and not theirs', t.offerA.length === 1 && t.offerB.length === 0);
    yes('and not more than you have', (w.trade.add(A, 'Iron Sword', 99), t.offerA[0].c === 3));

    yes('gold you do not have is refused', w.trade.gold(A, 500) !== '');
    yes('gold you do have is not', w.trade.gold(A, 40) === '');

    w.trade.add(B, 'Leek', 5);

    /*
      THE ONE RULE THAT MAKES A TRADE SAFE. What you agreed to is what you
      get: changing either pile takes both agreements back.
    */
    w.trade.confirm(A);
    yes('one side agreeing does not swap anything', w.count(B, 0x900) === 0);
    /*
      A REAL change, not a no-op. The first version of this added a fourth
      sword to a pile that already held all three, which answers "that is all
      of them already" and correctly changes nothing: it was testing that a
      refusal unconfirms, which would be the wrong behaviour to want.
    */
    w.trade.remove(A, 'Iron Sword');
    yes('and changing the pile takes the agreement back', t.okA === false);
    w.trade.add(A, 'Iron Sword', 3);

    w.trade.confirm(A);
    w.trade.confirm(B);
    yes('both agreeing swaps it', w.count(B, 0x900) === 3 && w.count(A, 0x901) === 5);
    yes('and the gold with it', w.count(B, GOLD) === 40 && w.count(A, GOLD) === 60);
    yes('and the trade is over', !w.trade.tradeOf(A) && !w.trade.tradeOf(B));

    // Something offered and then lost is refused whole rather than half done.
    const w2 = world();
    const X = w2.person(0xff000001, 'Bjorn', 101, 'town:X.esm', [0, 0, 0]);
    const Y = w2.person(0xff000002, 'Sera', 102, 'town:X.esm', [100, 0, 0]);
    w2.give(X, 0x900, 1, 'Iron Sword');
    w2.give(Y, 0x901, 1, 'Leek');
    w2.trade.begin(X, Y);
    w2.trade.add(X, 'Iron Sword', 1);
    w2.trade.add(Y, 'Leek', 1);
    w2.trade.confirm(X);
    w2.store[X].inventory = [];            // they dropped it
    const refused = w2.trade.confirm(Y);
    yes('a thing that is gone by the time both agree refuses the whole trade',
        /does not have/.test(refused) && w2.count(Y, 0x901) === 1);
    yes('and nothing moved', w2.count(X, 0x901) === 0);

    // Walking away ends it, and so does walking off.
    const w3 = world();
    const P = w3.person(0xff000001, 'Bjorn', 101, 'town:X.esm', [0, 0, 0]);
    const Q = w3.person(0xff000002, 'Sera', 102, 'town:X.esm', [100, 0, 0]);
    w3.trade.begin(P, Q);
    w3.moveTo(Q, [90000, 0, 0]);
    w3.trade.tick();
    yes('a trade ends when the two of you walk apart', !w3.trade.tradeOf(P));
  }

  // -------------------------------------------- the party bonus is paid once
  {
    /*
      A BONUS PAID IN WHOLE PIECES. Work is counted in pieces: one seam, one
      log. There is no such thing as 1.15 of a log, and rolling a die would
      make the same swing worth different amounts with nothing on screen
      saying why. So it is banked and paid as one extra piece, which at
      fifteen percent is every seventh.
    */
    yes('the bonus is banked rather than rolled for',
        /PARTY_BANK\[actorId\] >= 1/.test(src) && !/Math\.random\(\) < over/.test(src));
    yes('and it is paid through the one place all work passes',
        /function creditWork\(actorId, key\)/.test(src) &&
        src.slice(src.indexOf('function creditWork(actorId, key)'),
                  src.indexOf('function creditWork(actorId, key)') + 3000)
           .indexOf('workBonus') !== -1);
  }
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
