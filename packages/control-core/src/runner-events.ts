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

  if (type === "init" || type === "system") {
    return [{ type: "system", sessionId, text: JSON.stringify(record) }];
  }

  if (type === "assistant" || type === "message" || type === "partial") {
    const message = record.message && typeof record.message === "object" ? record.message as Record<string, unknown> : record;
    const text = textFromContent(message.content ?? record.content ?? record.delta);
    return text ? [{ type: "assistant", sessionId, text, partial: type === "partial" || record.partial === true }] : [];
  }

  if (type === "tool_use" || type === "tool") {
    const name = String(record.name ?? record.tool_name ?? record.tool ?? "tool");
    return [{ type: "tool", sessionId, name, input: record.input }];
  }

  if (type === "tool_result" || type === "result") {
    const text = textFromContent(record.content ?? record.result ?? record.output);
    return [{ type: "tool_result", sessionId, text: text || undefined, error: record.is_error === true || record.error === true }];
  }

  if (type === "error") {
    return [{ type: "error", sessionId, message: String(record.message ?? record.error ?? JSON.stringify(record)) }];
  }

  return [{ type: "system", sessionId, text: JSON.stringify(record) }];
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
