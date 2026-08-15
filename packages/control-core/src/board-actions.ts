// The one board mutation the Control Center performs: dragging a card between the lanes a human
// owns. Separate from board.ts (read path) because the guardrails below need a full snapshot,
// and snapshot.ts imports board.ts — keeping the write path downstream of both avoids an
// import cycle.
import type { LaneName, RepositoryRecord } from "@supersaiyan/control-protocol";
import { laneNames } from "@supersaiyan/control-protocol";
import { buildSnapshot } from "./snapshot";
import { run, safeJson } from "./shared";

const MUTABLE_SOURCES = new Set<LaneName>(["Backlog", "Ready", "Blocked", "Skipped"]);

export async function moveBoardCard(repository: RepositoryRecord, issueNumber: number, targetStatus: "Backlog" | "Ready"): Promise<void> {
  const snapshot = await buildSnapshot(repository);
  const card = laneNames.flatMap((lane) => snapshot.lanes[lane]).find((candidate) => candidate.number === issueNumber);
  if (!card) throw new Error(`Issue #${issueNumber} is not on the configured board`);
  if (!MUTABLE_SOURCES.has(card.status)) throw new Error(`Cards in ${card.status} are controlled by the pipeline`);
  if (card.state !== "OPEN") throw new Error("Closed issues cannot be moved");
  if (card.assignees.length) throw new Error("Assigned issues cannot be moved");
  if (!snapshot.config) throw new Error("No active board config");

  const fields = safeJson<{ fields?: Array<{ id: string; name: string; options?: Array<{ id: string; name: string }> }> }>(
    await run(repository.path, "gh", ["project", "field-list", String(snapshot.config.projectNumber), "--owner", snapshot.config.projectOwner, "--format", "json"]),
    {},
  );
  const statusField = fields.fields?.find((field) => field.name === "Status");
  const option = statusField?.options?.find((candidate) => candidate.name === targetStatus);
  if (!statusField || !option) throw new Error(`Project Status is missing ${targetStatus}`);
  const projectId = await run(repository.path, "gh", ["project", "view", String(snapshot.config.projectNumber), "--owner", snapshot.config.projectOwner, "--format", "json", "--jq", ".id"]);
  await run(repository.path, "gh", [
    "project", "item-edit",
    "--id", card.id,
    "--project-id", projectId,
    "--field-id", statusField.id,
    "--single-select-option-id", option.id,
  ]);
}
