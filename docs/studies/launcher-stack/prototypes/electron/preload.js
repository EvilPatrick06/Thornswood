const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('proto', {
  ready: () => ipcRenderer.invoke('ready'),
  play: () => ipcRenderer.invoke('play'),
});
