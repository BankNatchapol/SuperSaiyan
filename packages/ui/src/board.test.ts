import { describe, expect, it } from "vitest";
import type { BoardCard } from "@supersaiyan/control-protocol";
import { dropTargetLaneNames, laneNames, movableLaneNames } from "@supersaiyan/control-protocol";
import { isBoardCardMovable, isBoardDropTarget } from "./board";

function card(overrides: Partial<BoardCard> = {}): BoardCard {
  return {
    id: "card-1",
    number: 47,
    title: "Focused UI tests",
    status: "Backlog",
    labels: [],
    assignees: [],
    state: "OPEN",
    rebuildCount: 0,
    ...overrides,
  };
}

describe("isBoardCardMovable", () => {
  it.each([...movableLaneNames])(
    "allows an unassigned open card in %s",
    (status) => {
      expect(isBoardCardMovable(card({ status }))).toBe(true);
    },
  );

  it.each(laneNames.filter((lane) => !movableLaneNames.includes(lane)))(
    "rejects a card in %s",
    (status) => {
      expect(isBoardCardMovable(card({ status }))).toBe(false);
    },
  );

  it("rejects a closed card", () => {
    expect(isBoardCardMovable(card({ state: "CLOSED" }))).toBe(false);
  });

  it("rejects an assigned card", () => {
    expect(isBoardCardMovable(card({ assignees: ["octocat"] }))).toBe(false);
  });
});

describe("isBoardDropTarget", () => {
  it.each([...dropTargetLaneNames])("allows %s", (lane) => {
    expect(isBoardDropTarget(lane)).toBe(true);
  });

  it.each(laneNames.filter((lane) => !dropTargetLaneNames.some((target) => target === lane)))(
    "rejects %s",
    (lane) => {
      expect(isBoardDropTarget(lane)).toBe(false);
    },
  );
});
