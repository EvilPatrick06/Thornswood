const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('proto', {
  ready: () => ipcRenderer.invoke('ready'),
  play: () => ipcRenderer.invoke('play'),
});
// Whether the page is hidden to Chromium, which holds back animation frames,
// and with them the ready the page sends after two of them.
const visibility = () => ipcRenderer.send('log', `visibility ${document.visibilityState}`);
window.addEventListener('DOMContentLoaded', visibility);
document.addEventListener('visibilitychange', visibility);
