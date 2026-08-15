import { describe, expect, it } from "vitest";
import * as controlCore from "./index";
import { formatWorkerBackend, isPathInside } from "./index";

const repository = {
  id: "repo-12345678",
  path: "/tmp/project",
  name: "project",
  addedAt: "",
  lastOpenedAt: "",
};

// The barrel is the only entry point apps/desktop/src/main.ts has into this package, so the
// module split behind it must not add or drop names.
describe("package barrel", () => {
  it("publishes exactly the documented public surface", () => {
    expect(Object.keys(controlCore).sort()).toEqual([
      "RepositoryRegistry",
      "RepositoryWatchService",
      "buildSnapshot",
      "createSessionId",
      "formatWorkerBackend",
      "isPathInside",
      "moveBoardCard",
      "registerRepository",
      "runnerEventsFromClaudeJson",
      "runnerEventsFromClaudeJsonLine",
    ]);
  });
});

describe("control core safety", () => {
  it("accepts paths inside a registered repository", () => {
    expect(isPathInside(repository, "docs/spec.md")).toBe(true);
  });

  it("rejects path traversal", () => {
    expect(isPathInside(repository, "../../etc/passwd")).toBe(false);
  });
});

describe("formatWorkerBackend", () => {
  it("renders a per-lane string map as a compact summary", () => {
    const rendered = formatWorkerBackend({
      build: "codex-exec",
      qa: "cursor-agent",
      review: "claude-p",
    });
    expect(rendered).toBe("build=codex-exec qa=cursor-agent review=claude-p");
    expect(rendered).not.toContain("[object Object]");
  });

  it("defaults omitted lane keys to claude-p", () => {
    expect(formatWorkerBackend({ qa: "cursor-agent" })).toBe(
      "build=claude-p qa=cursor-agent review=claude-p",
    );
  });

  it("passes a string backend through unchanged", () => {
    expect(formatWorkerBackend("codex-exec")).toBe("codex-exec");
  });

  it("treats a missing worker_backend as workflow", () => {
    expect(formatWorkerBackend(undefined)).toBe("workflow");
    expect(formatWorkerBackend(null)).toBe("workflow");
    expect(formatWorkerBackend("")).toBe("workflow");
  });

  // The dispatcher rejects these (exit 78); the summary just has to stay readable.
  it("renders a malformed lane value as invalid, never [object Object]", () => {
    const rendered = formatWorkerBackend({ build: { name: "codex-exec" }, qa: "cursor-agent" });
    expect(rendered).toBe("build=invalid qa=cursor-agent review=claude-p");
    expect(rendered).not.toContain("[object Object]");
  });

  it("renders a non-object, non-string worker_backend as invalid rather than blank", () => {
    expect(formatWorkerBackend([])).toBe("invalid");
    expect(formatWorkerBackend(["codex-exec"])).toBe("invalid");
    expect(formatWorkerBackend(7)).toBe("invalid");
  });
});
