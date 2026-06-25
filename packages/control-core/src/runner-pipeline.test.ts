/**
 * Integration test: real Claude Code stream-json lines → parsed events → displayItems logic.
 * Uses the EXACT event sequence captured from a live `claude -p --output-format stream-json
 * --verbose --include-partial-messages` run.
 */
import { describe, expect, it } from "vitest";
import type { RunnerEvent } from "@supersaiyan/control-protocol";
import { runnerEventsFromClaudeJsonLine } from "./runner-events";

// ── Replicate the displayItems logic from SmartRunnerView ──────────────────────
type RunnerLine = { kind: "assistant" | "error" | "user"; id: string; text: string; partial?: boolean };
type ThinkingBlock = { kind: "thinking"; id: string; toolText: string; resultText?: string };
type DisplayItem = RunnerLine | ThinkingBlock;

function buildDisplayItems(events: RunnerEvent[]): DisplayItem[] {
  const result: DisplayItem[] = [];
  let i = 0;
  while (i < events.length) {
    const event = events[i]!;
    if (event.type === "tool") {
      const next = events[i + 1];
      const resultText = next?.type === "tool_result" ? (next.text || undefined) : undefined;
      result.push({ kind: "thinking", id: `thinking-${i}`, toolText: event.name, resultText });
      i += (next?.type === "tool_result" ? 2 : 1);
      continue;
    }
    if (event.type === "tool_result") { i++; continue; }
    if (event.type === "assistant" && event.text) {
      result.push({ kind: "assistant", id: `a-${i}`, text: event.text, partial: event.partial });
    }
    if (event.type === "error") {
      result.push({ kind: "error", id: `e-${i}`, text: event.message });
    }
    i++;
  }
  return result;
}

// ── Helpers ────────────────────────────────────────────────────────────────────
const SID = "test-session";
function parse(lines: string[]): RunnerEvent[] {
  return lines.flatMap((l) => runnerEventsFromClaudeJsonLine(SID, l));
}

// ── Exact stream-json lines captured from real Claude Code run ─────────────────
// Sequence: stream_events (skipped), assistant [thinking], assistant [tool_use:Read],
// user [tool_result], stream_events (skipped), assistant [text]
const REAL_STREAM_LINES = [
  // noise: stream_event wrapping — must be silently dropped
  JSON.stringify({ type: "stream_event", event: { type: "message_start", message: { id: "msg_abc", role: "assistant", content: [], stop_reason: null } }, session_id: SID }),
  JSON.stringify({ type: "stream_event", event: { type: "content_block_start", index: 0, content_block: { type: "thinking", thinking: "", signature: "" } }, session_id: SID }),
  JSON.stringify({ type: "stream_event", event: { type: "content_block_delta", index: 0, delta: { type: "thinking_delta", thinking: "Let me read..." } }, session_id: SID }),
  JSON.stringify({ type: "stream_event", event: { type: "content_block_stop", index: 0 }, session_id: SID }),

  // partial assistant snapshot: thinking block complete
  JSON.stringify({ type: "assistant", message: { id: "msg_abc", role: "assistant", content: [{ type: "thinking", thinking: "Let me read...", signature: "" }], stop_reason: null }, session_id: SID }),

  // noise: stream_event for tool_use content block
  JSON.stringify({ type: "stream_event", event: { type: "content_block_start", index: 1, content_block: { type: "tool_use", id: "toolu_xyz", name: "Read", input: {} } }, session_id: SID }),
  JSON.stringify({ type: "stream_event", event: { type: "content_block_delta", index: 1, delta: { type: "input_json_delta", partial_json: '{"file_path":"/etc/hosts"}' } }, session_id: SID }),
  JSON.stringify({ type: "stream_event", event: { type: "content_block_stop", index: 1 }, session_id: SID }),

  // partial assistant snapshot: tool_use block complete
  JSON.stringify({ type: "assistant", message: { id: "msg_abc", role: "assistant", content: [{ type: "tool_use", id: "toolu_xyz", name: "Read", input: { file_path: "/etc/hosts", limit: 1 } }], stop_reason: null }, session_id: SID }),

  // stream_event: message_delta / message_stop
  JSON.stringify({ type: "stream_event", event: { type: "message_delta", delta: { stop_reason: "tool_use" } }, session_id: SID }),

  // tool result — comes as user message
  JSON.stringify({ type: "user", message: { role: "user", content: [{ type: "tool_result", tool_use_id: "toolu_xyz", content: "## Host Database" }] }, session_id: SID }),

  JSON.stringify({ type: "stream_event", event: { type: "message_stop" }, session_id: SID }),

  // final assistant text
  JSON.stringify({ type: "stream_event", event: { type: "message_start", message: { id: "msg_def", role: "assistant", content: [], stop_reason: null } }, session_id: SID }),
  JSON.stringify({ type: "stream_event", event: { type: "content_block_start", index: 0, content_block: { type: "text", text: "" } }, session_id: SID }),
  JSON.stringify({ type: "stream_event", event: { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: "The first line is" } }, session_id: SID }),
  JSON.stringify({ type: "stream_event", event: { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: " a comment." } }, session_id: SID }),

  // partial assistant snapshot: text block complete
  JSON.stringify({ type: "assistant", message: { id: "msg_def", role: "assistant", content: [{ type: "text", text: "The first line is a comment." }], stop_reason: null }, session_id: SID }),

  JSON.stringify({ type: "stream_event", event: { type: "content_block_stop", index: 0 }, session_id: SID }),
  JSON.stringify({ type: "stream_event", event: { type: "message_delta", delta: { stop_reason: "end_turn" } }, session_id: SID }),
  JSON.stringify({ type: "stream_event", event: { type: "message_stop" }, session_id: SID }),
  JSON.stringify({ type: "rate_limit_event", rate_limit_info: {}, session_id: SID }),
  JSON.stringify({ type: "result", subtype: "success", result: "The first line is a comment.", session_id: SID }),
];

describe("runner pipeline integration", () => {
  it("parses real stream-json sequence into correct RunnerEvents", () => {
    const events = parse(REAL_STREAM_LINES);

    // Should have: tool (Read), tool_result, assistant (final text)
    // Should NOT have: system events from stream_event wrappers, rate_limit_event, result
    expect(events.filter((e) => e.type === "tool")).toHaveLength(1);
    expect(events.filter((e) => e.type === "tool_result")).toHaveLength(1);
    expect(events.filter((e) => e.type === "assistant")).toHaveLength(1);
    expect(events.filter((e) => e.type === "system")).toHaveLength(0);
    expect(events.filter((e) => e.type === "error")).toHaveLength(0);

    const toolEvent = events.find((e) => e.type === "tool")!;
    expect(toolEvent).toMatchObject({ type: "tool", name: "Read" });

    const resultEvent = events.find((e) => e.type === "tool_result")!;
    expect(resultEvent).toMatchObject({ type: "tool_result", text: "## Host Database", error: false });

    const textEvent = events.find((e) => e.type === "assistant")!;
    expect(textEvent).toMatchObject({ type: "assistant", text: "The first line is a comment.", partial: true });
  });

  it("buildDisplayItems produces ThinkingBlock + RunnerLine from parsed events", () => {
    const events = parse(REAL_STREAM_LINES);
    const items = buildDisplayItems(events);

    expect(items).toHaveLength(2);

    const pill = items[0];
    expect(pill?.kind).toBe("thinking");
    if (pill?.kind === "thinking") {
      expect(pill.toolText).toBe("Read");
      expect(pill.resultText).toBe("## Host Database");
    }

    const line = items[1];
    expect(line?.kind).toBe("assistant");
    if (line?.kind === "assistant") {
      expect(line.text).toBe("The first line is a comment.");
    }
  });
});
