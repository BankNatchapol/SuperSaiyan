import type { ControlTransport } from "@supersaiyan/control-protocol";

declare global {
  interface Window {
    supersaiyan: ControlTransport;
  }
}

export {};
