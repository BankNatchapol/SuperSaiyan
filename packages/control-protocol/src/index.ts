import { z } from "zod";

export const laneNames = [
  "Backlog",
  "Ready",
  "Building",
  "QA",
  "Review",
  "Done",
  "Blocked",
  "Skipped",
] as const;

export type LaneName = (typeof laneNames)[number];
export type CommandVerb = "setup" | "new" | "prepare" | "lint" | "run" | "stop";
export type Screen = "overview" | "board" | "features" | "runs" | "terminal" | "runner" | "repositories" | "settings";

export interface RepositoryRecord {
  id: string;
  path: string;
  name: string;
  addedAt: string;
  lastOpenedAt: string;
}

export interface Diagnostic {
  key: "git" | "remote" | "gh" | "claude" | "installed" | "config";
  label: string;
  ok: boolean;
  detail: string;
}

export interface BoardCard {
  id: string;
  number: number;
  title: string;
  status: LaneName;
  url?: string;
  repository?: string;
  labels: string[];
  assignees: string[];
  state: "OPEN" | "CLOSED";
  prUrl?: string;
  dependency?: number;
  rebuildCount: number;
}

export interface WorkerState {
  lane: "build" | "qa" | "review";
  issue: number;
  pid?: number;
  startedAt?: string;
  elapsedSeconds?: number;
}

export interface RunEvent {
  time?: string;
  kind: string;
  issue?: number;
  detail: string;
}

export interface FeatureSummary {
  slug: string;
  kind: "feature" | "project";
  design: boolean;
  spec: boolean;
  taskCount: number;
  issueCount: number;
  linted: boolean;
  phases?: number[];
}

export interface BoardConfigSummary {
  slug: string;
  path: string;
  projectOwner: string;
  projectNumber: number;
  projectTitle: string;
  variant: string;
  baseBranch: string;
  workerBackend: string;
}

export interface RepositorySnapshot {
  repository: RepositoryRecord;
  branch: string;
  remote?: string;
  diagnostics: Diagnostic[];
  config?: BoardConfigSummary;
  configs: BoardConfigSummary[];
  lanes: Record<LaneName, BoardCard[]>;
  workers: WorkerState[];
  events: RunEvent[];
  features: FeatureSummary[];
  runActive: boolean;
  lastUpdatedAt: string;
  error?: string;
}

export interface TerminalSession {
  id: string;
  repoId: string;
  title: string;
  kind: "supersaiyan" | "shell";
  active: boolean;
}

export interface RunnerSession {
  id: string;
  repoId: string;
  title: string;
  command: CommandRequest;
  active: boolean;
  /** Claude Code session name used for --continue on follow-up turns. */
  sessionName: string;
}

export type RunnerEvent =
  | { type: "init"; sessionId: string }
  | { type: "assistant"; sessionId: string; text: string; partial?: boolean }
  | { type: "tool"; sessionId: string; name: string; input?: unknown }
  | { type: "tool_result"; sessionId: string; text?: string; error?: boolean }
  | { type: "system"; sessionId: string; text: string }
  | { type: "error"; sessionId: string; message: string }
  | { type: "exit"; sessionId: string; exitCode: number };

export interface CommandRequest {
  verb: CommandVerb;
  args: string[];
}

export interface AppPreferences {
  theme: "aura-dark";
  idleRefreshSeconds: number;
  activeRefreshSeconds: number;
  shell: string;
  modelTier: "low" | "medium" | "high";
  glassOpacity: number;
  installerPath?: string;
}

export const repoIdSchema = z.string().min(8).max(128);
export const repositoryPathSchema = z.string().min(1).max(4096);
export const terminalIdSchema = z.string().min(8).max(128);
export const commandRequestSchema = z.object({
  verb: z.enum(["setup", "new", "prepare", "lint", "run", "stop"]),
  args: z.array(z.string().max(256)).max(8),
});
export const boardMoveSchema = z.object({
  repoId: repoIdSchema,
  issueNumber: z.number().int().positive(),
  targetStatus: z.enum(["Backlog", "Ready"]),
});

export interface ControlTransport {
  listRepositories(): Promise<RepositoryRecord[]>;
  addRepository(path?: string): Promise<RepositoryRecord | null>;
  removeRepository(repoId: string): Promise<void>;
  getSnapshot(repoId: string, refresh?: boolean): Promise<RepositorySnapshot>;
  installOrRepair(repoId: string): Promise<TerminalSession>;
  startCommand(repoId: string, request: CommandRequest): Promise<TerminalSession>;
  interruptCommand(sessionId: string): Promise<void>;
  startRunnerCommand(repoId: string, request: CommandRequest): Promise<RunnerSession>;
  interruptRunner(sessionId: string): Promise<void>;
  continueRunner(repoId: string, sessionName: string, userText: string): Promise<RunnerSession>;
  createTerminal(repoId: string, kind: TerminalSession["kind"]): Promise<TerminalSession>;
  replayTerminal(sessionId: string): Promise<string>;
  writeTerminal(sessionId: string, data: string): Promise<void>;
  resizeTerminal(sessionId: string, cols: number, rows: number): Promise<void>;
  closeTerminal(sessionId: string): Promise<void>;
  moveBoardCard(repoId: string, issueNumber: number, targetStatus: "Backlog" | "Ready"): Promise<void>;
  openPath(repoId: string, relativePath: string): Promise<void>;
  openExternal(url: string): Promise<void>;
  getPreferences(): Promise<AppPreferences>;
  updatePreferences(preferences: Partial<AppPreferences>): Promise<AppPreferences>;
  onTerminalData(listener: (event: { sessionId: string; data: string }) => void): () => void;
  onTerminalExit(listener: (event: { sessionId: string; exitCode: number }) => void): () => void;
  onRunnerEvent(listener: (event: RunnerEvent) => void): () => void;
  onRepositoryChanged(listener: (event: { repoId: string }) => void): () => void;
}

export const emptyLanes = (): Record<LaneName, BoardCard[]> => ({
  Backlog: [],
  Ready: [],
  Building: [],
  QA: [],
  Review: [],
  Done: [],
  Blocked: [],
  Skipped: [],
});
