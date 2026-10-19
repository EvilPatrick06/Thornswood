// test-2771-text-contrast.js
//
//     node tests\test-2771-text-contrast.js
//
// Issue #2771 (Patrick, 19 Oct 2026, option 1). The launcher's secondary text
// (Faint) and its error text (Bad) sat between 2 and 4 to 1 against the
// surfaces they are drawn on, in every theme, under the 4.5 to 1 WCAG 2.2
// 1.4.3 asks for. So:
//
//   1. every built-in theme in launcher\app\Themes.cs, and the DIY starter
//      palette, has every text colour (Ink, Muted, Faint, Ok, Warn, Bad) at
//      4.5 to 1 or more on every surface (Bg, Panel, Card, CardHover, Deep),
//      and AccentInk on Accent;
//   2. Muted stays brighter than Faint against every surface, so raising
//      Faint did not make the two one colour;
//   3. the placeholders at the top of launcher\ui.xaml are Forge's, so the
//      window never opens on the old values for a moment;
//   4. the launcher measures the same pairs at the same line (Themes.cs
//      MinContrast, TextNames, SurfaceNames), and the DIY editor and
//      ApplyCustomTheme both say what it finds;
//   5. the measure here goes red on the palette #2771 replaced, so it cannot
//      pass by reading nothing;
//   6. the setup program's window (installer\setup\Bootstrap.cs, #2851) has
//      no palette of its own: Setup.csproj compiles Themes.cs into it,
//      Themes.cs leans on nothing else in launcher\app, the window is drawn
//      in Forge from there, and every colour it names is one of the sixteen.
//
// Read only.
'use strict';
const REPO_DIR = require('path').join(__dirname, '..'); // the tests are in tests\, the repository is one folder up
const fs = require('fs');
const path = require('path');
const CR = String.fromCharCode(13);
function read() {
  const bits = Array.prototype.slice.call(arguments);
  return fs.readFileSync(path.join.apply(path, [REPO_DIR].concat(bits)), 'utf8').split(CR).join('');
}

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const MIN = 4.5;
const TEXT = ['Ink', 'Muted', 'Faint', 'Ok', 'Warn', 'Bad'];
const SURFACES = ['Bg', 'Panel', 'Card', 'CardHover', 'Deep'];
const NAMES = ['Bg', 'Panel', 'Card', 'CardHover', 'Deep', 'Line', 'Edge', 'Ink',
  'Muted', 'Faint', 'Accent', 'AccentSoft', 'AccentInk', 'Ok', 'Warn', 'Bad'];

// #RRGGBB or #AARRGGBB, as Themes.cs writes them.
function rgba(hex) {
  const h = hex.replace('#', '');
  const a = h.length === 8 ? parseInt(h.slice(0, 2), 16) : 255;
  const rgb = h.slice(-6);
  return { a: a, r: parseInt(rgb.slice(0, 2), 16), g: parseInt(rgb.slice(2, 4), 16), b: parseInt(rgb.slice(4, 6), 16) };
}
// The same compositing as Themes.Over: a colour with opacity over what is under it.
function over(top, under) {
  const a = top.a / 255;
  return { a: 255, r: Math.round(top.r * a + under.r * (1 - a)), g: Math.round(top.g * a + under.g * (1 - a)), b: Math.round(top.b * a + under.b * (1 - a)) };
}
function lin(v) { const s = v / 255; return s <= 0.04045 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4); }
function lum(c) { return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b); }
function contrast(a, b) { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); }

// Every pair under MIN in a palette, as "Faint on Card 2.59".
function low(colors) {
  const out = [];
  const bg = over(rgba(colors.Bg), { a: 255, r: 0, g: 0, b: 0 });
  for (const t of TEXT) {
    for (const s of SURFACES) {
      const under = s === 'Bg' ? bg : over(rgba(colors[s]), bg);
      const r = contrast(over(rgba(colors[t]), under), under);
      if (r < MIN) out.push(t + ' on ' + s + ' ' + r.toFixed(2));
    }
  }
  const acc = over(rgba(colors.Accent), bg);
  const ai = contrast(over(rgba(colors.AccentInk), acc), acc);
  if (ai < MIN) out.push('AccentInk on Accent ' + ai.toFixed(2));
  return out;
}
function pairs(text) {
  const o = {};
  const re = /"(\w+)","(#[0-9A-Fa-f]{6,8})"/g;
  let m;
  while ((m = re.exec(text))) o[m[1]] = m[2];
  return o;
}

const themes = read('launcher', 'app', 'Themes.cs');
const palettes = [];
const makeRe = /Make\("(\w+)",[\s\S]*?new string\[\] \{([\s\S]*?)\}/g;
let mm;
while ((mm = makeRe.exec(themes))) palettes.push({ name: mm[1], colors: pairs(mm[2]) });
const diy = /string\[\] diy = new string\[\] \{([\s\S]*?)\};/.exec(themes);
if (diy) palettes.push({ name: 'DIY starter', colors: pairs(diy[1]) });

// ---- 1. every text colour reaches 4.5 to 1 on every surface ---------------
yes('Themes.cs has its nine built-in themes and the DIY starter (' + palettes.length + ' read)', palettes.length === 10 && !!diy);
for (const p of palettes) {
  const missing = NAMES.filter((n) => !p.colors[n]);
  yes(p.name + ': all sixteen colours are written out' + (missing.length ? ' (missing ' + missing.join(', ') + ')' : ''), missing.length === 0);
  if (missing.length) continue;
  const l = low(p.colors);
  yes(p.name + ': every text colour is 4.5 to 1 or more on every surface' + (l.length ? ' (' + l.join(', ') + ')' : ''), l.length === 0);
}

// ---- 2. Muted stays above Faint -------------------------------------------
for (const p of palettes) {
  if (NAMES.some((n) => !p.colors[n])) continue;
  const bg = over(rgba(p.colors.Bg), { a: 255, r: 0, g: 0, b: 0 });
  const flat = SURFACES.filter((s) => {
    const under = s === 'Bg' ? bg : over(rgba(p.colors[s]), bg);
    return contrast(over(rgba(p.colors.Muted), under), under) <= contrast(over(rgba(p.colors.Faint), under), under);
  });
  yes(p.name + ': Muted stands out more than Faint on every surface' + (flat.length ? ' (not on ' + flat.join(', ') + ')' : ''), flat.length === 0);
}

// ---- 3. ui.xaml's placeholders are Forge's --------------------------------
const xaml = read('launcher', 'ui.xaml');
const forge = palettes.find((p) => p.name === 'Forge');
for (const n of TEXT.concat(['AccentInk'])) {
  const m = new RegExp('<SolidColorBrush x:Key="' + n + '"\\s+Color="(#[0-9A-Fa-f]+)"').exec(xaml);
  yes('ui.xaml: ' + n + ' starts as Forge\'s ' + (forge ? forge.colors[n] : '?') + (m ? ' (it is ' + m[1] + ')' : ' (not found)'),
    !!m && !!forge && m[1].toUpperCase() === forge.colors[n].toUpperCase());
}

// ---- 4. the launcher measures the same pairs and says what it finds -------
yes('Themes.cs: MinContrast is 4.5', /public const double MinContrast = 4\.5;/.test(themes));
const tn = /TextNames = new string\[\] \{([^}]*)\}/.exec(themes);
const sn = /SurfaceNames = new string\[\] \{([^}]*)\}/.exec(themes);
const list = (m) => (m ? m[1].match(/"(\w+)"/g).map((s) => s.replace(/"/g, '')) : []);
yes('Themes.cs: the text colours it measures are ' + TEXT.join(', '), list(tn).join(',') === TEXT.join(','));
yes('Themes.cs: the surfaces it measures them on are ' + SURFACES.join(', '), list(sn).join(',') === SURFACES.join(','));
yes('Themes.cs: AccentInk is measured on Accent', /ColorOf\(t, "AccentInk"\)[\s\S]{0,80}accent/.test(themes));
yes('Themes.cs: a pair just under the line is rounded down, never shown as 4.5', /Math\.Floor\(r \* 10\) \/ 10/.test(themes));

const shell = read('launcher', 'app', 'Shell.cs');
const editor = /static void BuildThemeEditor\(\)[\s\S]*?\n        \}\n/.exec(shell);
yes('Shell.cs: the DIY editor measures the colours on screen', !!editor && /Themes\.LowContrast\(cur\)/.test(editor[0]));
yes('Shell.cs: and says which text would be hard to read, and the 4.5 to 1 it needs',
  !!editor && editor[0].includes('hard to read') && editor[0].includes('4.5 to 1'));
const apply = /static void ApplyCustomTheme\(\)[\s\S]*?\n        \}\n/.exec(shell);
yes('Shell.cs: Use these colours logs it too', !!apply && /Themes\.LowContrast\(/.test(apply[0]) && apply[0].includes('hard to read'));

// ---- 5. the measure goes red on the palette it replaced -------------------
// Forge as it was before #2771: Faint 2.37 on CardHover, Bad 3.33.
const old = Object.assign({}, forge ? forge.colors : {}, { Faint: '#66594A', Muted: '#9C8D79', Bad: '#BC5039' });
const oldLow = forge ? low(old) : [];
yes('the measure finds the old Forge Faint and Bad under 4.5 to 1 (' + oldLow.length + ' pairs)',
  oldLow.some((s) => s.startsWith('Faint on CardHover')) && oldLow.some((s) => s.startsWith('Bad on Card')));
yes('and passes plain black on white', low(Object.assign({}, old, {
  Bg: '#FFFFFF', Panel: '#FFFFFF', Card: '#FFFFFF', CardHover: '#FFFFFF', Deep: '#FFFFFF',
  Ink: '#000000', Muted: '#000000', Faint: '#000000', Ok: '#000000', Warn: '#000000', Bad: '#000000',
  Accent: '#FFFFFF', AccentInk: '#000000' })).length === 0);

// ---- 6. the setup program draws its window in Forge from Themes.cs -------
// It kept its own copy of the old Forge in its markup and in literal colours,
// so #2771 left the first window a new tester sees at 2.6 to 1 (#2851).
const proj = read('installer', 'setup', 'Setup.csproj');
yes('Setup.csproj compiles the launcher\'s Themes.cs into the setup program',
  proj.includes('<Compile Include="..\\..\\launcher\\app\\Themes.cs"><Link>Themes.cs</Link></Compile>'));

// Themes.cs is compiled on its own there, so it may name no other class from
// launcher\app. Comments and strings are taken out before looking.
const code = (t) => t.replace(/\/\/.*$/gm, '').replace(/"(?:[^"\\]|\\.)*"/g, '""');
const appDir = path.join(REPO_DIR, 'launcher', 'app');
const others = new Set();
for (const f of fs.readdirSync(appDir)) {
  if (!f.endsWith('.cs') || f === 'Themes.cs') continue;
  const re = /\b(?:class|struct|enum|interface)\s+(\w+)/g;
  let c;
  const t = code(read('launcher', 'app', f));
  while ((c = re.exec(t))) others.add(c[1]);
}
others.delete('Theme'); others.delete('Themes');
const themesCode = code(themes);
const leans = Array.from(others).filter((n) => new RegExp('(?<![.\\w])' + n + '\\b').test(themesCode));
yes('Themes.cs uses nothing else from launcher\\app' + (leans.length ? ' (it names ' + leans.join(', ') + ')' : ''),
  others.size > 20 && leans.length === 0);

const boot = read('installer', 'setup', 'Bootstrap.cs');
yes('Bootstrap.cs draws the window in Forge straight after it is built',
  /win = \(Window\)XamlReader\.Parse\(Ui\);\s*(?:\/\/.*\s*)*Thornswood\.Themes\.Apply\(win, "Forge"\);/.test(boot));
const hexes = (boot.match(/#[0-9A-Fa-f]{6,8}\b/g) || []).filter((h) => h.toUpperCase() !== '#16808080');
yes('Bootstrap.cs holds no colour of its own, only the hatch lines' + (hexes.length ? ' (it has ' + hexes.join(', ') + ')' : ''),
  hexes.length === 0);
yes('its markup defines none of the sixteen colours itself',
  !NAMES.some((n) => new RegExp('x:Key=""' + n + '""').test(boot)));
const statics = (boot.match(/\{StaticResource (\w+)\}/g) || []).map((m) => m.slice(16, -1)).filter((n) => NAMES.includes(n));
yes('its markup reads every colour as a DynamicResource' + (statics.length ? ' (StaticResource ' + statics.join(', ') + ')' : ''),
  statics.length === 0);
const used = new Set();
let u;
const dynRe = /\{DynamicResource (\w+)\}/g;
while ((u = dynRe.exec(boot))) used.add(u[1]);
const bRe = /\bB\((?:[^;]*?)\)/g;
while ((u = bRe.exec(boot))) (u[0].match(/"(\w+)"/g) || []).forEach((q) => used.add(q.replace(/"/g, '')));
const unknown = Array.from(used).filter((n) => !NAMES.includes(n));
yes('every colour it names is one of the sixteen in Themes.cs (' + used.size + ' used)' + (unknown.length ? ' (not: ' + unknown.join(', ') + ')' : ''),
  used.size >= 10 && unknown.length === 0);
yes('the old tan for a close fit and a missing Skyrim is Warn now', /txtRoom\.Foreground = B\("Warn"\)/.test(boot) && /txtSkyrim\.Foreground = B\("Warn"\)/.test(boot));
// The setup window also writes text in the accent ("Skyrim is here" and the
// three Read them links), which the launcher's rule leaves to each theme.
if (forge) {
  const bg = over(rgba(forge.colors.Bg), { a: 255, r: 0, g: 0, b: 0 });
  const lowAccent = SURFACES.filter((s) => {
    const under = s === 'Bg' ? bg : over(rgba(forge.colors[s]), bg);
    return contrast(over(rgba(forge.colors.Accent), under), under) < MIN;
  });
  yes('Forge\'s Accent, which the setup window writes in, is 4.5 to 1 or more on every surface' + (lowAccent.length ? ' (not on ' + lowAccent.join(', ') + ')' : ''),
    lowAccent.length === 0);
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
