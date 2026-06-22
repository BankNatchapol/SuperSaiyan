import { chmod, stat } from "node:fs/promises";
import { createRequire } from "node:module";
import { dirname, resolve } from "node:path";

if (process.platform !== "darwin") process.exit(0);

const require = createRequire(import.meta.url);
const packageRoot = resolve(dirname(require.resolve("node-pty")), "..");

for (const arch of ["arm64", "x64"]) {
  const helper = resolve(packageRoot, "prebuilds", `darwin-${arch}`, "spawn-helper");
  try {
    const mode = (await stat(helper)).mode;
    await chmod(helper, mode | 0o111);
  } catch (error) {
    if (error?.code !== "ENOENT") throw error;
  }
}
