import { createHash, randomUUID } from "node:crypto";
import { access, mkdir, readFile, readdir, realpath, stat, writeFile } from "node:fs/promises";
import { constants } from "node:fs";
import { basename, dirname, isAbsolute, join, relative, resolve } from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import chokidar, { type FSWatcher } from "chokidar";
import {
  emptyLanes,
  laneNames,
  type AppPreferences,
  type BoardCard,
  type BoardConfigSummary,
  type Diagnostic,
  type FeatureSummary,
  type LaneName,
  type RepositoryRecord,
  type RepositorySnapshot,
  type RunEvent,
  type WorkerState,
} from "@supersaiyan/control-protocol";

const exec = promisify(execFile);
const MUTABLE_SOURCES = new Set<LaneName>(["Backlog", "Ready", "Blocked", "Skipped"]);

async function exists(path: string): Promise<boolean> {
  try {
    await access(path, constants.F_OK);
    return true;
  } catch {
    return false;
  }
}

async function run(cwd: string, command: string, args: string[], timeout = 15_000): Promise<string> {
  const result = await exec(command, args, {
    cwd,
    timeout,
    encoding: "utf8",
    env: { ...process.env, NO_COLOR: "1" },
    maxBuffer: 8 * 1024 * 1024,
  });
  return result.stdout.trim();
}

async function diagnostic(
  key: Diagnostic["key"],
  label: string,
  action: () => Promise<string>,
): Promise<Diagnostic> {
  try {
    const detail = await action();
    return { key, label, ok: true, detail: detail || "Ready" };
  } catch (error) {
    return { key, label, ok: false, detail: error instanceof Error ? (error.message.split("\n")[0] || error.name) : String(error) };
  }
}

function safeJson<T>(text: string, fallback: T): T {
  try {
    return JSON.parse(text) as T;
  } catch {
    return fallback;
  }
}

export class RepositoryRegistry {
  private readonly file: string;

  constructor(userDataPath: string) {
    this.file = join(userDataPath, "control-center.json");
  }

  async load(): Promise<{ repositories: RepositoryRecord[]; preferences: AppPreferences }> {
    const defaults = {
      repositories: [] as RepositoryRecord[],
      preferences: {
        theme: "aura-dark" as const,
        idleRefreshSeconds: 60,
        activeRefreshSeconds: 10,
        shell: process.env.SHELL || "/bin/zsh",
        modelTier: "medium" as const,
        glassOpacity: 1,
      },
    };
    if (!(await exists(this.file))) return defaults;
    const data = safeJson<Partial<typeof defaults>>(await readFile(this.file, "utf8"), {});
    return {
      repositories: data.repositories ?? defaults.repositories,
      preferences: { ...defaults.preferences, ...(data.preferences ?? {}) },
    };
  }

  async save(state: { repositories: RepositoryRecord[]; preferences: AppPreferences }): Promise<void> {
    await mkdir(dirname(this.file), { recursive: true });
    await writeFile(this.file, `${JSON.stringify(state, null, 2)}\n`, { mode: 0o600 });
  }
}

export async function registerRepository(path: string): Promise<RepositoryRecord> {
  const canonical = await realpath(path);
  const info = await stat(canonical);
  if (!info.isDirectory()) throw new Error("Repository path must be a directory");
  await run(canonical, "git", ["rev-parse", "--is-inside-work-tree"]);
  const now = new Date().toISOString();
  return {
    id: `repo-${createHash("sha256").update(canonical).digest("hex").slice(0, 20)}`,
    path: canonical,
    name: basename(canonical),
    addedAt: now,
    lastOpenedAt: now,
  };
}

async function discoverConfigs(repoPath: string): Promise<BoardConfigSummary[]> {
  const candidates = [
    join(repoPath, ".claude", "supersaiyan", "configs"),
    join(repoPath, ".claude", "super-board", "configs"),
  ];
  const found = new Map<string, BoardConfigSummary>();
  for (const directory of candidates) {
    if (!(await exists(directory))) continue;
    for (const file of (await readdir(directory)).filter((name) => name.endsWith(".json")).sort()) {
      const path = join(directory, file);
      const config = safeJson<Record<string, any>>(await readFile(path, "utf8"), {});
      const slug = file.slice(0, -5);
      if (!config.project?.number || !config.project?.owner) continue;
      if (!found.has(slug) || directory.includes("supersaiyan")) {
        found.set(slug, {
          slug,
          path,
          projectOwner: String(config.project.owner),
          projectNumber: Number(config.project.number),
          projectTitle: String(config.project.title || slug),
          variant: String(config.variant || "full"),
          baseBranch: String(config.base_branch || "main"),
          workerBackend: String(config.worker_backend || "workflow"),
        });
      }
    }
  }
  return [...found.values()];
}

async function activeConfig(repoPath: string, configs: BoardConfigSummary[]): Promise<BoardConfigSummary | undefined> {
  for (const base of ["supersaiyan", "super-board"]) {
    const active = join(repoPath, ".claude", base, "active");
    if (await exists(active)) {
      const slug = (await readFile(active, "utf8")).trim();
      const match = configs.find((config) => config.slug === slug);
      if (match) return match;
    }
  }
  return configs.length === 1 ? configs[0] : undefined;
}

type GhProjectItem = {
  id: string;
  status?: string;
  content?: {
    type?: string;
    number?: number;
    title?: string;
    url?: string;
    repository?: string;
    state?: string;
    labels?: Array<{ name?: string }> | string[];
    assignees?: Array<{ login?: string }> | string[];
    body?: string;
  };
};

function normalizeNames(values: unknown): string[] {
  if (!Array.isArray(values)) return [];
  return values.flatMap((value) => {
    if (typeof value === "string") return [value];
    if (value && typeof value === "object") {
      const object = value as Record<string, unknown>;
      return [String(object.name ?? object.login ?? "")].filter(Boolean);
    }
    return [];
  });
}

function normalizeStatus(status?: string): LaneName {
  return laneNames.includes(status as LaneName) ? (status as LaneName) : "Backlog";
}

async function fetchBoard(repoPath: string, config?: BoardConfigSummary): Promise<Record<LaneName, BoardCard[]>> {
  const lanes = emptyLanes();
  if (!config) return lanes;
  const raw = await run(repoPath, "gh", [
    "project",
    "item-list",
    String(config.projectNumber),
    "--owner",
    config.projectOwner,
    "--format",
    "json",
    "--limit",
    "500",
  ], 30_000);
  const payload = safeJson<{ items?: GhProjectItem[] }>(raw, {});
  for (const item of payload.items ?? []) {
    const content = item.content;
    if (content?.type !== "Issue" || !content.number) continue;
    const status = normalizeStatus(item.status);
    const body = content.body || "";
    const dependency = body.match(/depends on:\s*#(\d+)/i);
    const labels = normalizeNames(content.labels);
    lanes[status].push({
      id: item.id,
      number: content.number,
      title: content.title || `Issue #${content.number}`,
      status,
      url: content.url,
      repository: content.repository,
      labels,
      assignees: normalizeNames(content.assignees),
      state: content.state === "CLOSED" ? "CLOSED" : "OPEN",
      dependency: dependency ? Number(dependency[1]) : undefined,
      rebuildCount: Number(labels.find((label) => /^loop:rebuild-\d+$/.test(label))?.split("-").at(-1) || 0),
    });
  }
  for (const lane of laneNames) lanes[lane].sort((a, b) => b.number - a.number);
  return lanes;
}

async function discoverFeatures(repoPath: string): Promise<FeatureSummary[]> {
  const features = new Map<string, FeatureSummary>();
  const specsDir = join(repoPath, "docs", "superpowers", "specs");
  if (await exists(specsDir)) {
    for (const file of await readdir(specsDir)) {
      if (!file.endsWith(".md")) continue;
      const slug = file.replace(/-design\.md$/, "").replace(/\.md$/, "");
      features.set(slug, { slug, kind: "feature", design: false, spec: true, taskCount: 0, issueCount: 0, linted: false });
    }
  }
  const tasksDir = join(repoPath, "docs", "superpowers", "tasks");
  if (await exists(tasksDir)) {
    for (const slug of await readdir(tasksDir)) {
      const directory = join(tasksDir, slug);
      if (!(await stat(directory)).isDirectory()) continue;
      const files = await readdir(directory);
      const issueMap = files.includes(".issue-map.json")
        ? safeJson<Record<string, unknown>>(await readFile(join(directory, ".issue-map.json"), "utf8"), {})
        : {};
      const current = features.get(slug) ?? { slug, kind: "feature" as const, design: false, spec: false, taskCount: 0, issueCount: 0, linted: false };
      current.taskCount = files.filter((file) => file.endsWith(".md") && file !== "README.md").length;
      current.issueCount = Object.keys(issueMap).length;
      current.design = await exists(join(repoPath, "docs", "supersaiyan", "designs", `${slug}-design.md`));
      current.linted = await exists(join(repoPath, "docs", "super-board", "pre-flight.md")) ||
        await exists(join(repoPath, "docs", "supersaiyan", "pre-flight.md"));
      features.set(slug, current);
    }
  }
  const projectsDir = join(repoPath, "docs", "superpowers", "projects");
  if (await exists(projectsDir)) {
    for (const slug of await readdir(projectsDir)) {
      const directory = join(projectsDir, slug);
      if (!(await stat(directory)).isDirectory()) continue;
      const entries = await readdir(directory);
      const phases = entries.flatMap((entry) => {
        const match = entry.match(/^phase-(\d+)$/);
        return match ? [Number(match[1])] : [];
      });
      features.set(slug, {
        slug,
        kind: "project",
        design: await exists(join(repoPath, "docs", "supersaiyan", "designs", `${slug}-design.md`)),
        spec: await exists(join(directory, "PROJECT.md")),
        taskCount: 0,
        issueCount: 0,
        linted: false,
        phases: phases.sort((a, b) => a - b),
      });
    }
  }
  return [...features.values()].sort((a, b) => a.slug.localeCompare(b.slug));
}

function parseManifest(text: string): { workers: WorkerState[]; events: RunEvent[]; runActive: boolean } {
  const workers = new Map<string, WorkerState>();
  const events: RunEvent[] = [];
  let cleanExit = false;
  for (const line of text.split(/\r?\n/)) {
    const timestamp = line.match(/^\[(\d{2}:\d{2}:\d{2})\]/)?.[1];
    const dispatch = line.match(/dispatch lane=(build|qa|review) issue=#(\d+) pid=(\d+)/);
    if (dispatch) {
      const lane = dispatch[1] as WorkerState["lane"];
      workers.set(lane, { lane, issue: Number(dispatch[2]), pid: Number(dispatch[3]), startedAt: timestamp });
      events.push({ time: timestamp, kind: "dispatch", issue: Number(dispatch[2]), detail: `${lane} worker started` });
    }
    const reap = line.match(/reaped stale lock[^#]*#(\d+)/);
    if (reap) events.push({ time: timestamp, kind: "reap", issue: Number(reap[1]), detail: "Worker lock released" });
    if (/exiting cleanly|run finished/.test(line)) cleanExit = true;
  }
  return { workers: [...workers.values()], events: events.slice(-20).reverse(), runActive: workers.size > 0 && !cleanExit };
}

async function runState(repoPath: string, config?: BoardConfigSummary): Promise<{ workers: WorkerState[]; events: RunEvent[]; runActive: boolean }> {
  if (!config) return { workers: [], events: [], runActive: false };
  const configJson = safeJson<Record<string, any>>(await readFile(config.path, "utf8"), {});
  const runsDir = resolve(repoPath, configJson.paths?.runs_dir || "docs/supersaiyan/runs");
  if (!(await exists(runsDir))) return { workers: [], events: [], runActive: false };
  const files = (await readdir(runsDir)).filter((file) => file.endsWith(".md") && file.includes(config.slug)).sort();
  if (!files.length) return { workers: [], events: [], runActive: false };
  return parseManifest(await readFile(join(runsDir, files.at(-1)!), "utf8"));
}

type StructuredStatus = {
  lanes?: Partial<Record<LaneName, Array<{
    id?: string;
    number: number;
    title: string;
    url?: string;
    state?: string;
    repository?: string;
    assignees?: string[];
    labels?: string[];
    status?: string;
  }>>>;
  workers?: Array<{
    lane: WorkerState["lane"];
    issue: number;
    pid?: number;
    started_at?: string;
    elapsed_seconds?: number;
  }>;
  recent?: Array<{ verb?: string; issue?: string; detail?: string; target?: string }>;
  health?: { run_active?: boolean };
};

async function readStructuredStatus(
  repoPath: string,
  config?: BoardConfigSummary,
): Promise<{ lanes: Record<LaneName, BoardCard[]>; workers: WorkerState[]; events: RunEvent[]; runActive: boolean } | undefined> {
  if (!config) return undefined;
  const helper = join(repoPath, ".claude", "bin", "super-board-status.py");
  if (!(await exists(helper))) return undefined;
  const payload = safeJson<StructuredStatus>(
    await run(repoPath, "python3", [helper, config.slug, "--json"], 30_000),
    {},
  );
  if (!payload.lanes) return undefined;
  const lanes = emptyLanes();
  for (const lane of laneNames) {
    lanes[lane] = (payload.lanes[lane] ?? []).map((item) => {
      const labels = item.labels ?? [];
      return {
        id: item.id || `issue-${item.number}`,
        number: item.number,
        title: item.title,
        status: lane,
        url: item.url,
        repository: item.repository,
        labels,
        assignees: item.assignees ?? [],
        state: item.state === "CLOSED" ? "CLOSED" : "OPEN",
        rebuildCount: Number(labels.find((label) => /^loop:rebuild-\d+$/.test(label))?.split("-").at(-1) || 0),
      };
    });
  }
  return {
    lanes,
    workers: (payload.workers ?? []).map((worker) => ({
      lane: worker.lane,
      issue: worker.issue,
      pid: worker.pid,
      startedAt: worker.started_at,
      elapsedSeconds: worker.elapsed_seconds,
    })),
    events: (payload.recent ?? []).map((event) => ({
      kind: event.verb || "event",
      issue: event.issue ? Number(event.issue.replace("#", "")) : undefined,
      detail: [event.target, event.detail].filter(Boolean).join(" · "),
    })),
    runActive: Boolean(payload.health?.run_active),
  };
}

export async function buildSnapshot(repository: RepositoryRecord): Promise<RepositorySnapshot> {
  const diagnostics = await Promise.all([
    diagnostic("git", "Git repository", () => run(repository.path, "git", ["rev-parse", "--show-toplevel"])),
    diagnostic("remote", "Origin remote", () => run(repository.path, "git", ["remote", "get-url", "origin"])),
    diagnostic("gh", "GitHub CLI", async () => {
      await run(repository.path, "gh", ["auth", "status", "--active"]);
      return "Authenticated";
    }),
    diagnostic("claude", "Claude Code", () => run(repository.path, "claude", ["--version"])),
    diagnostic("installed", "SuperSaiyan runtime", async () => {
      const skill = join(repository.path, ".claude", "skills", "supersaiyan", "SKILL.md");
      const plugin = await run(repository.path, "claude", ["plugin", "list"]);
      if ((await exists(skill)) || plugin.includes("supersaiyan")) return "Installed";
      throw new Error("Not installed in this repository");
    }),
  ]);
  const configs = await discoverConfigs(repository.path);
  const config = await activeConfig(repository.path, configs);
  diagnostics.push({ key: "config", label: "Board config", ok: Boolean(config), detail: config ? config.slug : configs.length ? "Choose an active config" : "Run setup" });
  let lanes = emptyLanes();
  let state = { workers: [] as WorkerState[], events: [] as RunEvent[], runActive: false };
  let error: string | undefined;
  try {
    const structured = await readStructuredStatus(repository.path, config);
    if (structured) {
      lanes = structured.lanes;
      state = structured;
    } else {
      lanes = await fetchBoard(repository.path, config);
      state = await runState(repository.path, config);
    }
  } catch (cause) {
    error = cause instanceof Error ? cause.message.split("\n")[0] : String(cause);
    try {
      lanes = await fetchBoard(repository.path, config);
      state = await runState(repository.path, config);
    } catch {
      // Keep the original structured-status error for the health panel.
    }
  }
  return {
    repository,
    branch: await run(repository.path, "git", ["branch", "--show-current"]).catch(() => "unknown"),
    remote: await run(repository.path, "git", ["remote", "get-url", "origin"]).catch(() => undefined),
    diagnostics,
    config,
    configs,
    lanes,
    workers: state.workers,
    events: state.events,
    features: await discoverFeatures(repository.path),
    runActive: state.runActive,
    lastUpdatedAt: new Date().toISOString(),
    error,
  };
}

export async function moveBoardCard(repository: RepositoryRecord, issueNumber: number, targetStatus: "Backlog" | "Ready"): Promise<void> {
  const snapshot = await buildSnapshot(repository);
  const card = laneNames.flatMap((lane) => snapshot.lanes[lane]).find((candidate) => candidate.number === issueNumber);
  if (!card) throw new Error(`Issue #${issueNumber} is not on the configured board`);
  if (!MUTABLE_SOURCES.has(card.status)) throw new Error(`Cards in ${card.status} are controlled by the pipeline`);
  if (card.state !== "OPEN") throw new Error("Closed issues cannot be moved");
  if (card.assignees.length) throw new Error("Assigned issues cannot be moved");
  if (!snapshot.config) throw new Error("No active board config");

  const fields = safeJson<{ fields?: Array<{ id: string; name: string; options?: Array<{ id: string; name: string }> }> }>(
    await run(repository.path, "gh", ["project", "field-list", String(snapshot.config.projectNumber), "--owner", snapshot.config.projectOwner, "--format", "json"]),
    {},
  );
  const statusField = fields.fields?.find((field) => field.name === "Status");
  const option = statusField?.options?.find((candidate) => candidate.name === targetStatus);
  if (!statusField || !option) throw new Error(`Project Status is missing ${targetStatus}`);
  const projectId = await run(repository.path, "gh", ["project", "view", String(snapshot.config.projectNumber), "--owner", snapshot.config.projectOwner, "--format", "json", "--jq", ".id"]);
  await run(repository.path, "gh", [
    "project", "item-edit",
    "--id", card.id,
    "--project-id", projectId,
    "--field-id", statusField.id,
    "--single-select-option-id", option.id,
  ]);
}

export class RepositoryWatchService {
  private readonly watchers = new Map<string, FSWatcher>();

  watch(repository: RepositoryRecord, onChange: () => void): void {
    if (this.watchers.has(repository.id)) return;
    const targets = [
      join(repository.path, ".claude", "supersaiyan"),
      join(repository.path, ".claude", "super-board"),
      join(repository.path, "docs", "superpowers"),
      join(repository.path, "docs", "supersaiyan"),
      join(repository.path, "docs", "super-board"),
    ];
    const watcher = chokidar.watch(targets, { ignoreInitial: true, depth: 5 });
    let timer: NodeJS.Timeout | undefined;
    watcher.on("all", () => {
      clearTimeout(timer);
      timer = setTimeout(onChange, 250);
    });
    this.watchers.set(repository.id, watcher);
  }

  async unwatch(repoId: string): Promise<void> {
    const watcher = this.watchers.get(repoId);
    if (watcher) await watcher.close();
    this.watchers.delete(repoId);
  }

  async close(): Promise<void> {
    await Promise.all([...this.watchers.values()].map((watcher) => watcher.close()));
    this.watchers.clear();
  }
}

export function isPathInside(repository: RepositoryRecord, candidate: string): boolean {
  const rel = relative(repository.path, resolve(repository.path, candidate));
  return rel === "" || (rel !== ".." && !rel.startsWith(`..${process.platform === "win32" ? "\\" : "/"}`) && !isAbsolute(rel));
}

export const createSessionId = (): string => `session-${randomUUID()}`;
