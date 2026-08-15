import { expect, test } from "@playwright/test";
import { symlink, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { createTestWorkspace, expectNoRendererErrors, launchControlCenter, readJsonLines, seedRegistry } from "./helpers";

test("enforces Electron isolation and rejects unsafe IPC payloads", async () => {
  const workspace = await createTestWorkspace();
  await seedRegistry(workspace, [workspace.repoA]);
  const { app, page, errors } = await launchControlCenter(workspace);
  try {
    const preferences = await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].webContents.getLastWebPreferences());
    expect(preferences.nodeIntegration).toBe(false);
    expect(preferences.contextIsolation).toBe(true);
    expect(preferences.sandbox).toBe(true);

    // Wait until the first snapshot finishes so diagnostic `claude --version`
    // has been recorded. The security property is that rejected IPC did not
    // spawn a command — not that Claude never ran. E2E fixtures already have
    // SKILL.md, so `plugin list` is skipped.
    await expect(page.getByText("E2E Project · full · main")).toBeVisible();
    const commandLog = join(workspace.records, "commands.jsonl");
    const before = await readJsonLines(commandLog);

    const checks = await page.evaluate(async () => {
      const bridge = (window as any).supersaiyan;
      const attempt = async (action: () => Promise<unknown>) => {
        try { await action(); return "accepted"; } catch (error) { return String(error); }
      };
      return {
        url: await attempt(() => bridge.openExternal("file:///etc/passwd")),
        domain: await attempt(() => bridge.openExternal("https://example.com")),
        path: await attempt(() => bridge.openPath("repo-e2e-100000", "../../etc/passwd")),
        verb: await attempt(() => bridge.startCommand("repo-e2e-100000", { verb: "rm", args: [] })),
        newline: await attempt(() => bridge.startCommand("repo-e2e-100000", { verb: "run", args: ["ok\nbad"] })),
        oversized: await attempt(() => bridge.writeTerminal("session-invalid", "x".repeat(70_000))),
      };
    });
    for (const result of Object.values(checks)) expect(result).not.toBe("accepted");
    // startCommand records `claude --name supersaiyan-ui-<repo>-<verb>` (and
    // stdin later), not a `"rm"` argv token — so assert no new jsonl lines.
    expect(await readJsonLines(commandLog)).toEqual(before);
    await expectNoRendererErrors(errors);
  } finally {
    await app.close();
    await workspace.cleanup();
  }
});

test("rejects symlink escapes and recovers from GitHub outages", async () => {
  const workspace = await createTestWorkspace();
  await seedRegistry(workspace, [workspace.repoA]);
  const outside = join(workspace.root, "outside.txt");
  await writeFile(outside, "secret");
  await symlink(outside, join(workspace.repoA, "outside-link"));
  const offline = await launchControlCenter(workspace, { SUPERSAIYAN_E2E_GH_OFFLINE: "1" });
  try {
    await offline.page.getByRole("button", { name: /^Board/ }).click();
    await expect(offline.page.locator(".issue-card")).toHaveCount(0);
    const result = await offline.page.evaluate(async () => {
      try {
        await (window as any).supersaiyan.openPath("repo-e2e-100000", "outside-link");
        return "accepted";
      } catch (error) {
        return String(error);
      }
    });
    expect(result).toContain("outside");
  } finally {
    await offline.app.close();
  }

  const recovered = await launchControlCenter(workspace);
  try {
    await expect(recovered.page.getByText("E2E Project · full · main")).toBeVisible();
  } finally {
    await recovered.app.close();
    await workspace.cleanup();
  }
});
