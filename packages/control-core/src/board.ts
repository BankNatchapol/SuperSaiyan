// Read-only GitHub Project board access: `gh project item-list` → lane-bucketed BoardCards.
// The write side (moveBoardCard) lives in board-actions.ts because it needs a full snapshot,
// and snapshot.ts already depends on this module.
import type { BoardCard, BoardConfigSummary, LaneName } from "@supersaiyan/control-protocol";
import { emptyLanes, laneNames } from "@supersaiyan/control-protocol";
import { run, safeJson } from "./shared";

type GhProjectItem = {
  id: string;
  status?: string;
  content?: {
    type?: string;
    number?: number;
    title?: string;
    url?: string;
    repository?: string;
    state?: string;
    labels?: Array<{ name?: string }> | string[];
    assignees?: Array<{ login?: string }> | string[];
    body?: string;
  };
};

function normalizeNames(values: unknown): string[] {
  if (!Array.isArray(values)) return [];
  return values.flatMap((value) => {
    if (typeof value === "string") return [value];
    if (value && typeof value === "object") {
      const object = value as Record<string, unknown>;
      return [String(object.name ?? object.login ?? "")].filter(Boolean);
    }
    return [];
  });
}

function normalizeStatus(status?: string): LaneName {
  return laneNames.includes(status as LaneName) ? (status as LaneName) : "Backlog";
}

export async function fetchBoard(repoPath: string, config?: BoardConfigSummary): Promise<Record<LaneName, BoardCard[]>> {
  const lanes = emptyLanes();
  if (!config) return lanes;
  const raw = await run(repoPath, "gh", [
    "project",
    "item-list",
    String(config.projectNumber),
    "--owner",
    config.projectOwner,
    "--format",
    "json",
    "--limit",
    "500",
  ], 30_000);
  const payload = safeJson<{ items?: GhProjectItem[] }>(raw, {});
  for (const item of payload.items ?? []) {
    const content = item.content;
    if (content?.type !== "Issue" || !content.number) continue;
    const status = normalizeStatus(item.status);
    const body = content.body || "";
    const dependency = body.match(/depends on:\s*#(\d+)/i);
    const labels = normalizeNames(content.labels);
    lanes[status].push({
      id: item.id,
      number: content.number,
      title: content.title || `Issue #${content.number}`,
      status,
      url: content.url,
      repository: content.repository,
      labels,
      assignees: normalizeNames(content.assignees),
      state: content.state === "CLOSED" ? "CLOSED" : "OPEN",
      dependency: dependency ? Number(dependency[1]) : undefined,
      rebuildCount: Number(labels.find((label) => /^loop:rebuild-\d+$/.test(label))?.split("-").at(-1) || 0),
    });
  }
  for (const lane of laneNames) lanes[lane].sort((a, b) => b.number - a.number);
  return lanes;
}
