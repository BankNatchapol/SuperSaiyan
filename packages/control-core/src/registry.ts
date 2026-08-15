// Persisted list of registered repositories plus app preferences, and the validation that
// turns a user-picked directory into a RepositoryRecord.
import { createHash } from "node:crypto";
import { mkdir, readFile, realpath, stat, writeFile } from "node:fs/promises";
import { basename, dirname, join } from "node:path";
import type { AppPreferences, RepositoryRecord } from "@supersaiyan/control-protocol";
import { exists, run, safeJson } from "./shared";

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
