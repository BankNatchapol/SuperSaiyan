import type { BoardCard, LaneName } from "@supersaiyan/control-protocol";

export function isBoardCardMovable(
  card: Pick<BoardCard, "assignees" | "state" | "status">,
): boolean {
  return ["Backlog", "Ready", "Blocked", "Skipped"].includes(card.status)
    && card.state === "OPEN"
    && card.assignees.length === 0;
}

export function isBoardDropTarget(lane: LaneName): lane is "Backlog" | "Ready" {
  return lane === "Backlog" || lane === "Ready";
}
