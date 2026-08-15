import { execFileSync } from "node:child_process";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const script = join(__dirname, "json-encode.mjs");

function encode(...args: string[]): string {
  return execFileSync(process.execPath, [script, ...args], { encoding: "utf8" });
}

describe("json-encode", () => {
  it("encodes --version as JSON args instead of Node's version string", () => {
    expect(JSON.parse(encode("--version"))).toEqual(["--version"]);
  });

  it("encodes --name as JSON args instead of a Node bad-option error", () => {
    expect(JSON.parse(encode("--name", "supersaiyan-ui-repo-alpha-rm"))).toEqual([
      "--name",
      "supersaiyan-ui-repo-alpha-rm",
    ]);
  });

  it("encodes a single value with escaped newlines", () => {
    expect(JSON.parse(encode("--value", "ok\nbad"))).toBe("ok\nbad");
  });
});
