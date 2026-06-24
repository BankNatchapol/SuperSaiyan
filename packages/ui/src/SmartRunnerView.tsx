import { useEffect, useRef, useState } from "react";
import { CircleStop, Play, Plus, RefreshCw, Search, SquareTerminal, Wrench, X, Zap } from "lucide-react";
import type { CommandRequest, ControlTransport, TerminalSession } from "@supersaiyan/control-protocol";

function stripAnsi(str: string): string {
  return str
    .replace(/\x1B\[[0-?]*[ -/]*[@-~]/g, "")
    .replace(/\x1B[@-_][0-?]*[ -/]*[@-~]/g, "")
    .replace(/\x1B./g, "");
}

function parseNumberedOptions(buffer: string): string[] {
  const pattern = /^\s*(?:❯\s*)?\d+\.\s+(.+)/gm;
  const results: string[] = [];
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(buffer)) !== null) {
    const label = match[1].trim();
    if (label.length > 0 && label.length < 120) results.push(label);
  }
  return [...new Set(results)];
}

interface SmartRunnerViewProps {
  transport: ControlTransport;
  repoId: string | undefined;
  sessions: TerminalSession[];
  runnerSessionId: string | undefined;
  setRunnerSessionId: (id: string | undefined) => void;
  onStartCommand: (request: CommandRequest) => Promise<TerminalSession | undefined>;
  onSessionCreated: (session: TerminalSession) => void;
  onSwitchToTerminal: () => void;
}

export function SmartRunnerView({
  transport,
  repoId,
  sessions,
  runnerSessionId,
  setRunnerSessionId,
  onStartCommand,
  onSessionCreated,
  onSwitchToTerminal,
}: SmartRunnerViewProps) {
  const [lines, setLines] = useState<string[]>([]);
  const [isRunning, setIsRunning] = useState(false);
  const [exited, setExited] = useState(false);
  const [exitCode, setExitCode] = useState<number>();
  const [inputText, setInputText] = useState("");
  const [uiMode, setUiMode] = useState<"normal" | "choice" | "permission">("normal");
  const [choices, setChoices] = useState<string[]>([]);
  const [newFeatureSlug, setNewFeatureSlug] = useState<string | null>(null);

  const pendingLineRef = useRef<string>("");
  const rollingBufferRef = useRef<string>("");
  const scrollRef = useRef<HTMLDivElement>(null);
  const sessionIdRef = useRef<string | undefined>(runnerSessionId);

  useEffect(() => {
    sessionIdRef.current = runnerSessionId;
  }, [runnerSessionId]);

  useEffect(() => {
    const removeData = transport.onTerminalData((event) => {
      if (event.sessionId !== sessionIdRef.current) return;

      const stripped = stripAnsi(event.data);
      rollingBufferRef.current = (rollingBufferRef.current + stripped).slice(-2000);

      const committed: string[] = [];
      for (const ch of stripped) {
        if (ch === "\r") {
          pendingLineRef.current = "";
        } else if (ch === "\n") {
          committed.push(pendingLineRef.current);
          pendingLineRef.current = "";
        } else {
          pendingLineRef.current += ch;
        }
      }

      if (committed.length > 0) {
        setLines((prev) => {
          const next = [...prev, ...committed];
          return next.length > 500 ? next.slice(next.length - 500) : next;
        });
      }

      const buf = rollingBufferRef.current;
      if (/Enter to select.*↑\/↓ to navigate/i.test(buf) || /\(Use arrow keys\)/i.test(buf)) {
        const parsed = parseNumberedOptions(buf);
        if (parsed.length >= 2) {
          setChoices(parsed);
          setUiMode("choice");
        }
      } else if (/Esc to cancel.*Tab to amend/i.test(buf) || /Do you want to proceed/i.test(buf)) {
        setUiMode("permission");
        setChoices([]);
      } else {
        setUiMode("normal");
        setChoices([]);
      }
    });

    const removeExit = transport.onTerminalExit((event) => {
      if (event.sessionId !== sessionIdRef.current) return;
      setIsRunning(false);
      setExited(true);
      setExitCode(event.exitCode);
      setUiMode("normal");
      setChoices([]);
    });

    return () => {
      removeData();
      removeExit();
    };
  }, [transport]);

  useEffect(() => {
    scrollRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [lines]);

  const startRunner = async (request: CommandRequest) => {
    if (!repoId) return;
    setLines([]);
    setExited(false);
    setExitCode(undefined);
    setUiMode("normal");
    setChoices([]);
    pendingLineRef.current = "";
    rollingBufferRef.current = "";
    setIsRunning(true);

    const session = await onStartCommand(request);
    if (!session) {
      setIsRunning(false);
      return;
    }
    sessionIdRef.current = session.id;
    setRunnerSessionId(session.id);
    onSessionCreated(session);
  };

  const sendInput = (text: string) => {
    const id = sessionIdRef.current;
    if (!id) return;
    void transport.writeTerminal(id, text);
  };

  const handleChoiceSelect = (index: number) => {
    sendInput(String(index + 1) + "\n");
    setUiMode("normal");
    setChoices([]);
  };

  const handleFreeFormSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!inputText) return;
    sendInput(inputText + "\n");
    setInputText("");
  };

  // Idle splash
  if (!runnerSessionId) {
    return (
      <div className="runner-shell glass">
        <div className="runner-idle">
          <Zap size={40} className="runner-idle-icon" />
          <div className="runner-idle-title">Smart Runner</div>
          <div className="runner-idle-subtitle">
            Launch SuperSaiyan commands and interact with Claude through native UI
          </div>
          <div className="runner-command-grid">
            <button className="runner-cmd-btn" disabled={!repoId} onClick={() => void startRunner({ verb: "setup", args: [] })}>
              <Wrench size={20} />
              <span className="runner-cmd-label">Setup</span>
              <span className="runner-cmd-desc">Connect GitHub Project</span>
            </button>
            {newFeatureSlug !== null ? (
              <form
                className="runner-cmd-btn runner-cmd-form"
                onSubmit={(e) => {
                  e.preventDefault();
                  if (newFeatureSlug.trim()) void startRunner({ verb: "new", args: [newFeatureSlug.trim()] });
                  setNewFeatureSlug(null);
                }}
              >
                <input
                  className="field"
                  autoFocus
                  placeholder="feature-slug"
                  value={newFeatureSlug}
                  onChange={(e) => setNewFeatureSlug(e.target.value)}
                  style={{ height: 34 }}
                  onKeyDown={(e) => { if (e.key === "Escape") setNewFeatureSlug(null); }}
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

  const session = sessions.find((s) => s.id === runnerSessionId);

  return (
    <div className="runner-shell glass">
      <div className="runner-header">
        <div className="runner-header-left">
          {isRunning ? <span className="runner-live-dot" /> : <span className="runner-exit-dot" />}
          <span className="runner-session-title">{session?.title ?? "Runner"}</span>
          {exited && exitCode !== undefined && (
            <span className={`status-pill ${exitCode === 0 ? "ok" : "bad"}`}>exit {exitCode}</span>
          )}
        </div>
        <div className="topbar-actions">
          <button className="command-button" onClick={onSwitchToTerminal}>
            <SquareTerminal size={14} /> Raw terminal
          </button>
          {isRunning && runnerSessionId && (
            <button className="command-button danger" onClick={() => void transport.closeTerminal(runnerSessionId)}>
              <CircleStop size={14} /> Stop
            </button>
          )}
          {!isRunning && (
            <button className="command-button" onClick={() => {
              setRunnerSessionId(undefined);
              setLines([]);
              setExited(false);
              setExitCode(undefined);
            }}>
              <RefreshCw size={14} /> New command
            </button>
          )}
        </div>
      </div>

      <div className="runner-output">
        {lines.map((line, i) => (
          <div key={i} className="runner-line">{line || " "}</div>
        ))}
        <div ref={scrollRef} />
      </div>

      {uiMode === "choice" && choices.length > 0 && (
        <div className="runner-choices">
          <div className="runner-choices-label">Select an option</div>
          <div className="runner-choices-grid">
            {choices.map((label, i) => (
              <button key={i} className="runner-choice-btn" onClick={() => handleChoiceSelect(i)}>
                <span className="runner-choice-num">{i + 1}</span>
                <span>{label}</span>
              </button>
            ))}
          </div>
        </div>
      )}

      {uiMode === "permission" && (
        <div className="runner-permission">
          <div className="runner-permission-title">Permission required</div>
          <div className="runner-permission-context">
            {lines.slice(-3).map((l, i) => <div key={i} className="runner-line runner-line--muted">{l}</div>)}
          </div>
          <div className="runner-permission-actions">
            <button className="command-button primary" onClick={() => { sendInput("y\n"); setUiMode("normal"); }}>
              <Play size={14} fill="currentColor" /> Yes / Allow
            </button>
            <button className="command-button danger" onClick={() => { sendInput("n\n"); setUiMode("normal"); }}>
              <X size={14} /> No / Deny
            </button>
            <button className="command-button" onClick={() => { sendInput("\x1b"); setUiMode("normal"); }}>
              Esc / Cancel
            </button>
          </div>
        </div>
      )}

      <form className="runner-input-bar" onSubmit={handleFreeFormSubmit}>
        <input
          className="field runner-input"
          placeholder={isRunning ? "Type a response and press Enter…" : "Start a new command above"}
          value={inputText}
          disabled={!isRunning}
          onChange={(e) => setInputText(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Escape") sendInput("\x1b"); }}
        />
        <button type="submit" className="command-button primary" disabled={!isRunning || !inputText}>
          Send
        </button>
      </form>
    </div>
  );
}
