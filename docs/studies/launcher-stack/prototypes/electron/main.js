// The Electron prototype for the launcher stack study (#3209): the window is
// web\index.html in Electron's own Chromium. README.md has the contract every
// prototype keeps.
const { app, BrowserWindow, ipcMain } = require('electron');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const readyFile = process.env.PROTO_READY;

ipcMain.handle('ready', () => { if (readyFile) fs.writeFileSync(readyFile, 'ready'); });
ipcMain.handle('play', () => {
  const child = process.platform === 'win32'
    ? spawn('cmd.exe', ['/c', 'exit', '0'], { windowsHide: true })
    : spawn('true');
  child.on('spawn', () => { if (readyFile) fs.writeFileSync(readyFile + '.active', 'active'); });
});

app.whenReady().then(() => {
  const win = new BrowserWindow({
    width: 1220,
    height: 800,
    title: 'Thornswood electron',
    backgroundColor: '#14110e',
    autoHideMenuBar: true,
    webPreferences: { preload: path.join(__dirname, 'preload.js'), autoplayPolicy: 'no-user-gesture-required' },
  });
  win.loadFile(path.join(__dirname, 'index.html'));
});
app.on('window-all-closed', () => app.quit());
