import { defineConfig } from "vite";
import { nitro } from "nitro/vite";

// Vercel hosts the Meta proxy for the native iOS app. No web medication UI remains.
export default defineConfig({
  plugins: [nitro()],
  server: { host: "127.0.0.1", port: 5173 },
  nitro: {
    serverDir: "./server",
    preset: process.env.VERCEL ? "vercel" : undefined,
    vercel: { functions: { maxDuration: 60 } },
  },
});
