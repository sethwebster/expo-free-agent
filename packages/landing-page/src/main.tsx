import { StrictMode, useState, useEffect } from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import { HeroGlobePage } from "./pages/HeroGlobePage";
import { CLILoginPage } from "./pages/CLILoginPage";
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

// Custom hook for hash-based routing
function useHashRoute() {
  const [route, setRoute] = useState(window.location.hash);

  useEffect(() => {
    const handleHashChange = () => setRoute(window.location.hash);
    window.addEventListener("hashchange", handleHashChange);
    return () => window.removeEventListener("hashchange", handleHashChange);
  }, []);

  return route;
}

// Simple hash-based router
function Router() {
  const route = useHashRoute();

  // Route matching
  if (route === "#/hero-globe") {
    return <HeroGlobePage />;
  }

  if (route.startsWith("#/cli/login")) {
    return <CLILoginPage />;
  }

  return <App />;
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <ThemeProvider>
      <Router />
    </ThemeProvider>
  </StrictMode>
);
