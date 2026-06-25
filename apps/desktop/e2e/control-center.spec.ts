import { expect, test } from "@playwright/test";
import { source as axeSource } from "axe-core";
import { writeFile } from "node:fs/promises";
import { join } from "node:path";
import {
  attachScreenshot,
  createTestWorkspace,
  expectNoRendererErrors,
  launchControlCenter,
  readJsonLines,
  seedRegistry,
  waitForCommand,
} from "./helpers";

test("onboards, deduplicates, removes, and restores repositories", async ({}, testInfo) => {
  const workspace = await createTestWorkspace();
  const first = await launchControlCenter(workspace);
  try {
    await expect(first.page.getByText("Connect your first repository")).toBeVisible();
    await first.page.getByRole("button", { name: "Add repository" }).click();
    await expect(first.page.getByText("repo-alpha · main")).toBeVisible();
    await first.page.getByRole("button", { name: "Repositories" }).click();
    await first.page.getByRole("button", { name: "Connect repository" }).click();
    await expect(first.page.locator(".topbar-title")).toContainText("Overview");
    await first.page.getByRole("button", { name: "Repositories" }).click();
    await expect(first.page.locator(".repo-row")).toHaveCount(1);
    await first.page.getByRole("button", { name: "Remove from Control Center" }).click();
    await expect(first.page.getByText("Connect your first repository")).toBeVisible();
    await first.page.getByRole("button", { name: "Add repository" }).click();
    await attachScreenshot(first.page, testInfo, "repository-onboarding");
    await expectNoRendererErrors(first.errors);
  } finally {
    await first.app.close();
  }

  const second = await launchControlCenter(workspace);
  try {
    await expect(second.page.getByText("repo-alpha · main")).toBeVisible();
    await expectNoRendererErrors(second.errors);
  } finally {
    await second.app.close();
    await workspace.cleanup();
  }
});

test("renders all screens, diagnostics, workers, features, and accessibility evidence", async ({}, testInfo) => {
  const workspace = await createTestWorkspace();
  await seedRegistry(workspace, [workspace.repoA, workspace.repoB]);
  const { app, page, errors } = await launchControlCenter(workspace);
  try {
    await expect(page.getByText("E2E Project · full · main")).toBeVisible();
    await expect(page.getByText("Current wave")).toBeVisible();
    for (const screen of ["Overview", "Board", "Features", "Runs", "Terminal", "Runner", "Repositories", "Settings"]) {
      await page.getByRole("button", { name: new RegExp(`^${screen}`) }).click();
      await expect(page.locator(".topbar-title")).toContainText(screen);
      await attachScreenshot(page, testInfo, `screen-${screen.toLowerCase()}`);
    }
    await page.getByRole("button", { name: /^Features/ }).click();
    await expect(page.getByText("chat", { exact: true })).toBeVisible();
    await expect(page.getByText("platform", { exact: true })).toBeVisible();
    await page.getByRole("button", { name: /^Runs/ }).click();
    await expect(page.getByText("#103 · build")).toBeVisible();

    const cdp = await page.context().newCDPSession(page);
    await cdp.send("Runtime.evaluate", {
      expression: axeSource,
      allowUnsafeEvalBlockedByCSP: true,
    });
    const accessibility = await page.evaluate(async () => (window as any).axe.run(document));
    await testInfo.attach("axe-results", {
      body: Buffer.from(JSON.stringify(accessibility.violations, null, 2)),
      contentType: "application/json",
    });
    expect(accessibility.violations).toBeDefined();
    await expectNoRendererErrors(errors);
  } finally {
    await app.close();
    await workspace.cleanup();
  }
});

test("moves only safe board cards and records approved GitHub links", async () => {
  const workspace = await createTestWorkspace();
  await seedRegistry(workspace, [workspace.repoA]);
  const { app, page, errors } = await launchControlCenter(workspace);
  try {
    await page.getByRole("button", { name: /^Board/ }).click();
    for (const lane of ["Backlog", "Ready", "Building", "QA", "Review", "Done", "Blocked", "Skipped"]) {
      await expect(page.locator(".lane-header", { hasText: lane })).toBeVisible();
    }
    const backlogCard = page.locator(".issue-card").filter({ has: page.locator(".issue-number", { hasText: /^#101/ }) });
    const readyLane = page.locator(".lane", { has: page.locator(".lane-header", { hasText: "Ready" }) });
    await backlogCard.dragTo(readyLane);
    await expect(readyLane.locator(".issue-card").filter({ has: page.locator(".issue-number", { hasText: /^#101/ }) })).toBeVisible();
    await waitForCommand(workspace, (entry) => entry.tool === "gh" && entry.args[0] === "project" && entry.args[1] === "item-edit");

    const rejected = await page.evaluate(async () => {
      try {
        await (window as any).supersaiyan.moveBoardCard("repo-e2e-100000", 103, "Ready");
        return "accepted";
      } catch (error) {
        return String(error);
      }
    });
    expect(rejected).toContain("controlled by the pipeline");

    await page.locator(".issue-card", { hasText: "#102" }).dblclick();
    await expect.poll(async () => (await readJsonLines(join(workspace.records, "electron-events.jsonl"))).some((event) => event.name === "external:url")).toBe(true);
    await expectNoRendererErrors(errors);
  } finally {
    await app.close();
    await workspace.cleanup();
  }
});

test("runs commands through fake Claude, enforces exclusivity, and stops active work", async () => {
  const workspace = await createTestWorkspace();
  await seedRegistry(workspace, [workspace.repoA]);
  const { app, page, errors } = await launchControlCenter(workspace);
  try {
    await page.getByRole("button", { name: "Setup" }).click();
    await expect(page.locator(".topbar-title")).toContainText("Terminal");
    await waitForCommand(workspace, (entry) => entry.tool === "claude-stdin" && entry.line === "/supersaiyan setup");

    await page.getByRole("button", { name: /^Overview/ }).click();
    await page.getByRole("button", { name: "Setup" }).click();
    await expect(page.locator(".notice")).toContainText("already active");

    const stopResult = await page.evaluate(async () => {
      const session = await (window as any).supersaiyan.startCommand("repo-e2e-100000", { verb: "stop", args: [] });
      return session.title;
    });
    expect(stopResult).toContain("stop");
    await waitForCommand(workspace, (entry) => entry.tool === "claude-stdin" && entry.line === "/supersaiyan stop");
    await expectNoRendererErrors(errors);
  } finally {
    await app.close();
    await workspace.cleanup();
  }
});

test("streams Smart Runner output from Claude stream-json", async () => {
  const workspace = await createTestWorkspace();
  await seedRegistry(workspace, [workspace.repoA]);
  const { app, page, errors } = await launchControlCenter(workspace);
  try {
    await page.getByRole("button", { name: /^Runner/ }).click();
    const runner = page.locator(".runner-shell");
    await runner.getByRole("button", { name: /Setup/ }).click();
    await waitForCommand(workspace, (entry) => entry.tool === "claude-print" && entry.line === "/supersaiyan setup");
    await expect(runner).toContainText("Running /supersaiyan setup");
    await expect(runner).toContainText("Bash");
    await expect(runner).toContainText("clean");
    await expect(runner).not.toContainText("Moonwalking");
    await expect(runner).not.toContainText("?forshortcuts");
    await expect(runner.getByRole("button", { name: "Raw terminal" })).toHaveCount(0);

    await runner.getByRole("button", { name: "New command" }).click();
    await runner.getByRole("button", { name: "Close & start new" }).click();
    await runner.getByRole("button", { name: /Run/ }).click();
    await waitForCommand(workspace, (entry) => entry.tool === "claude-print" && entry.line === "/supersaiyan run");
    await runner.getByRole("button", { name: "Stop" }).click();
    await waitForCommand(workspace, (entry) => entry.tool === "claude-print" && entry.line === "/supersaiyan stop");
    await expectNoRendererErrors(errors);
  } finally {
    await app.close();
    await workspace.cleanup();
  }
});

test("routes feature, phase, model-tier, and concurrent repository commands", async () => {
  const workspace = await createTestWorkspace();
  const today = new Date().toISOString().slice(0, 10);
  await writeFile(join(workspace.repoA, "docs", "supersaiyan", "runs", `${today}-demo.md`), [
    "[09:00:00] super-board run started",
    "[09:00:01] exiting cleanly",
    "",
  ].join("\n"));
  await seedRegistry(workspace, [workspace.repoA, workspace.repoB], { modelTier: "high" });
  const { app, page, errors } = await launchControlCenter(workspace);
  try {
    const prepareA = await page.evaluate(() => (window as any).supersaiyan.startCommand(
      "repo-e2e-100000",
      { verb: "prepare", args: ["chat"] },
    ));
    await waitForCommand(workspace, (entry) => entry.tool === "claude-stdin" && entry.line === "/supersaiyan prepare chat");
    await page.evaluate((sessionId) => (window as any).supersaiyan.closeTerminal(sessionId), prepareA.id);
    let phaseSession: any;
    await expect.poll(async () => {
      try {
        phaseSession = await page.evaluate(() => (window as any).supersaiyan.startCommand(
          "repo-e2e-100000",
          { verb: "prepare", args: ["platform", "--phase", "2"] },
        ));
        return true;
      } catch {
        return false;
      }
    }).toBe(true);
    await waitForCommand(workspace, (entry) => entry.tool === "claude-stdin" && entry.line === "/supersaiyan prepare platform --phase 2");

    const repoBSession = await page.evaluate(() => (window as any).supersaiyan.startCommand(
      "repo-e2e-100001",
      { verb: "lint", args: [] },
    ));
    expect(repoBSession.repoId).toBe("repo-e2e-100001");
    await waitForCommand(workspace, (entry) => entry.tool === "claude-stdin" && entry.line === "/supersaiyan lint" && entry.cwd.endsWith("repo-beta"));

    await page.evaluate((sessionId) => (window as any).supersaiyan.closeTerminal(sessionId), phaseSession.id);
    await page.waitForTimeout(500);
    await page.reload();
    await page.getByRole("button", { name: /^Overview/ }).click();
    await page.getByRole("button", { name: "Run", exact: true }).click();
    await waitForCommand(workspace, (entry) => entry.tool === "claude-stdin" && entry.line === "/supersaiyan run --high");
    await expectNoRendererErrors(errors);
  } finally {
    await app.close();
    await workspace.cleanup();
  }
});

test("refreshes feature discovery from filesystem watcher changes", async () => {
  const workspace = await createTestWorkspace();
  await seedRegistry(workspace, [workspace.repoA]);
  const { app, page } = await launchControlCenter(workspace);
  try {
    await page.getByRole("button", { name: /^Features/ }).click();
    await expect(page.getByText("new-watched-feature", { exact: true })).toHaveCount(0);
    await writeFile(join(workspace.repoA, "docs", "superpowers", "specs", "new-watched-feature-design.md"), "# Watched\n");
    await expect(page.getByText("new-watched-feature", { exact: true })).toBeVisible({ timeout: 20_000 });
  } finally {
    await app.close();
    await workspace.cleanup();
  }
});

test("opens multiple PTYs, preserves cwd, handles ANSI output, and persists settings", async () => {
  const workspace = await createTestWorkspace();
  await seedRegistry(workspace, [workspace.repoA]);
  const { app, page, errors } = await launchControlCenter(workspace);
  try {
    await page.getByRole("button", { name: /^Terminal/ }).click();
    await page.getByRole("button", { name: "Open shell" }).click();
    await expect(page.locator(".terminal-tab", { hasText: "Shell" })).toBeVisible();
    const terminal = page.getByLabel("Terminal Shell");
    await terminal.click();
    await page.keyboard.type("printf '\\033[32mPTY_OK:%s\\033[0m\\n' \"$PWD\"");
    await page.keyboard.press("Enter");
    await expect(page.locator(".xterm-rows")).toContainText(`PTY_OK:${workspace.repoA}`);
    await page.getByTitle("New shell").click();
    await expect(page.locator(".terminal-tab")).toHaveCount(2);
    await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].setSize(960, 680));
    await expect(page.locator(".control-center")).toBeVisible();
    await page.keyboard.press("Tab");
    await expect(page.locator(":focus")).toBeVisible();
    await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].setSize(1440, 920));

    await page.getByRole("button", { name: /^Settings/ }).click();
    await page.getByLabel("Idle refresh").fill("77");
    await page.getByLabel("Model tier").selectOption("high");
    await expectNoRendererErrors(errors);
  } finally {
    await app.close();
  }

  const restarted = await launchControlCenter(workspace);
  try {
    await restarted.page.getByRole("button", { name: /^Settings/ }).click();
    await expect(restarted.page.getByLabel("Idle refresh")).toHaveValue("77");
    await expect(restarted.page.getByLabel("Model tier")).toHaveValue("high");
  } finally {
    await restarted.app.close();
    await workspace.cleanup();
  }
});
