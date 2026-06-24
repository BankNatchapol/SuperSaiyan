import {
  app,
  BrowserWindow,
  dialog,
  ipcMain,
  protocol,
  shell,
  type IpcMainInvokeEvent,
} from "electron";
import started from "electron-squirrel-startup";
import { spawn, type ChildProcess } from "node:child_process";
import { existsSync } from "node:fs";
import { realpath } from "node:fs/promises";
import { createRequire } from "node:module";
import { join, resolve } from "node:path";
import type * as NodePty from "node-pty";
import {
  RepositoryRegistry,
  RepositoryWatchService,
  buildSnapshot,
  createSessionId,
  isPathInside,
  moveBoardCard,
  registerRepository,
  runnerEventsFromClaudeJsonLine,
} from "@supersaiyan/control-core";
import {
  boardMoveSchema,
  commandRequestSchema,
  repoIdSchema,
  repositoryPathSchema,
  terminalIdSchema,
  type AppPreferences,
  type CommandRequest,
  type RepositoryRecord,
  type RepositorySnapshot,
  type RunnerSession,
  type TerminalSession,
} from "@supersaiyan/control-protocol";

if (started) app.quit();

const e2eMode = process.env.SUPERSAIYAN_E2E === "1";
const e2eRecordDir = process.env.SUPERSAIYAN_E2E_RECORD_DIR;

if (e2eMode && process.env.SUPERSAIYAN_E2E_USER_DATA) {
  app.setPath("userData", process.env.SUPERSAIYAN_E2E_USER_DATA);
}

if (!app.isPackaged) app.commandLine.appendSwitch("remote-debugging-port", "9223");

protocol.registerSchemesAsPrivileged([
  { scheme: "supersaiyan", privileges: { standard: true, secure: true, supportFetchAPI: true } },
]);

let mainWindow: BrowserWindow | undefined;
let registry: RepositoryRegistry;
let state: { repositories: RepositoryRecord[]; preferences: AppPreferences };
const snapshots = new Map<string, RepositorySnapshot>();
const watchers = new RepositoryWatchService();
const terminals = new Map<string, { session: TerminalSession; process: NodePty.IPty }>();
const runners = new Map<string, { session: RunnerSession; process: ChildProcess; repoId: string }>();
const mutatingSessions = new Map<string, string>();
const require = createRequire(__filename);

function ptyRuntime(): typeof NodePty {
  return app.isPackaged
    ? require(join(process.resourcesPath, "node-pty"))
    : require("node-pty");
}

function send(channel: string, payload: unknown): void {
  if (mainWindow && !mainWindow.isDestroyed()) mainWindow.webContents.send(channel, payload);
}

function sendRunnerEvent(event: import("@supersaiyan/control-protocol").RunnerEvent): void {
  send("runner:event", event);
}

function assertTrusted(event: IpcMainInvokeEvent): void {
  if (!mainWindow || event.sender.id !== mainWindow.webContents.id) throw new Error("Untrusted IPC sender");
}

function repositoryFor(id: string): RepositoryRecord {
  repoIdSchema.parse(id);
  const repository = state.repositories.find((item) => item.id === id);
  if (!repository) throw new Error("Repository is not registered");
  return repository;
}

async function persist(): Promise<void> {
  await registry.save(state);
}

async function recordE2eEvent(name: string, payload: unknown): Promise<void> {
  if (!e2eMode || !e2eRecordDir) return;
  const { appendFile, mkdir } = await import("node:fs/promises");
  await mkdir(e2eRecordDir, { recursive: true });
  await appendFile(
    join(e2eRecordDir, "electron-events.jsonl"),
    `${JSON.stringify({ name, payload, at: new Date().toISOString() })}\n`,
  );
}

async function snapshotFor(repoId: string, refresh = false): Promise<RepositorySnapshot> {
  const existing = snapshots.get(repoId);
  if (existing && !refresh) return existing;
  const repository = repositoryFor(repoId);
  const snapshot = await buildSnapshot(repository);
  snapshots.set(repoId, snapshot);
  watchers.watch(repository, () => {
    snapshots.delete(repoId);
    send("workspace:changed", { repoId });
  });
  return snapshot;
}

function validateTerminalText(data: string): void {
  if (Buffer.byteLength(data, "utf8") > 64 * 1024) throw new Error("Terminal write is too large");
}

function spawnTerminal(repository: RepositoryRecord, title: string, kind: TerminalSession["kind"], command?: { file: string; args: string[]; initialInput?: string }): TerminalSession {
  const id = createSessionId();
  const shellPath = command?.file || state.preferences.shell || process.env.SHELL || "/bin/zsh";
  const args = command?.args || ["-l"];
  const environment = Object.fromEntries(
    Object.entries(process.env).filter((entry): entry is [string, string] => typeof entry[1] === "string"),
  );
  delete environment.npm_config_prefix;
  delete environment.NPM_CONFIG_PREFIX;
  const term = ptyRuntime().spawn(shellPath, args, {
    name: "xterm-256color",
    cols: 110,
    rows: 34,
    cwd: repository.path,
    env: { ...environment, TERM: "xterm-256color", COLORTERM: "truecolor" },
  });
  const session: TerminalSession = { id, repoId: repository.id, title, kind, active: true };
  terminals.set(id, { session, process: term });
  term.onData((data) => send("terminal:data", { sessionId: id, data }));
  term.onExit(({ exitCode }) => {
    session.active = false;
    terminals.delete(id);
    if (mutatingSessions.get(repository.id) === id) mutatingSessions.delete(repository.id);
    snapshots.delete(repository.id);
    send("terminal:exit", { sessionId: id, exitCode });
    send("workspace:changed", { repoId: repository.id });
  });
  if (command?.initialInput) setTimeout(() => term.write(`${command.initialInput}\r`), 2000);
  return session;
}

function supersaiyanCommand(request: CommandRequest): string {
  const cleanArgs = request.args.map((arg) => {
    if (/[\r\n]/.test(arg)) throw new Error("Command arguments cannot contain newlines");
    if (!/^[A-Za-z0-9._:/=-]+$/.test(arg)) throw new Error(`Unsupported command argument: ${arg}`);
    return arg;
  });
  return `/supersaiyan ${request.verb}${cleanArgs.length ? ` ${cleanArgs.join(" ")}` : ""}`;
}

function processRunnerLine(sessionId: string, line: string): void {
  for (const event of runnerEventsFromClaudeJsonLine(sessionId, line)) sendRunnerEvent(event);
}

function spawnRunner(repository: RepositoryRecord, request: CommandRequest): RunnerSession {
  const id = createSessionId();
  const command = supersaiyanCommand(request);
  const environment = Object.fromEntries(
    Object.entries(process.env).filter((entry): entry is [string, string] => typeof entry[1] === "string"),
  );
  delete environment.npm_config_prefix;
  delete environment.NPM_CONFIG_PREFIX;
  const child = spawn("claude", [
    "-p",
    "--verbose",
    "--output-format", "stream-json",
    "--include-partial-messages",
    "--name", `supersaiyan-ui-${repository.name}-${request.verb}`,
    command,
  ], {
    cwd: repository.path,
    env: environment,
    stdio: ["ignore", "pipe", "pipe"],
  });
  const session: RunnerSession = { id, repoId: repository.id, title: `SuperSaiyan · ${request.verb}`, command: request, active: true };
  runners.set(id, { session, process: child, repoId: repository.id });
  sendRunnerEvent({ type: "init", sessionId: id });

  let stdoutBuffer = "";
  let stderrBuffer = "";
  child.stdout.setEncoding("utf8");
  child.stderr.setEncoding("utf8");
  child.stdout.on("data", (data: string) => {
    stdoutBuffer += data;
    const lines = stdoutBuffer.split(/\r?\n/);
    stdoutBuffer = lines.pop() ?? "";
    for (const line of lines) processRunnerLine(id, line);
  });
  child.stderr.on("data", (data: string) => {
    stderrBuffer += data;
    const lines = stderrBuffer.split(/\r?\n/);
    stderrBuffer = lines.pop() ?? "";
    for (const line of lines) if (line.trim()) sendRunnerEvent({ type: "error", sessionId: id, message: line.trim() });
  });
  child.on("error", (error) => {
    sendRunnerEvent({ type: "error", sessionId: id, message: error.message });
  });
  child.on("exit", (exitCode) => {
    if (stdoutBuffer.trim()) processRunnerLine(id, stdoutBuffer);
    if (stderrBuffer.trim()) sendRunnerEvent({ type: "error", sessionId: id, message: stderrBuffer.trim() });
    session.active = false;
    runners.delete(id);
    if (mutatingSessions.get(repository.id) === id) mutatingSessions.delete(repository.id);
    snapshots.delete(repository.id);
    sendRunnerEvent({ type: "exit", sessionId: id, exitCode: exitCode ?? 0 });
    send("workspace:changed", { repoId: repository.id });
  });
  return session;
}

function toolkitInstallerPath(): string {
  if (app.isPackaged) return join(process.resourcesPath, "install.sh");
  return resolve(app.getAppPath(), "../../install.sh");
}

function registerIpc(): void {
  ipcMain.handle("workspace:list", (event) => {
    assertTrusted(event);
    return state.repositories;
  });
  ipcMain.handle("workspace:add", async (event, path?: string) => {
    assertTrusted(event);
    let selected = path;
    if (!selected) {
      if (e2eMode) {
        selected = process.env.SUPERSAIYAN_E2E_PICKER_RESULT || undefined;
      } else {
        const result = await dialog.showOpenDialog(mainWindow!, { properties: ["openDirectory"] });
        selected = result.canceled ? undefined : result.filePaths[0];
      }
    }
    if (!selected) return null;
    repositoryPathSchema.parse(selected);
    const repository = await registerRepository(selected);
    state.repositories = [...state.repositories.filter((item) => item.id !== repository.id), repository];
    await persist();
    snapshots.delete(repository.id);
    return repository;
  });
  ipcMain.handle("workspace:remove", async (event, repoId: string) => {
    assertTrusted(event);
    repositoryFor(repoId);
    state.repositories = state.repositories.filter((item) => item.id !== repoId);
    snapshots.delete(repoId);
    await watchers.unwatch(repoId);
    await persist();
  });
  ipcMain.handle("workspace:snapshot", async (event, repoId: string, refresh?: boolean) => {
    assertTrusted(event);
    return snapshotFor(repoId, Boolean(refresh));
  });
  ipcMain.handle("workspace:repair", (event, repoId: string) => {
    assertTrusted(event);
    const repository = repositoryFor(repoId);
    const installer = state.preferences.installerPath || toolkitInstallerPath();
    if (!existsSync(installer)) throw new Error(`Installer not found: ${installer}`);
    return spawnTerminal(repository, "Install / Repair", "supersaiyan", { file: "/bin/bash", args: [installer, repository.path] });
  });
  ipcMain.handle("command:start", (event, repoId: string, input: unknown) => {
    assertTrusted(event);
    const repository = repositoryFor(repoId);
    const request = commandRequestSchema.parse(input);
    const activeSessionId = mutatingSessions.get(repoId);
    if (activeSessionId && request.verb !== "stop") throw new Error("A SuperSaiyan command is already active for this repository");
    if (activeSessionId && request.verb === "stop") {
      terminals.get(activeSessionId)?.process.write("\x03");
      runners.get(activeSessionId)?.process.kill("SIGINT");
      mutatingSessions.delete(repoId);
    }
    const command = supersaiyanCommand(request);
    const session = spawnTerminal(repository, `SuperSaiyan · ${request.verb}`, "supersaiyan", {
      file: "claude",
      args: ["--name", `supersaiyan-ui-${repository.name}-${request.verb}`],
      initialInput: command,
    });
    mutatingSessions.set(repoId, session.id);
    return session;
  });
  ipcMain.handle("runner:start", (event, repoId: string, input: unknown) => {
    assertTrusted(event);
    const repository = repositoryFor(repoId);
    const request = commandRequestSchema.parse(input);
    const activeSessionId = mutatingSessions.get(repoId);
    if (activeSessionId && request.verb !== "stop") throw new Error("A SuperSaiyan command is already active for this repository");
    if (activeSessionId && request.verb === "stop") {
      terminals.get(activeSessionId)?.process.write("\x03");
      runners.get(activeSessionId)?.process.kill("SIGINT");
      mutatingSessions.delete(repoId);
    }
    const session = spawnRunner(repository, request);
    mutatingSessions.set(repoId, session.id);
    return session;
  });
  ipcMain.handle("command:interrupt", (event, sessionId: string) => {
    assertTrusted(event);
    terminalIdSchema.parse(sessionId);
    terminals.get(sessionId)?.process.write("\x03");
  });
  ipcMain.handle("runner:interrupt", (event, sessionId: string) => {
    assertTrusted(event);
    terminalIdSchema.parse(sessionId);
    const runner = runners.get(sessionId);
    if (!runner) return;
    runner.process.kill("SIGINT");
    mutatingSessions.delete(runner.repoId);
  });
  ipcMain.handle("terminal:create", (event, repoId: string, kind: TerminalSession["kind"]) => {
    assertTrusted(event);
    if (kind !== "shell" && kind !== "supersaiyan") throw new Error("Unsupported terminal kind");
    return spawnTerminal(repositoryFor(repoId), kind === "shell" ? "Shell" : "SuperSaiyan", kind);
  });
  ipcMain.handle("terminal:write", (event, sessionId: string, data: string) => {
    assertTrusted(event);
    terminalIdSchema.parse(sessionId);
    validateTerminalText(data);
    const terminal = terminals.get(sessionId);
    if (!terminal) throw new Error("Terminal session not found");
    terminal.process.write(data);
  });
  ipcMain.handle("terminal:resize", (event, sessionId: string, cols: number, rows: number) => {
    assertTrusted(event);
    terminalIdSchema.parse(sessionId);
    if (!Number.isInteger(cols) || !Number.isInteger(rows) || cols < 20 || rows < 5 || cols > 500 || rows > 200) return;
    terminals.get(sessionId)?.process.resize(cols, rows);
  });
  ipcMain.handle("terminal:close", (event, sessionId: string) => {
    assertTrusted(event);
    terminalIdSchema.parse(sessionId);
    terminals.get(sessionId)?.process.kill();
  });
  ipcMain.handle("board:move", async (event, repoId: string, issueNumber: number, targetStatus: "Backlog" | "Ready") => {
    assertTrusted(event);
    boardMoveSchema.parse({ repoId, issueNumber, targetStatus });
    await moveBoardCard(repositoryFor(repoId), issueNumber, targetStatus);
    snapshots.delete(repoId);
    send("workspace:changed", { repoId });
  });
  ipcMain.handle("external:path", async (event, repoId: string, candidate: string) => {
    assertTrusted(event);
    const repository = repositoryFor(repoId);
    if (!isPathInside(repository, candidate)) throw new Error("Path is outside the registered repository");
    const path = await realpath(resolve(repository.path, candidate));
    if (!isPathInside(repository, path)) throw new Error("Resolved path is outside the registered repository");
    if (e2eMode) await recordE2eEvent("external:path", { repoId, path });
    else await shell.openPath(path);
  });
  ipcMain.handle("external:url", async (event, url: string) => {
    assertTrusted(event);
    const parsed = new URL(url);
    if (parsed.protocol !== "https:" || !["github.com", "www.github.com"].includes(parsed.hostname)) throw new Error("Only GitHub HTTPS links may be opened");
    if (e2eMode) await recordE2eEvent("external:url", { url: parsed.toString() });
    else await shell.openExternal(parsed.toString());
  });
  ipcMain.handle("preferences:get", (event) => {
    assertTrusted(event);
    return state.preferences;
  });
  ipcMain.handle("preferences:update", async (event, update: Partial<AppPreferences>) => {
    assertTrusted(event);
    state.preferences = {
      ...state.preferences,
      ...update,
      idleRefreshSeconds: Math.max(10, Math.min(600, Number(update.idleRefreshSeconds ?? state.preferences.idleRefreshSeconds))),
      activeRefreshSeconds: Math.max(5, Math.min(120, Number(update.activeRefreshSeconds ?? state.preferences.activeRefreshSeconds))),
      theme: "aura-dark",
    };
    await persist();
    return state.preferences;
  });
}

async function createWindow(): Promise<void> {
  mainWindow = new BrowserWindow({
    width: 1440,
    height: 920,
    minWidth: 960,
    minHeight: 680,
    titleBarStyle: "hiddenInset",
    transparent: true,
    backgroundColor: "#00000000",
    vibrancy: "under-window",
    visualEffectState: "active",
    show: false,
    webPreferences: {
      preload: join(__dirname, "preload.js"),
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true,
      webSecurity: true,
    },
  });
  mainWindow.once("ready-to-show", () => mainWindow?.show());
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith("https://github.com/")) {
      if (e2eMode) void recordE2eEvent("window-open", { url });
      else void shell.openExternal(url);
    }
    return { action: "deny" };
  });
  mainWindow.webContents.on("will-navigate", (event, url) => {
    if (!url.startsWith("supersaiyan://") && !url.startsWith("http://localhost:")) event.preventDefault();
  });
  if (MAIN_WINDOW_VITE_DEV_SERVER_URL) {
    // Retry until the Vite dev server is ready (cold-start race condition)
    for (let attempt = 0; attempt < 20; attempt++) {
      try {
        await mainWindow.loadURL(MAIN_WINDOW_VITE_DEV_SERVER_URL);
        break;
      } catch {
        await new Promise((r) => setTimeout(r, 500));
      }
    }
  } else {
    await mainWindow.loadURL(`supersaiyan://bundle/index.html`);
  }
}

app.whenReady().then(async () => {
  protocol.handle("supersaiyan", async (request) => {
    const url = new URL(request.url);
    const relative = url.pathname === "/" ? "index.html" : url.pathname.slice(1);
    const root = join(__dirname, `../renderer/${MAIN_WINDOW_VITE_NAME}`);
    const file = resolve(root, relative);
    if (!file.startsWith(root)) return new Response("Forbidden", { status: 403 });
    return netFetchFile(file);
  });
  registry = new RepositoryRegistry(app.getPath("userData"));
  state = await registry.load();
  registerIpc();
  await createWindow();
  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) void createWindow();
  });
});

async function netFetchFile(path: string): Promise<Response> {
  const { net } = await import("electron");
  return net.fetch(new URL(`file://${path}`).toString());
}

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});

app.on("before-quit", () => {
  for (const terminal of terminals.values()) terminal.process.kill();
  for (const runner of runners.values()) runner.process.kill("SIGTERM");
  void watchers.close();
});
