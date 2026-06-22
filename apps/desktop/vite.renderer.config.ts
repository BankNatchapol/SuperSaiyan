import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { resolve } from "node:path";

export default defineConfig({
  root: resolve(__dirname, "src/renderer"),
  plugins: [react()],
  resolve: {
    alias: {
      "@supersaiyan/control-protocol": resolve(__dirname, "../../packages/control-protocol/src/index.ts"),
      "@supersaiyan/ui": resolve(__dirname, "../../packages/ui/src/index.tsx"),
    },
  },
  build: {
    outDir: resolve(__dirname, ".vite/renderer/main_window"),
    emptyOutDir: true,
  },
});
