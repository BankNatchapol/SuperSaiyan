import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { deepMerge, resolveExtends } from "./config";

describe("deepMerge", () => {
  it("lets the overlay win per key and keeps base-only keys", () => {
    expect(deepMerge({ variant: "full", rebuild_cap: 2 }, { variant: "lite" })).toEqual({
      variant: "lite",
      rebuild_cap: 2,
    });
  });

  it("merges nested objects recursively instead of replacing them", () => {
    expect(
      deepMerge(
        { project: { owner: "@me", number: 3, title: "Base" }, notifications: { telegram: true } },
        { project: { number: 7 } },
      ),
    ).toEqual({
      project: { owner: "@me", number: 7, title: "Base" },
      notifications: { telegram: true },
    });
  });

  it("replaces arrays rather than concatenating them", () => {
    expect(deepMerge({ labels: ["a", "b"] }, { labels: ["c"] })).toEqual({ labels: ["c"] });
  });

  it("replaces base outright when the two sides are different shapes", () => {
    expect(deepMerge({ worker_backend: { build: "codex-exec" } }, { worker_backend: "claude-p" })).toEqual({
      worker_backend: "claude-p",
    });
  });
});

describe("resolveExtends", () => {
  let directory: string;

  beforeEach(async () => {
    directory = await mkdtemp(join(tmpdir(), "supersaiyan-configs-"));
  });

  afterEach(async () => {
    await rm(directory, { recursive: true, force: true });
  });

  const writeConfig = (slug: string, config: unknown) =>
    writeFile(join(directory, `${slug}.json`), JSON.stringify(config));

  it("returns the config unchanged when there is no extends key", async () => {
    const config = { project: { owner: "@me", number: 3 } };
    expect(await resolveExtends(directory, config)).toEqual(config);
  });

  it("returns the config unchanged when the extends target is missing", async () => {
    const config = { extends: "absent", variant: "lite" };
    expect(await resolveExtends(directory, config)).toEqual({ extends: "absent", variant: "lite" });
  });

  it("inherits base fields and strips the extends key from the merged output", async () => {
    await writeConfig("base", {
      project: { owner: "@me", number: 3, title: "Board" },
      rebuild_cap: 2,
      variant: "full",
    });
    expect(await resolveExtends(directory, { extends: "base", variant: "lite" })).toEqual({
      project: { owner: "@me", number: 3, title: "Board" },
      rebuild_cap: 2,
      variant: "lite",
    });
  });

  it("refuses a chained extends and returns the overlay unchanged", async () => {
    await writeConfig("root", { project: { owner: "@me", number: 3 } });
    await writeConfig("middle", { extends: "root", rebuild_cap: 5 });
    expect(await resolveExtends(directory, { extends: "middle", variant: "lite" })).toEqual({
      extends: "middle",
      variant: "lite",
    });
  });

  it("treats an unparseable base config as empty rather than throwing", async () => {
    await writeFile(join(directory, "broken.json"), "{ not json");
    expect(await resolveExtends(directory, { extends: "broken", variant: "lite" })).toEqual({
      variant: "lite",
    });
  });
});
