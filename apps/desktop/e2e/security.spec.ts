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
    const commands = await readJsonLines(join(workspace.records, "commands.jsonl"));
    expect(commands.filter((entry) => entry.tool === "claude")).toEqual([]);
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
