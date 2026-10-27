import { defineConfig } from "vite";
import { nitro } from "nitro/vite";
import { workflow } from "workflow/vite";
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
export default defineConfig({
  base: "/",
  build: { target: "es2022" },
  server: { host: "127.0.0.1", port: 5173 },
  plugins: [
    nitro(),
    workflow(),
    {
      name: "pillcheck-offline",
      apply: "build",
      applyToEnvironment: (env) => env.name === "client",
      generateBundle(_, bundle) {
        const assets = Object.keys(bundle).filter((x) => !x.endsWith(".map"));
        const version = createHash("sha256")
          .update(assets.join())
          .digest("hex")
          .slice(0, 10);
        const files = [
          "/",
          "/favicon.svg",
          "/manifest.webmanifest",
          "/labels/metformin.png",
          "/labels/glucophage.png",
          "/labels/cimetidine.png",
          "/icons/icon-192.png",
          "/icons/icon-512.png",
          ...assets.map((x) => `/${x}`),
        ];
        const sw = readFileSync("src/sw.template.js", "utf8")
          .replace("__VERSION__", version)
          .replace("__PRECACHE__", JSON.stringify(files));
        this.emitFile({ type: "asset", fileName: "sw.js", source: sw });
      },
    },
  ],
  nitro: {
    serverDir: "./server",
    preset: process.env.VERCEL ? "vercel" : undefined,
    vercel: { functions: { maxDuration: 30 } },
  },
});
