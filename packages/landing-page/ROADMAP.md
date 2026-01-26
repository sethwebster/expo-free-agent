# Expo Free Agent - Product Roadmap

## 🏁 Phase 1: Foundation (Completed)
- ✅ **Design System Upgrade**: Migrated to "Cinematic Product Reveal" aesthetic (Apple/teenage engineering style).
- ✅ **Tech Stack**: Vite, React 19, Tailwind v4.
- ✅ **Core Components**: Immersive Hero, Bento Grid Features, How It Works, Get Started.
- ✅ **Dark/Light Mode**: Seamless scaling transitions.

## 🚧 Phase 2: Live Network Intelligence (Current Focus)
The goal of this phase is to make the landing page feel "alive" and connected to the distributed mesh.

### 2.1 Live Network Stats Ticker
- **Objective**: Show real-time activity to prove network vitality.
- **Metrics**:
  - `Nodes Online` (e.g., 24 macs)
  - `Builds Queued` (e.g., 3 pending)
  - `Active Builds` (e.g., 2 running)
  - `Today's Throughput` (e.g., 148 builds)
- **Implementation**:
  - Top-level ticker or Hero badge row.
  - "Live" pulsing indicator.
  - Mocked data hook (`useNetworkStats`) for now, ready for API integration later.

### 2.2 Visual Immersion
- **WebGL Globe**: Replace static network image with interactive `cobe` or `react-globe.gl` globe showing active worker nodes.
- **Video Hero**: Replace static background with subtle looping neural network/mesh visualization.

## 🔭 Phase 3: Ecosystem Expansion
- **Documentation**: Dedicated docs site integration.
- **Controller Dashboard**: Admin view for managing the mesh (separate app/route).
- **GitHub Integration**: Live star count and contributor activity.

## 🛠 Backlog / Nice-to-Haves
- Magnetic button effects.
- Dynamic "spotlight" borders on bento cards.
- Sound design (subtle clicks/hums on interaction).
