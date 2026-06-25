import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { Play, Plus, Search, Wrench, X, Zap } from "lucide-react";
import type { CommandRequest, ControlTransport, RunnerEvent, RunnerSession } from "@supersaiyan/control-protocol";

type RunnerLine = {
  kind: "assistant" | "error" | "user" | "question";
  id: string;
  text: string;
  partial?: boolean;
};

type ThinkingBlock = {
  kind: "thinking";
  id: string;
  toolVerb: string;
  toolTarget: string;
  lineCount?: number;
  resultText?: string;
};

type DisplayItem = RunnerLine | ThinkingBlock;

const TOOL_PREVIEW_LINES = 3;

type Choice = { letter: string; description: string };

type ParsedChoices = { choices: Choice[]; preamble: string };

function detectChoices(text: string): ParsedChoices | null {
  const lines = text.split("\n");
  const choices: Choice[] = [];
  let firstChoiceLine = -1;

  for (let i = 0; i < lines.length; i++) {
    const m = lines[i]!.match(/^(?:>\s*)?\*{0,2}([A-Z])\)\*{0,2}\s+(.*)/);
    if (m && m[1] && m[2]) {
      if (firstChoiceLine === -1) firstChoiceLine = i;
      choices.push({ letter: m[1], description: m[2].replace(/\*+/g, "").trim() });
    }
  }
  if (choices.length < 2) return null;

  const preamble = lines.slice(0, firstChoiceLine).join("\n").trim();
  return { choices, preamble };
}

function inlineNodes(text: string, lineKey: number): ReactNode[] {
  const parts: ReactNode[] = [];
  const pat = /(\*\*[^*\n]+\*\*|`[^`\n]+`)/g;
  let last = 0; let key = 0; let m: RegExpExecArray | null;
  while ((m = pat.exec(text)) !== null) {
    if (m.index > last) parts.push(text.slice(last, m.index));
    const tok = m[0]!;
    if (tok.startsWith("**")) parts.push(<strong key={`${lineKey}-${key++}`}>{tok.slice(2, -2)}</strong>);
    else if (tok.startsWith("`")) parts.push(<code key={`${lineKey}-${key++}`} className="runner-code">{tok.slice(1, -1)}</code>);
    last = m.index + tok.length;
  }
  if (last < text.length) parts.push(text.slice(last));
  return parts;
}

function renderText(text: string): ReactNode[] {
  const nodes: ReactNode[] = [];
  const lines = text.split("\n");
  for (let i = 0; i < lines.length; i++) {
    if (i > 0) nodes.push("\n");
    let line = lines[i]!;
    if (/^(?:---|___|\*\*\*)$/.test(line.trim())) {
      nodes.push(<hr key={`hr-${i}`} className="runner-hr" />);
      continue;
    }
    if (line.startsWith("> ")) line = line.slice(2);
    nodes.push(...inlineNodes(line, i));
  }
  return nodes;
}

function parseToolParts(name: string, input: unknown): { verb: string; target: string } {
  if (!input || typeof input !== "object") return { verb: name, target: "" };
  const inp = input as Record<string, unknown>;
  if (name === "Bash" && typeof inp.command === "string") {
    const cmd = inp.command.trim().split("\n")[0] ?? "";
    return { verb: "Bash", target: cmd.length > 60 ? cmd.slice(0, 57) + "…" : cmd };
  }
  if (typeof inp.file_path === "string") {
    return { verb: name, target: inp.file_path.split("/").pop() ?? inp.file_path };
  }
  if (typeof inp.pattern === "string") return { verb: name, target: String(inp.pattern) };
  if (typeof inp.query === "string") return { verb: name, target: String(inp.query) };
  return { verb: name, target: "" };
}

function ToolIcon({ verb }: { verb: string }) {
  const s = { width: 13, height: 13, fill: "none" as const, stroke: "currentColor", strokeWidth: 2, strokeLinecap: "round" as const, strokeLinejoin: "round" as const };
  if (verb === "Read") return (
    <svg {...s} viewBox="0 0 24 24">
      <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
      <path d="M14 2v6h6M9 13h6M9 17h4"/>
    </svg>
  );
  if (verb === "Bash" || verb === "Execute") return (
    <svg {...s} viewBox="0 0 24 24"><path d="m4 17 6-6-6-6M12 19h8"/></svg>
  );
  if (verb === "Glob" || verb === "Grep" || verb === "Search") return (
    <svg {...s} viewBox="0 0 24 24"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></svg>
  );
  if (verb === "Write" || verb === "Edit") return (
    <svg {...s} viewBox="0 0 24 24">
      <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/>
      <path d="M18.5 2.5a2.12 2.12 0 0 1 3 3L12 15l-4 1 1-4Z"/>
    </svg>
  );
  return (
    <svg {...s} viewBox="0 0 24 24">
      <path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/>
    </svg>
  );
}

function ThinkingPill({ item }: { item: ThinkingBlock }) {
  const [open, setOpen] = useState(false);
  const [showAll, setShowAll] = useState(false);
  const lines = item.resultText
    ? item.resultText.split("\n").filter((l) => l.trim())
    : [];
  const visible = showAll ? lines : lines.slice(0, TOOL_PREVIEW_LINES);
  const hidden = lines.length - visible.length;

  return (
    <div className={`runner-tool${open ? " runner-tool--open" : ""}`}>
      <button className="runner-tool-row" onClick={() => setOpen((o) => !o)}>
        <span className="runner-tool-ico"><ToolIcon verb={item.toolVerb} /></span>
        <span className="runner-tool-main">
          <span className="runner-tool-verb">{item.toolVerb}</span>
          {item.toolTarget && <span className="runner-tool-target">{item.toolTarget}</span>}
        </span>
        {item.lineCount !== undefined && item.lineCount > 0 && (
          <span className="runner-tool-meta">{item.lineCount} lines</span>
        )}
        <svg className="runner-tool-chev" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
          <path d="m9 18 6-6-6-6"/>
        </svg>
      </button>
      {lines.length > 0 && (
        <div className="runner-tool-body" style={open ? undefined : { display: "none" }}>
          {visible.map((line, i) => (
            <div key={i} className="runner-tool-line">{line}</div>
          ))}
          {hidden > 0 && (
            <button className="runner-tool-more" onClick={(e) => { e.stopPropagation(); setShowAll(true); }}>
              Show {hidden} more lines
            </button>
          )}
        </div>
      )}
    </div>
  );
}

interface SmartRunnerViewProps {
  transport: ControlTransport;
  repoId: string | undefined;
  runnerSession: RunnerSession | undefined;
  setRunnerSession: (session: RunnerSession | undefined) => void;
  events: RunnerEvent[];
  setEvents: (events: RunnerEvent[] | ((prev: RunnerEvent[]) => RunnerEvent[])) => void;
  exitCode: number | undefined;
  setExitCode: (code: number | undefined) => void;
}


export function SmartRunnerView({
  transport,
  repoId,
  runnerSession,
  setRunnerSession,
  events,
  setEvents,
  exitCode,
  setExitCode,
}: SmartRunnerViewProps) {
  const [isRunning, setIsRunning] = useState(Boolean(runnerSession?.active));
  const [isConfirmingNew, setIsConfirmingNew] = useState(false);
  const [newFeatureSlug, setNewFeatureSlug] = useState<string | null>(null);
  const [notice, setNotice] = useState<string>();
  const [inputText, setInputText] = useState("");
  const [userReplies, setUserReplies] = useState<Array<{ afterSessionId: string; text: string }>>([]);
  const scrollRef = useRef<HTMLDivElement>(null);
  const sessionIdRef = useRef<string | undefined>(runnerSession?.id);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    sessionIdRef.current = runnerSession?.id;
    setIsRunning(Boolean(runnerSession?.active));
  }, [runnerSession]);

  useEffect(() => {
    const remove = transport.onRunnerEvent((event) => {
      if (event.sessionId !== sessionIdRef.current) return;
      setEvents((current) => [...current, event]);
      if (event.type === "exit") {
        setIsRunning(false);
        setExitCode(event.exitCode);
        setRunnerSession(runnerSession ? { ...runnerSession, active: false } : undefined);
      }
    });
    return remove;
  }, [runnerSession, setRunnerSession, transport]);

  useEffect(() => {
    scrollRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [events]);

  const lastAssistantIdx = useMemo(() => {
    for (let i = events.length - 1; i >= 0; i--) {
      const e = events[i];
      if (e?.type === "assistant" && e.text?.trim()) return i;
    }
    return -1;
  }, [events]);

  const parsedChoices = useMemo<ParsedChoices | null>(() => {
    if (isRunning || lastAssistantIdx === -1) return null;
    const e = events[lastAssistantIdx];
    return e?.type === "assistant" && e.text ? detectChoices(e.text) : null;
  }, [events, isRunning, lastAssistantIdx]);

  const detectedChoices = parsedChoices?.choices ?? [];

  const displayItems = useMemo(() => {
    const result: DisplayItem[] = [];
    let lastSessionId: string | undefined;
    let replyIndex = 0;
    let i = 0;
    while (i < events.length) {
      const event = events[i]!;
      if (lastSessionId && event.sessionId !== lastSessionId) {
        const reply = userReplies.find((r) => r.afterSessionId === lastSessionId);
        if (reply) result.push({ kind: "user", id: `user-reply-${replyIndex++}`, text: reply.text });
      }
      lastSessionId = event.sessionId;

      if (event.type === "tool") {
        const next = events[i + 1];
        const resultText = next?.type === "tool_result" ? (next.text || undefined) : undefined;
        const { verb, target } = parseToolParts(event.name, event.input);
        const lineCount = resultText ? resultText.split("\n").filter(l => l.trim()).length : undefined;
        result.push({ kind: "thinking", id: `thinking-${event.sessionId}-${i}`, toolVerb: verb, toolTarget: target, lineCount, resultText });
        i += (next?.type === "tool_result" ? 2 : 1);
        continue;
      }
      if (event.type === "tool_result") { i++; continue; }
      if (event.type === "assistant" && event.text) {
        if (i === lastAssistantIdx && parsedChoices) {
          const preamble = parsedChoices.preamble;
          const blocks = preamble.split(/\n(?:---|___|\*\*\*)\n|\n{2,}/).map(b => b.trim()).filter(Boolean);
          const questionText = blocks[blocks.length - 1] ?? preamble;
          const contextText = blocks.slice(0, -1).join("\n\n").trim();
          if (contextText) result.push({ kind: "assistant", id: `${event.sessionId}-${i}-ctx`, text: contextText });
          if (questionText) result.push({ kind: "question", id: `${event.sessionId}-${i}-q`, text: questionText, partial: event.partial });
        } else {
          result.push({ kind: "assistant", id: `${event.sessionId}-${i}`, text: event.text, partial: event.partial });
        }
      }
      if (event.type === "error") {
        result.push({ kind: "error", id: `${event.sessionId}-${i}`, text: event.message });
      }
      i++;
    }
    return result;
  }, [events, userReplies, lastAssistantIdx, parsedChoices]);

  const currentActivity = useMemo(() => {
    if (!isRunning) return null;
    const last = events[events.length - 1];
    if (!last || last.type === "init") return "Starting up…";
    if (last.type === "tool") return `Running ${last.name}…`;
    if (last.type === "assistant" && last.partial) return "Generating…";
    if (last.type === "tool_result") return "Thinking…";
    return "Working…";
  }, [isRunning, events]);

  const interruptCurrent = async () => {
    const id = sessionIdRef.current;
    if (id) {
      try { await transport.interruptRunner(id); } catch { /* already gone */ }
    }
  };

  const handleNewCommand = () => setIsConfirmingNew(true);

  const confirmNewCommand = () => {
    void interruptCurrent().then(() => {
      setIsConfirmingNew(false);
      sessionIdRef.current = undefined;
      setRunnerSession(undefined);
      setEvents([]);
      setExitCode(undefined);
      setNotice(undefined);
      setUserReplies([]);
    });
  };

  const sendReply = async (text: string) => {
    if (!repoId || !runnerSession || !text.trim()) return;
    const prevSessionId = runnerSession.id;
    setInputText("");
    setIsRunning(true);
    setNotice(undefined);
    setUserReplies((prev) => [...prev, { afterSessionId: prevSessionId, text }]);
    try {
      const next = await transport.continueRunner(repoId, runnerSession.sessionName, text);
      sessionIdRef.current = next.id;
      setRunnerSession(next);
    } catch (error) {
      setIsRunning(false);
      setNotice(error instanceof Error ? error.message : String(error));
    }
  };

  const startRunner = async (request: CommandRequest) => {
    if (!repoId) return;
    await interruptCurrent();
    setIsConfirmingNew(false);
    setNewFeatureSlug(null);
    sessionIdRef.current = undefined;
    setRunnerSession(undefined);
    setEvents([]);
    setExitCode(undefined);
    setNotice(undefined);
    setUserReplies([]);
    setIsRunning(true);
    try {
      const session = await transport.startRunnerCommand(repoId, request);
      sessionIdRef.current = session.id;
      setRunnerSession(session);
    } catch (error) {
      setIsRunning(false);
      setNotice(error instanceof Error ? error.message : String(error));
    }
  };

  const stopRunner = async () => {
    if (!runnerSession) return;
    setNotice(undefined);
    await transport.interruptRunner(runnerSession.id);
    if (repoId) {
      try {
        await transport.startRunnerCommand(repoId, { verb: "stop", args: [] });
      } catch (error) {
        setNotice(error instanceof Error ? error.message : String(error));
      }
    }
  };

  if (!runnerSession) {
    return (
      <div className="runner-shell glass">
        <div className="runner-idle">
          <Zap size={40} className="runner-idle-icon" />
          <div className="runner-idle-title">Smart Runner</div>
          <div className="runner-idle-subtitle">
            Launch SuperSaiyan commands through Claude Code stream-json output
          </div>
          {notice && <div className="notice">{notice}</div>}
          <div className="runner-command-grid">
            <button className="runner-cmd-btn" disabled={!repoId} onClick={() => void startRunner({ verb: "setup", args: [] })}>
              <Wrench size={20} />
              <span className="runner-cmd-label">Setup</span>
              <span className="runner-cmd-desc">Connect GitHub Project</span>
            </button>
            {newFeatureSlug !== null ? (
              <form
                className="runner-cmd-btn runner-cmd-form"
                onSubmit={(event) => {
                  event.preventDefault();
                  if (newFeatureSlug.trim()) void startRunner({ verb: "new", args: [newFeatureSlug.trim()] });
                  setNewFeatureSlug(null);
                }}
              >
                <input
                  className="field"
                  autoFocus
                  placeholder="feature-slug"
                  value={newFeatureSlug}
                  onChange={(event) => setNewFeatureSlug(event.target.value)}
                  style={{ height: 34 }}
                  onKeyDown={(event) => { if (event.key === "Escape") setNewFeatureSlug(null); }}
                />
                <button type="submit" className="command-button primary" disabled={!newFeatureSlug.trim()}>
                  <Plus size={14} />
                </button>
                <button type="button" className="icon-button" onClick={() => setNewFeatureSlug(null)}>
                  <X size={14} />
                </button>
              </form>
            ) : (
              <button className="runner-cmd-btn" disabled={!repoId} onClick={() => setNewFeatureSlug("")}>
                <Plus size={20} />
                <span className="runner-cmd-label">New Feature</span>
                <span className="runner-cmd-desc">Start a feature slug</span>
              </button>
            )}
            <button className="runner-cmd-btn runner-cmd-btn--primary" disabled={!repoId} onClick={() => void startRunner({ verb: "run", args: [] })}>
              <Play size={20} fill="currentColor" />
              <span className="runner-cmd-label">Run</span>
              <span className="runner-cmd-desc">Start autonomous pipeline</span>
            </button>
            <button className="runner-cmd-btn" disabled={!repoId} onClick={() => void startRunner({ verb: "lint", args: [] })}>
              <Search size={20} />
              <span className="runner-cmd-label">Lint</span>
              <span className="runner-cmd-desc">Validate feature artifacts</span>
            </button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="runner-shell glass">
      {/* Header */}
      <div className="runner-header">
        <div className="runner-header-top">
          <span className="runner-gem" />
          <div className="runner-id-block">
            <div className="runner-id-name">{runnerSession.title}</div>
            <div className="runner-id-sub">
              {isRunning ? currentActivity ?? "Working…" : exitCode !== undefined ? "Completed" : "Ready"}
            </div>
          </div>
          {isRunning && (
            <span className="runner-status">
              <span className="runner-pulse" />
              RUNNING
            </span>
          )}
          {!isRunning && exitCode !== undefined && (
            <span className={`runner-status ${exitCode === 0 ? "runner-status--ok" : "runner-status--err"}`}>
              <span className={`runner-pulse ${exitCode === 0 ? "runner-pulse--ok" : "runner-pulse--err"}`} />
              EXIT {exitCode}
            </span>
          )}
          <div className="runner-head-actions">
            {isRunning && (
              <button className="runner-iconbtn runner-iconbtn--stop" title="Stop" onClick={() => void stopRunner()}>
                <svg width="13" height="13" viewBox="0 0 24 24" fill="currentColor">
                  <rect x="5" y="5" width="14" height="14" rx="2.5"/>
                </svg>
              </button>
            )}
            {!isRunning && (
              <button className="runner-iconbtn" title="New command" onClick={handleNewCommand}>
                <Plus size={15} />
              </button>
            )}
          </div>
        </div>
      </div>

      {/* Output */}
      <div className="runner-output">
        {notice && <div className="notice">{notice}</div>}
        <div className="runner-turn">
          <div className="runner-gutter">
            <span className="runner-gem" />
            <span className="runner-thread" />
          </div>
          <div className="runner-content">
            {displayItems.length === 0 && isRunning ? (
              <div className="runner-waiting">
                <span className="runner-waiting-dot" />
                <span className="runner-waiting-dot" />
                <span className="runner-waiting-dot" />
              </div>
            ) : (
              displayItems.map((item, index) => {
                if (item.kind === "thinking") return <ThinkingPill key={item.id} item={item} />;
                if (item.kind === "user") return <div key={item.id} className="runner-line--user">{item.text}</div>;
                if (item.kind === "error") return <div key={item.id} className="runner-line--error">{item.text}</div>;
                if (item.kind === "question") {
                  return (
                    <div key={item.id} className="runner-prose runner-prose--ask">
                      <span className="runner-q-tag">
                        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" style={{ width: 11, height: 11 }}>
                          <path d="M9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3"/>
                          <path d="M12 17h.01"/>
                        </svg>
                        Question
                      </span>
                      {renderText(item.text)}
                      {item.partial && <span className="runner-cursor" />}
                    </div>
                  );
                }
                return (
                  <div key={item.id} className="runner-prose">
                    {renderText(item.text)}
                    {index === displayItems.length - 1 && item.partial && <span className="runner-cursor" />}
                  </div>
                );
              })
            )}
            {isRunning && (
              <div className="runner-activity">
                <span className="runner-activity-spinner" />
                {currentActivity}
              </div>
            )}
          </div>
        </div>
        <div ref={scrollRef} />
      </div>

      {/* Confirm new command — modal overlay */}
      {isConfirmingNew && (
        <div className="runner-modal-backdrop" onClick={() => setIsConfirmingNew(false)}>
          <div className="runner-modal" onClick={(e) => e.stopPropagation()}>
            <div className="runner-modal-title">Start a new command?</div>
            <div className="runner-modal-msg">This will close the current session and its output.</div>
            <div className="runner-modal-actions">
              <button className="runner-confirm-cancel" onClick={() => setIsConfirmingNew(false)}>Cancel</button>
              <button className="runner-confirm-yes" onClick={confirmNewCommand}>Close &amp; start new</button>
            </div>
          </div>
        </div>
      )}

      {/* Reply area */}
      {!isRunning && !isConfirmingNew && exitCode !== undefined && (
        <div className="runner-reply-area">
          {detectedChoices.length > 0 && (
            <div className="runner-choices">
              <div className="runner-choices-label">Choose a direction</div>
              {detectedChoices.map(({ letter, description }) => (
                <button
                  key={letter}
                  className="runner-choice-btn"
                  onClick={() => void sendReply(letter)}
                >
                  <span className="runner-choice-key">{letter}</span>
                  <span className="runner-choice-desc">{description}</span>
                  <svg className="runner-choice-arrow" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M5 12h14M13 6l6 6-6 6"/>
                  </svg>
                </button>
              ))}
            </div>
          )}
          <form
            className="runner-input-bar"
            onSubmit={(e) => { e.preventDefault(); void sendReply(inputText); }}
          >
            <div className="runner-input-wrap">
              <span className="runner-prompt-char">›</span>
              <input
                ref={inputRef}
                autoFocus={detectedChoices.length === 0}
                className="runner-input"
                placeholder={detectedChoices.length > 0 ? "Type your own answer, or pick an option above…" : "Reply to Claude… (press Enter to send)"}
                value={inputText}
                onChange={(e) => setInputText(e.target.value)}
                autoComplete="off"
              />
            </div>
            <button type="submit" className="runner-send-btn" disabled={!inputText.trim()}>
              Send
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" style={{ width: 15, height: 15 }}>
                <path d="M22 2 11 13M22 2l-7 20-4-9-9-4 20-7z"/>
              </svg>
            </button>
          </form>
        </div>
      )}
    </div>
  );
}
