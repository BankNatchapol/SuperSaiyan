import { describe, expect, it } from "vitest";
import { parseJsonLines } from "./json-lines";

describe("parseJsonLines", () => {
  it("parses one JSON object per line", () => {
    expect(parseJsonLines('{"tool":"claude","args":["--version"]}\n{"tool":"gh"}\n')).toEqual([
      { tool: "claude", args: ["--version"] },
      { tool: "gh" },
    ]);
  });

  it("keeps JSON-escaped newlines inside a single record", () => {
    expect(parseJsonLines(`${JSON.stringify({ line: "ok\nbad" })}\n`)).toEqual([{ line: "ok\nbad" }]);
  });

  it("throws when a JSONL line is malformed instead of dropping it", () => {
    const splitByRawNewline = '{"tool":"claude-stdin","line":"/supersaiyan run ok\nbad","cwd":"."}\n';
    expect(() => parseJsonLines(splitByRawNewline)).toThrow(/Invalid JSONL/);
  });
});
