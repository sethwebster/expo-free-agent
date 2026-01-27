import * as THREE from 'three';
import { GEOMETRY } from './constants';

/**
 * Geometry Pool - Singleton pattern for shared Three.js geometries
 *
 * Prevents duplicate GPU memory allocation by sharing identical geometries
 * across all components. All geometries are created lazily and disposed
 * together when the visualization unmounts.
 */

type GeometryType =
  | 'icosahedron'
  | 'sphereSmall'
  | 'sphereMedium'
  | 'sphereLarge'
  | 'innerCore'
  | 'cylinderUnit'
  | 'cyclorama'
  | 'globe';

const pool: Partial<Record<GeometryType, THREE.BufferGeometry>> = {};
let refCount = 0;

/**
 * Get or create a shared geometry instance.
 * Call releasePool() when done to allow cleanup.
 */
export function getGeometry(type: GeometryType): THREE.BufferGeometry {
  if (!pool[type]) {
    switch (type) {
      case 'icosahedron':
        pool[type] = new THREE.IcosahedronGeometry(1, GEOMETRY.ICOSAHEDRON_DETAIL);
        break;

      case 'sphereSmall':
        pool[type] = new THREE.SphereGeometry(
          GEOMETRY.PULSE_RADIUS,
          GEOMETRY.SPHERE_SEGMENTS.LOW,
          GEOMETRY.SPHERE_SEGMENTS.LOW
        );
        break;

      case 'sphereMedium':
        pool[type] = new THREE.SphereGeometry(
          GEOMETRY.FLASH_RADIUS,
          GEOMETRY.SPHERE_SEGMENTS.MEDIUM,
          GEOMETRY.SPHERE_SEGMENTS.MEDIUM
        );
        break;

      case 'sphereLarge':
        pool[type] = new THREE.SphereGeometry(
          1,
          GEOMETRY.SPHERE_SEGMENTS.HIGH,
          GEOMETRY.SPHERE_SEGMENTS.HIGH
        );
        break;

      case 'innerCore':
        pool[type] = new THREE.SphereGeometry(
          GEOMETRY.INNER_CORE_SCALE,
          GEOMETRY.SPHERE_SEGMENTS.MEDIUM,
          GEOMETRY.SPHERE_SEGMENTS.MEDIUM
        );
        break;

      case 'cylinderUnit':
        // Unit cylinder (radius=1, height=1) - scale in shader/transform
        pool[type] = new THREE.CylinderGeometry(
          1,
          1,
          1,
          GEOMETRY.CYLINDER_SEGMENTS,
          1
        );
        break;

      case 'cyclorama':
        pool[type] = new THREE.SphereGeometry(35, 32, 32);
        break;

      case 'globe':
        pool[type] = new THREE.SphereGeometry(50, 64, 64);
        break;

      default:
        throw new Error(`Unknown geometry type: ${type}`);
    }
  }

  return pool[type]!;
}

/**
 * Create an EdgesGeometry from a source geometry (not pooled as it depends on source)
 */
export function createEdgesGeometry(source: THREE.BufferGeometry): THREE.EdgesGeometry {
  return new THREE.EdgesGeometry(source);
}

/**
 * Acquire a reference to the geometry pool.
 * Must be paired with releasePool().
 */
export function acquirePool(): void {
  refCount++;
}

/**
 * Release a reference to the geometry pool.
 * When refCount reaches 0, all geometries are disposed.
 */
export function releasePool(): void {
  refCount--;

  if (refCount <= 0) {
    refCount = 0;
    disposePool();
  }
}

/**
 * Dispose all pooled geometries immediately.
 * Called automatically when refCount reaches 0.
 */
export function disposePool(): void {
  for (const key in pool) {
    const geom = pool[key as GeometryType];
    if (geom) {
      geom.dispose();
      delete pool[key as GeometryType];
    }
  }
}

/**
 * Get current pool stats for debugging
 */
export function getPoolStats(): { types: GeometryType[]; refCount: number } {
  return {
    types: Object.keys(pool) as GeometryType[],
    refCount,
  };
}
