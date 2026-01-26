import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import { ThemeProvider } from "./hooks/useTheme";
import "./styles/globals.css";

// Console art
console.log(
  "%c Free Agent %c Distributed Build Mesh ",
  "background: linear-gradient(135deg, #6366f1, #a855f7, #ec4899); color: white; font-size: 16px; padding: 8px 12px; border-radius: 8px 0 0 8px;",
  "background: #18181b; color: #a1a1aa; font-size: 16px; padding: 8px 12px; border-radius: 0 8px 8px 0;"
);
console.log(
  "%cBuilt with Vite + React Compiler + Tailwind v4",
  "color: #71717a; font-size: 12px;"
);

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <ThemeProvider>
      <App />
    </ThemeProvider>
  </StrictMode>
);
