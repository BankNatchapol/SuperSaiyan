// Path, process, and parsing helpers shared by every control-core module. This module is the
// bottom of the internal dependency graph — it must not import from any sibling module, so the
// package stays free of import cycles.
import { randomUUID } from "node:crypto";
import { access } from "node:fs/promises";
import { constants } from "node:fs";
import { isAbsolute, relative, resolve } from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { RepositoryRecord } from "@supersaiyan/control-protocol";

const exec = promisify(execFile);

export async function exists(path: string): Promise<boolean> {
  try {
    await access(path, constants.F_OK);
    return true;
  } catch {
    return false;
  }
}

export async function run(cwd: string, command: string, args: string[], timeout = 15_000): Promise<string> {
  const result = await exec(command, args, {
    cwd,
    timeout,
    encoding: "utf8",
    env: { ...process.env, NO_COLOR: "1" },
    maxBuffer: 8 * 1024 * 1024,
  });
  return result.stdout.trim();
}

export function safeJson<T>(text: string, fallback: T): T {
  try {
    return JSON.parse(text) as T;
  } catch {
    return fallback;
  }
}

export function isPathInside(repository: RepositoryRecord, candidate: string): boolean {
  const rel = relative(repository.path, resolve(repository.path, candidate));
  return rel === "" || (rel !== ".." && !rel.startsWith(`..${process.platform === "win32" ? "\\" : "/"}`) && !isAbsolute(rel));
}

export const createSessionId = (): string => `session-${randomUUID()}`;
