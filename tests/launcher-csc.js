'use strict';
// launcher-csc.js
// For the JavaScript harnesses that compile launcher C#, what
// tests\Launcher-Csc.ps1 is for the PowerShell ones (#498): the code is built
// the way launcher\app\Thornswood.csproj builds it, by the .NET 10 SDK at the
// project's LangVersion, against its target framework and every package it
// references (#4823). That works on Linux as well as on Windows, so a harness
// compiles and runs launcher code everywhere.
//
//   const lc = require('./launcher-csc');
//   const dll = lc.build({ sources: [code], files: [path], exe: true });
//   const r = lc.run(dll, ['arg']);   // { status, stdout, stderr }
//
//   lc.dotnet       the dotnet that builds the launcher: the one on PATH, else
//                   DOTNET_ROOT's, else ~/.dotnet's; null when there is none.
//   lc.langVersion  the LangVersion the project names.
//   lc.framework    the TargetFramework the project names.
//   lc.onWindows    true on Windows, for a harness whose code under test does
//                   something only Windows has.
//
// build() throws with the compiler's words when the code is refused, and
// when there is no SDK. The builds go under out/harness/ in the repository,
// which git ignores, in a folder named by a hash of the project and every
// source, so the same code is built once, and the folder and the assembly
// carry that hash in their name. tests\Launcher-Csc.ps1 writes the same
// project the same way.
//
// Until #4823 this found the Roslyn csc in Visual Studio's Build Tools, which
// only Windows has, and every compile here was SKIP off Windows (#3005).

const fs = require('fs');
const os = require('os');
const path = require('path');
const cp = require('child_process');
const crypto = require('crypto');

const repo = path.resolve(__dirname, '..');
const proj = fs.readFileSync(path.join(repo, 'launcher', 'app', 'Thornswood.csproj'), 'utf8');
const onWindows = process.platform === 'win32';

function prop(name) {
  const m = new RegExp('<' + name + '>([^<]*)</' + name + '>').exec(proj);
  return m ? m[1].trim() : null;
}
const langVersion = prop('LangVersion');
if (!langVersion) throw new Error('launcher\\app\\Thornswood.csproj names no LangVersion, so the harnesses cannot compile at the version the build does.');
const framework = prop('TargetFramework');
if (!framework) throw new Error('launcher\\app\\Thornswood.csproj names no TargetFramework, so the harnesses cannot compile against what the build does.');

function esc(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&apos;');
}
const copied = ['Nullable', 'ImplicitUsings', 'AllowUnsafeBlocks', 'EnableWindowsTargeting']
  .filter((n) => prop(n) !== null).map((n) => '    <' + n + '>' + esc(prop(n)) + '</' + n + '>');
const packages = [];
for (const m of proj.matchAll(/<PackageReference\s+Include="([^"]+)"\s+Version="([^"]+)"\s*\/>/g)) {
  packages.push('    <PackageReference Include="' + esc(m[1]) + '" Version="' + esc(m[2]) + '" />');
}

function findDotnet() {
  const exe = onWindows ? 'dotnet.exe' : 'dotnet';
  for (const dir of (process.env.PATH || '').split(path.delimiter)) {
    if (dir && fs.existsSync(path.join(dir, exe))) return path.join(dir, exe);
  }
  for (const root of [process.env.DOTNET_ROOT, path.join(os.homedir(), '.dotnet')]) {
    if (root && fs.existsSync(path.join(root, exe))) return path.join(root, exe);
  }
  return null;
}
const dotnet = findDotnet();

function build(opts) {
  const sources = (opts && opts.sources) || [];
  const files = ((opts && opts.files) || []).map((f) => {
    if (!fs.existsSync(f)) throw new Error('launcher-csc build: ' + f + ' is not there.');
    return fs.realpathSync(f);
  });
  if (!dotnet) throw new Error('launcher-csc build: the .NET SDK the launcher builds with is not on this machine. Developer-Guide.md "Setting up a machine" has the install line.');
  if (sources.length + files.length === 0) throw new Error('launcher-csc build: nothing to build.');

  let text = [
    '<Project Sdk="Microsoft.NET.Sdk">',
    '  <PropertyGroup>',
    '    <OutputType>' + (opts.exe ? 'Exe' : 'Library') + '</OutputType>',
    '    <TargetFramework>' + framework + '</TargetFramework>',
    '    <LangVersion>' + langVersion + '</LangVersion>',
    ...copied,
    '    <AssemblyName>ASSEMBLY_NAME</AssemblyName>',
    '    <RootNamespace>Thornswood</RootNamespace>',
    '    <EnableDefaultItems>false</EnableDefaultItems>',
    '    <UseAppHost>false</UseAppHost>',
    '    <GenerateDocumentationFile>false</GenerateDocumentationFile>',
    '    <SatelliteResourceLanguages>en</SatelliteResourceLanguages>',
    '  </PropertyGroup>',
    '  <ItemGroup>',
    ...packages,
    '  </ItemGroup>',
    '  <ItemGroup>',
    ...sources.map((s, i) => '    <Compile Include="source' + i + '.cs" />'),
    ...files.map((f) => '    <Compile Include="' + esc(f) + '" />'),
    '  </ItemGroup>',
    '</Project>',
  ].join('\n') + '\n';

  // The folder and the assembly are named by everything in the build: .NET
  // loads one assembly of a name, and the same code is built once.
  const h = crypto.createHash('sha256');
  h.update(text);
  for (const s of sources) h.update('\0' + s);
  for (const f of files) h.update('\0' + fs.readFileSync(f, 'utf8'));
  const hash = h.digest('hex').slice(0, 24);
  const name = 'launcher-code-' + hash;
  text = text.replace('ASSEMBLY_NAME', name);
  const base = path.join(repo, 'out', 'harness');
  const done = path.join(base, hash);
  const dll = path.join(done, name + '.dll');
  if (fs.existsSync(dll)) return dll;

  const work = path.join(base, 'building-' + crypto.randomBytes(6).toString('hex'));
  fs.mkdirSync(work, { recursive: true });
  try {
    fs.writeFileSync(path.join(work, 'launcher-code.csproj'), text);
    sources.forEach((s, i) => fs.writeFileSync(path.join(work, 'source' + i + '.cs'), s));
    const bin = path.join(work, 'bin');
    const r = cp.spawnSync(dotnet, ['build', path.join(work, 'launcher-code.csproj'), '-c', 'Release', '-o', bin,
      '-nologo', '-v:q', '-clp:NoSummary;ErrorsOnly'], { encoding: 'utf8' });
    if (r.status !== 0 || !fs.existsSync(path.join(bin, name + '.dll'))) {
      throw new Error('launcher-csc build: the .NET SDK refused it:\n' + ((r.stdout || '') + (r.stderr || '')).trim());
    }
    // Into place in one rename. Another harness may have built the same code
    // meanwhile; its copy is the same, and is used.
    try { fs.renameSync(bin, done); } catch (e) { if (!fs.existsSync(dll)) throw e; }
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
  }
  return dll;
}

function run(dll, args, options) {
  const r = cp.spawnSync(dotnet, [dll, ...(args || [])], Object.assign({ encoding: 'utf8', timeout: 120000 }, options || {}));
  return { status: r.status, stdout: r.stdout || '', stderr: r.stderr || '' };
}

module.exports = { onWindows, dotnet, langVersion, framework, build, run };
