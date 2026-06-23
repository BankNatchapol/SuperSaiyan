import { expect, test } from "@playwright/test";
import { createTestWorkspace, launchControlCenter, seedRegistry } from "./helpers";

test("window is transparent and renderer root has no background", async () => {
  const workspace = await createTestWorkspace();
  await seedRegistry(workspace, [workspace.repoA]);
  const { app, page } = await launchControlCenter(workspace);
  try {
    const isTransparent = await app.evaluate(({ BrowserWindow }) =>
      BrowserWindow.getAllWindows()[0].isTransparent()
    );
    expect(isTransparent).toBe(true);

    const bgColor = await app.evaluate(({ BrowserWindow }) =>
      BrowserWindow.getAllWindows()[0].getBackgroundColor()
    );
    expect(bgColor).toBe("#00000000");

    const bodyBg = await page.evaluate(() =>
      getComputedStyle(document.body).backgroundColor
    );
    expect(bodyBg).toBe("rgba(0, 0, 0, 0)");
  } finally {
    await app.close();
    await workspace.cleanup();
  }
});
