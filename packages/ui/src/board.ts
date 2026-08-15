import type { BoardCard, LaneName } from "@supersaiyan/control-protocol";

const movableStatuses: readonly LaneName[] = ["Backlog", "Ready", "Blocked", "Skipped"];

export function isBoardCardMovable(
  card: Pick<BoardCard, "assignees" | "state" | "status">,
): boolean {
  return movableStatuses.includes(card.status)
    && card.state === "OPEN"
    && card.assignees.length === 0;
}

export function isBoardDropTarget(lane: LaneName): lane is "Backlog" | "Ready" {
  return lane === "Backlog" || lane === "Ready";
}
