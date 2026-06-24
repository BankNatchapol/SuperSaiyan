import { useEffect, useRef } from "react";
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import "@xterm/xterm/css/xterm.css";
import type { ControlTransport, TerminalSession } from "@supersaiyan/control-protocol";

export function TerminalView({ transport, session }: { transport: ControlTransport; session: TerminalSession }) {
  const host = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!host.current) return;
    const terminal = new Terminal({
      convertEol: true,
      cursorBlink: true,
      fontFamily: '"JetBrains Mono", monospace',
      fontSize: 12,
      scrollback: 10_000,
      theme: {
        background: "#07070b",
        foreground: "#e7e7ed",
        cursor: "#ffd60a",
        selectionBackground: "#4d430f",
        black: "#111118",
        brightBlack: "#666674",
        yellow: "#ffd60a",
        brightYellow: "#ffe45c",
        green: "#4ade80",
        blue: "#60a5fa",
        cyan: "#22d3ee",
        magenta: "#a78bfa",
        red: "#f87171",
      },
    });
    const fit = new FitAddon();
    terminal.loadAddon(fit);
    terminal.open(host.current);
    fit.fit();
    void transport.resizeTerminal(session.id, terminal.cols, terminal.rows);
    const input = terminal.onData((data) => void transport.writeTerminal(session.id, data));
    // Subscribe before replaying so we don't miss data that arrives during the replay IPC call.
    const removeData = transport.onTerminalData((event) => {
      if (event.sessionId === session.id) terminal.write(event.data);
    });
    // Replay buffered output that the PTY emitted before this xterm instance subscribed.
    void transport.replayTerminal(session.id).then((buffered) => {
      if (buffered) terminal.write(buffered);
    });
    const observer = new ResizeObserver(() => {
      fit.fit();
      void transport.resizeTerminal(session.id, terminal.cols, terminal.rows);
    });
    observer.observe(host.current);
    terminal.focus();
    return () => {
      observer.disconnect();
      removeData();
      input.dispose();
      terminal.dispose();
    };
  }, [session.id, transport]);

  return <div ref={host} className="terminal-host" aria-label={`Terminal ${session.title}`} />;
}
