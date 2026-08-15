import { describe, expect, it } from "vitest";
import { formatWorkerBackend, isPathInside } from "./index";

const repository = {
  id: "repo-12345678",
  path: "/tmp/project",
  name: "project",
  addedAt: "",
  lastOpenedAt: "",
};

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
    expect(formatWorkerBackend("")).toBe("workflow");
  });
});
