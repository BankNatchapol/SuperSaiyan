// Public surface of @supersaiyan/control-core, consumed by apps/desktop/src/main.ts. This file
// is a barrel only — behavior lives in the focused modules below, whose internal dependency
// order is shared → config/registry/board → snapshot → board-actions, with no cycles:
//
//   shared.ts        path/process/JSON helpers, repository path containment, session ids
//   config.ts        config roots, `extends` inheritance, discovery/selection, backend display
//   registry.ts      persisted repository list + preferences
//   board.ts         GitHub Project board reads
//   snapshot.ts      diagnostics, features, run/structured status, buildSnapshot
//   board-actions.ts board card moves
//   watcher.ts       filesystem watching for refresh
//   runner-events.ts Claude Code stream-json → RunnerEvent
export { moveBoardCard } from "./board-actions";
export { formatWorkerBackend } from "./config";
export { RepositoryRegistry, registerRepository } from "./registry";
export { createSessionId, isPathInside } from "./shared";
export { buildSnapshot } from "./snapshot";
export { RepositoryWatchService } from "./watcher";
export { runnerEventsFromClaudeJson, runnerEventsFromClaudeJsonLine } from "./runner-events";
