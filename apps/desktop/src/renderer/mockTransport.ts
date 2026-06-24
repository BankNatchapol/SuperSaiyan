import {
  emptyLanes,
  type AppPreferences,
  type ControlTransport,
  type RepositoryRecord,
  type RepositorySnapshot,
  type TerminalSession,
} from "@supersaiyan/control-protocol";

const repository: RepositoryRecord = {
  id: "repo-preview-123456",
  path: "/Users/demo/acme/payments-api",
  name: "payments-api",
  addedAt: new Date().toISOString(),
  lastOpenedAt: new Date().toISOString(),
};

const lanes = emptyLanes();
lanes.Backlog.push({
  id: "backlog-1", number: 2855, title: "Add idempotency keys to payment intents", status: "Backlog",
  repository: "acme/payments-api", labels: ["feature", "infra"], assignees: [], state: "OPEN", rebuildCount: 0,
});
lanes.Ready.push({
  id: "ready-1", number: 2849, title: "Rate-limit webhook endpoints", status: "Ready",
  repository: "acme/payments-api", labels: ["bug", "P0"], assignees: [], state: "OPEN", rebuildCount: 0,
});
lanes.Building.push({
  id: "building-1", number: 2841, title: "Refactor auth middleware to edge sessions", status: "Building",
  repository: "acme/payments-api", labels: ["feature", "perf"], assignees: ["agent-vegeta"], state: "OPEN", rebuildCount: 1,
});
lanes.QA.push({
  id: "qa-1", number: 2839, title: "Stripe webhook retry with backoff", status: "QA",
  repository: "acme/payments-api", labels: ["bug"], assignees: ["agent-gohan"], state: "OPEN", rebuildCount: 0,
});
lanes.Review.push({
  id: "review-1", number: 2820, title: "Validate currency on checkout", status: "Review",
  repository: "acme/payments-api", labels: ["bug"], assignees: ["agent-piccolo"], state: "OPEN", rebuildCount: 0,
});
lanes.Done.push({
  id: "done-1", number: 2811, title: "Cache pricing lookups", status: "Done",
  repository: "acme/payments-api", labels: ["perf"], assignees: [], state: "CLOSED", rebuildCount: 0,
});

const snapshot: RepositorySnapshot = {
  repository,
  branch: "main",
  remote: "git@github.com:acme/payments-api.git",
  diagnostics: [
    { key: "git", label: "Git repository", ok: true, detail: "Ready" },
    { key: "remote", label: "Origin remote", ok: true, detail: "GitHub connected" },
    { key: "gh", label: "GitHub CLI", ok: true, detail: "Authenticated" },
    { key: "claude", label: "Claude Code", ok: true, detail: "2.1.0" },
    { key: "installed", label: "SuperSaiyan runtime", ok: true, detail: "Installed" },
    { key: "config", label: "Board config", ok: true, detail: "payments-production" },
  ],
  config: {
    slug: "payments-production", path: "", projectOwner: "acme", projectNumber: 3,
    projectTitle: "Payments Platform", variant: "full", baseBranch: "main", workerBackend: "workflow",
  },
  configs: [],
  lanes,
  workers: [
    { lane: "build", issue: 2841, pid: 4241, startedAt: "13:04:01" },
    { lane: "qa", issue: 2839, pid: 4242, startedAt: "13:06:12" },
    { lane: "review", issue: 2820, pid: 4243, startedAt: "13:08:44" },
  ],
  events: [
    { time: "13:08", kind: "dispatch", issue: 2820, detail: "review worker started" },
    { time: "13:06", kind: "dispatch", issue: 2839, detail: "qa worker started" },
    { time: "13:04", kind: "dispatch", issue: 2841, detail: "build worker started" },
  ],
  features: [
    { slug: "webhook-reliability", kind: "feature", design: true, spec: true, taskCount: 4, issueCount: 4, linted: true },
    { slug: "checkout-hardening", kind: "project", design: true, spec: true, taskCount: 0, issueCount: 0, linted: false, phases: [1, 2, 3] },
  ],
  runActive: true,
  lastUpdatedAt: new Date().toISOString(),
};

const preferences: AppPreferences = {
  theme: "aura-dark",
  idleRefreshSeconds: 60,
  activeRefreshSeconds: 10,
  shell: "/bin/zsh",
  modelTier: "medium",
  glassOpacity: 1,
};

const unavailable = async (): Promise<never> => {
  throw new Error("Desktop bridge unavailable in browser preview");
};

export const mockTransport: ControlTransport = {
  listRepositories: async () => [repository],
  addRepository: async () => repository,
  removeRepository: async () => undefined,
  getSnapshot: async () => snapshot,
  installOrRepair: unavailable,
  startCommand: unavailable,
  interruptCommand: async () => undefined,
  startRunnerCommand: unavailable,
  interruptRunner: async () => undefined,
  createTerminal: async () => ({ id: "preview-terminal", repoId: repository.id, title: "Preview terminal", kind: "shell", active: true } satisfies TerminalSession),
  replayTerminal: async () => "",
  writeTerminal: async () => undefined,
  resizeTerminal: async () => undefined,
  closeTerminal: async () => undefined,
  moveBoardCard: async () => undefined,
  openPath: async () => undefined,
  openExternal: async () => undefined,
  getPreferences: async () => preferences,
  updatePreferences: async (update) => Object.assign(preferences, update),
  onTerminalData: () => () => undefined,
  onTerminalExit: () => () => undefined,
  onRunnerEvent: () => () => undefined,
  onRepositoryChanged: () => () => undefined,
};
