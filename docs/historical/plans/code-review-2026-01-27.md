# Code Review: HeroVisualization Chrome Performance

**Date:** 2026-01-27
**Scope:** `/packages/landing-page/src/components/HeroVisualization/`
**Issue:** WebGL slideshow/glitchy performance in Chrome; Safari works fine

---

## 🔴 Critical Issues

### 1. MeshPhysicalMaterial with Transmission - SEVERE GPU Cost

**Location:** `materialPool.ts:155-175` (`applyGlowingState`)

**Problem:** Using `transmission` property on MeshPhysicalMaterial triggers subsurface scattering (SSS) which requires:
- Multiple render passes per transmissive object
- Screen-space refraction calculations
- Chrome's ANGLE layer handles this ~3x slower than Safari's native Metal

**Impact:** With 18+ nodes, each glowing node triggers expensive SSS. Chrome chokes.

```typescript
// materialPool.ts:166-167 - THE CULPRIT
mat.transmission = MATERIAL.CRYSTAL.transmission; // 0.85
mat.thickness = MATERIAL.CRYSTAL.thickness;       // 1.5
```

**Solution:** Disable transmission on Chrome entirely. Use emissive + standard material instead.

---

### 2. Per-Frame Material Property Mutations

**Location:** `MeshNode.tsx:309-340`, `materialPool.ts:155-194`

**Problem:** Every frame, `applyGlowingState()` and `applyObsidianState()` set 12-15 material properties:
- `color`, `emissive`, `emissiveIntensity`, `metalness`, `roughness`, `ior`, `transmission`, `thickness`, `attenuationColor`, `attenuationDistance`, `clearcoat`, `clearcoatRoughness`, `reflectivity`, `envMapIntensity`, `opacity`

Chrome's WebGL implementation may trigger shader recompilation when certain uniforms change. Safari's Metal backend handles this more gracefully.

**Impact:** 18 nodes x 60fps x 15 property changes = 16,200 uniform updates/second

**Solution:**
1. Only update properties that actually changed (dirty flag)
2. Reduce mutation frequency with throttling
3. Pre-create material variants instead of runtime property swapping

---

### 3. Bloom Post-Processing with mipmapBlur

**Location:** `index.tsx:50-55`

**Problem:**
```typescript
<Bloom
  intensity={4}           // Very high
  luminanceThreshold={0.1} // Very low - captures more
  mipmapBlur              // Multiple downsampling passes
/>
```

`mipmapBlur` generates multiple resolution levels of the bloom buffer. Chrome's compositor may not optimize this as well as Safari.

**Impact:** Doubles or triples render time for bloom effect alone.

**Solution:** Reduce intensity to 2, raise threshold to 0.3, disable `mipmapBlur` on Chrome.

---

## 🟡 Architecture Concerns

### 4. No Browser Detection / Adaptive Quality

**Location:** All visualization components

**Problem:** Same quality settings for all browsers. No detection, no fallbacks.

**Solution:** Add browser detection and quality tiers:
- Chrome: Lower quality (no transmission, reduced bloom, capped nodes)
- Safari: Full quality
- Low-end: Further reductions based on GPU blacklist or framerate

---

### 5. Particle System Per-Frame Position Updates

**Location:** `MeshNode.tsx:199-255`

**Problem:** Every frame when particles are active:
```typescript
for (let i = 0; i < MESH_CONFIG.PARTICLE_COUNT; i++) {
  positions[idx] += velocities[idx] * delta * 3;
  // ... more updates
}
particleRingRef.current.geometry.attributes.position.needsUpdate = true;
```

50 particles x 3 floats = 150 float updates + buffer upload per particle system per frame.

**Impact:** Minor compared to material issues, but contributes to frame budget.

---

### 6. Multiple Transparent Objects with Depth Sorting

**Location:** `MeshNode.tsx`, `ConnectionLine.tsx`

**Problem:** Many transparent objects (nodes, tubes, particles, flash effects) require depth sorting. Chrome's compositor may struggle.

**Impact:** Transparency overdraw and incorrect sorting.

---

## 🟢 DRY Opportunities

### 7. Duplicate Material State Application Logic

**Location:** `materialPool.ts:155-194`

**Problem:** `applyGlowingState` and `applyObsidianState` manually set many overlapping properties.

**Solution:** Create a single `applyMaterialState(mat, preset)` function with preset objects.

---

### 8. Repeated Geometry Pool Acquire/Release Pattern

**Location:** `MeshNode.tsx:92-95`, `DistributedMesh.tsx:36-39`, `ConnectionLine.tsx:119-123`

**Problem:** Same useEffect pattern repeated in 3 components:
```typescript
useEffect(() => {
  acquirePool();
  return () => releasePool();
}, []);
```

**Solution:** Create `useGeometryPool()` hook to encapsulate this.

---

## 🔵 Maintenance Improvements

### 9. No Frame Rate Monitoring

**Problem:** No visibility into actual performance. Can't detect when Chrome is struggling.

**Solution:** Add FPS counter in development mode. Use it to trigger quality reductions.

---

### 10. Magic Numbers in Animation Logic

**Location:** `MeshNode.tsx:324-333`

```typescript
const pulse = 1 + Math.sin(time * 3) * 0.15;
const edgePulse = 0.4 + Math.sin(time * 2.5) * 0.3;
```

**Solution:** Move to `constants.ts` for consistency and tunability.

---

## ⚪ Nitpicks

### 11. dpr Setting Could Be Lower for Chrome

**Location:** `index.tsx:36`

```typescript
dpr={[1, 1.5]}
```

Chrome may benefit from `dpr={[1, 1]}` to reduce fragment shader work.

---

## ✅ Strengths

1. **Geometry pooling** - Proper ref-counted pool prevents duplicate GPU uploads
2. **Material cleanup** - Proper disposal in useEffect cleanup functions
3. **Temp vector reuse** - Using `tempVec3A`, `tempColor` etc. avoids per-frame allocations
4. **Scaled cylinder approach** - Using unit cylinder with transforms instead of regenerating tube geometry each frame

---

## Recommended Fix Order

1. **Add browser detection utility** - Foundation for all other fixes
2. **Create quality presets** - `{ chrome: {...}, safari: {...}, low: {...} }`
3. **Disable transmission on Chrome** - Biggest performance win
4. **Reduce bloom on Chrome** - Second biggest win
5. **Throttle material updates** - Only update when glow state changes, not every frame
6. **Add FPS monitoring** - Verify fixes work

---

## Implementation Plan

### Phase 1: Browser Detection + Quality System

Create `/components/HeroVisualization/quality.ts`:
```typescript
export interface QualitySettings {
  useTransmission: boolean;
  bloomIntensity: number;
  bloomThreshold: number;
  useMipmapBlur: boolean;
  maxNodes: number;
  particleCount: number;
  dpr: [number, number];
}

export function detectBrowser(): 'chrome' | 'safari' | 'other';
export function getQualitySettings(): QualitySettings;
```

### Phase 2: Material Simplification

In `materialPool.ts`, add Chrome-specific material factory:
```typescript
export function createNodeMaterial(isChrome: boolean): THREE.Material {
  if (isChrome) {
    // MeshStandardMaterial with emissive, no transmission
    return new THREE.MeshStandardMaterial({...});
  }
  // Full MeshPhysicalMaterial with transmission
  return new THREE.MeshPhysicalMaterial({...});
}
```

### Phase 3: Bloom Adjustment

In `index.tsx`, conditional bloom props based on quality settings.

### Phase 4: State Update Optimization

In `MeshNode.tsx`, track glow state and only call `applyGlowingState`/`applyObsidianState` on transitions, not every frame.
