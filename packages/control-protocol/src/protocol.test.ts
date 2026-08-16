import { describe, expect, it } from "vitest";
import { boardMoveSchema, commandRequestSchema, dropTargetLaneNames, laneNames, movableLaneNames } from "./index";

describe("control protocol", () => {
  it("locks the canonical lane order", () => {
    expect(laneNames).toEqual(["Backlog", "Ready", "Building", "QA", "Review", "Done", "Blocked", "Skipped"]);
  });

  it("locks the lanes a human may move a card out of", () => {
    expect(movableLaneNames).toEqual(["Backlog", "Ready", "Blocked", "Skipped"]);
    expect(movableLaneNames.every((lane) => laneNames.includes(lane))).toBe(true);
  });

  it("locks the lanes a human may drop a card into", () => {
    expect(dropTargetLaneNames).toEqual(["Backlog", "Ready"]);
    expect(dropTargetLaneNames.every((lane) => laneNames.includes(lane))).toBe(true);
  });

  it("rejects arbitrary command verbs", () => {
    expect(commandRequestSchema.safeParse({ verb: "rm", args: [] }).success).toBe(false);
  });

  it("allows only safe board targets", () => {
    for (const targetStatus of dropTargetLaneNames) {
      expect(boardMoveSchema.safeParse({ repoId: "repo-12345678", issueNumber: 7, targetStatus }).success).toBe(true);
    }
    expect(boardMoveSchema.safeParse({ repoId: "repo-12345678", issueNumber: 7, targetStatus: "Done" }).success).toBe(false);
  });
});
