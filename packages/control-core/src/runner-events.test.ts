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

  it("handles real Claude Code stream-json format (tool_use in assistant, tool_result in user)", () => {
    // Tool call: comes as type:"assistant" with content[].type="tool_use"
    expect(runnerEventsFromClaudeJsonLine(sessionId, JSON.stringify({
      type: "assistant",
      message: {
        role: "assistant",
        content: [{ type: "tool_use", id: "toolu_abc", name: "Read", input: { file_path: "/tmp/x" } }],
        stop_reason: null,
      },
    }))).toEqual([{ type: "tool", sessionId, name: "Read", input: { file_path: "/tmp/x" } }]);

    // Tool result: comes as type:"user" with content[].type="tool_result"
    expect(runnerEventsFromClaudeJsonLine(sessionId, JSON.stringify({
      type: "user",
      message: {
        role: "user",
        content: [{ type: "tool_result", tool_use_id: "toolu_abc", content: "file contents here" }],
      },
    }))).toEqual([{ type: "tool_result", sessionId, text: "file contents here", error: false }]);

    // Partial assistant text (stop_reason: null means still streaming)
    expect(runnerEventsFromClaudeJsonLine(sessionId, JSON.stringify({
      type: "assistant",
      message: {
        role: "assistant",
        content: [{ type: "text", text: "Thinking..." }],
        stop_reason: null,
      },
    }))).toEqual([{ type: "assistant", sessionId, text: "Thinking...", partial: true }]);

    // noise events are silently dropped
    expect(runnerEventsFromClaudeJsonLine(sessionId, JSON.stringify({ type: "rate_limit_event" }))).toEqual([]);
    expect(runnerEventsFromClaudeJsonLine(sessionId, JSON.stringify({ type: "result", subtype: "success" }))).toEqual([]);
  });

  it("silently drops unknown event types and reports malformed JSONL", () => {
    // Unknown types (rate_limit_event, result, etc.) are dropped — no value showing raw JSON in the UI.
    expect(runnerEventsFromClaudeJsonLine(sessionId, JSON.stringify({
      type: "surprise",
      value: 42,
    }))).toEqual([]);

    expect(runnerEventsFromClaudeJsonLine(sessionId, "{bad")).toEqual([{
      type: "error",
      sessionId,
      message: "Malformed Claude stream-json line: {bad",
    }]);
  });
});
