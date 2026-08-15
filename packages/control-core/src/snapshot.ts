// Everything the Control Center needs about one repository in a single object: environment
// diagnostics, board config selection, lanes, active workers, run events, and feature docs.
import { readFile, readdir, stat } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import {
  emptyLanes,
  laneNames,
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
import { fetchBoard } from "./board";
import { activeConfig, discoverConfigs, resolveExtends } from "./config";
import { exists, run, safeJson } from "./shared";

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
  let configJson = safeJson<Record<string, any>>(await readFile(config.path, "utf8"), {});
  // `paths.runs_dir` may live in the base config for an `extends`-linked overlay — resolve it
  // the same way discoverConfigs does, or a customized (non-default) runs_dir silently shows
  // no active run for this board.
  configJson = await resolveExtends(dirname(config.path), configJson);
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
      if (await exists(skill)) return "Installed";
      const plugin = await run(repository.path, "claude", ["plugin", "list"]);
      if (plugin.includes("supersaiyan")) return "Installed";
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
