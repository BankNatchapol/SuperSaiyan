// Debounced filesystem watching of the config roots and doc trees a snapshot is built from, so
// the Control Center refreshes when the pipeline or a human edits them.
import { join } from "node:path";
import chokidar, { type FSWatcher } from "chokidar";
import type { RepositoryRecord } from "@supersaiyan/control-protocol";
import { CONFIG_ROOTS } from "./config";

export class RepositoryWatchService {
  private readonly watchers = new Map<string, FSWatcher>();

  watch(repository: RepositoryRecord, onChange: () => void): void {
    if (this.watchers.has(repository.id)) return;
    const targets = [
      ...CONFIG_ROOTS.map((root) => join(repository.path, root)),
      join(repository.path, "docs", "superpowers"),
      join(repository.path, "docs", "supersaiyan"),
      join(repository.path, "docs", "super-board"),
    ];
    const watcher = chokidar.watch(targets, { ignoreInitial: true, depth: 5 });
    let timer: NodeJS.Timeout | undefined;
    watcher.on("all", () => {
      clearTimeout(timer);
      timer = setTimeout(onChange, 250);
    });
    this.watchers.set(repository.id, watcher);
  }

  async unwatch(repoId: string): Promise<void> {
    const watcher = this.watchers.get(repoId);
    if (watcher) await watcher.close();
    this.watchers.delete(repoId);
  }

  async close(): Promise<void> {
    await Promise.all([...this.watchers.values()].map((watcher) => watcher.close()));
    this.watchers.clear();
  }
}
