// The Electron prototype for the launcher stack study (#3209): the window is
// index.html in Electron's own Chromium. README.md has the contract every
// prototype keeps.
const { app, BrowserWindow, ipcMain } = require('electron');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const readyFile = process.env.PROTO_READY;

// On One the window never said ready and nothing reached stdout or stderr
// (27 Oct, runs 2 and 3), so what happens on the way there goes to a file
// beside the ready file, which Measure-Prototypes.ps1 keeps for such a run.
const say = (line) => { if (readyFile) fs.appendFileSync(readyFile + '.log', `${Date.now()} ${line}\n`); };
process.on('uncaughtException', (e) => { say(`main: ${e.stack || e}`); app.exit(1); });
app.on('child-process-gone', (e, d) => say(`${d.type} process gone: ${d.reason}, exit code ${d.exitCode}`));
app.once('gpu-info-update', () => say(`gpu: ${JSON.stringify(app.getGPUFeatureStatus())}`));
ipcMain.on('log', (e, line) => say(`page: ${line}`));

ipcMain.handle('ready', () => { say('ready'); if (readyFile) fs.writeFileSync(readyFile, 'ready'); });
ipcMain.handle('play', () => {
  const child = process.platform === 'win32'
    ? spawn('cmd.exe', ['/c', 'exit', '0'], { windowsHide: true })
    : spawn('true');
  child.on('spawn', () => { if (readyFile) fs.writeFileSync(readyFile + '.active', 'active'); });
});

app.whenReady().then(() => {
  say('app ready');
  const win = new BrowserWindow({
    width: 1220,
    height: 800,
    title: 'Thornswood electron',
    backgroundColor: '#14110e',
    autoHideMenuBar: true,
    webPreferences: { preload: path.join(__dirname, 'preload.js'), autoplayPolicy: 'no-user-gesture-required' },
  });
  say('window made');
  win.on('show', () => say('window shown'));
  win.webContents.on('did-finish-load', () => say('page loaded'));
  win.webContents.on('did-fail-load', (e, code, text) => say(`page failed: ${code} ${text}`));
  win.webContents.on('render-process-gone', (e, d) => say(`page process gone: ${d.reason}`));
  win.webContents.on('preload-error', (e, file, err) => say(`preload failed: ${err}`));
  win.webContents.on('console-message', (e) => say(`console: ${e.message}`));
  win.loadFile(path.join(__dirname, 'index.html'));
});
app.on('window-all-closed', () => app.quit());
