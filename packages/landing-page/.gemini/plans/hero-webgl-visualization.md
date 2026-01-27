# Hero WebGL Distributed Compute Graph Visualization

## Overview

Replace the static `hero-bg-large.png` with a live, interactive WebGL visualization that brings the distributed compute mesh concept to life. The visualization should match the aesthetic of the original image (geometric nodes, glowing connections, light/airy feel) while adding motion and interactivity.

---

## Visual Design Goals

### Aesthetic Reference (from existing image)
- **Nodes**: Icosahedral/polyhedral shapes (low-poly geometric solids)
- **Connections**: Thin, glowing white lines between nodes
- **Color palette**: Soft whites, subtle grays, with indigo/purple accent glows
- **Depth**: Multiple layers of nodes at different Z-depths for parallax
- **Mood**: Clean, ethereal, high-tech but approachable

### Animation Goals
1. **Ambient Motion**: Nodes gently float/drift with subtle rotation
2. **Connection Pulses**: Periodic "data packets" travel along connection lines
3. **Breathing Effect**: Subtle scale pulsing on nodes (like they're "alive")
4. **Mouse Parallax**: Layers shift based on cursor position for depth
5. **Scroll Response**: Visualization responds to scroll (already have parallax infra)

---

## Technical Architecture

### Technology Stack
- **React Three Fiber** (`@react-three/fiber`) - React renderer for Three.js
- **Drei** (`@react-three/drei`) - Useful R3F helpers (OrbitControls, shaders, etc.)
- **Three.js** - Underlying WebGL engine

### Component Structure

```
src/
├── components/
│   └── HeroVisualization/
│       ├── index.tsx              # Main export, canvas setup
│       ├── DistributedMesh.tsx    # Scene container with nodes + connections
│       ├── MeshNode.tsx           # Individual geometric node
│       ├── ConnectionLine.tsx     # Animated line between nodes
│       ├── DataPulse.tsx          # Traveling pulse along connection
│       └── useNodePositions.ts    # Hook to generate/manage node layout
```

### Performance Considerations
- **Instanced Meshes**: Use `InstancedMesh` for nodes to batch draw calls
- **Line Segments**: Use `LineSegments` or `Line2` for connections
- **LOD**: Reduce detail at distance (if needed)
- **Frame Budget**: Target 60fps on M1 MacBooks, graceful degradation on older hardware
- **Fallback**: Detect WebGL support; show static image if unavailable

---

## Implementation Phases

### Phase 1: Foundation (Est. 30 min)
- [ ] Install dependencies: `@react-three/fiber`, `@react-three/drei`, `three`
- [ ] Create `<HeroVisualization />` component with basic Canvas
- [ ] Set up camera, lighting, and background
- [ ] Render a single test node (icosahedron)

### Phase 2: Node System (Est. 45 min)
- [ ] Create `useNodePositions` hook to generate 20-30 node positions in 3D space
- [ ] Implement `<MeshNode />` component with icosahedron geometry
- [ ] Add ambient rotation animation (useFrame)
- [ ] Add subtle floating/drift animation (sine wave offset)
- [ ] Style nodes: white/gray material with subtle metallic sheen

### Phase 3: Connection Lines (Est. 45 min)
- [ ] Calculate connections between nearby nodes (distance threshold)
- [ ] Implement `<ConnectionLine />` using Three.js Line or LineBasicMaterial
- [ ] Add glow effect using `LineMaterial` from Drei or custom shader
- [ ] Animate line opacity (subtle pulse)

### Phase 4: Data Pulses (Est. 30 min)
- [ ] Implement `<DataPulse />` - small glowing sphere that travels along a line
- [ ] Random timing for pulses (mimics network activity)
- [ ] Easing: accelerate at start, decelerate at end
- [ ] Integrate with NetworkContext (optional: sync with HUD stats)

### Phase 5: Interactivity (Est. 30 min)
- [ ] Mouse parallax: shift camera or layer groups based on cursor
- [ ] Scroll integration: connect to existing `--scroll-y` CSS variable
- [ ] Optional: subtle "hover" effect if cursor is near a node

### Phase 6: Polish & Integration (Est. 30 min)
- [ ] Replace static image in Hero with `<HeroVisualization />`
- [ ] Add WebGL fallback detection (show static PNG if no support)
- [ ] Performance testing on various devices
- [ ] Dark/light mode support (adjust materials/lighting)
- [ ] Final visual tuning (colors, speeds, densities)

---

## Node Layout Algorithm

```
Strategy: Clustered Random Distribution

1. Generate N nodes (25-35) with positions:
   - X: -15 to +15 (spread horizontally)
   - Y: -10 to +10 (spread vertically)
   - Z: -5 to +5 (depth layers)

2. Cluster tendency: 60% of nodes in central "core" (tighter radius)
   - 40% in outer "halo" (wider spread for depth)

3. Connection rules:
   - Connect nodes within distance threshold (e.g., 5 units)
   - Max 4 connections per node (avoid spaghetti)
   - Ensure no isolated nodes (at least 1 connection)

4. Randomize on mount (or use seeded random for consistency)
```

---

## Visual Tuning Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `nodeCount` | 30 | Number of geometric nodes |
| `nodeScale` | 0.3-0.8 | Random scale range for nodes |
| `driftSpeed` | 0.1 | How fast nodes float around |
| `rotationSpeed` | 0.2 | Node self-rotation speed |
| `connectionDistance` | 6 | Max distance to draw connection |
| `pulseFrequency` | 2000ms | Average time between pulses |
| `parallaxStrength` | 0.02 | Mouse movement sensitivity |

---

## Fallback Strategy

```tsx
function HeroBackground() {
  const [webglSupported, setWebglSupported] = useState(true);

  useEffect(() => {
    try {
      const canvas = document.createElement('canvas');
      const gl = canvas.getContext('webgl') || canvas.getContext('experimental-webgl');
      setWebglSupported(!!gl);
    } catch {
      setWebglSupported(false);
    }
  }, []);

  if (!webglSupported) {
    return <img src="/assets/hero-bg-large.png" ... />;
  }

  return <HeroVisualization />;
}
```

---

## Success Criteria

1. ✅ Visualization renders without performance issues (60fps on M1)
2. ✅ Visual style matches/exceeds the original static image quality
3. ✅ Animations are subtle and premium (not distracting or "gamey")
4. ✅ Dark and light mode both look excellent
5. ✅ Graceful fallback on unsupported browsers
6. ✅ Integrates seamlessly with existing scroll parallax system

---

## Dependencies to Install

```bash
npm install @react-three/fiber @react-three/drei three
npm install -D @types/three
```

---

## Questions / Decisions Needed

1. **Should pulses sync with HUD stats?** (e.g., pulse when "Active Builds" changes)
2. **Mouse interactivity level**: Just parallax, or actual node hover effects?
3. **Mobile behavior**: Simplified version or disable entirely?
4. **Performance budget**: How aggressive on older hardware?

---

## Ready to Proceed?

Once approved, I'll begin with **Phase 1: Foundation** and iterate through each phase, testing visually along the way.
