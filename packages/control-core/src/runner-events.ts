import type { RunnerEvent } from "@supersaiyan/control-protocol";

function textFromContent(content: unknown): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content.flatMap((part) => {
    if (!part || typeof part !== "object") return [];
    const record = part as Record<string, unknown>;
    if (typeof record.text === "string") return [record.text];
    if (typeof record.content === "string") return [record.content];
    return [];
  }).join("");
}

export function runnerEventsFromClaudeJson(sessionId: string, payload: unknown): RunnerEvent[] {
  if (!payload || typeof payload !== "object") return [{ type: "system", sessionId, text: String(payload) }];
  const record = payload as Record<string, unknown>;
  const type = typeof record.type === "string" ? record.type : "unknown";

  if (type === "system") {
    const subtype = typeof record.subtype === "string" ? record.subtype : "";
    if (subtype === "init") return [{ type: "system", sessionId, text: JSON.stringify(record) }];
    return [];
  }

  // Real Claude Code format: assistant messages carry both text and tool_use blocks in content array.
  if (type === "assistant" || type === "message") {
    const message = record.message && typeof record.message === "object" ? record.message as Record<string, unknown> : record;
    const content = Array.isArray(message.content) ? message.content : (Array.isArray(record.content) ? record.content : null);
    if (!content) {
      // Fallback: treat as plain text (old/test format with string delta)
      const text = textFromContent(record.content ?? record.delta);
      return text ? [{ type: "assistant", sessionId, text, partial: false }] : [];
    }
    // stop_reason: null = still streaming; stop_reason: "end_turn" = complete; key absent = treat as complete.
    const stopReason = "stop_reason" in message ? message.stop_reason : record.stop_reason;
    const isPartial = stopReason === null;
    const events: RunnerEvent[] = [];
    for (const block of content) {
      if (!block || typeof block !== "object") continue;
      const b = block as Record<string, unknown>;
      if (b.type === "text" && typeof b.text === "string" && b.text) {
        events.push({ type: "assistant", sessionId, text: b.text, partial: isPartial });
      } else if (b.type === "tool_use") {
        events.push({ type: "tool", sessionId, name: String(b.name ?? "tool"), input: b.input });
      }
      // "thinking" blocks are skipped — they're internal extended thinking
    }
    return events;
  }

  // Legacy/test format: partial events with top-level content
  if (type === "partial") {
    const text = textFromContent(record.content ?? record.delta);
    return text ? [{ type: "assistant", sessionId, text, partial: true }] : [];
  }

  // Real Claude Code format: tool results come wrapped in a "user" message.
  if (type === "user") {
    const message = record.message && typeof record.message === "object" ? record.message as Record<string, unknown> : record;
    const content = Array.isArray(message.content) ? message.content : [];
    const events: RunnerEvent[] = [];
    for (const block of content) {
      if (!block || typeof block !== "object") continue;
      const b = block as Record<string, unknown>;
      if (b.type === "tool_result") {
        const text = textFromContent(b.content ?? b.output);
        events.push({ type: "tool_result", sessionId, text: text || undefined, error: b.is_error === true || b.error === true });
      }
    }
    return events;
  }

  // Legacy/test format: tool_use and tool_result at top level
  if (type === "tool_use" || type === "tool") {
    const name = String(record.name ?? record.tool_name ?? record.tool ?? "tool");
    return [{ type: "tool", sessionId, name, input: record.input }];
  }

  if (type === "tool_result") {
    const text = textFromContent(record.content ?? record.output);
    return [{ type: "tool_result", sessionId, text: text || undefined, error: record.is_error === true || record.error === true }];
  }

  if (type === "error") {
    return [{ type: "error", sessionId, message: String(record.message ?? record.error ?? JSON.stringify(record)) }];
  }

  // "result", "rate_limit_event", and other noise — silently drop
  return [];
}

export function runnerEventsFromClaudeJsonLine(sessionId: string, line: string): RunnerEvent[] {
  const trimmed = line.trim();
  if (!trimmed) return [];
  try {
    return runnerEventsFromClaudeJson(sessionId, JSON.parse(trimmed));
  } catch {
    return [{ type: "error", sessionId, message: `Malformed Claude stream-json line: ${trimmed}` }];
  }
}
