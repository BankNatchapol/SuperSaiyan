import { describe, expect, it } from "vitest";
import { isPathInside } from "./index";

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
