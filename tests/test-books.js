/*
  test-books.js

  The faction and business book from docs/systems/factions.md, run as the
  real thornswoodBooks() taken out of game/gamemode.js. A book is kept for
  the group in the server's private folder (#2582). It is not a page on one
  character.
*/
const fs = require('fs');
const os = require('os');
const path = require('path');
const vm = require('vm');

const ROOT = path.join(__dirname, '..');
const GM = process.env.GM || path.join(ROOT, 'game', 'gamemode.js');
const CR = String.fromCharCode(13);
const src = fs.readFileSync(GM, 'utf8').split(CR).join('');
const start = src.indexOf('/* BOOKS-START */');
const end = src.indexOf('/* BOOKS-END */');
const block = start >= 0 && end > start ? src.slice(start, end) : '';

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

yes('the book block is in gamemode.js', !!block && /function thornswoodBooks\(/.test(block));
yes('a book command is answered, and a plain line is not a book line',
    /if \(word === '\/book'\)/.test(src) && src.indexOf("word === '/book'") > 0);
yes('the price list never moves gold or an item', block.indexOf('addItem') < 0 && block.indexOf('removeItem') < 0);

function rolesFor(pid) {
  pid = Number(pid);
  if (pid === 1 || pid === 2) {
    return { business: true, faction: true, staff: false, account: 'discord-a' };
  }
  if (pid === 9) { return { business: false, faction: false, staff: true, account: 'discord-staff' }; }
  if (pid === 4) { return { business: false, faction: false, staff: false, account: 'discord-b' }; }
  return { business: false, faction: false, staff: false, account: 'p:' + pid };
}

function make(dir, extra) {
  extra = extra || {};
  const box = {
    globalThis: null,
    env: {
      fs: fs,
      path: path,
      privDir: dir,
      now: function () { return extra.now ? extra.now() : Date.now(); },
      roles: extra.roles || rolesFor,
      silenced: extra.silenced || function () { return false; },
      nameOf: function (actorId, pid) {
        if (extra.names && extra.names[pid]) { return extra.names[pid]; }
        if (Number(pid) === 1) { return 'Ada'; }
        if (Number(pid) === 4) { return 'Bjorn'; }
        return 'M' + pid;
      },
      find: extra.find || function (actorId, who) {
        const n = Number(who);
        if (!n) { return { actorId: 0, pid: 0, name: '', why: 'Nobody here by that name.' }; }
        return { actorId: 50 + n, pid: n, name: 'M' + n, why: '' };
      },
      offer: function () { return ''; },
      refresh: function () { extra.pushes = (extra.pushes || 0) + 1; },
      online: function () { return extra.online ? extra.online() : {}; },
      atBox: extra.atBox || function () { return ''; }
    }
  };
  box.globalThis = box;
  vm.createContext(box);
  vm.runInContext(block + '\nthis.api = thornswoodBooks(env);', box, { filename: 'books.js' });
  return box.api;
}

function parts(line) { return line.trim().split(/\s+/); }

if (block) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tw-books-'));
  let clock = 1700000000000;
  const online = {};
  let hush = false;
  const api = make(dir, {
    now: function () { return clock; },
    online: function () { return online; },
    silenced: function (pid) { return hush && Number(pid) === 1; }
  });

  yes('someone with no role and no book never sees the tab',
      api.view(3, {}).show === false);

  const bizOnly = make(fs.mkdtempSync(path.join(os.tmpdir(), 'tw-books-')), {
    roles: function () { return { business: true, faction: false, staff: false, account: 'discord-c' }; }
  });
  yes('Business Owner cannot found a faction',
      /does not hold Faction Owner/.test(bizOnly.command({
        actorId: 1, profileId: 5, parts: parts('/book new faction The North Gate')
      })));
  const noRole = make(fs.mkdtempSync(path.join(os.tmpdir(), 'tw-books-')), {
    roles: function () { return { staff: true, business: false, faction: false, account: 'discord-staff' }; }
  });
  yes('staff without the Discord role cannot found a book',
      /does not hold Business Owner/.test(noRole.command({
        actorId: 1, profileId: 9, parts: parts('/book new business The Bee')
      })));
  const asDev = make(fs.mkdtempSync(path.join(os.tmpdir(), 'tw-books-')), {
    roles: function () { return { staff: true, dev: true, business: false, faction: false, account: 'discord-dev' }; }
  });
  const devBefore = asDev.view(9, {});
  yes('a Dev may start one business and one faction',
      devBefore.show === true && devBefore.canBusiness === true && devBefore.canFaction === true);
  yes('a Dev founds a business without Business Owner',
      asDev.command({ actorId: 1, profileId: 9, parts: parts('/book new business The Bee') }) === 'Founded The Bee.');
  yes('a Dev founds a faction as well',
      asDev.command({ actorId: 1, profileId: 9, parts: parts('/book new faction The North Gate') }) === 'Founded The North Gate.');
  const devAfter = asDev.view(9, {});
  yes('a Dev who already has both cannot found another',
      devAfter.canBusiness === false && devAfter.canFaction === false);
  yes('a second business from a Dev is refused',
      asDev.command({ actorId: 1, profileId: 9, parts: parts('/book new business Another Bee') }) === 'This account already has a business.');

  const founded = api.command({
    actorId: 1, profileId: 1, parts: parts('/book new business The Bee')
  });
  yes('a business is founded and named', founded === 'Founded The Bee.');
  const again = api.command({
    actorId: 2, profileId: 2, parts: parts('/book new business The Other Bee')
  });
  yes('a second business on the same account is refused',
      again === 'This account already has a business.');
  const faction = api.command({
    actorId: 1, profileId: 1, parts: parts('/book new faction The North Gate')
  });
  yes('the same account may found one faction as well',
      faction === 'Founded The North Gate.');
  const factionAgain = api.command({
    actorId: 1, profileId: 1, parts: parts('/book new faction Another Gate')
  });
  yes('a second faction is refused', factionAgain === 'This account already has a faction.');

  const mine = api.view(1, {});
  yes('the founder sees the tab and both books, and cannot found another',
      mine.show === true && mine.books.length === 2 &&
      mine.canBusiness === false && mine.canFaction === false);
  const bee = mine.books.filter(function (b) { return b.name === 'The Bee'; })[0];
  yes('the founder is the owner and Member starts with read and speak',
      !!bee && bee.owner === true && bee.read === true && bee.speak === true &&
      bee.canPrices === true && bee.people.length === 1 && bee.people[0].role === 'Owner');
  const alt = api.view(2, {});
  const altBee = alt.books.filter(function (b) { return b.name === 'The Bee'; })[0];
  yes('another character on the account opens the book as its owner',
      alt.show === true && !!altBee && altBee.owner === true);

  yes('a stranger still does not see the tab before they accept',
      api.view(4, {}).show === false);
  const asked = api.command({
    actorId: 1, profileId: 1, parts: parts('/book invite ' + bee.id + ' 4')
  });
  yes('an invite names the 45 seconds', /45 seconds/.test(asked));
  yes('until they accept they still do not see the tab', api.view(4, {}).show === false);
  clock += 45001;
  const late = api.accept(4, 'Bjorn');
  yes('an invite dies after 45 seconds', late.ok === false && /gone/.test(late.text));
  clock -= 45001;
  api.command({ actorId: 1, profileId: 1, parts: parts('/book invite ' + bee.id + ' 4') });
  clock += 45000;
  const joined = api.accept(4, 'Bjorn');
  yes('accepting within 45 seconds puts them in the book',
      joined.ok === true && joined.text === 'You joined The Bee.');
  const memberView = api.view(4, {});
  const memberBee = memberView.books.filter(function (b) { return b.name === 'The Bee'; })[0];
  yes('a new member has read and speak, and not prices',
      memberView.show === true && !!memberBee && memberBee.read === true &&
      memberBee.speak === true && memberBee.canPrices === false && memberBee.owner === false);

  const refusedPrice = api.command({
    actorId: 4, profileId: 4,
    parts: parts('/book price ' + bee.id + ' | Iron dagger | 12 | -')
  });
  yes('prices are refused without the permission', /cannot set prices/.test(refusedPrice));
  const set = api.command({
    actorId: 1, profileId: 1,
    parts: parts('/book price ' + bee.id + ' | Iron dagger | 12 | -')
  });
  yes('a blank sell is kept and does not have to be a number', /Set Iron dagger/.test(set));
  const free = api.command({
    actorId: 1, profileId: 1,
    parts: parts('/book price ' + bee.id + ' | Water | 0 | 0')
  });
  yes('zero gold is free and is kept', /Set Water/.test(free));
  const bad = api.command({
    actorId: 1, profileId: 1,
    parts: parts('/book price ' + bee.id + ' | Mead | 1.5 | 2')
  });
  yes('a price has to be a whole number', /whole number/.test(bad));
  const priced = api.view(1, {}).books.filter(function (b) { return b.id === bee.id; })[0];
  const dagger = priced.priceList.filter(function (p) { return p.name === 'Iron dagger'; })[0];
  const water = priced.priceList.filter(function (p) { return p.name === 'Water'; })[0];
  yes('buy 12 and a blank sell are stored, and zero is stored as zero',
      dagger.buy === 12 && dagger.sell === null && water.buy === 0 && water.sell === 0);
  const submitted = api.command({
    actorId: 1, profileId: 1, parts: parts('/book submit ' + bee.id)
  });
  const afterSubmit = api.books().filter(function (b) { return b.id === bee.id; })[0];
  yes('submitting away from a box is refused and the list stays',
      /Stand at the hold/.test(submitted) && afterSubmit.prices.length === 2);

  for (let n = 0; n < 98; n++) {
    api.command({
      actorId: 1, profileId: 1,
      parts: parts('/book price ' + bee.id + ' | Line ' + n + ' | 1 | 1')
    });
  }
  const fullList = api.command({
    actorId: 1, profileId: 1,
    parts: parts('/book price ' + bee.id + ' | One more | 1 | 1')
  });
  yes('the 101st price line is refused', fullList === 'The list is full. 100 lines.');

  const said = api.command({
    actorId: 1, profileId: 1, parts: parts('/book say ' + bee.id + ' ' + 'where is the gate')
  });
  yes('a line goes into the book', said === 'Said in The Bee.');
  const long = api.command({
    actorId: 1, profileId: 1, parts: parts('/book say ' + bee.id + ' ' + 'x'.repeat(301))
  });
  yes('a long line is cut to 300', /Said in/.test(long));
  const storedChat = api.books().filter(function (b) { return b.id === bee.id; })[0].chat;
  yes('the stored line is 300 characters',
      storedChat[storedChat.length - 1].text.length === 300);
  api.command({
    actorId: 4, profileId: 4, parts: parts('/book say ' + bee.id + ' bring iron')
  });
  const heard = api.view(1, {}).books.filter(function (b) { return b.id === bee.id; })[0];
  const hidden = api.view(1, { 4: true }).books.filter(function (b) { return b.id === bee.id; })[0];
  const bjornLine = heard.chat.filter(function (c) { return c.text === 'bring iron'; });
  const hiddenLine = hidden.chat.filter(function (c) { return c.text === 'bring iron'; });
  yes('a personal text mute hides that line for you only',
      bjornLine.length === 1 && hiddenLine.length === 0 &&
      hidden.chat.length === heard.chat.length - 1);
  const drawn = heard.chat[heard.chat.length - 1];
  yes('the line is out of character text kept on the book, not a place',
      drawn.name === 'Bjorn' && drawn.text === 'bring iron');
  hush = true;
  const hushed = api.command({
    actorId: 1, profileId: 1, parts: parts('/book say ' + bee.id + ' I will shout')
  });
  hush = false;
  yes('staff silence stops a line for everybody',
      /silenced/.test(hushed) &&
      api.books().filter(function (b) { return b.id === bee.id; })[0].chat
        .filter(function (c) { return c.text === 'I will shout'; }).length === 0);

  for (let n = 0; n < 48; n++) {
    api.command({
      actorId: 1, profileId: 1, parts: parts('/book say ' + bee.id + ' line ' + n)
    });
  }
  const kept = api.books().filter(function (b) { return b.id === bee.id; })[0].chat;
  yes('only the last 50 lines are kept', kept.length === 50 && kept[0].text !== 'where is the gate');

  online[1] = 'Ada';
  api.noteTick();
  const never = api.view(4, {}).books.filter(function (b) { return b.id === bee.id; })[0];
  const bjornRow = never.people.filter(function (p) { return p.name === 'Bjorn'; })[0];
  yes('someone who has never left has no time on the row',
      !!bjornRow && bjornRow.on === false && bjornRow.left === 0);
  online[4] = 'Bjorn';
  api.noteTick();
  delete online[4];
  clock += 5000;
  api.noteTick();
  const away = api.view(1, {}).books.filter(function (b) { return b.id === bee.id; })[0];
  const awayBjorn = away.people.filter(function (p) { return p.name === 'Bjorn'; })[0];
  const adaRow = away.people.filter(function (p) { return p.name === 'Ada'; })[0];
  yes('leaving writes a time, and someone still here has none',
      awayBjorn.left === clock && adaRow.on === true && adaRow.left === 0);

  const api2 = make(dir, { now: function () { return clock; } });
  const back = api2.view(1, {}).books.filter(function (b) { return b.name === 'The Bee'; })[0];
  yes('the book, the prices and the chat survive a new load',
      !!back && back.priceList.length === 100 && back.chat.length === 50);
  const backBjorn = back.people.filter(function (p) { return p.name === 'Bjorn'; })[0];
  yes('the last time they left survives too', backBjorn.left === clock);

  const staffView = api.view(9, {});
  yes('staff see a book they were not invited to',
      staffView.show === true &&
      staffView.books.filter(function (b) { return b.name === 'The Bee'; }).length === 1);
  const handed = api.command({
    actorId: 9, profileId: 9, parts: parts('/book give ' + bee.id + ' | Bjorn')
  });
  yes('staff can hand the book to someone already in it', /Bjorn owns The Bee/.test(handed));
  const afterHand = api.books().filter(function (b) { return b.id === bee.id; })[0];
  yes('ownership moves to that character\'s account',
      afterHand.owner === 4 && afterHand.account === 'discord-b');
  const foundedAfter = api.command({
    actorId: 1, profileId: 1, parts: parts('/book new business The Second Bee')
  });
  yes('the old account can found again once the book has moved',
      foundedAfter === 'Founded The Second Bee.');

  for (let n = 10; n < 48; n++) {
    api.command({ actorId: 4, profileId: 4, parts: parts('/book invite ' + bee.id + ' ' + n) });
    api.accept(n, 'M' + n);
  }
  const packed = api.books().filter(function (b) { return b.id === bee.id; })[0];
  const overflowAsk = api.command({
    actorId: 4, profileId: 4, parts: parts('/book invite ' + bee.id + ' 70')
  });
  yes('the 41st person is refused',
      packed.members.length === 40 && /full/.test(overflowAsk));

  const left = api.command({ actorId: 10, profileId: 10, parts: parts('/book leave ' + bee.id) });
  yes('a member can leave, and the book name is in the answer', left === 'You left The Bee.');
  const ownerLeave = api.command({
    actorId: 4, profileId: 4, parts: parts('/book leave ' + bee.id)
  });
  yes('the owner is told to disband rather than leave', /disbands/.test(ownerLeave));

  try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) { }

  const ledgerDir = fs.mkdtempSync(path.join(os.tmpdir(), 'tw-books-'));
  let hold = '';
  const ledger = make(ledgerDir, {
    roles: function (pid) {
      if (Number(pid) === 1) {
        return { business: true, faction: true, staff: false, account: 'ledger-a' };
      }
      if (Number(pid) === 2) {
        return { business: true, faction: false, staff: false, account: 'ledger-b' };
      }
      if (Number(pid) === 4) {
        return { business: false, faction: false, staff: false, account: 'ledger-c' };
      }
      return { business: false, faction: false, staff: false, account: 'p:' + pid };
    },
    atBox: function () { return hold; }
  });
  ledger.command({ actorId: 1, profileId: 1, parts: parts('/book new business The Bee') });
  ledger.command({ actorId: 2, profileId: 2, parts: parts('/book new business The Other') });
  const beeId = ledger.books().filter(function (b) { return b.name === 'The Bee'; })[0].id;
  const otherId = ledger.books().filter(function (b) { return b.name === 'The Other'; })[0].id;
  ledger.command({
    actorId: 1, profileId: 1,
    parts: parts('/book price ' + beeId + ' | Iron dagger | 10 | -')
  });
  ledger.command({
    actorId: 1, profileId: 1,
    parts: parts('/book price ' + beeId + ' | Water | 0 | 0')
  });
  ledger.command({
    actorId: 2, profileId: 2,
    parts: parts('/book price ' + otherId + ' | Iron dagger | 11 | 5')
  });
  const notThere = ledger.command({
    actorId: 1, profileId: 1, parts: parts('/book submit ' + beeId)
  });
  yes('a list is not submitted until they are at the box', /Stand at the hold/.test(notThere));
  hold = 'Whiterun';
  const sent = ledger.command({
    actorId: 1, profileId: 1, parts: parts('/book submit ' + beeId)
  });
  const bookAfter = ledger.books().filter(function (b) { return b.id === beeId; })[0];
  yes('the box keeps a copy and the book still has its list',
      /Submitted The Bee to whiterun/.test(sent) && bookAfter.prices.length === 2);
  ledger.command({
    actorId: 1, profileId: 1,
    parts: parts('/book price ' + beeId + ' | Iron dagger | 99 | 99')
  });
  const held = ledger.ledgers().whiterun[beeId].prices.filter(function (p) {
    return p.name === 'Iron dagger';
  })[0];
  yes('editing the book does not change the copy until they submit again',
      held.buy === 10 && held.sell === null);
  ledger.command({
    actorId: 2, profileId: 2, parts: parts('/book submit ' + otherId)
  });
  const whiterun = ledger.guildPrice('whiterun', 'Iron dagger');
  const waterPrice = ledger.guildPrice('whiterun', 'Water');
  yes('a blank is not averaged, zero is, and a half rounds up',
      whiterun.buy === 11 && whiterun.sell === 5 && waterPrice.buy === 0 && waterPrice.sell === 0);
  ledger.command({ actorId: 1, profileId: 1, parts: parts('/book new faction The Gate') });
  const gateId = ledger.books().filter(function (b) { return b.name === 'The Gate'; })[0].id;
  ledger.command({
    actorId: 1, profileId: 1,
    parts: parts('/book price ' + gateId + ' | Iron dagger | 20 | 20')
  });
  hold = 'solitude';
  ledger.command({ actorId: 1, profileId: 1, parts: parts('/book submit ' + gateId) });
  const own = ledger.guildPrice('whiterun', 'Iron dagger');
  const otherHold = ledger.guildPrice('riften', 'Iron dagger');
  const none = ledger.guildPrice('whiterun', 'Mead');
  yes('a hold keeps its own price, and a hold with none uses the others',
      own.buy === 11 && otherHold.buy === 16 && none.buy === null && none.sell === null);
  const listed = ledger.catalog('riften');
  const listedDagger = listed.filter(function (row) { return row.name === 'Iron dagger'; })[0];
  yes('the hold catalogue is the same submitted average',
      listedDagger && listedDagger.buy === 16 && listed.every(function (row) { return row.buy !== null || row.sell !== null; }));
  ledger.command({
    actorId: 1, profileId: 1,
    parts: parts('/book price ' + beeId + ' | Iron dagger | 12 | -')
  });
  hold = 'whiterun';
  ledger.command({ actorId: 1, profileId: 1, parts: parts('/book submit ' + beeId) });
  yes('a later submission from the same book replaces the earlier copy',
      ledger.guildPrice('whiterun', 'Iron dagger').buy === 12);
  ledger.command({ actorId: 1, profileId: 1, parts: parts('/book invite ' + beeId + ' 4') });
  ledger.accept(4, 'Bjorn');
  const memberSubmit = ledger.command({
    actorId: 4, profileId: 4, parts: parts('/book submit ' + beeId)
  });
  yes('a member without prices cannot submit', /cannot set prices/.test(memberSubmit));
  ledger.command({ actorId: 2, profileId: 2, parts: parts('/book disband ' + otherId) });
  yes('disbanding drops that book\'s copy, and a missing sell uses another hold',
      !ledger.ledgers().whiterun[otherId] &&
      ledger.ledgers().whiterun[beeId].prices[0].buy === 12 &&
      ledger.guildPrice('whiterun', 'Iron dagger').sell === 20);
  const reloaded = make(ledgerDir, { atBox: function () { return 'whiterun'; } });
  yes('the copy survives a new load',
      reloaded.guildPrice('whiterun', 'Iron dagger').buy === 12);
  try { fs.rmSync(ledgerDir, { recursive: true, force: true }); } catch (e2) { }
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
