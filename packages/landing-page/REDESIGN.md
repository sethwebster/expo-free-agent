# Free Agent - Apple-Style Launch Redesign

## Design Philosophy: "The Product Launch"

We have pivoted from a standard SaaS landing page to a **Cinematic Product Reveal**. The goal is to make "Free Agent" feel like high-end infrastructure hardware (e.g., Apple M-series, Teenage Engineering).

### 🎨 Key Aesthetic Pillars
1.  **Immersive Hero**: Full-screen, fixed 3D visualization that zooms and fades on scroll.
2.  **Typography**: Massive, tight-tracking headers (`text-[10rem]`) that demand attention.
3.  **Bento Grid**: Features are presented in a modular, high-fidelity grid rather than lists.
4.  **Motion**: Elements don't just appear; they stagger, float, and curtain-reveal using scroll observers.
5.  **Light/Dark Duality**: 
    *   **Light Mode (Default)**: Clean, sterile, lab-like precision. White backgrounds, gray-900 text.
    *   **Dark Mode**: Deep, cinematic, "Pro" mode. True black backgrounds.

## 🛠 Technical Implementation

### Scroll-Driven Animation
- **Parallax**: The Hero background is `fixed`, creating a curtain effect where the content slides over it.
- **Dynamic Zoom/Fade**: We use a `scroll` event listener to calculate `opacity` (1 → 0) and `scale` (1.05 → 1.2) based on `window.scrollY`. This ensures the background disappears exactly when the second section arrives.

### Component Architecture
- **Hero**: `h-screen`, fixed background, scroll logic.
- **BentoGrid**: CSS Grid with `auto-rows-[400px]` and column spans.
- **ScrollReveal**: A custom `useScrollReveal` hook triggers CSS transforms (`translate-y`, `opacity`) when elements enter the viewport.

### Assets
- **3D Visuals**: Custom generated 8k-style renders in `/public/assets/`.
    - `hero-bg-large.png`: Full mesh network.
    - `feature-cpu.png`: Macro chip shot.
    - `feature-security.png`: Glass/Metal shield.
    - `feature-network.png`: Abstract nodes.

## 📝 Messaging Strategy
- **Positioning**: "Distributed Build Mesh"
- **Value Prop**: "Turn your idle Mac into build credits."
- **Architecture**:
    - **Worker**: Run by you (Open Source).
    - **Controller**: Centralized (managed queue).
    - **CLI**: The interface.

## Future Recommendations
- **Video**: Replace the hero image with a WebM loop of the network pulsing for even more immersion.
- **Interactive Globe**: A WebGL globe in the "Community Mesh" card showing active workers.
