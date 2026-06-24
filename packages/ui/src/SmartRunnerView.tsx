import { useEffect, useMemo, useRef, useState } from "react";
import { CircleStop, Play, Plus, RefreshCw, Search, SquareTerminal, Wrench, X, Zap } from "lucide-react";
import type { CommandRequest, ControlTransport, RunnerEvent, RunnerSession } from "@supersaiyan/control-protocol";

type RunnerLine = {
  id: string;
  kind: "assistant" | "tool" | "tool_result" | "system" | "error";
  text: string;
  partial?: boolean;
};

interface SmartRunnerViewProps {
  transport: ControlTransport;
  repoId: string | undefined;
  runnerSession: RunnerSession | undefined;
  setRunnerSession: (session: RunnerSession | undefined) => void;
  events: RunnerEvent[];
  setEvents: (events: RunnerEvent[] | ((prev: RunnerEvent[]) => RunnerEvent[])) => void;
  exitCode: number | undefined;
  setExitCode: (code: number | undefined) => void;
  onOpenRawTerminal: () => void;
}

function formatRunnerEvent(event: RunnerEvent, index: number): RunnerLine | undefined {
  if (event.type === "init" || event.type === "exit" || event.type === "system") return undefined;
  if (event.type === "assistant") {
    return { id: `${event.sessionId}-${index}`, kind: "assistant", text: event.text, partial: event.partial };
  }
  if (event.type === "tool") {
    return {
      id: `${event.sessionId}-${index}`,
      kind: "tool",
      text: event.input === undefined ? event.name : `${event.name} ${JSON.stringify(event.input)}`,
    };
  }
  if (event.type === "tool_result") {
    return {
      id: `${event.sessionId}-${index}`,
      kind: "tool_result",
      text: event.text || (event.error ? "(error)" : "(no output)"),
    };
  }
  if (event.type === "error") {
    return { id: `${event.sessionId}-${index}`, kind: "error", text: event.message };
  }
  return undefined;
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
  onOpenRawTerminal,
}: SmartRunnerViewProps) {
  const [isRunning, setIsRunning] = useState(Boolean(runnerSession?.active));
  const [newFeatureSlug, setNewFeatureSlug] = useState<string | null>(null);
  const [notice, setNotice] = useState<string>();
  const scrollRef = useRef<HTMLDivElement>(null);
  const sessionIdRef = useRef<string | undefined>(runnerSession?.id);

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

  const lines = useMemo(() => events.flatMap((event, index) => {
    const line = formatRunnerEvent(event, index);
    return line ? [line] : [];
  }), [events]);

  const startRunner = async (request: CommandRequest) => {
    if (!repoId) return;
    setEvents([]);
    setExitCode(undefined);
    setNotice(undefined);
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

  const requiresRawTerminal = lines.some((line) => /interactive|tty|terminal/i.test(line.text));

  return (
    <div className="runner-shell glass">
      <div className="runner-header">
        <div className="runner-header-left">
          {isRunning ? <span className="runner-live-dot" /> : <span className="runner-exit-dot" />}
          <span className="runner-session-title">{runnerSession.title}</span>
          {isRunning && <span className="runner-spinner-pill">streaming structured output</span>}
          {exitCode !== undefined && (
            <span className={`status-pill ${exitCode === 0 ? "ok" : "bad"}`}>exit {exitCode}</span>
          )}
        </div>
        <div className="topbar-actions">
          <button className="command-button" onClick={onOpenRawTerminal}>
            <SquareTerminal size={14} /> Raw terminal
          </button>
          {isRunning && (
            <button className="command-button danger" onClick={() => void stopRunner()}>
              <CircleStop size={14} /> Stop
            </button>
          )}
          {!isRunning && (
            <button className="command-button" onClick={() => {
              setRunnerSession(undefined);
              setEvents([]);
              setExitCode(undefined);
              setNotice(undefined);
            }}>
              <RefreshCw size={14} /> New command
            </button>
          )}
        </div>
      </div>

      <div className="runner-output">
        {notice && <div className="notice">{notice}</div>}
        {requiresRawTerminal && (
          <div className="runner-raw-fallback">
            This command appears to need interactive terminal mode.
            <button className="command-button" onClick={onOpenRawTerminal}>Open Raw Terminal</button>
          </div>
        )}
        {lines.length === 0 && isRunning ? (
          <div className="runner-waiting">
            <span className="runner-waiting-dot" />
            <span className="runner-waiting-dot" />
            <span className="runner-waiting-dot" />
          </div>
        ) : (
          lines.map((line) => (
            <div key={line.id} className={`runner-line runner-line--${line.kind}`}>
              {line.text}
            </div>
          ))
        )}
        <div ref={scrollRef} />
      </div>
    </div>
  );
}
