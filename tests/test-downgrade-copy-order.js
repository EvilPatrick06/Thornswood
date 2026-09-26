/*
  test-downgrade-copy-order.js

  The downgrade finishes safely and the installer sends a wrong build to it.
  This guards the three fixes from issue #369 that shipped without a harness of
  their own (commit 146b605, "Launcher: #369 F1/F2/F3/F4 downgrade path").

  WHY THIS EXISTS. Three small faults were found on the downgrade path and
  fixed but never covered by a test, so a later change could undo any of them
  in silence. This reads the source and checks the shape each fix relies on:

    F1  installer\Setup-Thornswood.ps1: a wrong Skyrim build is not a failed
        check. Counting it as a miss kept the window shut and never opened the
        launcher whose Downgrade button fixes it. So the build check counts it
        as next, and the notice above tells the person to press Downgrade in
        the launcher, not to pick a build from Steam's Betas list.

    F3  launcher\app\Downgrade.cs: SkyrimSE.exe is held back and copied last,
        after every other file is in place. The build is read from that one
        file, so the moment it lands the copy reads as 1.6.1170. Copied first,
        a copy that then stops part way took the Downgrade card and its Try
        again button away with the job unfinished; copied last, a stop part way
        leaves the exe on the old build so the card and button stay.

    F4  launcher\app\Downgrade.cs: the twenty minute fallback takes a part as
        done only once the folder has reached the size Steam announced for it.
        A folder short of that is a stall, not a finish, and taking it as done
        writes the marker and copies truncated files over the Steam copy.

  The launcher cannot be started from here (CLAUDE.md forbids it), and this
  machine has no Windows csc, so like test-downgrade-asks.js this reads the
  source and checks the shape rather than running the button.

  Read only. It reads launcher\app\Downgrade.cs and installer\Setup-Thornswood.ps1.
*/
const TOOLS_DIR = require('path').join(__dirname, '..', 'tools'); // the tests are in tests\, what they test is in tools\
const fs = require('fs');
const path = require('path');

const ROOT = path.join(TOOLS_DIR, '..');
const APP = path.join(ROOT, 'launcher', 'app');
const DOWN = fs.readFileSync(path.join(APP, 'Downgrade.cs'), 'utf8');
const SETUP = fs.readFileSync(path.join(ROOT, 'installer', 'Setup-Thornswood.ps1'), 'utf8');

let pass = 0, fail = 0;
const yes = (w, c) => {
  if (c) { pass++; console.log('PASS  ' + w); }
  else { fail++; console.log('FAIL  ' + w); }
};

/* A method's body: from its signature to the closing brace at the same indent. */
function body(src, signature) {
  const at = src.indexOf(signature);
  if (at < 0) return '';
  const lineStart = src.lastIndexOf('\n', at) + 1;
  const indent = src.slice(lineStart, at);
  const end = src.indexOf('\n' + indent + '}', at);
  return end < 0 ? '' : src.slice(at, end + indent.length + 2);
}

// ============================================================ F1, the installer

// The build check counts a wrong game build as next, under a collection
// install, and hands it to the launcher's Downgrade button.
const gameBranch = /\}\s*elseif \(\$Collection -and \$k -eq 'Game 1\.6\.1170'\) \{([\s\S]*?)\n\s*\} else \{/.exec(SETUP);
yes('F1: the build check has a branch for a wrong Game 1.6.1170 under a collection install', !!gameBranch);
const branchText = gameBranch ? gameBranch[1] : '';
yes('F1: a wrong build is counted as next, not a miss', /\$later\+\+/.test(branchText) && !/\$bad\+\+/.test(branchText));
yes('F1: it says the launcher\'s Downgrade button fixes it', /\[next\] \$k  the launcher's Downgrade button fixes this/.test(branchText));
// The MISS branch that increments $bad is the one after it, so the two do not
// collapse into one: a real miss still fails the install.
yes('F1: a real miss still counts against the install', /\} else \{[\s\S]*?Say "  \[MISS\] \$k"[\s\S]*?\$bad\+\+/.test(SETUP));

// The notice above the check points at the launcher's Downgrade button, not at
// Steam's Betas list, which is where it used to send people.
yes('F1: the wrong-build notice tells the person to open the launcher and press Downgrade',
    /Open the launcher and press Downgrade/.test(SETUP));
yes('F1: and no longer sends anybody to Steam\'s Betas list', !/Betas/.test(SETUP));

// ======================================================== F3, SkyrimSE.exe last

const run = body(DOWN, 'static bool Run(Config cfg');
yes('Run is found in Downgrade.cs', run.length > 0);

// In the per-depot copy loop SkyrimSE.exe is not copied where it is met: it is
// held in exeSrc/exeRel and skipped with continue.
yes('F3: SkyrimSE.exe is held back in the copy loop, not copied in place',
    /if \(string\.Equals\(rel, "SkyrimSE\.exe", StringComparison\.OrdinalIgnoreCase\)\) \{ exeSrc = f; exeRel = rel; continue; \}/.test(run));

// The held-back exe is copied after the loop, guarded by exeSrc having a value,
// and a failure there stops through Stop so the card and button stay.
const heldSkip = run.indexOf('exeSrc = f; exeRel = rel; continue;');
const exeCopy = run.indexOf('if (exeSrc.Length > 0)');
yes('F3: the held-back exe is copied after the loop', heldSkip >= 0 && exeCopy > heldSkip);
const exeBlock = exeCopy >= 0 ? run.slice(exeCopy, run.indexOf('log("Copied ', exeCopy)) : '';
yes('F3: the last copy writes the exe from exeSrc to exeRel',
    /File\.Copy\(exeSrc, dest, false\);/.test(exeBlock) && /Path\.Combine\(target, exeRel\)/.test(exeBlock));
yes('F3: a locked exe stops through Stop, so the card and Try again button stay',
    /return Stop\("Could not replace " \+ exeRel/.test(exeBlock));
// The plain copy loop no longer writes SkyrimSE.exe itself: the only File.Copy
// of exeSrc is the one after the loop, and the loop copies rel.
const loopCopyOfExe = /File\.Copy\(f, dest, false\);/.test(run);
yes('F3: the loop still copies the other files by rel', loopCopyOfExe);

// ================================================== F4, only at the announced size

// The twenty minute fallback takes a part as done only once size has reached
// the total Steam announced, and only for a download this run saw start.
yes('F4: a stalled part is taken as done only at the size Steam announced',
    /if \(sawStart && total > 0 && size >= total\)/.test(run));
yes('F4: and the log says it was the announced size that was reached',
    /the folder has reached the " \+ \(total \/ 1048576\)\.ToString\("n0"\) \+ " MB Steam announced for this part/.test(run));
// A folder that never saw a start line is still refused as leftover, so a short
// or aborted folder is not trusted.
yes('F4: a folder this run never saw start is still refused as leftover',
    /if \(!sawStart\)\s*\n\s*return Stop\("Steam never started this download/.test(run));

// ---- C# 5 --------------------------------------------------------------------
for (const [name, src] of [['Run', run]]) {
  yes(name + ' is C# 5: no interpolated strings', !/\$"/.test(src));
  yes(name + ' is C# 5: no ?.', !/\?\./.test(src));
  yes(name + ' is C# 5: no nameof, no out var', !/\bnameof\s*\(/.test(src) && !/\bout var\b/.test(src));
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
