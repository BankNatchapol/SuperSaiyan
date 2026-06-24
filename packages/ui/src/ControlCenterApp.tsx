import { useCallback, useEffect, useMemo, useState } from "react";
import {
  Activity,
  Bolt,
  Boxes,
  CircleStop,
  FolderGit2,
  Gauge,
  GitPullRequest,
  LayoutDashboard,
  ListTodo,
  Play,
  Plus,
  RefreshCw,
  Search,
  Settings,
  SquareTerminal,
  Wrench,
  X,
} from "lucide-react";
import {
  emptyLanes,
  laneNames,
  type AppPreferences,
  type BoardCard,
  type CommandRequest,
  type ControlTransport,
  type RepositoryRecord,
  type RepositorySnapshot,
  type Screen,
  type TerminalSession,
} from "@supersaiyan/control-protocol";
import { TerminalView } from "./TerminalView";

export interface ControlCenterAppProps {
  transport: ControlTransport;
}

const DIAG_GUIDE: Record<string, { body: string; code?: string; action?: { label: string; verb: "setup" | "install" } }> = {
  config:    { body: "Connect your GitHub Project board to enable the SuperSaiyan pipeline.", action: { label: "Run Setup", verb: "setup" } },
  installed: { body: "SuperSaiyan skills are not installed in this repository.", action: { label: "Repair / Install", verb: "install" } },
  git:       { body: "Initialise a Git repository in this directory:", code: "git init" },
  remote:    { body: "Add a GitHub remote so the pipeline can push issues:", code: "git remote add origin <your-repo-url>" },
  gh:        { body: "Authenticate the GitHub CLI:", code: "gh auth login" },
  claude:    { body: "Install Claude Code:", code: "npm install -g @anthropic-ai/claude-code" },
};

const laneColors: Record<string, string> = {
  Backlog: "#888895",
  Ready: "#ffd60a",
  Building: "#60a5fa",
  QA: "#22d3ee",
  Review: "#a78bfa",
  Done: "#4ade80",
  Blocked: "#f87171",
  Skipped: "#666674",
};

function MetricCard({ label, value, detail, hot = false }: { label: string; value: string | number; detail: string; hot?: boolean }) {
  return (
    <div className={`metric glass hover-lift ${hot ? "glass--hot" : ""}`}>
      <div className="metric-label">{label}</div>
      <div className={`metric-value ${hot ? "gold" : ""}`}>{value}</div>
      <div className="metric-meta">{detail}</div>
      <div className="mini-bars" aria-hidden="true">
        {[35, 48, 42, 60, 52, 68, 61, 77, 70, 88].map((height, index) => (
          <i key={index} className={hot && index > 6 ? "hot" : ""} style={{ height: `${height}%` }} />
        ))}
      </div>
    </div>
  );
}

function HealthCore({ snapshot }: { snapshot?: RepositorySnapshot }) {
  const ok = snapshot?.diagnostics.filter((item) => item.ok).length ?? 0;
  const total = snapshot?.diagnostics.length || 1;
  const score = Math.round((ok / total) * 100);
  return (
    <div className="health-core">
      <div className="health-row">
        <div className="health-orb power-core"><Bolt size={17} fill="currentColor" /></div>
        <div className="health-copy">
          <div className="eyebrow">Pipeline health</div>
          <div className="health-value">{score}%</div>
        </div>
      </div>
      <div className="health-bar"><div style={{ width: `${score}%` }} /></div>
    </div>
  );
}

function BoardView({ snapshot, onMove, onOpen }: {
  snapshot: RepositorySnapshot;
  onMove: (card: BoardCard, target: "Backlog" | "Ready") => void;
  onOpen: (url?: string) => void;
}) {
  return (
    <div className="board">
      {laneNames.map((lane) => (
        <section
          className="lane"
          key={lane}
          onDragOver={(event) => {
            if (lane === "Backlog" || lane === "Ready") event.preventDefault();
          }}
          onDrop={(event) => {
            if (lane !== "Backlog" && lane !== "Ready") return;
            const number = Number(event.dataTransfer.getData("text/issue-number"));
            const source = laneNames.flatMap((name) => snapshot.lanes[name]).find((card) => card.number === number);
            if (source) onMove(source, lane);
          }}
        >
          <div className="lane-header" style={{ "--lane-color": laneColors[lane] } as React.CSSProperties}>
            <span className="lane-dot" />
            {lane}
            <span className="lane-count">{snapshot.lanes[lane].length}</span>
          </div>
          <div className="lane-cards">
            {snapshot.lanes[lane].map((card) => {
              const movable = ["Backlog", "Ready", "Blocked", "Skipped"].includes(card.status) && card.state === "OPEN" && !card.assignees.length;
              return (
                <article
                  className={`issue-card hover-lift ${movable ? "movable" : ""}`}
                  key={card.id}
                  draggable={movable}
                  onDragStart={(event) => event.dataTransfer.setData("text/issue-number", String(card.number))}
                  onDoubleClick={() => onOpen(card.url)}
                >
                  <div className="issue-number">#{card.number} · {card.repository || snapshot.repository.name}</div>
                  <div className="issue-title">{card.title}</div>
                  <div className="issue-meta">
                    {card.dependency && <span className="chip">waits #{card.dependency}</span>}
                    {card.rebuildCount > 0 && <span className="chip">rebuild {card.rebuildCount}</span>}
                    {card.assignees.map((assignee) => <span className="chip" key={assignee}>{assignee}</span>)}
                    {card.labels.slice(0, 3).map((label) => <span className="chip" key={label}>{label}</span>)}
                  </div>
                </article>
              );
            })}
          </div>
        </section>
      ))}
    </div>
  );
}

export function ControlCenterApp({ transport }: ControlCenterAppProps) {
  const [repositories, setRepositories] = useState<RepositoryRecord[]>([]);
  const [repoId, setRepoId] = useState<string>();
  const [snapshot, setSnapshot] = useState<RepositorySnapshot>();
  const [screen, setScreen] = useState<Screen>("overview");
  const [loading, setLoading] = useState(false);
  const [notice, setNotice] = useState<string>();
  const [sessions, setSessions] = useState<TerminalSession[]>([]);
  const [activeSession, setActiveSession] = useState<string>();
  const [preferences, setPreferences] = useState<AppPreferences>();
  const [newFeatureSlug, setNewFeatureSlug] = useState<string | null>(null);
  const [phaseInputs, setPhaseInputs] = useState<Record<string, string>>({});
  const [expandedDiag, setExpandedDiag] = useState<string | null>(null);

  const refresh = useCallback(async (force = false) => {
    if (!repoId) return;
    setLoading(true);
    try {
      setSnapshot(await transport.getSnapshot(repoId, force));
      setNotice(undefined);
    } catch (error) {
      setNotice(error instanceof Error ? error.message : String(error));
    } finally {
      setLoading(false);
    }
  }, [repoId, transport]);

  useEffect(() => {
    void transport.listRepositories().then((items) => {
      setRepositories(items);
      setRepoId((current) => current || items[0]?.id);
    });
    void transport.getPreferences().then((prefs) => {
      setPreferences(prefs);
      document.documentElement.style.setProperty("--glass", String(prefs.glassOpacity ?? 1));
    });
  }, [transport]);

  useEffect(() => {
    if (!repoId) {
      setSnapshot(undefined);
      return;
    }
    setSnapshot(undefined);
    void refresh(true);
    const remove = transport.onRepositoryChanged((event) => {
      if (event.repoId === repoId) void refresh();
    });
    return remove;
  }, [repoId, refresh, transport]);

  useEffect(() => {
    if (!repoId || !preferences) return;
    const seconds = snapshot?.runActive ? preferences.activeRefreshSeconds : preferences.idleRefreshSeconds;
    const timer = window.setInterval(() => void refresh(), Math.max(5, seconds) * 1000);
    return () => window.clearInterval(timer);
  }, [preferences, refresh, repoId, snapshot?.runActive]);

  const startCommand = async (request: CommandRequest) => {
    if (!repoId) return;
    try {
      const session = await transport.startCommand(repoId, request);
      setSessions((current) => current.some((item) => item.id === session.id) ? current : [...current, session]);
      setActiveSession(session.id);
      setScreen("terminal");
    } catch (error) {
      setNotice(error instanceof Error ? error.message : String(error));
    }
  };

  const createShell = async () => {
    if (!repoId) return;
    const session = await transport.createTerminal(repoId, "shell");
    setSessions((current) => [...current, session]);
    setActiveSession(session.id);
    setScreen("terminal");
  };

  const addRepository = async () => {
    const repository = await transport.addRepository();
    if (!repository) return;
    setRepositories((current) => [...current.filter((item) => item.id !== repository.id), repository]);
    setRepoId(repository.id);
    setScreen("overview");
  };

  const removeRepository = async () => {
    if (!repoId) return;
    await transport.removeRepository(repoId);
    const next = repositories.filter((item) => item.id !== repoId);
    setRepositories(next);
    setRepoId(next[0]?.id);
  };

  const counts = useMemo(() => {
    const lanes = snapshot?.lanes ?? emptyLanes();
    return Object.fromEntries(laneNames.map((lane) => [lane, lanes[lane].length])) as Record<string, number>;
  }, [snapshot]);

  const health = snapshot?.diagnostics.filter((item) => item.ok).length ?? 0;
  const totalCards = laneNames.reduce((sum, lane) => sum + (snapshot?.lanes[lane].length ?? 0), 0);
  const currentSession = sessions.find((session) => session.id === activeSession);
  const repo = repositories.find((item) => item.id === repoId);
  const nav = [
    { id: "overview" as const, label: "Overview", icon: LayoutDashboard, badge: snapshot?.runActive ? "LIVE" : "" },
    { id: "board" as const, label: "Board", icon: Boxes, badge: totalCards ? String(totalCards) : "" },
    { id: "features" as const, label: "Features", icon: ListTodo, badge: snapshot?.features.length ? String(snapshot.features.length) : "" },
    { id: "runs" as const, label: "Runs", icon: Activity, badge: snapshot?.workers.length ? String(snapshot.workers.length) : "" },
    { id: "terminal" as const, label: "Terminal", icon: SquareTerminal, badge: sessions.length ? String(sessions.length) : "" },
    { id: "repositories" as const, label: "Repositories", icon: FolderGit2, badge: "" },
    { id: "settings" as const, label: "Settings", icon: Settings, badge: "" },
  ];

  const screenTitle = nav.find((item) => item.id === screen)?.label || "Overview";
  const renderContent = () => {
    if (!repoId) {
      return (
        <div className="empty-state">
          <div><strong>Connect your first repository</strong>Select a local Git repository to begin.<br /><br />
            <button className="command-button primary" onClick={addRepository}><Plus size={15} /> Add repository</button>
          </div>
        </div>
      );
    }
    if (!snapshot) {
      if (screen === "board") return (
        <div style={{ display: "flex", gap: 12 }}>
          {[...Array(5)].map((_, i) => <div key={i} className="glass skeleton" style={{ width: 278, flexShrink: 0, minHeight: 420, borderRadius: 13 }} />)}
        </div>
      );
      if (screen === "features" || screen === "runs" || screen === "repositories") return (
        <div className="grid-2">
          <div className="panel glass skeleton" style={{ minHeight: 280 }} />
          <div className="panel glass skeleton" style={{ minHeight: 280 }} />
        </div>
      );
      if (screen === "settings") return (
        <div className="panel glass skeleton" style={{ minHeight: 260 }} />
      );
      if (screen === "terminal") return (
        <div className="glass skeleton" style={{ height: "calc(100vh - 145px)", borderRadius: 16 }} />
      );
      return (
        <div className="stack">
          <div className="grid-4">{[...Array(4)].map((_, i) => <div key={i} className="metric glass skeleton" />)}</div>
          <div className="grid-2">
            <div className="panel glass skeleton" style={{ minHeight: 220 }} />
            <div className="panel glass skeleton" style={{ minHeight: 220 }} />
          </div>
        </div>
      );
    }

    if (screen === "board") {
      return <BoardView snapshot={snapshot} onOpen={(url) => url && void transport.openExternal(url)} onMove={(card, target) => {
        void transport.moveBoardCard(repoId, card.number, target).then(() => refresh(true)).catch((error) => setNotice(error.message));
      }} />;
    }

    if (screen === "features") {
      return (
        <div className="stack">
          <div className="panel glass">
            <h3 className="panel-title">Feature pipeline</h3>
            <div className="panel-subtitle">Design → Spec → Tasks → Issues → Lint → Run</div>
            <div className="feature-list">
              {snapshot.features.map((feature) => (
                <div className="feature-row" key={feature.slug}>
                  <div className="worker-icon"><ListTodo size={16} /></div>
                  <div className="row-main">
                    <div className="row-title">{feature.slug}</div>
                    <div className="row-subtitle">
                      {feature.kind} · {feature.spec ? "spec ✓" : "no spec"} · {feature.taskCount} tasks · {feature.issueCount} issues
                      {feature.phases?.length ? ` · phases ${feature.phases.join(", ")}` : ""}
                    </div>
                  </div>
                  <div className="topbar-actions">
                    {feature.phases?.length ? (
                      phaseInputs[feature.slug] !== undefined ? (
                        <form style={{ display: "flex", gap: 6 }} onSubmit={(e) => { e.preventDefault(); const v = phaseInputs[feature.slug]; if (v && /^\d+$/.test(v)) void startCommand({ verb: "prepare", args: [feature.slug, "--phase", v] }); setPhaseInputs((p) => { const n = { ...p }; delete n[feature.slug]; return n; }); }}>
                          <input className="field" autoFocus placeholder={feature.phases?.join(", ")} value={phaseInputs[feature.slug]} onChange={(e) => setPhaseInputs((p) => ({ ...p, [feature.slug]: e.target.value }))} style={{ height: 34, width: 80 }} onKeyDown={(e) => { if (e.key === "Escape") setPhaseInputs((p) => { const n = { ...p }; delete n[feature.slug]; return n; }); }} />
                          <button type="submit" className="command-button">Unlock</button>
                        </form>
                      ) : (
                        <button className="command-button" onClick={() => setPhaseInputs((p) => ({ ...p, [feature.slug]: "" }))}>Unlock phase</button>
                      )
                    ) : null}
                    <button className="command-button" onClick={() => void startCommand({ verb: "prepare", args: [feature.slug] })}>Prepare</button>
                  </div>
                </div>
              ))}
              {!snapshot.features.length && <div className="empty-state"><div><strong>No feature artifacts yet</strong>Start one with New Feature.</div></div>}
            </div>
          </div>
        </div>
      );
    }

    if (screen === "runs") {
      return (
        <div className="grid-2">
          <div className="panel glass glass--hot">
            <h3 className="panel-title">Current wave</h3>
            <div className="panel-subtitle">{snapshot.runActive ? `${snapshot.workers.length} workers active` : "No active run"}</div>
            <div className="worker-list">
              {snapshot.workers.map((worker) => (
                <div className="worker-row" key={`${worker.lane}-${worker.issue}`}>
                  <div className="worker-icon live-dot">{worker.lane === "build" ? "B" : worker.lane === "qa" ? "Q" : "R"}</div>
                  <div className="row-main"><div className="row-title">#{worker.issue} · {worker.lane}</div><div className="row-subtitle">PID {worker.pid || "workflow"} · started {worker.startedAt || "recently"}</div></div>
                  <span className="status-pill warn">Active</span>
                </div>
              ))}
              {!snapshot.workers.length && <div className="empty-state"><div><strong>Pipeline idle</strong>Run a prepared feature to start a wave.</div></div>}
            </div>
          </div>
          <div className="panel glass">
            <h3 className="panel-title">Recent events</h3>
            <div className="activity-list">
              {snapshot.events.map((event, index) => (
                <div className="activity-row" key={`${event.time}-${index}`}>
                  <Activity size={15} color="#ffd60a" />
                  <div className="row-main"><div className="row-title">{event.kind}{event.issue ? ` · #${event.issue}` : ""}</div><div className="row-subtitle">{event.detail}</div></div>
                  <span className="metric-meta">{event.time}</span>
                </div>
              ))}
              {!snapshot.events.length && <div className="row-subtitle">No manifest events yet.</div>}
            </div>
          </div>
        </div>
      );
    }

    if (screen === "terminal") {
      return (
        <div className="terminal-shell glass">
          <div className="terminal-tabs">
            {sessions.map((session) => (
              <button key={session.id} className={`terminal-tab ${session.id === activeSession ? "active" : ""}`} onClick={() => setActiveSession(session.id)}>
                {session.title}
              </button>
            ))}
            <button className="icon-button" title="New shell" onClick={createShell}><Plus size={15} /></button>
            {currentSession && <button className="icon-button" title="Close terminal" onClick={() => {
              void transport.closeTerminal(currentSession.id);
              setSessions((current) => current.filter((item) => item.id !== currentSession.id));
              setActiveSession(sessions.find((item) => item.id !== currentSession.id)?.id);
            }}><X size={14} /></button>}
          </div>
          {currentSession ? <TerminalView key={currentSession.id} transport={transport} session={currentSession} /> :
            <div className="empty-state"><div><strong>No terminal session</strong><button className="command-button primary" onClick={createShell}><SquareTerminal size={15} /> Open shell</button></div></div>}
        </div>
      );
    }

    if (screen === "repositories") {
      return (
        <div className="grid-2">
          <div className="panel glass">
            <h3 className="panel-title">Connected repositories</h3>
            <div className="repo-list">
              {repositories.map((item) => (
                <button className="repo-row hover-lift" key={item.id} onClick={() => setRepoId(item.id)} style={{ color: "inherit", textAlign: "left", cursor: "pointer" }}>
                  <div className="worker-icon"><FolderGit2 size={16} /></div>
                  <div className="row-main"><div className="row-title">{item.name}</div><div className="row-subtitle">{item.path}</div></div>
                  {item.id === repoId && <span className="status-pill ok">Active</span>}
                </button>
              ))}
            </div>
          </div>
          <div className="panel glass">
            <h3 className="panel-title">Repository actions</h3>
            <div className="stack" style={{ marginTop: 16 }}>
              <button className="command-button primary" onClick={addRepository}><Plus size={15} /> Connect repository</button>
              <button className="command-button" onClick={() => repoId && void transport.installOrRepair(repoId).then((session) => {
                setSessions((current) => [...current, session]); setActiveSession(session.id); setScreen("terminal");
              })}><Wrench size={15} /> Install / Repair</button>
              <button className="command-button danger" onClick={removeRepository}><X size={15} /> Remove from Control Center</button>
            </div>
          </div>
        </div>
      );
    }

    if (screen === "settings") {
      return preferences ? (
        <div className="panel glass">
          <h3 className="panel-title">Control Center settings</h3>
          <div className="settings-grid" style={{ marginTop: 20 }}>
            <label htmlFor="idle-refresh">Idle refresh</label>
            <input id="idle-refresh" className="field" type="number" value={preferences.idleRefreshSeconds} onChange={(event) => {
              const next = { ...preferences, idleRefreshSeconds: Number(event.target.value) };
              setPreferences(next); void transport.updatePreferences(next);
            }} />
            <label htmlFor="active-refresh">Active refresh</label>
            <input id="active-refresh" className="field" type="number" value={preferences.activeRefreshSeconds} onChange={(event) => {
              const next = { ...preferences, activeRefreshSeconds: Number(event.target.value) };
              setPreferences(next); void transport.updatePreferences(next);
            }} />
            <label htmlFor="shell">Shell</label>
            <input id="shell" className="field" value={preferences.shell} onChange={(event) => {
              const next = { ...preferences, shell: event.target.value };
              setPreferences(next); void transport.updatePreferences(next);
            }} />
            <label htmlFor="model-tier">Model tier</label>
            <select id="model-tier" className="field" value={preferences.modelTier} onChange={(event) => {
              const next = { ...preferences, modelTier: event.target.value as AppPreferences["modelTier"] };
              setPreferences(next); void transport.updatePreferences(next);
            }}>
              <option value="low">Low</option><option value="medium">Medium</option><option value="high">High</option>
            </select>
            <label htmlFor="glass-opacity">Transparency</label>
            <input id="glass-opacity" className="field" type="range" min="0" max="1" step="0.05"
              value={preferences.glassOpacity ?? 1}
              onChange={(event) => {
                const v = Number(event.target.value);
                document.documentElement.style.setProperty("--glass", String(v));
                const next = { ...preferences, glassOpacity: v };
                setPreferences(next); void transport.updatePreferences(next);
              }}
            />
          </div>
        </div>
      ) : null;
    }

    return (
      <div className="stack">
        <div className="grid-4">
          <MetricCard label="Pipeline health" value={`${Math.round((health / Math.max(snapshot.diagnostics.length, 1)) * 100)}%`} detail={`${health}/${snapshot.diagnostics.length} checks ready`} hot />
          <MetricCard label="Active workers" value={snapshot.workers.length} detail={snapshot.runActive ? "Autonomous run active" : "Pipeline idle"} />
          <MetricCard label="Completed" value={counts.Done ?? 0} detail={`${totalCards} cards on board`} />
          <MetricCard label="Ready queue" value={counts.Ready ?? 0} detail={`${counts.Blocked ?? 0} blocked · ${counts.Skipped ?? 0} skipped`} />
        </div>
        <div className="grid-2">
          <div className="panel glass glass--hot">
            <h3 className="panel-title">{snapshot.runActive ? "Current wave" : "Pipeline ready"}</h3>
            <div className="panel-subtitle">{snapshot.config ? `${snapshot.config.projectTitle} · ${snapshot.config.variant} · ${snapshot.config.baseBranch}` : "Run Setup to connect a GitHub Project"}</div>
            <div className="worker-list">
              {snapshot.workers.length ? snapshot.workers.map((worker) => (
                <div className="worker-row" key={`${worker.lane}-${worker.issue}`}>
                  <div className="worker-icon live-dot">{worker.lane.slice(0, 1).toUpperCase()}</div>
                  <div className="row-main"><div className="row-title">{worker.lane} · #{worker.issue}</div><div className="row-subtitle">Working in {snapshot.repository.name}</div></div>
                  <span className="status-pill warn">Powering up</span>
                </div>
              )) : snapshot.diagnostics.map((item) => {
                const guide = DIAG_GUIDE[item.key];
                const expanded = expandedDiag === item.key;
                return (
                  <div key={item.key}>
                    <div
                      className={`worker-row${!item.ok ? " hover-lift" : ""}`}
                      style={!item.ok ? { cursor: "pointer" } : undefined}
                      onClick={!item.ok ? () => setExpandedDiag(expanded ? null : item.key) : undefined}
                    >
                      <div className="worker-icon">{item.ok ? "✓" : "!"}</div>
                      <div className="row-main"><div className="row-title">{item.label}</div><div className="row-subtitle">{item.detail}</div></div>
                      <span className={`status-pill ${item.ok ? "ok" : "bad"}`}>{item.ok ? "Ready" : "Action"}</span>
                    </div>
                    {expanded && guide && (
                      <div className="diag-guide glass">
                        <span>{guide.body}</span>
                        {guide.code && <code className="diag-code">{guide.code}</code>}
                        {guide.action && (
                          <div>
                            <button className="command-button primary" onClick={() => {
                              if (guide.action!.verb === "install") {
                                void transport.installOrRepair(repoId!).then((session) => {
                                  setSessions((c) => c.some((s) => s.id === session.id) ? c : [...c, session]);
                                  setActiveSession(session.id);
                                  setScreen("terminal");
                                });
                              } else {
                                void startCommand({ verb: "setup", args: [] });
                              }
                              setExpandedDiag(null);
                            }}>{guide.action.label}</button>
                          </div>
                        )}
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          </div>
          <div className="panel glass">
            <h3 className="panel-title">Activity</h3>
            <div className="panel-subtitle">Latest pipeline events</div>
            <div className="activity-list">
              {snapshot.events.slice(0, 7).map((event, index) => (
                <div className="activity-row" key={`${event.time}-${index}`}>
                  <Activity size={15} color="#ffd60a" />
                  <div className="row-main"><div className="row-title">{event.kind}{event.issue ? ` · #${event.issue}` : ""}</div><div className="row-subtitle">{event.detail}</div></div>
                  <span className="metric-meta">{event.time}</span>
                </div>
              ))}
              {!snapshot.events.length && <div className="row-subtitle">Activity appears when a run starts.</div>}
            </div>
          </div>
        </div>
      </div>
    );
  };

  return (
    <div className="control-center">
      <aside className="sidebar">
        <div className="brand">
          <div className="brand-mark"><Bolt size={21} fill="currentColor" /></div>
          <div className="brand-copy"><div className="brand-title">SuperSaiyan</div><div className="eyebrow">Control Center</div></div>
        </div>
        <select className="repo-select" value={repoId || ""} onChange={(event) => setRepoId(event.target.value)}>
          <option value="">Select repository</option>
          {repositories.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}
        </select>
        {nav.map((item) => {
          const Icon = item.icon;
          return <button className={`nav-button ${screen === item.id ? "active" : ""}`} key={item.id} onClick={() => setScreen(item.id)}><Icon size={18} /><span>{item.label}</span>{item.badge && <span className="nav-badge">{item.badge}</span>}</button>;
        })}
        <div className="sidebar-spacer" />
        <HealthCore snapshot={snapshot} />
      </aside>
      <main className="main">
        <header className="topbar">
          <div>
            <div className="topbar-title">{screenTitle}<span className="tag">{snapshot?.runActive ? "LIVE" : snapshot?.config?.slug || "LOCAL"}</span></div>
            <div className="topbar-subtitle">{repo ? `${repo.name} · ${snapshot?.branch || "…"}` : "Connect a repository"}{snapshot?.config ? ` · ${snapshot.config.projectOwner}#${snapshot.config.projectNumber}` : ""}</div>
          </div>
          <div className="topbar-actions">
            <button className="icon-button" onClick={() => void refresh(true)} title="Refresh" disabled={loading}><RefreshCw size={16} className={loading ? "spinning" : ""} /></button>
            <button className="command-button" disabled={!repoId} onClick={() => void startCommand({ verb: "setup", args: [] })}><Wrench size={14} /> Setup</button>
            {newFeatureSlug !== null ? (
              <form style={{ display: "flex", gap: 6 }} onSubmit={(e) => { e.preventDefault(); if (newFeatureSlug.trim()) void startCommand({ verb: "new", args: [newFeatureSlug.trim()] }); setNewFeatureSlug(null); }}>
                <input className="field" autoFocus placeholder="feature-slug" value={newFeatureSlug} onChange={(e) => setNewFeatureSlug(e.target.value)} style={{ height: 38, width: 160 }} onKeyDown={(e) => { if (e.key === "Escape") setNewFeatureSlug(null); }} />
                <button type="submit" className="command-button primary" disabled={!newFeatureSlug.trim()}><Plus size={14} /> Create</button>
                <button type="button" className="icon-button" onClick={() => setNewFeatureSlug(null)}><X size={14} /></button>
              </form>
            ) : (
              <button className="command-button" disabled={!repoId} onClick={() => setNewFeatureSlug("")}><Plus size={14} /> New Feature</button>
            )}
            {snapshot?.runActive ?
              <button className="command-button danger" onClick={() => void startCommand({ verb: "stop", args: [] })}><CircleStop size={14} /> Stop</button> :
              <button className="command-button primary" disabled={!repoId} onClick={() => void startCommand({ verb: "run", args: preferences?.modelTier && preferences.modelTier !== "medium" ? [`--${preferences.modelTier}`] : [] })}><Play size={14} fill="currentColor" /> Run</button>}
          </div>
        </header>
        <section className="content">
          {notice && <div className="notice" style={{ marginBottom: 14 }}>{notice}</div>}
          {renderContent()}
        </section>
      </main>
    </div>
  );
}
