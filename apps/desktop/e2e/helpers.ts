import { _electron as electron, chromium, expect, type Browser, type ElectronApplication, type Page, type TestInfo } from "@playwright/test";
import { chmod, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { execFile, spawn, type ChildProcess } from "node:child_process";
import { createRequire } from "node:module";
import { promisify } from "node:util";

const exec = promisify(execFile);
const root = resolve(__dirname, "../../..");
const require = createRequire(__filename);
const electronExecutable = require("electron") as string;

type FixtureItem = {
  id: string;
  status?: string;
  content: {
    type: "Issue";
    number: number;
    title: string;
    url: string;
    repository: string;
    state: "OPEN" | "CLOSED";
    labels: string[];
    assignees: string[];
    body?: string;
  };
};

export type TestWorkspace = {
  root: string;
  userData: string;
  records: string;
  bin: string;
  stateFile: string;
  repoA: string;
  repoB: string;
  cleanup(): Promise<void>;
};

const fixtureItems: FixtureItem[] = [
  { id: "item-backlog", status: "Backlog", content: { type: "Issue", number: 101, title: "Manual backlog idea", url: "https://github.com/acme/demo/issues/101", repository: "acme/demo", state: "OPEN", labels: ["manual"], assignees: [] } },
  { id: "item-ready", status: "Ready", content: { type: "Issue", number: 102, title: "Generated task ready", url: "https://github.com/acme/demo/issues/102", repository: "acme/demo", state: "OPEN", labels: ["generated"], assignees: [], body: "Depends on: #101" } },
  { id: "item-building", status: "Building", content: { type: "Issue", number: 103, title: "Builder owns this", url: "https://github.com/acme/demo/issues/103", repository: "acme/demo", state: "OPEN", labels: ["loop:rebuild-2"], assignees: ["agent-build"] } },
  { id: "item-qa", status: "QA", content: { type: "Issue", number: 104, title: "Testing active change", url: "https://github.com/acme/demo/issues/104", repository: "acme/demo", state: "OPEN", labels: [], assignees: ["agent-qa"] } },
  { id: "item-review", status: "Review", content: { type: "Issue", number: 105, title: "Reviewing result", url: "https://github.com/acme/demo/issues/105", repository: "acme/demo", state: "OPEN", labels: [], assignees: ["agent-review"] } },
  { id: "item-done", status: "Done", content: { type: "Issue", number: 106, title: "Finished task", url: "https://github.com/acme/demo/issues/106", repository: "acme/demo", state: "CLOSED", labels: [], assignees: [] } },
  { id: "item-blocked", status: "Blocked", content: { type: "Issue", number: 107, title: "Retry blocked work", url: "https://github.com/acme/demo/issues/107", repository: "acme/demo", state: "OPEN", labels: [], assignees: [] } },
  { id: "item-skipped", status: "Skipped", content: { type: "Issue", number: 108, title: "Retry skipped work", url: "https://github.com/acme/demo/issues/108", repository: "acme/demo", state: "OPEN", labels: [], assignees: [] } },
  { id: "item-unset", content: { type: "Issue", number: 109, title: "Unset status defaults to backlog", url: "https://github.com/acme/demo/issues/109", repository: "acme/demo", state: "OPEN", labels: [], assignees: [] } },
];

async function run(cwd: string, command: string, args: string[]): Promise<void> {
  await exec(command, args, { cwd });
}

async function createRepo(path: string, name: string): Promise<void> {
  await mkdir(path, { recursive: true });
  await run(path, "git", ["init", "-b", "main"]);
  await run(path, "git", ["config", "user.email", "e2e@example.test"]);
  await run(path, "git", ["config", "user.name", "E2E"]);
  await writeFile(join(path, "README.md"), `# ${name}\n`);
  await run(path, "git", ["add", "README.md"]);
  await run(path, "git", ["commit", "-m", "fixture"]);
  await run(path, "git", ["remote", "add", "origin", `https://github.com/acme/${name}.git`]);

  const configDir = join(path, ".claude", "supersaiyan", "configs");
  await mkdir(configDir, { recursive: true });
  await writeFile(join(path, ".claude", "supersaiyan", "active"), "demo\n");
  await writeFile(join(configDir, "demo.json"), JSON.stringify({
    variant: "full",
    base_branch: "main",
    worker_backend: "workflow",
    project: { owner: "acme", number: 7, title: "E2E Project" },
    paths: { runs_dir: "docs/supersaiyan/runs" },
  }, null, 2));
  await mkdir(join(path, ".claude", "skills", "supersaiyan"), { recursive: true });
  await writeFile(join(path, ".claude", "skills", "supersaiyan", "SKILL.md"), "---\nname: supersaiyan\n---\n");

  await mkdir(join(path, "docs", "superpowers", "specs"), { recursive: true });
  await writeFile(join(path, "docs", "superpowers", "specs", "chat-design.md"), "# Chat\n");
  const taskDir = join(path, "docs", "superpowers", "tasks", "chat");
  await mkdir(taskDir, { recursive: true });
  await writeFile(join(taskDir, "01-chat.md"), "---\ntitle: Chat\n---\n");
  await writeFile(join(taskDir, ".issue-map.json"), JSON.stringify({ "01-chat.md": 102 }));
  const projectDir = join(path, "docs", "superpowers", "projects", "platform");
  await mkdir(join(projectDir, "phase-1"), { recursive: true });
  await mkdir(join(projectDir, "phase-2"), { recursive: true });
  await writeFile(join(projectDir, "PROJECT.md"), "# Platform\n");
  const runsDir = join(path, "docs", "supersaiyan", "runs");
  await mkdir(runsDir, { recursive: true });
  const today = new Date().toISOString().slice(0, 10);
  await writeFile(join(runsDir, `${today}-demo.md`), [
    "[09:00:00] super-board run started",
    "[09:00:01] dispatch lane=build issue=#103 pid=4301 claim=ok",
    "[09:00:02] tick — workers=1",
    "",
  ].join("\n"));
}

async function createExecutable(path: string, content: string): Promise<void> {
  await writeFile(path, content);
  await chmod(path, 0o755);
}

export async function createTestWorkspace(): Promise<TestWorkspace> {
  const directory = await mkdtemp(join(tmpdir(), "supersaiyan-e2e-"));
  const userData = join(directory, "user-data");
  const records = join(directory, "records");
  const bin = join(directory, "bin");
  const stateFile = join(directory, "gh-state.json");
  const repoA = join(directory, "repo-alpha");
  const repoB = join(directory, "repo-beta");
  await Promise.all([mkdir(userData), mkdir(records), mkdir(bin), createRepo(repoA, "repo-alpha"), createRepo(repoB, "repo-beta")]);
  await writeFile(stateFile, JSON.stringify({ items: fixtureItems }, null, 2));

  await createExecutable(join(bin, "gh"), `#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");
const args = process.argv.slice(2);
const statePath = process.env.SUPERSAIYAN_E2E_STATE;
const recordDir = process.env.SUPERSAIYAN_E2E_RECORD_DIR;
fs.mkdirSync(recordDir, { recursive: true });
fs.appendFileSync(path.join(recordDir, "commands.jsonl"), JSON.stringify({ tool: "gh", args, cwd: process.cwd(), at: new Date().toISOString() }) + "\\n");
if (process.env.SUPERSAIYAN_E2E_GH_OFFLINE === "1") { console.error("network unavailable"); process.exit(1); }
if (args[0] === "auth" && args[1] === "status") process.exit(0);
if (args[0] === "project" && args[1] === "item-list") {
  process.stdout.write(JSON.stringify({ items: JSON.parse(fs.readFileSync(statePath, "utf8")).items }));
  process.exit(0);
}
if (args[0] === "project" && args[1] === "field-list") {
  process.stdout.write(JSON.stringify({ fields: [{ id: "status-field", name: "Status", options: [
    { id: "opt-backlog", name: "Backlog" }, { id: "opt-ready", name: "Ready" }
  ] }] }));
  process.exit(0);
}
if (args[0] === "project" && args[1] === "view") {
  if (args.includes("--jq")) process.stdout.write("PVT_project\\n");
  else process.stdout.write(JSON.stringify({ id: "PVT_project", title: "E2E Project", number: 7 }));
  process.exit(0);
}
if (args[0] === "project" && args[1] === "item-edit") {
  const state = JSON.parse(fs.readFileSync(statePath, "utf8"));
  const itemId = args[args.indexOf("--id") + 1];
  const option = args[args.indexOf("--single-select-option-id") + 1];
  const item = state.items.find((candidate) => candidate.id === itemId);
  if (item) item.status = option === "opt-ready" ? "Ready" : "Backlog";
  fs.writeFileSync(statePath, JSON.stringify(state, null, 2));
  process.exit(0);
}
console.error("unsupported fake gh command", args.join(" "));
process.exit(2);
`);

  await createExecutable(join(bin, "claude"), `#!/bin/bash
set -u
record_dir="\${SUPERSAIYAN_E2E_RECORD_DIR}"
mkdir -p "$record_dir"
printf '{"tool":"claude","args":%s,"cwd":"%s"}\\n' "$(node -e 'console.log(JSON.stringify(process.argv.slice(1)))' "$@")" "$PWD" >> "$record_dir/commands.jsonl"
if [ "\${1:-}" = "--version" ]; then echo "2.1.153 (Claude Code)"; exit 0; fi
if [ "\${1:-}" = "plugin" ] && [ "\${2:-}" = "list" ]; then echo "supersaiyan"; exit 0; fi
if printf '%s\n' "$@" | grep -qx -- "-p"; then
  prompt="\${@: -1}"
  printf '{"tool":"claude-print","line":%s,"cwd":"%s"}\n' "$(node -e 'console.log(JSON.stringify(process.argv[1]))' "$prompt")" "$PWD" >> "$record_dir/commands.jsonl"
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"Running %s"}]}}\n' "$prompt"
  printf '{"type":"tool_use","name":"Bash","input":{"command":"git status --short"}}\n'
  printf '{"type":"tool_result","content":[{"type":"text","text":"clean"}]}\n'
  if [ "$prompt" = "/supersaiyan run" ]; then sleep 20; fi
  exit 0
fi
echo "Fake Claude ready"
while IFS= read -r line; do
  printf '{"tool":"claude-stdin","line":%s,"cwd":"%s"}\\n' "$(node -e 'console.log(JSON.stringify(process.argv[1]))' "$line")" "$PWD" >> "$record_dir/commands.jsonl"
  echo "received: $line"
done
`);

  return {
    root: directory,
    userData,
    records,
    bin,
    stateFile,
    repoA,
    repoB,
    cleanup: () => rm(directory, { recursive: true, force: true }),
  };
}

export async function seedRegistry(workspace: TestWorkspace, repositories: string[], preferences: Record<string, unknown> = {}): Promise<void> {
  const records = repositories.map((path, index) => ({
    id: `repo-e2e-${index + 100000}`,
    path,
    name: path.split("/").at(-1),
    addedAt: "2026-06-22T00:00:00.000Z",
    lastOpenedAt: "2026-06-22T00:00:00.000Z",
  }));
  await writeFile(join(workspace.userData, "control-center.json"), JSON.stringify({
    repositories: records,
    preferences: {
      theme: "aura-dark",
      idleRefreshSeconds: 60,
      activeRefreshSeconds: 10,
      shell: "/bin/zsh",
      modelTier: "medium",
      ...preferences,
    },
  }, null, 2));
}

export function packagedExecutable(arch = process.arch): string {
  return join(root, "apps", "desktop", "out", `SuperSaiyan Control Center-darwin-${arch}`, "SuperSaiyan Control Center.app", "Contents", "MacOS", "supersaiyan-control-center");
}

function testEnvironment(workspace: TestWorkspace, extraEnv: Record<string, string> = {}): Record<string, string> {
  const environment = Object.fromEntries(
    Object.entries(process.env).filter((entry): entry is [string, string] => typeof entry[1] === "string"),
  );
  delete environment.ELECTRON_RUN_AS_NODE;
  return {
    ...environment,
    PATH: `${workspace.bin}:${environment.PATH || ""}`,
    SUPERSAIYAN_E2E: "1",
    SUPERSAIYAN_E2E_USER_DATA: workspace.userData,
    SUPERSAIYAN_E2E_RECORD_DIR: workspace.records,
    SUPERSAIYAN_E2E_STATE: workspace.stateFile,
    SUPERSAIYAN_E2E_PICKER_RESULT: workspace.repoA,
    ...extraEnv,
  };
}

export async function launchControlCenter(workspace: TestWorkspace, extraEnv: Record<string, string> = {}): Promise<{ app: ElectronApplication; page: Page; errors: string[] }> {
  const errors: string[] = [];
  const app = await electron.launch({
    executablePath: electronExecutable,
    args: [join(root, "apps", "desktop")],
    env: testEnvironment(workspace, extraEnv),
  });
  const page = await app.firstWindow();
  page.on("pageerror", (error) => errors.push(`pageerror: ${error.message}`));
  page.on("console", (message) => {
    if (message.type() === "error") errors.push(`console: ${message.text()}`);
  });
  await page.waitForLoadState("domcontentloaded");
  return { app, page, errors };
}

export async function launchPackagedControlCenter(
  workspace: TestWorkspace,
  port = 9333 + Math.floor(Math.random() * 500),
): Promise<{ browser: Browser; process: ChildProcess; page: Page; close(): Promise<void> }> {
  const child = spawn(packagedExecutable(), [`--remote-debugging-port=${port}`], {
    env: testEnvironment(workspace),
    stdio: "pipe",
  });
  await expect.poll(async () => {
    try {
      const response = await fetch(`http://127.0.0.1:${port}/json/version`);
      return response.ok;
    } catch {
      return false;
    }
  }, { timeout: 15_000 }).toBe(true);
  const browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`);
  const page = browser.contexts()[0].pages()[0];
  await page.waitForLoadState("domcontentloaded");
  return {
    browser,
    process: child,
    page,
    close: async () => {
      await browser.close();
      child.kill("SIGTERM");
      await new Promise<void>((resolveClose) => {
        if (child.exitCode !== null) resolveClose();
        else {
          child.once("exit", () => resolveClose());
          setTimeout(() => {
            child.kill("SIGKILL");
            resolveClose();
          }, 3_000).unref();
        }
      });
    },
  };
}

export async function readJsonLines(path: string): Promise<any[]> {
  try {
    return (await readFile(path, "utf8")).split(/\r?\n/).filter(Boolean).flatMap((line) => {
      try { return [JSON.parse(line)]; }
      catch { return []; }
    });
  } catch {
    return [];
  }
}

export async function attachScreenshot(page: Page, testInfo: TestInfo, name: string): Promise<void> {
  const path = testInfo.outputPath(`${name}.png`);
  const image = await page.screenshot({ path, fullPage: true });
  const qaDirectory = join(root, ".gstack", "qa-reports", "control-center", "screenshots");
  await mkdir(qaDirectory, { recursive: true });
  await writeFile(join(qaDirectory, `${name}.png`), image);
  await testInfo.attach(name, { path, contentType: "image/png" });
}

export async function expectNoRendererErrors(errors: string[]): Promise<void> {
  const unexpected = errors.filter((error) => !error.includes("fonts.googleapis.com") || !error.includes("Content Security Policy"));
  expect(unexpected, unexpected.join("\n")).toEqual([]);
}

export async function waitForCommand(workspace: TestWorkspace, predicate: (entry: any) => boolean): Promise<any> {
  const path = join(workspace.records, "commands.jsonl");
  await expect.poll(async () => (await readJsonLines(path)).find(predicate)).toBeTruthy();
  return (await readJsonLines(path)).find(predicate);
}
