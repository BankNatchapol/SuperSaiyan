import { contextBridge, ipcRenderer } from "electron";
import type { AppPreferences, CommandRequest, ControlTransport } from "@supersaiyan/control-protocol";

function subscribe<T>(channel: string, listener: (event: T) => void): () => void {
  const wrapped = (_event: Electron.IpcRendererEvent, payload: T) => listener(payload);
  ipcRenderer.on(channel, wrapped);
  return () => ipcRenderer.removeListener(channel, wrapped);
}

const transport: ControlTransport = {
  listRepositories: () => ipcRenderer.invoke("workspace:list"),
  addRepository: (path) => ipcRenderer.invoke("workspace:add", path),
  removeRepository: (repoId) => ipcRenderer.invoke("workspace:remove", repoId),
  getSnapshot: (repoId, refresh) => ipcRenderer.invoke("workspace:snapshot", repoId, refresh),
  installOrRepair: (repoId) => ipcRenderer.invoke("workspace:repair", repoId),
  startCommand: (repoId, request: CommandRequest) => ipcRenderer.invoke("command:start", repoId, request),
  interruptCommand: (sessionId) => ipcRenderer.invoke("command:interrupt", sessionId),
  startRunnerCommand: (repoId, request: CommandRequest) => ipcRenderer.invoke("runner:start", repoId, request),
  interruptRunner: (sessionId) => ipcRenderer.invoke("runner:interrupt", sessionId),
  createTerminal: (repoId, kind) => ipcRenderer.invoke("terminal:create", repoId, kind),
  writeTerminal: (sessionId, data) => ipcRenderer.invoke("terminal:write", sessionId, data),
  resizeTerminal: (sessionId, cols, rows) => ipcRenderer.invoke("terminal:resize", sessionId, cols, rows),
  closeTerminal: (sessionId) => ipcRenderer.invoke("terminal:close", sessionId),
  moveBoardCard: (repoId, issueNumber, targetStatus) => ipcRenderer.invoke("board:move", repoId, issueNumber, targetStatus),
  openPath: (repoId, relativePath) => ipcRenderer.invoke("external:path", repoId, relativePath),
  openExternal: (url) => ipcRenderer.invoke("external:url", url),
  getPreferences: () => ipcRenderer.invoke("preferences:get"),
  updatePreferences: (preferences: Partial<AppPreferences>) => ipcRenderer.invoke("preferences:update", preferences),
  onTerminalData: (listener) => subscribe("terminal:data", listener),
  onTerminalExit: (listener) => subscribe("terminal:exit", listener),
  onRunnerEvent: (listener) => subscribe("runner:event", listener),
  onRepositoryChanged: (listener) => subscribe("workspace:changed", listener),
};

contextBridge.exposeInMainWorld("supersaiyan", transport);
