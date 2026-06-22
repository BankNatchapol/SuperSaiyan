import { expect, test } from "@playwright/test";
import { FuseV1Options, getCurrentFuseWire } from "@electron/fuses";
import { access, constants } from "node:fs/promises";
import { join, resolve } from "node:path";
import { createTestWorkspace, launchPackagedControlCenter, packagedExecutable, seedRegistry } from "./helpers";

test("@packaged packaged app contains runtime payload and launches PTY", async () => {
  const executable = packagedExecutable();
  await access(executable, constants.X_OK);
  const appBundle = resolve(executable, "../../..");
  const fuses = await getCurrentFuseWire(appBundle);
  expect(fuses[FuseV1Options.RunAsNode]).toBe(48);
  expect(fuses[FuseV1Options.EnableNodeOptionsEnvironmentVariable]).toBe(48);
  expect(fuses[FuseV1Options.EnableNodeCliInspectArguments]).toBe(48);
  expect(fuses[FuseV1Options.EnableEmbeddedAsarIntegrityValidation]).toBe(49);
  expect(fuses[FuseV1Options.OnlyLoadAppFromAsar]).toBe(49);
  const resources = resolve(executable, "../../Resources");
  for (const relative of [
    "install.sh",
    "scripts/super-board-status.py",
    "skills/supersaiyan/SKILL.md",
    "templates/task-file.md",
    `node-pty/prebuilds/darwin-${process.arch}/pty.node`,
    `node-pty/prebuilds/darwin-${process.arch}/spawn-helper`,
  ]) {
    await access(join(resources, relative), relative.endsWith("spawn-helper") ? constants.X_OK : constants.R_OK);
  }

  const workspace = await createTestWorkspace();
  await seedRegistry(workspace, [workspace.repoA]);
  const packaged = await launchPackagedControlCenter(workspace);
  try {
    const { page } = packaged;
    await page.getByRole("button", { name: /^Terminal/ }).click();
    await page.getByRole("button", { name: "Open shell" }).click();
    await page.getByLabel("Terminal Shell").click();
    await page.keyboard.type("echo PACKAGED_PTY_OK");
    await page.keyboard.press("Enter");
    await expect(page.locator(".xterm-rows")).toContainText("PACKAGED_PTY_OK");
  } finally {
    await packaged.close();
    await workspace.cleanup();
  }
});
