import type { BoardCard, DropTargetLaneName, LaneName } from "@supersaiyan/control-protocol";
import { dropTargetLaneNames, movableLaneNames } from "@supersaiyan/control-protocol";

export function isBoardCardMovable(
  card: Pick<BoardCard, "assignees" | "state" | "status">,
): boolean {
  return movableLaneNames.includes(card.status)
    && card.state === "OPEN"
    && card.assignees.length === 0;
}

export function isBoardDropTarget(lane: LaneName): lane is DropTargetLaneName {
  return dropTargetLaneNames.some((target) => target === lane);
}
