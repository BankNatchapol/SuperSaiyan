import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { ControlCenterApp } from "@supersaiyan/ui";
import { mockTransport } from "./mockTransport";

const root = document.getElementById("root");
if (!root) throw new Error("Renderer root missing");

createRoot(root).render(
  <StrictMode>
    <ControlCenterApp transport={window.supersaiyan || mockTransport} />
  </StrictMode>,
);
