import { describe, expect, it } from "vitest";
import { runnerEventsFromClaudeJsonLine } from "./runner-events";

describe("runnerEventsFromClaudeJsonLine", () => {
  const sessionId = "session-runner-123456";

  it("normalizes assistant partial and final content", () => {
    expect(runnerEventsFromClaudeJsonLine(sessionId, JSON.stringify({
      type: "partial",
      content: [{ type: "text", text: "Running" }],
    }))).toEqual([{ type: "assistant", sessionId, text: "Running", partial: true }]);

    expect(runnerEventsFromClaudeJsonLine(sessionId, JSON.stringify({
      type: "assistant",
      message: { content: [{ type: "text", text: "Done" }] },
    }))).toEqual([{ type: "assistant", sessionId, text: "Done", partial: false }]);
  });

  it("normalizes tool calls and tool results", () => {
    expect(runnerEventsFromClaudeJsonLine(sessionId, JSON.stringify({
      type: "tool_use",
      name: "Bash",
      input: { command: "git status --short" },
    }))).toEqual([{ type: "tool", sessionId, name: "Bash", input: { command: "git status --short" } }]);

    expect(runnerEventsFromClaudeJsonLine(sessionId, JSON.stringify({
      type: "tool_result",
      content: [{ type: "text", text: "clean" }],
    }))).toEqual([{ type: "tool_result", sessionId, text: "clean", error: false }]);
  });

  it("keeps unknown events visible and reports malformed JSONL", () => {
    expect(runnerEventsFromClaudeJsonLine(sessionId, JSON.stringify({
      type: "surprise",
      value: 42,
    }))).toEqual([{ type: "system", sessionId, text: "{\"type\":\"surprise\",\"value\":42}" }]);

    expect(runnerEventsFromClaudeJsonLine(sessionId, "{bad")).toEqual([{
      type: "error",
      sessionId,
      message: "Malformed Claude stream-json line: {bad",
    }]);
  });
});
