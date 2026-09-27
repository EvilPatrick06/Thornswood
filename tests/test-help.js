// test-help.js
//
// /help is a short menu, and nothing advertises a command it will then refuse.
//
// From the To Do List: "/help is a developer's command list, and the
// unknown-command reply advertises a command everybody is then refused...
// /help opens a short menu: controls, how to talk, the rules, how to reach
// staff, what to do first. Filter it by permission, which /help two lines
// above already does correctly and the fallback simply forgot to."
//
// The second half is the one worth a harness. A reply that names /tp to
// somebody who will be refused /tp is worse than saying nothing: it is the
// first thing a new person learns about this server and it is a no.
//
// Read only.
const TOOLS_DIR = require('path').join(__dirname, '..', 'tools'); // the tests are in tests\, what they test is in tools\
const fs = require('fs');
const path = require('path');
const SRC = process.env.GM || path.join(TOOLS_DIR, '..', 'game', 'gamemode.js');
const CR = String.fromCharCode(13);
const src = fs.readFileSync(SRC, 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const a = src.indexOf("    if (word === '/help' || word === '/commands') {");
const b = a < 0 ? -1 : src.indexOf('\n    // Anything else beginning with a slash', a);
const help = (a >= 0 && b >= 0) ? src.slice(a, b) : null;
yes('/help is in the gamemode', help !== null);

/*
  Run it, for a playtester and for everybody else, on every topic.

  Everything it needs is passed in: whether this profile is a playtester, what
  they are called, and somewhere for the answer to land.
*/
function ask(topic, playtester) {
  if (!help) { return []; }
  const said = [];
  const body = 'var word = "/help";\n' +
               'var parts = ["/help"].concat(topic ? [topic] : []);\n' +
               help.replace(/\n\s*$/, '') + '\n';
  const fn = new Function(
    'topic', 'toProfile', 'isPlaytester', 'roleOf', 'profileId', 'String',
    body);
  fn(topic,
     function (pid, line) { said.push(String(line)); },
     function () { return !!playtester; },
     function () { return 'a playtester'; },
     11, String);
  return said;
}

if (help) {
  // ------------------------------------------------------------ the menu
  {
    const top = ask('', false);
    yes('/help on its own answers once', top.length === 1);
    const line = top[0] || '';
    yes('and it is a menu rather than every verb there is',
        /\/help talking/.test(line) && /\/help land/.test(line));
    yes('it names the keys people actually press first',
        /Press K/.test(line) && /P for friends/.test(line) &&
        /J for journals/.test(line) && /Enter to talk/.test(line));
    yes('and it is short enough to read in a chat window', line.length < 420);
  }

  // --------------------------------------------------- one topic each
  {
    const topics = ['talking', 'people', 'living', 'work', 'land', 'staff'];
    let every = true, short = true;
    topics.forEach(function (t) {
      const out = ask(t, false);
      if (out.length !== 1 || !out[0]) { every = false; }
      else if (out[0].length > 520) { short = false; }
    });
    yes('every topic on the menu answers something', every);
    yes('and each answer is short', short);

    yes('talking explains the chat and the dice',
        /Enter opens the chat/.test(ask('talking', false)[0]) &&
        /the server rolls it/.test(ask('talking', false)[0]));
    yes('people explains the three keys, which is what was asked for',
        /press Y/.test(ask('people', false)[0]) &&
        /H to offer a/.test(ask('people', false)[0]) &&
        /L to stop hearing/.test(ask('people', false)[0]));
    yes('and staff points at the places a person is actually reachable',
        /thornswood\.net/.test(ask('staff', false)[0]) &&
        /Discord/.test(ask('staff', false)[0]));

    // A topic nobody has is the menu again rather than silence.
    const odd = ask('fish', false);
    yes('an unknown topic is answered with the menu',
        odd.length === 1 && /\/help talking/.test(odd[0]));
  }

  // ------------------------------------------- filtered the same way twice
  {
    const plain = ask('', false)[0] || '';
    const staff = ask('', true)[0] || '';
    yes('an ordinary person is not told about /tp', plain.indexOf('/tp') === -1);
    yes('a playtester is', /\/tp <place>/.test(staff));
    yes('and is told what they are', /a playtester/.test(staff));
  }
}

// --------------------------------------- the reply to a command that is not
{
  const c = src.indexOf("    toProfile(profileId, 'No command called ' + word");
  const fallback = c >= 0 ? src.slice(c, c + 500) : '';
  yes('there is a reply for a command nobody has', !!fallback);

  /*
    THE DEFECT ITSELF. This line named /tp to everybody and then refused
    everybody who was not a playtester, which is the To Do entry's own
    complaint and the first thing a new person learned about this server.
  */
  yes('it only names the playtester commands to a playtester',
      /isPlaytester\(profileId\) \? ', and \/tp <place>\.' : '\.'/.test(fallback));
  yes('and it points at /help rather than listing everything again',
      /Try \/help/.test(fallback));
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
