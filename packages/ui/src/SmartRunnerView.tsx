import { useEffect, useRef, useState } from "react";
import { CircleStop, Play, Plus, RefreshCw, Search, SquareTerminal, Wrench, X, Zap } from "lucide-react";
import type { CommandRequest, ControlTransport, TerminalSession } from "@supersaiyan/control-protocol";

// ─── ANSI / escape stripping ──────────────────────────────────────────────────

function stripAnsi(str: string): string {
  return str
    .replace(/\x1B\][^\x07]*(?:\x07|\x1B\\)/g, "") // OSC: \x1b]...\x07
    .replace(/\x1BP[^]*?\x1B\\/g, "")               // DCS
    .replace(/\x1B\[[0-?]*[ -/]*[@-~]/g, "")        // CSI
    .replace(/\x1B[@-_]/g, "")                       // Fe 2-char
    .replace(/\x1B./g, "")                           // remaining ESC+char
    .replace(/\x07/g, "")                            // BEL
    .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, ""); // control chars (keep \r \n \t)
}

// ─── Chrome line detection ────────────────────────────────────────────────────

const BOX_CHARS = /[▐▛▜▝▘▙▟▚▞░▒▓│─┤├┼┬┴┐└┘┌█▀▄■◆◇▸▾]/g;

const CHROME_PATTERNS = [
  /^[─┄═\s]+$/,                           // separator / blank lines of box chars
  /^\?\s*for shortcuts/i,
  /^←\s*for agents/i,
  /^esc\s+to interrupt/i,
  /^●\s*(low|medium|high)\s*·/i,          // model tier status bar
  /^·\s*(low|medium|high)\s*·/i,
  /^ctrl\+[a-z]/i,
  /^resume this session with:/i,
  /thinking with (high|medium|low) effort/i, // extended thinking status bar fragment
  // Lines starting with spinner/braille chars are status-bar leakage
  /^[✶✻✽⊕✢✳⠂⠃⠇⠏⠋⠙⠹⠸⠼⠴⠦⠧]\s/,
];

function isChromeLine(line: string): boolean {
  const t = line.trim();
  if (!t) return true;
  for (const p of CHROME_PATTERNS) if (p.test(t)) return true;
  const chromeCount = (t.match(BOX_CHARS) || []).length;
  return chromeCount > t.length * 0.2;
}

// ─── Extraction ───────────────────────────────────────────────────────────────

// Spinner character prefixes used by Ink / Claude Code
const SPINNER_PREFIX = /[ \t]*[✶✻⏺✽⊕✢✳·⠂⠃⠇⠏⠋⠙⠹⠸⠼⠴⠦⠧]/;

function extractReadable(raw: string): { lines: string[]; spinnerText: string | null } {
  let spinnerText: string | null = null;

  // Capture spinner from bare \r in-place overwrites
  const spinRe = /\r(?!\n)([^\r\n]*)/g;
  let sm: RegExpExecArray | null;
  while ((sm = spinRe.exec(raw)) !== null) {
    const candidate = stripAnsi(sm[1]).trim();
    if (candidate.length > 0 && SPINNER_PREFIX.test(candidate)) spinnerText = candidate;
  }

  // Convert cursor-position ANSI codes BEFORE stripping to preserve line structure.
  // KEY FIX: ESC[N;1H (col 1) → \n (new line), ESC[N;MH (col M>1) → space (same line).
  // Previously ALL cursor positions became \n, which split mid-row text into fake lines
  // (e.g. "✳ Sm" + "\n" + "thinking with high effort" from one status-bar row).
  const withBreaks = raw
    .replace(/\x1B\[2J/g, "\n")                    // clear screen
    .replace(/\x1B\[H/g, "\n")                     // cursor home (no params)
    .replace(/\x1B\[\d+;1[Hf]/g, "\n")             // ESC[N;1H → col 1 → new line
    .replace(/\x1B\[\d+;[2-9][Hf]/g, " ")          // ESC[N;2–9H → col 2-9 → space
    .replace(/\x1B\[\d+;\d{2,}[Hf]/g, " ")         // ESC[N;10+H → space
    .replace(/\x1B\[\d*[BE]/g, "\n");              // cursor down / next line

  const stripped = stripAnsi(withBreaks);
  const normalized = stripped.replace(/\r\n/g, "\n").replace(/\r/g, "\n");
  const allLines = normalized.split("\n").map((l) => l.trimEnd()).filter((l) => l.length > 0);

  // Also capture spinner from status-bar lines that become committed lines
  for (const l of allLines) {
    const t = l.trim();
    if (SPINNER_PREFIX.test(t) && /\d+[sm]/.test(t)) spinnerText = t;
  }

  const lines = allLines.filter((l) => !isChromeLine(l));
  return { lines, spinnerText };
}

// ─── Line classification (for styled display) ────────────────────────────────

type LineKind = "tool-call" | "tool-result" | "progress" | "command" | "text";

function classifyLine(line: string): LineKind {
  const t = line.trimStart();
  if (/^[●⏺✢]\s/.test(t)) return "tool-call";
  if (/^[└├]\s/.test(t) || /^\s+[└├]/.test(line)) return "tool-result";
  if (/^\+\s/.test(t)) return "progress";
  if (/^[❯>]\s/.test(t)) return "command";
  return "text";
}

// ─── Option parser (for choice menus) ────────────────────────────────────────

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

// ─── Component ────────────────────────────────────────────────────────────────

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
  const [lines, setLines] = useState<{ text: string; kind: LineKind }[]>([]);
  const [spinnerText, setSpinnerText] = useState<string | null>(null);
  const [isRunning, setIsRunning] = useState(runnerSessionId !== undefined);
  const [exited, setExited] = useState(false);
  const [exitCode, setExitCode] = useState<number>();
  const [inputText, setInputText] = useState("");
  const [uiMode, setUiMode] = useState<"normal" | "choice" | "permission">("normal");
  const [choices, setChoices] = useState<string[]>([]);
  const [newFeatureSlug, setNewFeatureSlug] = useState<string | null>(null);

  // Ring buffer for dedup: don't re-add a line we showed in the last 40 lines
  const shownRef = useRef<string[]>([]);
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

      const { lines: newRaw, spinnerText: spin } = extractReadable(event.data);

      // Raw stripped text for prompt detection
      const rawStripped = stripAnsi(event.data);
      rollingBufferRef.current = (rollingBufferRef.current + rawStripped).slice(-2000);

      if (spin !== null) setSpinnerText(spin);

      // Dedup against the last 40 shown lines
      const recent = shownRef.current.slice(-40);
      const fresh = newRaw.filter((l) => !recent.includes(l));

      if (fresh.length > 0) {
        fresh.forEach((l) => {
          shownRef.current.push(l);
          if (shownRef.current.length > 400) shownRef.current.shift();
        });
        setSpinnerText(null);
        setLines((prev) => {
          const next = [...prev, ...fresh.map((text) => ({ text, kind: classifyLine(text) }))];
          return next.length > 800 ? next.slice(-800) : next;
        });
      }

      // Prompt detection
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
  }, [lines]);

  const startRunner = async (request: CommandRequest) => {
    if (!repoId) return;
    setLines([]); setSpinnerText(null); setExited(false); setExitCode(undefined);
    setUiMode("normal"); setChoices([]);
    shownRef.current = [];
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

  // ── Idle splash ─────────────────────────────────────────────────────────────
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
  const lastToolResult = lines.length > 0 ? lines[lines.length - 1].text.slice(0, 80) : "";

  return (
    <div className="runner-shell glass">
      <div className="runner-header">
        <div className="runner-header-left">
          {isRunning ? <span className="runner-live-dot" /> : <span className="runner-exit-dot" />}
          <span className="runner-session-title">{session?.title ?? "Runner"}</span>
          {spinnerText && isRunning && (
            <span className="runner-spinner-pill" title={spinnerText}>{spinnerText}</span>
          )}
          {!spinnerText && isRunning && lines.length > 0 && (
            <span className="runner-spinner-pill runner-spinner-pill--muted" title={lastToolResult}>{lastToolResult}</span>
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
              setLines([]); setSpinnerText(null);
              setExited(false); setExitCode(undefined);
            }}>
              <RefreshCw size={14} /> New command
            </button>
          )}
        </div>
      </div>

      <div className="runner-output">
        {lines.length === 0 && isRunning ? (
          <div className="runner-waiting">
            <span className="runner-waiting-dot" />
            <span className="runner-waiting-dot" />
            <span className="runner-waiting-dot" />
          </div>
        ) : (
          lines.map((line, i) => (
            <div key={i} className={`runner-line runner-line--${line.kind}`}>
              {line.text}
            </div>
          ))
        )}
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
            {lines.slice(-5).map((l) => l.text).join("\n")}
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
