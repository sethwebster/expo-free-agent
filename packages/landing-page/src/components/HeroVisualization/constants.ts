import * as THREE from 'three';

// ============================================================================
// MESH CONFIGURATION
// ============================================================================

export const MESH_CONFIG = {
  /** Maximum connections per node to prevent visual clutter */
  MAX_CONNECTIONS_PER_NODE: 4,

  /** Distance in world units for automatic connection */
  CONNECTION_DISTANCE: 15,

  /** Number of particles in birth explosion ring */
  PARTICLE_COUNT: 50,

  /** Big bang expansion multiplier (1 = original size, 9 = 9x original) */
  BIG_BANG_EXPANSION: 8,

  /** Minimum distance between node centers */
  MIN_NODE_DISTANCE: 2.5,

  /** Node positioning bounds */
  BOUNDS: {
    X_SPREAD: 32,
    Y_SPREAD: 20,
    Z_MIN: -10,
    Z_MAX: 4,
  },

  /** Grid layout for initial nodes */
  GRID: {
    COLS: 6,
    ROWS: 5,
  },

  /** Globe reveal settings */
  GLOBE: {
    RADIUS: 50,
    CAMERA_START_Z: 18,
    CAMERA_PULLBACK_Z: 120,
    NODE_EXPANSION_SCALE: 3,
  },
} as const;

// ============================================================================
// SPRING PHYSICS
// ============================================================================

export const SPRING = {
  /** Entry animation - overshoot bounce */
  ENTRY_STIFFNESS: 140,
  ENTRY_DAMPING: 15,

  /** Exit animation - snappy collapse */
  EXIT_STIFFNESS: 180,
  EXIT_DAMPING: 25,
} as const;

// ============================================================================
// ANIMATION SPEEDS (units per second)
// ============================================================================

export const ANIM_SPEED = {
  /** Lightsaber extend/retract speed */
  LIGHTSABER: 3,

  /** Pulse travel speed along connection */
  PULSE: 1.2,

  /** Big bang flash expansion */
  BIG_BANG: 10,

  /** Particle ring expansion duration (1/speed = seconds) */
  PARTICLE_RING: 0.5,

  /** Glow interpolation factor */
  GLOW_LERP: 0.15,

  /** Online/offline transition factor */
  ONLINE_LERP: 0.05,

  /** Joining flash transition factor */
  JOINING_LERP: 0.1,
} as const;

// ============================================================================
// COLORS
// ============================================================================

export const COLORS = {
  BASE: 0xe0e7ff,
  OFFLINE: 0x52525b,
  AMBER: 0xfef3c7,
  GREEN: 0xbbf7d0,
  GLOW_AMBER: 0xfbbf24,
  GLOW_GREEN: 0x4ade80,
  OBSIDIAN: 0x0a0a0a,
  DARK_GRAY: 0x1a1a1a,
  WHITE: 0xffffff,
  ORANGE: 0xff9500,
  RED: 0xff3b30,
  INDIGO: 0xa5b4fc,
} as const;

// ============================================================================
// GEOMETRY CONFIGURATION
// ============================================================================

export const GEOMETRY = {
  /** Icosahedron detail level (0 = 20 faces) */
  ICOSAHEDRON_DETAIL: 0,

  /** Sphere segment counts */
  SPHERE_SEGMENTS: {
    LOW: 8,
    MEDIUM: 16,
    HIGH: 32,
  },

  /** Cylinder radial segments */
  CYLINDER_SEGMENTS: 8,

  /** Inner core scale relative to node */
  INNER_CORE_SCALE: 0.6,

  /** Tube radii for connections */
  TUBE: {
    INNER_RADIUS: 0.015,
    OUTER_RADIUS: 0.04,
  },

  /** Pulse and flash radii */
  PULSE_RADIUS: 0.25, // Increased from 0.1 for better visibility
  FLASH_RADIUS: 0.3,
} as const;

// ============================================================================
// MATERIAL PROPERTIES
// ============================================================================

export const MATERIAL = {
  /** Glass material for active nodes */
  GLASS: {
    metalness: 0.1,
    roughness: 0.1,
    opacity: 0.7,
    envMapIntensity: 1.5,
    clearcoat: 1,
    clearcoatRoughness: 0.1,
    reflectivity: 0.9,
  },

  /** Obsidian material for inactive nodes */
  OBSIDIAN: {
    metalness: 0.05,
    roughness: 0.01,
    transmission: 0,
    clearcoat: 1.0,
    clearcoatRoughness: 0.02,
    reflectivity: 1.0,
    ior: 1.5,
    envMapIntensity: 2.0,
  },

  /** Crystal material for glowing nodes */
  CRYSTAL: {
    metalness: 0,
    roughness: 0.05,
    ior: 1.5,
    transmission: 0.85,
    thickness: 1.5,
    attenuationDistance: 0.8,
    clearcoat: 1.0,
    clearcoatRoughness: 0.05,
    reflectivity: 0.5,
    envMapIntensity: 1.0,
  },
} as const;

// ============================================================================
// TIMING
// ============================================================================

export const TIMING = {
  /** Amber glow duration before switching to green (ms) */
  AMBER_DURATION: 200,

  /** Lifecycle tick interval (ms) */
  LIFECYCLE_TICK: 100,

  /** Stats sync interval (ms) */
  STATS_SYNC: 100,

  /** Joining animation duration (ms) */
  JOINING_DURATION: 1200,

  /** Hover timeout before hiding tooltip (ms) */
  HOVER_TIMEOUT: 100,
} as const;

// ============================================================================
// REUSABLE TEMP OBJECTS (avoid allocations in hot paths)
// ============================================================================

export const tempVec3A = new THREE.Vector3();
export const tempVec3B = new THREE.Vector3();
export const tempVec3C = new THREE.Vector3();
export const tempQuat = new THREE.Quaternion();
export const tempColor = new THREE.Color();
export const tempColorB = new THREE.Color();
export const Y_AXIS = new THREE.Vector3(0, 1, 0);
