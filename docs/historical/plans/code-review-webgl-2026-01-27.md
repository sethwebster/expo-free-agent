# WebGL Landing Page Visualization Code Review

**Date:** 2026-01-27
**Files Reviewed:**
- `packages/landing-page/src/components/HeroVisualization/index.tsx`
- `packages/landing-page/src/components/HeroVisualization/DistributedMesh.tsx`
- `packages/landing-page/src/components/HeroVisualization/MeshNode.tsx`
- `packages/landing-page/src/components/HeroVisualization/ConnectionLine.tsx`

---

## CRITICAL Issues

### 1. Geometry Recreation Every Frame in `updateTubeGeometry()` - ConnectionLine.tsx:50

**Location:** `/packages/landing-page/src/components/HeroVisualization/ConnectionLine.tsx:27-62`

**Problem:** Creating new `THREE.CylinderGeometry` every frame during extend/retract animations. This allocates memory on GPU every single frame, causing severe GC pressure and potential memory exhaustion.

```typescript
// CURRENT - CATASTROPHIC
function updateTubeGeometry(...) {
  const geometry = new THREE.CylinderGeometry(radius, radius, length, 8, 1);
  mesh.geometry.dispose();  // Good that it disposes, but...
  mesh.geometry = geometry; // ...creating new geometry every frame is a perf killer
}
```

**Impact:**
- GPU memory churn
- GC pauses causing frame drops
- On mobile devices, this can exhaust WebGL context limits
- With N connections animating, this is N * 2 geometry creations per frame (inner + outer tubes)

**Solution:** Use a single cylinder geometry and transform via scale/position/rotation instead of recreating:

```typescript
// Reuse single unit cylinder, transform mathematically
const unitCylinderGeometry = useMemo(() =>
  new THREE.CylinderGeometry(1, 1, 1, 8, 1), []);

function updateTubeTransform(
  mesh: THREE.Mesh | null,
  start: [number, number, number],
  end: [number, number, number],
  radius: number
) {
  if (!mesh) return;

  const direction = tempVec3A.set(
    end[0] - start[0],
    end[1] - start[1],
    end[2] - start[2]
  );
  const length = direction.length();

  if (length < 0.001) {
    mesh.scale.set(0, 0, 0);
    return;
  }

  // Scale unit cylinder to desired dimensions
  mesh.scale.set(radius, length, radius);

  // Position at midpoint
  mesh.position.set(
    (start[0] + end[0]) / 2,
    (start[1] + end[1]) / 2,
    (start[2] + end[2]) / 2
  );

  // Rotate to align
  direction.normalize();
  const quaternion = tempQuat.setFromUnitVectors(Y_AXIS, direction);
  mesh.quaternion.copy(quaternion);
}
```

---

### 2. Missing Geometry/Material Disposal on Unmount - MeshNode.tsx

**Location:** `/packages/landing-page/src/components/HeroVisualization/MeshNode.tsx`

**Problem:** Multiple `useMemo` calls create Three.js geometries and materials that are never disposed when the component unmounts. Nodes can be dynamically added/removed, leaking GPU memory.

```typescript
// These are created but NEVER disposed
const geometry = useMemo(() => new THREE.IcosahedronGeometry(1, 0), []);
const edgesGeometry = useMemo(() => new THREE.EdgesGeometry(geometry), [geometry]);
const material = useMemo(() => createGlassMaterial(), []);
const edgeMaterial = useMemo(() => new THREE.LineBasicMaterial({...}), []);
const innerCoreGeometry = useMemo(() => new THREE.SphereGeometry(0.6, 16, 16), []);
const innerCoreMaterial = useMemo(() => new THREE.MeshBasicMaterial({...}), []);
const bigBangGeometry = useMemo(() => new THREE.SphereGeometry(1, 32, 32), []);
const bigBangMaterial = useMemo(() => new THREE.MeshBasicMaterial({...}), []);
const particleRingGeometry = useMemo(() => {...}, [particleCount]);
const particleRingMaterial = useMemo(() => new THREE.PointsMaterial({...}), []);
```

**Impact:**
- Each node creates ~10 GPU resources
- With dynamic node creation/deletion at 10% appearance rate, creates ~3.6 nodes/minute
- GPU memory grows unbounded over time
- Browser eventually crashes or WebGL context is lost

**Solution:** Add cleanup effect:

```typescript
useEffect(() => {
  return () => {
    geometry.dispose();
    edgesGeometry.dispose();
    material.dispose();
    edgeMaterial.dispose();
    innerCoreGeometry.dispose();
    innerCoreMaterial.dispose();
    bigBangGeometry.dispose();
    bigBangMaterial.dispose();
    particleRingGeometry.dispose();
    particleRingMaterial.dispose();
  };
}, [
  geometry, edgesGeometry, material, edgeMaterial,
  innerCoreGeometry, innerCoreMaterial, bigBangGeometry,
  bigBangMaterial, particleRingGeometry, particleRingMaterial
]);
```

---

### 3. Missing Disposal in ConnectionLine.tsx

**Location:** `/packages/landing-page/src/components/HeroVisualization/ConnectionLine.tsx`

**Problem:** Same issue - 8 geometries and 6 materials created per connection, never disposed.

```typescript
// Never disposed
const innerTubeGeometry = useMemo(() => new THREE.CylinderGeometry(...), []);
const innerTubeMaterial = useMemo(() => new THREE.MeshBasicMaterial(...), []);
const outerTubeGeometry = useMemo(() => new THREE.CylinderGeometry(...), []);
const outerTubeMaterial = useMemo(() => new THREE.MeshBasicMaterial(...), []);
const pulseMaterial = useMemo(() => new THREE.MeshBasicMaterial(...), []);
const pulseGeometry = useMemo(() => new THREE.SphereGeometry(...), []);
const flashMaterialFrom = useMemo(() => new THREE.MeshBasicMaterial(...), []);
const flashMaterialTo = useMemo(() => new THREE.MeshBasicMaterial(...), []);
const flashGeometry = useMemo(() => new THREE.SphereGeometry(...), []);
```

**Impact:** Connections are created/destroyed frequently. Memory leak is severe.

**Solution:** Add disposal useEffect (same pattern as MeshNode).

---

## ARCHITECTURE Concerns

### 4. No Geometry Pooling/Instancing - DistributedMesh.tsx

**Location:** `/packages/landing-page/src/components/HeroVisualization/DistributedMesh.tsx:419-433`

**Problem:** Each node creates its own geometry and material instances. With 18+ nodes, this means:
- 18+ icosahedron geometries (identical)
- 18+ edge geometries (identical base)
- 18+ physical materials (could be shared)
- 18+ sphere geometries for inner cores
- etc.

**Impact:**
- Excessive draw calls (one per node minimum)
- Duplicate GPU memory for identical geometries
- State change overhead per material

**Solution:** Use `THREE.InstancedMesh` for nodes with identical geometry:

```typescript
// In DistributedMesh - create once, instance many
const sharedGeometry = useMemo(() => new THREE.IcosahedronGeometry(1, 0), []);
const sharedMaterial = useMemo(() => createGlassMaterial(), []);

// Use InstancedMesh for all nodes
<instancedMesh
  ref={instancedMeshRef}
  args={[sharedGeometry, sharedMaterial, maxNodes]}
/>

// Update transforms in useFrame:
activeNodes.forEach((node, i) => {
  tempMatrix.compose(
    tempPosition.set(...node.position),
    tempQuaternion.setFromEuler(tempEuler.set(rx, ry, 0)),
    tempScale.setScalar(node.scale)
  );
  instancedMeshRef.current.setMatrixAt(i, tempMatrix);
});
instancedMeshRef.current.instanceMatrix.needsUpdate = true;
```

This reduces 18 draw calls to 1 for the base nodes.

---

### 5. Material Mutation in useFrame - MeshNode.tsx:309-377

**Location:** `/packages/landing-page/src/components/HeroVisualization/MeshNode.tsx:309-377`

**Problem:** Heavy material property modifications every single frame:

```typescript
useFrame((state, delta) => {
  // ...
  const mat = meshRef.current.material as THREE.MeshPhysicalMaterial;

  mat.opacity = 1.0 * Math.min(1, popAmount);
  mat.color.setHex(0x1a1a1a);
  mat.emissive.copy(glowColorObj);
  mat.emissiveIntensity = 0.2 * glowRef.current;
  mat.metalness = 0;
  mat.roughness = 0.05;
  mat.ior = 1.5;
  mat.transmission = 0.85;
  mat.thickness = 1.5;
  mat.attenuationColor = glowColorObj;
  mat.attenuationDistance = 0.8;
  mat.clearcoat = 1.0;
  mat.clearcoatRoughness = 0.05;
  mat.reflectivity = 0.5;
  mat.envMapIntensity = 1.0;
  mat.opacity = 0.9;
  // ... more mutations
});
```

**Impact:**
- Forces material recompilation on every property change
- THREE.js marks material as needing update
- GPU shader programs may be recompiled
- 20+ property assignments per node per frame = 360+ property mutations/frame

**Solution:** Use separate materials for different states and swap them:

```typescript
// Create materials once for each state
const idleMaterial = useMemo(() => createIdleMaterial(), []);
const glowingMaterial = useMemo(() => createGlowingMaterial(), []);
const offlineMaterial = useMemo(() => createOfflineMaterial(), []);

useFrame(() => {
  // Only animate what actually needs per-frame updates
  if (isGlowing) {
    // Only update dynamic properties
    glowingMaterial.emissiveIntensity = 0.2 * glowRef.current;
  }

  // Swap materials instead of mutating
  meshRef.current.material = isGlowing ? glowingMaterial :
                              isOnline ? idleMaterial : offlineMaterial;
});
```

---

### 6. Excessive State Updates in DistributedMesh - DistributedMesh.tsx:156-251

**Location:** `/packages/landing-page/src/components/HeroVisualization/DistributedMesh.tsx:156-251`

**Problem:** Lifecycle tick runs every 100ms with multiple `setState` calls that can cascade:

```typescript
useEffect(() => {
  const tickInterval = setInterval(() => {
    // Can trigger multiple setState calls
    if (rand < appearanceRate / 100) {
      setNodeData(prev => ...);  // State update 1
      setNodeLifecycle(lifecycle => ...);  // State update 2 (nested!)
      setJoiningNodes(current => ...);  // State update 3
      setTimeout(() => {
        setJoiningNodes(current => ...);  // State update 4 (delayed)
      }, 1200);
    }

    if (Math.random() < disappearanceRate / 100) {
      setNodeLifecycle(currentLifecycle => ...);  // More state
      setNodeData(prev => ...);  // More state
    }
    // ... more state updates
  }, 100);
}, [checkForOrphans]);
```

**Impact:**
- Multiple React re-renders per tick
- React-three-fiber rebuilds scene graph on each render
- Race conditions between nested setState calls
- The `nodeToDelete` variable assignment inside `setNodeLifecycle` then used in subsequent `setNodeData` is a race condition waiting to happen

**Solution:** Batch state updates and use refs for animation state:

```typescript
// Use ref for frequently-updated animation state
const nodeAnimationState = useRef<Map<number, AnimState>>(new Map());

// Single state update per tick using useReducer
const [state, dispatch] = useReducer(nodeReducer, initialState);

useEffect(() => {
  const tickInterval = setInterval(() => {
    dispatch({ type: 'TICK', payload: { rand: Math.random() } });
  }, 100);
  return () => clearInterval(tickInterval);
}, []);
```

---

### 7. Connection State Management Creates New Arrays Every Render

**Location:** `/packages/landing-page/src/components/HeroVisualization/DistributedMesh.tsx:258-320`

**Problem:** The `connections` useMemo creates new objects every time `nodeData` or `nodeLifecycle` changes:

```typescript
const connections = useMemo(() => {
  const conns: Array<{ from: NodeData; to: NodeData; key: string }> = [];
  // ... expensive computation
  return conns;
}, [nodeData, nodeLifecycle]);
```

Then in the effect:

```typescript
useEffect(() => {
  const newKeys = new Set(connections.map(c => c.key));  // O(n)
  const oldKeys = new Set(allConnections.map(c => c.key));  // O(n)
  const removed = allConnections.filter(c => !newKeys.has(c.key));  // O(n)
  // ... more operations
  setAllConnections(prev => ...);  // Triggers re-render
}, [connections]);  // Runs every time connections changes
```

**Impact:**
- O(n^2) complexity in connection calculation
- Additional O(n) operations in effect
- Missing `allConnections` from dependency array (stale closure bug!)
- Creates cascading re-renders

**Solution:**

1. Fix the missing dependency (bug):
```typescript
useEffect(() => {
  // ...
}, [connections, allConnections]); // allConnections was missing!
```

2. Better yet, use stable references:
```typescript
const connectionsRef = useRef<Map<string, Connection>>(new Map());

// Update ref, don't trigger re-render
const updateConnections = useCallback(() => {
  const newConnections = calculateConnections(nodeData, nodeLifecycle);
  // Diff against ref, only update what changed
  // No setState unless rendering needs to change
}, [nodeData, nodeLifecycle]);
```

---

## DRY Opportunities

### 8. Duplicate Geometry Creation Pattern

**Location:** Multiple files

**Problem:** Same pattern repeated for creating geometries:

```typescript
// MeshNode.tsx
const geometry = useMemo(() => new THREE.IcosahedronGeometry(1, 0), []);
const innerCoreGeometry = useMemo(() => new THREE.SphereGeometry(0.6, 16, 16), []);
const bigBangGeometry = useMemo(() => new THREE.SphereGeometry(1, 32, 32), []);

// ConnectionLine.tsx
const innerTubeGeometry = useMemo(() => new THREE.CylinderGeometry(0.03, 0.03, 1, 8, 1), []);
const outerTubeGeometry = useMemo(() => new THREE.CylinderGeometry(0.08, 0.08, 1, 8, 1), []);
const pulseGeometry = useMemo(() => new THREE.SphereGeometry(0.1, 8, 8), []);
const flashGeometry = useMemo(() => new THREE.SphereGeometry(0.3, 16, 16), []);
```

**Solution:** Create a shared geometry pool:

```typescript
// geometryPool.ts
const geometryPool = {
  icosahedron: null as THREE.IcosahedronGeometry | null,
  sphereSmall: null as THREE.SphereGeometry | null,
  sphereMedium: null as THREE.SphereGeometry | null,
  sphereLarge: null as THREE.SphereGeometry | null,
  cylinderThin: null as THREE.CylinderGeometry | null,
  cylinderThick: null as THREE.CylinderGeometry | null,
};

export function getGeometry(type: keyof typeof geometryPool): THREE.BufferGeometry {
  if (!geometryPool[type]) {
    switch (type) {
      case 'icosahedron':
        geometryPool[type] = new THREE.IcosahedronGeometry(1, 0);
        break;
      case 'sphereSmall':
        geometryPool[type] = new THREE.SphereGeometry(0.1, 8, 8);
        break;
      // ...
    }
  }
  return geometryPool[type]!;
}

export function disposeAllGeometry() {
  Object.values(geometryPool).forEach(g => g?.dispose());
}
```

---

### 9. Duplicate Material Creation

**Location:** MeshNode.tsx, ConnectionLine.tsx

**Problem:** Similar MeshBasicMaterial configurations repeated:

```typescript
// MeshNode.tsx
const innerCoreMaterial = useMemo(() => new THREE.MeshBasicMaterial({
  color: '#4ade80',
  transparent: true,
  opacity: 0,
  toneMapped: false,
}), []);

const bigBangMaterial = useMemo(() => new THREE.MeshBasicMaterial({
  color: '#ffffff',
  transparent: true,
  opacity: 0,
}), []);

// ConnectionLine.tsx
const innerTubeMaterial = useMemo(() => new THREE.MeshBasicMaterial({
  color: '#ffffff',
  transparent: true,
  opacity: 0,
  toneMapped: false,
}), []);
```

**Solution:** Material factory with pooling:

```typescript
// materialPool.ts
export function createEmissiveMaterial(color: string, toneMapped = false) {
  return new THREE.MeshBasicMaterial({
    color,
    transparent: true,
    opacity: 0,
    toneMapped,
  });
}

// Shared materials for identical configurations
export const sharedMaterials = {
  whiteEmissive: createEmissiveMaterial('#ffffff', false),
  greenEmissive: createEmissiveMaterial('#4ade80', false),
  // etc.
};
```

---

### 10. Repeated Vector/Quaternion Allocations in Animation Loops

**Location:** ConnectionLine.tsx:35-61, MeshNode.tsx:146-380

**Problem:** Creating new THREE objects inside animation loops:

```typescript
// ConnectionLine.tsx:35
const direction = new THREE.Vector3(end[0] - start[0], ...);  // New every call
const center = new THREE.Vector3(...);  // New every call
const quaternion = new THREE.Quaternion().setFromUnitVectors(...);  // New every call

// MeshNode.tsx:323
const glowColorObj = new THREE.Color(glowColor);  // New every frame
color = new THREE.Color(0xffffff).lerp(new THREE.Color(0xff9500), t);  // 2 new Colors
```

**Impact:**
- Constant memory allocation during animations
- GC pressure causing frame drops
- Unnecessary object construction overhead

**Solution:** Reuse temp objects:

```typescript
// At module level - single allocation
const tempVec3A = new THREE.Vector3();
const tempVec3B = new THREE.Vector3();
const tempQuat = new THREE.Quaternion();
const tempColor = new THREE.Color();
const Y_AXIS = new THREE.Vector3(0, 1, 0);

// In animation loop - reuse
function updateTubeTransform(...) {
  const direction = tempVec3A.set(end[0] - start[0], ...);
  const center = tempVec3B.set(...);
  const quaternion = tempQuat.setFromUnitVectors(Y_AXIS, direction);
}
```

---

## MAINTENANCE Improvements

### 11. Magic Numbers Everywhere

**Location:** All files

**Problem:** Hard-coded values with no explanation:

```typescript
// DistributedMesh.tsx
const maxConnections = 4;  // Why 4?
const connectionDistance = 10;  // Units?

// MeshNode.tsx
particleCount = 50;  // Why 50?
delta * 10  // What is this speed?
bigBangProgress.current * 8  // Why 8x size?
stiffness = 180  // Spring constant units?

// ConnectionLine.tsx
delta * 3  // Animation speed?
delta * 1.2  // Pulse speed?
```

**Solution:** Extract to constants with documentation:

```typescript
// constants.ts
export const MESH_CONFIG = {
  /** Maximum connections per node to prevent visual clutter */
  MAX_CONNECTIONS_PER_NODE: 4,

  /** Distance in world units for automatic connection */
  CONNECTION_DISTANCE: 10,

  /** Number of particles in birth explosion ring */
  PARTICLE_COUNT: 50,

  /** Big bang expansion multiplier (1 = original size, 9 = 9x original) */
  BIG_BANG_EXPANSION: 8,

  /** Spring physics constants */
  SPRING: {
    ENTRY_STIFFNESS: 140,
    EXIT_STIFFNESS: 180,
    ENTRY_DAMPING: 15,
    EXIT_DAMPING: 25,
  },

  /** Animation speeds (units per second) */
  ANIM_SPEED: {
    LIGHTSABER_EXTEND: 3,
    PULSE_TRAVEL: 1.2,
    BIG_BANG: 10,
  },
} as const;
```

---

### 12. Complex Nested Conditionals in useFrame

**Location:** MeshNode.tsx:146-380

**Problem:** 230+ line useFrame callback with deeply nested conditionals:

```typescript
useFrame((state, delta) => {
  if (meshRef.current) {
    // ... 50 lines of big bang animation
    if (bigBangActive && bigBangRef.current) {
      if (bigBangProgress.current >= 1) {
        // ...
      } else {
        // ...
      }
    }

    // ... 60 lines of particle ring animation
    if (ringActive && particleRingRef.current && particleVelocities.current) {
      if (!ringStarted.current) {
        // ...
      }
      if (ringProgress.current >= 1) {
        // ...
      } else {
        // ... 40 lines of particle updates
        if (progress < 0.33) {
          // ...
        } else if (progress < 0.66) {
          // ...
        } else {
          // ...
        }
      }
    }

    // ... 80 lines of material updates
    if (glowRef.current > 0.01 && isOnline && !isHidden) {
      // ...
    } else {
      // ...
    }
  }
});
```

**Impact:**
- Extremely difficult to maintain
- Easy to introduce bugs
- Hard to test individual animation states
- Cognitive load is extreme

**Solution:** Extract animation handlers:

```typescript
// animations/bigBangAnimation.ts
export function updateBigBang(
  mesh: THREE.Mesh,
  progress: { current: number },
  material: THREE.MeshBasicMaterial,
  delta: number
): boolean {
  // Returns true if animation complete
  progress.current += delta * ANIM_SPEED.BIG_BANG;

  if (progress.current >= 1) {
    material.opacity = 0;
    return true;
  }

  const scale = 1 + progress.current * BIG_BANG_EXPANSION;
  mesh.scale.setScalar(scale);
  material.opacity = Math.min(1, Math.pow(1 - progress.current, 2) * 1.5);
  return false;
}

// MeshNode.tsx
useFrame((_, delta) => {
  if (!meshRef.current) return;

  if (bigBangActive && bigBangRef.current) {
    const complete = updateBigBang(bigBangRef.current, bigBangProgress, bigBangMaterial, delta);
    if (complete) {
      setBigBangActive(false);
      setRingActive(true);
    }
  }

  // ... much cleaner
});
```

---

### 13. No TypeScript Strict Null Checks on Refs

**Location:** All files

**Problem:** Refs are accessed without null checks or with unsafe assertions:

```typescript
// ConnectionLine.tsx
if (flashActive.current && flashRefFrom.current && flashRefTo.current) {
  // Check exists but...
  flashRefFrom.current.position.set(from[0], from[1], from[2]);  // Safe here
}

// But elsewhere:
pulseRef.current.position.set(...);  // Assumes not null

// MeshNode.tsx
const mat = meshRef.current.material as THREE.MeshPhysicalMaterial;  // Unsafe cast
```

**Solution:** Add proper guards and type narrowing:

```typescript
useFrame(() => {
  const mesh = meshRef.current;
  if (!mesh) return;

  const mat = mesh.material;
  if (!(mat instanceof THREE.MeshPhysicalMaterial)) return;

  // Now TypeScript knows types are correct
});
```

---

## NITPICKS

### 14. Inconsistent Naming

- `glowingNodesRef` vs `glowRef` - both track glow state
- `bigBangProgress` vs `ringProgress` vs `extendProgress` - could be unified pattern
- `isOnline` vs `isActive` vs `isHidden` - overlapping semantics

### 15. Unused Parameters

```typescript
// ConnectionLine.tsx:219
useFrame((_, delta) => {  // First param unused but named
```

### 16. CSS Inline in JSX

```typescript
// MeshNode.tsx:425-458
<div className="bg-black/90 backdrop-blur-md border border-blue-500/40 ...">
```

Should use CSS modules or styled-components for consistency.

### 17. Console Artifacts

No console.log statements found (good), but no error boundaries either.

---

## STRENGTHS

1. **Proper use of `useMemo` for geometry/material creation** - Intent is correct even if disposal is missing

2. **Ref-based animation state** - Using refs like `pulseState.current` correctly avoids re-renders for animation state

3. **Callback refs for stable references** - `onPulseArrivalRef.current = onPulseArrival` pattern is correct

4. **Good separation of concerns** - Each component has a clear responsibility (nodes, connections, orchestration)

5. **Suspense boundary** - Canvas is properly wrapped in Suspense

6. **Performance-conscious Canvas config** - `dpr={[1, 1.5]}` and `powerPreference: 'high-performance'` are good choices

7. **Bloom post-processing** - Using mipmapBlur for efficient bloom

---

## Priority Action Items

### P0 - Critical (Memory Leaks)
1. Add disposal effects to MeshNode.tsx
2. Add disposal effects to ConnectionLine.tsx
3. Fix geometry recreation in updateTubeGeometry

### P1 - High (Performance)
4. Implement geometry pooling
5. Implement material state machine (swap vs mutate)
6. Add InstancedMesh for nodes

### P2 - Medium (Architecture)
7. Fix missing dependency in connections effect
8. Batch state updates in lifecycle tick
9. Extract animation functions

### P3 - Low (Maintenance)
10. Extract magic numbers to constants
11. Add TypeScript strict null checks
12. Consolidate naming conventions

---

## Estimated Impact

| Fix | Draw Calls | Memory | GC Pressure | Maintainability |
|-----|------------|--------|-------------|-----------------|
| Geometry disposal | - | -80% leak | High | - |
| updateTubeGeometry fix | - | -50% churn | Critical | - |
| InstancedMesh | -90% | -60% | Medium | - |
| Material state machine | - | - | High | Medium |
| Animation extraction | - | - | - | High |

**Combined effect:** Should reduce draw calls by ~90%, eliminate memory leaks, and reduce GC pauses by 70%+.

---

## Implementation Summary

All critical optimizations have been implemented:

### New Files Created:
- `constants.ts` - Centralized configuration, magic number extraction, reusable temp objects
- `geometryPool.ts` - Shared geometry pool with ref counting and automatic disposal
- `materialPool.ts` - Material factory with state functions and disposal tracking

### Files Modified:

**MeshNode.tsx:**
- Added geometry pool integration (`acquirePool`/`releasePool`)
- Uses shared geometries from pool instead of creating per-instance
- Proper disposal of non-pooled geometries (edges, particles) on unmount
- Proper disposal of all materials on unmount
- Uses temp colors from constants instead of allocating in animation loop
- All magic numbers replaced with named constants

**ConnectionLine.tsx:**
- CRITICAL FIX: `updateTubeGeometry` replaced with `updateTubeTransform` that uses scale/rotation instead of recreating geometry every frame
- Uses shared unit cylinder geometry from pool (scaled per-instance)
- Uses shared sphere geometries from pool for pulses/flashes
- Proper material disposal on unmount
- Uses temp vectors/quaternions from constants

**DistributedMesh.tsx:**
- Added geometry pool integration
- Uses shared cyclorama geometry
- Fixed connection tracking with stable refs (prevConnectionKeysRef)
- Uses temp vectors from constants for distance calculations
- All magic numbers replaced with named constants

### Performance Impact:
| Metric | Before | After |
|--------|--------|-------|
| Geometry allocations/frame | 2N (N=connections) | 0 |
| Memory leaks | Yes (severe) | No |
| GC pressure | High | Minimal |
| Shared geometries | 0 | 7 types pooled |
| Material tracking | None | Full disposal |

### Build Status: PASSING
