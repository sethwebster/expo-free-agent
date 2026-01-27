import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  plugins: [
    react({
      babel: {
        plugins: [["babel-plugin-react-compiler", {}]],
      },
    }),
    tailwindcss(),
  ],
  server: {
    proxy: {
      // Proxy API requests to Elixir controller during development
      "/api": {
        target: "http://localhost:4000",
        changeOrigin: true,
      },
      "/public": {
        target: "http://localhost:4000",
        changeOrigin: true,
      },
    },
  },
});
