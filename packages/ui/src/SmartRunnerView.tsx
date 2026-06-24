import { useEffect, useRef, useState } from "react";
import { CircleStop, Play, Plus, RefreshCw, Search, SquareTerminal, Wrench, X, Zap } from "lucide-react";
import type { CommandRequest, ControlTransport, TerminalSession } from "@supersaiyan/control-protocol";

// Strip all escape sequences: CSI, OSC (terminal title), DCS, Fe, BEL, stray control chars
function stripAnsi(str: string): string {
  return str
    .replace(/\x1B\][^\x07]*(?:\x07|\x1B\\)/g, "") // OSC: \x1b]...\x07 or \x1b]...\x1b\
    .replace(/\x1BP[^]*?\x1B\\/g, "")               // DCS sequences
    .replace(/\x1B\[[0-?]*[ -/]*[@-~]/g, "")        // CSI sequences
    .replace(/\x1B[@-_]/g, "")                       // Fe 2-char sequences
    .replace(/\x1B./g, "")                           // remaining ESC + char
    .replace(/\x07/g, "")                            // stray BEL
    .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, ""); // other control chars (keep \r \n \t)
}

// Box-drawing / block-element chars used in Claude Code's Ink TUI chrome
const BOX_CHARS = /[▐▛▜▝▘▙▟▚▞░▒▓│─┤├┼┬┴┐└┘┌█▀▄■◆◇▸▾]/g;

// Known Claude Code status-bar / chrome line patterns
const CHROME_PATTERNS = [
  /^[─┄═]+(\s+\S.*\S\s+[─┄═]+)?$/, // separator lines (────── title ──────)
  /^\?\s*for shortcuts/i,
  /^←\s*for agents/i,
  /^esc\s+to interrupt/i,
  /^●\s*(low|medium|high)\s*·\s*\/effort/i, // model tier status bar
  /^·\s*(low|medium|high)\s*·/i,
];

function isChromeLine(line: string): boolean {
  const t = line.trim();
  if (!t) return false;
  for (const p of CHROME_PATTERNS) if (p.test(t)) return true;
  // High density of box-drawing chars → UI chrome
  const chromeCount = (t.match(BOX_CHARS) || []).length;
  return chromeCount > t.length * 0.2;
}

// Characters that begin a spinner / thinking update from Ink
const SPINNER_START = /^[✶✻⏺✽⊕✢✳⧉·⠂⠃⠇⠏⠋⠙⠹⠸⠼⠴⠦⠧]/;

// Process one raw PTY chunk using a proper \r-overwrite model.
// pendingRef holds the current incomplete line across chunks.
// Returns committed full lines and optional spinner text captured from bare \r resets.
function processChunk(
  text: string,
  pendingRef: { current: string },
): { committed: string[]; spinnerText: string | null } {
  const committed: string[] = [];
  let spinnerText: string | null = null;

  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (ch === "\r") {
      if (text[i + 1] === "\n") {
        // \r\n → Windows newline, commit
        committed.push(pendingRef.current);
        pendingRef.current = "";
        i++;
      } else {
        // bare \r → in-place overwrite (spinner tick); capture text before reset
        const pending = pendingRef.current.trimStart();
        if (SPINNER_START.test(pending)) {
          spinnerText = pending.replace(/\s+/g, " ").trim();
        }
        pendingRef.current = "";
      }
    } else if (ch === "\n") {
      committed.push(pendingRef.current);
      pendingRef.current = "";
    } else {
      pendingRef.current += ch;
    }
  }

  return { committed, spinnerText };
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
  const [output, setOutput] = useState("");
  const [spinnerText, setSpinnerText] = useState<string | null>(null);
  const [isRunning, setIsRunning] = useState(runnerSessionId !== undefined);
  const [exited, setExited] = useState(false);
  const [exitCode, setExitCode] = useState<number>();
  const [inputText, setInputText] = useState("");
  const [uiMode, setUiMode] = useState<"normal" | "choice" | "permission">("normal");
  const [choices, setChoices] = useState<string[]>([]);
  const [newFeatureSlug, setNewFeatureSlug] = useState<string | null>(null);

  const pendingRef = useRef<string>("");   // current incomplete line across chunks
  const rollingBufferRef = useRef<string>("");
  const scrollRef = useRef<HTMLDivElement>(null);
  const sessionIdRef = useRef<string | undefined>(runnerSessionId);

  useEffect(() => {
    sessionIdRef.current = runnerSessionId;
    if (runnerSessionId) setIsRunning(true);
  }, [runnerSessionId]);

  useEffect(() => {
    const removeData = transport.onTerminalData((event) => {
      if (event.sessionId !== sessionIdRef.current) return;

      const stripped = stripAnsi(event.data);

      // Use rolling buffer (raw stripped) for prompt detection — unfiltered
      rollingBufferRef.current = (rollingBufferRef.current + stripped).slice(-2000);

      const { committed, spinnerText: spin } = processChunk(stripped, pendingRef);

      if (spin !== null) setSpinnerText(spin);

      if (committed.length > 0) {
        // Keep only non-chrome content lines
        const clean = committed
          .map((l) => l.trimEnd())
          .filter((l) => l.length > 0 && !isChromeLine(l));

        if (clean.length > 0) {
          setSpinnerText(null); // real output arrived → clear thinking indicator
          setOutput((prev) => {
            const next = prev + clean.join("\n") + "\n";
            return next.length > 50_000 ? next.slice(-50_000) : next;
          });
        }
      }

      // Prompt detection on rolling buffer
      const buf = rollingBufferRef.current;
      if (/Enter to select.*↑\/↓ to navigate/i.test(buf) || /\(Use arrow keys\)/i.test(buf)) {
        const parsed = parseNumberedOptions(buf);
        if (parsed.length >= 2) { setChoices(parsed); setUiMode("choice"); }
      } else if (/Esc to cancel.*Tab to amend/i.test(buf) || /Do you want to proceed/i.test(buf)) {
        setUiMode("permission"); setChoices([]);
      } else {
        setUiMode("normal"); setChoices([]);
      }
    });

    const removeExit = transport.onTerminalExit((event) => {
      if (event.sessionId !== sessionIdRef.current) return;
      setIsRunning(false); setExited(true); setExitCode(event.exitCode);
      setSpinnerText(null); setUiMode("normal"); setChoices([]);
    });

    return () => { removeData(); removeExit(); };
  }, [transport]);

  useEffect(() => {
    scrollRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [output]);

  const startRunner = async (request: CommandRequest) => {
    if (!repoId) return;
    setOutput(""); setSpinnerText(null); setExited(false); setExitCode(undefined);
    setUiMode("normal"); setChoices([]);
    pendingRef.current = "";
    rollingBufferRef.current = "";
    setIsRunning(true);

    const session = await onStartCommand(request);
    if (!session) { setIsRunning(false); return; }
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
    setUiMode("normal"); setChoices([]);
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
          {spinnerText && isRunning && (
            <span className="runner-spinner-pill">{spinnerText}</span>
          )}
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
              setOutput(""); setSpinnerText(null);
              setExited(false); setExitCode(undefined);
            }}>
              <RefreshCw size={14} /> New command
            </button>
          )}
        </div>
      </div>

      <div className="runner-output">
        {output ? (
          <pre className="runner-pre">{output}</pre>
        ) : isRunning ? (
          <div className="runner-waiting">
            <span className="runner-waiting-dot" />
            <span className="runner-waiting-dot" />
            <span className="runner-waiting-dot" />
          </div>
        ) : null}
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
          <div className="runner-permission-context runner-pre">
            {output.slice(-300)}
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
