'use strict';
// launcher-csc.js
// For the JavaScript harnesses that compile lifted launcher C#, what
// tests\Launcher-Csc.ps1 is for the PowerShell ones (#498): the Roslyn csc that
// MSBuild runs when it builds launcher\app\Thornswood.csproj, found the way
// scripts\release\Find-MSBuild.ps1 finds MSBuild (vswhere, newest install with
// the MSBuild component), and the LangVersion that project names. So a harness
// compiles launcher code with the compiler and the C# version the build uses,
// not the in-box .NET Framework csc, which stops at C# 5.
//
//   const { csc, langVersion } = require('./launcher-csc');
//   csc is null on a machine without the Build Tools.

const fs = require('fs');
const path = require('path');
const cp = require('child_process');

function findCsc() {
  const pf86 = process.env['ProgramFiles(x86)'] || process.env.ProgramFiles || 'C:\\Program Files (x86)';
  const vswhere = path.join(pf86, 'Microsoft Visual Studio', 'Installer', 'vswhere.exe');
  if (!fs.existsSync(vswhere)) return null;
  let out = '';
  try {
    out = cp.execFileSync(vswhere, ['-latest', '-products', '*', '-requires', 'Microsoft.Component.MSBuild',
      '-find', 'MSBuild\\**\\Bin\\MSBuild.exe'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
  } catch (e) { return null; }
  const msbuild = out.split(/\r?\n/).map((l) => l.trim()).find((l) => l && !/\\(amd64|arm64)\\/i.test(l));
  if (!msbuild) return null;
  const roslyn = path.join(path.dirname(msbuild), 'Roslyn', 'csc.exe');
  return fs.existsSync(roslyn) ? roslyn : null;
}

const proj = fs.readFileSync(path.join(__dirname, '..', 'launcher', 'app', 'Thornswood.csproj'), 'utf8');
const m = /<LangVersion>([^<]+)<\/LangVersion>/.exec(proj);
if (!m) throw new Error('launcher\\app\\Thornswood.csproj names no LangVersion, so the harnesses cannot compile at the version the build does.');

module.exports = { csc: findCsc(), langVersion: m[1].trim() };
