// Board config discovery, `extends` inheritance, and display formatting. `deepMerge` and
// `resolveExtends` are exported for direct unit tests (src/config.test.ts) but deliberately
// stay out of the package barrel — they are inheritance internals, not part of the public API
// apps/desktop consumes.
import { readFile, readdir } from "node:fs/promises";
import { join } from "node:path";
import type { BoardConfigSummary } from "@supersaiyan/control-protocol";
import { exists, safeJson } from "./shared";

// Config/state root search order, highest priority first: the vendor-neutral root (new
// onboards write only here), then the two Claude-Code-branded roots this project used before
// multi-tool worker_backend support (current, then legacy). Full relative paths, not bare
// names — `.supersaiyan` has no `.claude/` prefix, the other two do, so every consumer of this
// list can `join(repoPath, root, ...)` directly with no per-entry special-casing. See
// scripts/super-board-status.py's config_roots() (Python's independent, but semantically
// identical, resolver) and references/config-schema.json.
export const CONFIG_ROOTS: readonly string[] = [".supersaiyan", ".claude/supersaiyan", ".claude/super-board"];

// Recursive merge matching the bash dispatcher's `jq -s '.[0] * .[1]'`: overlay wins per-key;
// when both sides are plain objects at a key, merge recursively, otherwise overlay replaces
// base outright (this includes arrays — they are never concatenated).
export function deepMerge(base: unknown, overlay: unknown): unknown {
  const isPlainObject = (v: unknown): v is Record<string, unknown> =>
    typeof v === "object" && v !== null && !Array.isArray(v);
  if (isPlainObject(base) && isPlainObject(overlay)) {
    const merged: Record<string, unknown> = { ...base };
    for (const [key, value] of Object.entries(overlay)) {
      merged[key] = key in base ? deepMerge(base[key], value) : value;
    }
    return merged;
  }
  return overlay;
}

// A config may set `extends: "<slug>"` to inherit shared fields (project, variant,
// rebuild_cap, notifications, ...) from another config file in the same directory — see
// skills/super-board/references/config-schema.json (`extends`). Without this, an overlay
// config (which never sets `project` itself) would silently fail discoverConfigs' `project.number`
// check and never appear in the Control Center at all. Resolution failures (missing/chained
// base) return the config unchanged — this is a display path, not a dispatcher, so a broken
// overlay should just fall out of the same "missing project fields" skip below it always had,
// not crash discovery for every other board.
export async function resolveExtends(
  directory: string,
  config: Record<string, any>,
): Promise<Record<string, any>> {
  const ext = config.extends;
  if (!ext || typeof ext !== "string") return config;
  const basePath = join(directory, `${ext}.json`);
  if (!(await exists(basePath))) return config;
  const base = safeJson<Record<string, any>>(await readFile(basePath, "utf8"), {});
  if (base.extends) return config;
  const merged = deepMerge(base, config) as Record<string, any>;
  delete merged.extends;
  return merged;
}

// Display-only summary of config.worker_backend for the Control Center. The value is either a
// single backend name for the whole run or a per-lane object (see
// skills/super-board/references/backends.md); the object form renders as a compact
// `build=… qa=… review=…` string because String() on it would yield "[object Object]", and lane
// keys omitted from it default to claude-p, matching the dispatcher's own resolution. The
// dispatcher is the authority on validity (it exits 78 and names the offending lane), so this
// only has to render a malformed value legibly — anything non-string collapses to "invalid"
// rather than being stringified or left blank.
export function formatWorkerBackend(value: unknown): string {
  const laneBackend = (lane: unknown): string => {
    if (lane === undefined || lane === null) return "claude-p"; // dispatcher's omitted-lane default
    return typeof lane === "string" ? lane : "invalid";
  };
  if (value && typeof value === "object" && !Array.isArray(value)) {
    const lanes = value as Record<string, unknown>;
    return ["build", "qa", "review"].map((lane) => `${lane}=${laneBackend(lanes[lane])}`).join(" ");
  }
  if (value === undefined || value === null) return "workflow";
  if (typeof value === "string") return value || "workflow";
  return "invalid";
}

export async function discoverConfigs(repoPath: string): Promise<BoardConfigSummary[]> {
  const found = new Map<string, { summary: BoardConfigSummary; rootIndex: number }>();
  // `.entries()` rather than an index loop: indexing a readonly array yields `string | undefined`
  // under the strict-index checks this package compiles with, and `root` here is always defined.
  for (const [rootIndex, root] of CONFIG_ROOTS.entries()) {
    const directory = join(repoPath, root, "configs");
    if (!(await exists(directory))) continue;
    for (const file of (await readdir(directory)).filter((name) => name.endsWith(".json")).sort()) {
      const path = join(directory, file);
      let config = safeJson<Record<string, any>>(await readFile(path, "utf8"), {});
      config = await resolveExtends(directory, config);
      const slug = file.slice(0, -5);
      if (!config.project?.number || !config.project?.owner) continue;
      // Results merge across roots; on a same-slug collision the higher-priority root (lower
      // rootIndex) wins. A substring check like `directory.includes("supersaiyan")` would be
      // ambiguous here — `.supersaiyan` and `.claude/supersaiyan` both contain "supersaiyan" —
      // so priority is tracked by index into CONFIG_ROOTS instead.
      const existing = found.get(slug);
      if (existing && existing.rootIndex <= rootIndex) continue;
      found.set(slug, {
        rootIndex,
        summary: {
          slug,
          path,
          projectOwner: String(config.project.owner),
          projectNumber: Number(config.project.number),
          projectTitle: String(config.project.title || slug),
          variant: String(config.variant || "full"),
          baseBranch: String(config.base_branch || "main"),
          workerBackend: formatWorkerBackend(config.worker_backend),
        },
      });
    }
  }
  return [...found.values()].map((entry) => entry.summary);
}

export async function activeConfig(repoPath: string, configs: BoardConfigSummary[]): Promise<BoardConfigSummary | undefined> {
  for (const root of CONFIG_ROOTS) {
    const active = join(repoPath, root, "active");
    if (await exists(active)) {
      const slug = (await readFile(active, "utf8")).trim();
      const match = configs.find((config) => config.slug === slug);
      if (match) return match;
    }
  }
  return configs.length === 1 ? configs[0] : undefined;
}
