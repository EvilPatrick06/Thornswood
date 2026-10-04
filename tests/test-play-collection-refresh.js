/*
  test-play-collection-refresh.js

  Play offers the same Vortex bring-up-to-date Diagnostics does.

  WHY THIS EXISTS. The Diagnostics button BtnOwnGameRefresh runs
  StartOwnGame(false), which is OwnGame.Refresh when Vortex has deployed
  since the folder was made (OwnGame.NeedsRefresh). Play never asked
  NeedsRefresh. It checked ownGameBusy and launched. A collection Vortex
  had already deployed while the launcher was open went into the game
  from the last refresh.

  This holds the cause to the source:
    - StartPlay asks OwnGameRefreshIfDue before Discord and before Play();
    - Play() asks it again, because Play() is also the path a running game
      and other callers come through, and the button being grey does
      nothing for those;
    - OwnGameRefreshIfDue is StartOwnGame(false, true), the same call as
      BtnOwnGameRefresh, not a second refresh;
    - when NeedsRefresh is false, StartPlay still reaches Play().

  Read only. It reads source files and nothing else.
*/
const REPO_DIR = require('path').join(__dirname, '..');
const fs = require('fs');
const path = require('path');

const APP = path.join(REPO_DIR, 'launcher', 'app');
const CR = String.fromCharCode(13);
const read = f => fs.readFileSync(path.join(APP, f), 'utf8').split(CR).join('');

let pass = 0, fail = 0;
const yes = (w, c) => {
  if (c) { pass++; console.log('PASS  ' + w); }
  else { fail++; console.log('FAIL  ' + w); }
};

function body(src, sig) {
  const at = src.indexOf(sig);
  if (at < 0) return '';
  const open = src.indexOf('{', at);
  if (open < 0) return '';
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === '{') depth++;
    else if (src[i] === '}') {
      depth--;
      if (depth === 0) return src.slice(open, i + 1);
    }
  }
  return src.slice(open);
}

const own = read('ShellOwnGame.cs');
const chars = read('ShellChars.cs');
const shell = read('Shell.cs');
const due = body(own, 'static bool OwnGameRefreshIfDue()');
const startPlay = body(chars, 'static void StartPlay()');
const play = body(shell, 'static void Play()');
const wire = body(own, 'static void WireOwnGame()');

yes('OwnGameRefreshIfDue exists', due.length > 0);
yes('it asks OwnGame.NeedsRefresh, the same test Diagnostics refresh uses',
    due.indexOf('OwnGame.NeedsRefresh(cfg)') >= 0);
yes('it runs StartOwnGame(false, true), the same call as the Diagnostics button',
    /StartOwnGame\(\s*false\s*,\s*true\s*\)/.test(due));
yes('the Diagnostics button is still that same StartOwnGame(false, true)',
    /btnOwnGameRefresh\.Click \+= delegate \{ StartOwnGame\(false, true\); \}/.test(wire));
yes('it does not start a second refresh of its own',
    due.indexOf('OwnGame.Refresh(') < 0 && due.indexOf('OwnGame.Make(') < 0);
yes('it leaves a running game alone',
    /playing \|\| Checks\.GameRunning\(\)/.test(due));
yes('it does nothing when the folder is not due',
    /if \(!due\) return false;/.test(due));

const requiredAt = startPlay.indexOf('if (!OwnGameRequired()) return;');
const dueAt = startPlay.indexOf('if (OwnGameRefreshIfDue()) return;');
const doorAt = startPlay.indexOf('if (!Door.RecentlyCleared)');
yes('StartPlay asks it after OwnGameRequired and before Discord',
    requiredAt >= 0 && dueAt > requiredAt && doorAt > dueAt);
yes('StartPlay still reaches Play() when the folder is current',
    /if \(OwnGameRefreshIfDue\(\)\) return;[\s\S]*\n\s*Play\(\);/.test(startPlay));

const playHead = play.slice(0, 1200);
yes('Play() asks it on the way in, with the other holds',
    playHead.indexOf('if (OwnGameRefreshIfDue()) return;') >= 0);
yes('Play() still checks ownGameBusy before it, so work already going is not started twice',
    playHead.indexOf('if (ownGameBusy)') >= 0 &&
    playHead.indexOf('if (ownGameBusy)') < playHead.indexOf('if (OwnGameRefreshIfDue()) return;'));
yes('Play() still launches when none of those holds fire',
    play.indexOf('Process.Start') >= 0 || play.indexOf('skse64_loader') >= 0 ||
    play.indexOf('Paths.Loader') >= 0);

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
