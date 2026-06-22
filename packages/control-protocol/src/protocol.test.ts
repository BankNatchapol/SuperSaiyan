import { describe, expect, it } from "vitest";
import { boardMoveSchema, commandRequestSchema, laneNames } from "./index";

describe("control protocol", () => {
  it("locks the canonical lane order", () => {
    expect(laneNames).toEqual(["Backlog", "Ready", "Building", "QA", "Review", "Done", "Blocked", "Skipped"]);
  });

  it("rejects arbitrary command verbs", () => {
    expect(commandRequestSchema.safeParse({ verb: "rm", args: [] }).success).toBe(false);
  });

  it("allows only safe board targets", () => {
    expect(boardMoveSchema.safeParse({ repoId: "repo-12345678", issueNumber: 7, targetStatus: "Ready" }).success).toBe(true);
    expect(boardMoveSchema.safeParse({ repoId: "repo-12345678", issueNumber: 7, targetStatus: "Done" }).success).toBe(false);
  });
});
