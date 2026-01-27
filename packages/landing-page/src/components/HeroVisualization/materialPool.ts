import * as THREE from 'three';
import { COLORS, MATERIAL } from './constants';
import { getQualitySettings } from './quality';

/**
 * Material Pool - Factory and cache for Three.js materials
 *
 * Provides pre-configured materials for different visual states.
 * Materials that need per-instance state (opacity, emissive) are cloned.
 * Static materials are shared across instances.
 *
 * Chrome Optimization:
 * - When transmission is disabled (Chrome), uses MeshStandardMaterial
 * - This avoids expensive subsurface scattering calculations
 * - Visual quality is slightly reduced but performance is ~3x better
 */

// ============================================================================
// SHARED MATERIAL TEMPLATES (cloned for instances that need mutation)
// ============================================================================

// Union type for node materials (Physical for Safari, Standard for Chrome)
export type NodeMaterial = THREE.MeshPhysicalMaterial | THREE.MeshStandardMaterial;

const templates = {
  glass: null as THREE.MeshPhysicalMaterial | null,
  glassStandard: null as THREE.MeshStandardMaterial | null,
  obsidian: null as THREE.MeshPhysicalMaterial | null,
  crystal: null as THREE.MeshPhysicalMaterial | null,
  emissiveWhite: null as THREE.MeshBasicMaterial | null,
  emissiveGreen: null as THREE.MeshBasicMaterial | null,
  line: null as THREE.LineBasicMaterial | null,
  point: null as THREE.PointsMaterial | null,
};

// Track all created materials for disposal
const allMaterials: THREE.Material[] = [];

// ============================================================================
// GLASS MATERIAL - Default node appearance
// ============================================================================

function createGlassTemplate(): THREE.MeshPhysicalMaterial {
  if (!templates.glass) {
    templates.glass = new THREE.MeshPhysicalMaterial({
      color: COLORS.BASE,
      metalness: MATERIAL.GLASS.metalness,
      roughness: MATERIAL.GLASS.roughness,
      transparent: true,
      opacity: MATERIAL.GLASS.opacity,
      envMapIntensity: MATERIAL.GLASS.envMapIntensity,
      clearcoat: MATERIAL.GLASS.clearcoat,
      clearcoatRoughness: MATERIAL.GLASS.clearcoatRoughness,
      reflectivity: MATERIAL.GLASS.reflectivity,
      side: THREE.DoubleSide,
    });
    allMaterials.push(templates.glass);
  }
  return templates.glass;
}

/**
 * Chrome-optimized glass material using MeshStandardMaterial
 * Avoids expensive transmission calculations
 */
function createGlassStandardTemplate(): THREE.MeshStandardMaterial {
  if (!templates.glassStandard) {
    templates.glassStandard = new THREE.MeshStandardMaterial({
      color: COLORS.BASE,
      metalness: MATERIAL.GLASS.metalness,
      roughness: MATERIAL.GLASS.roughness,
      transparent: true,
      opacity: MATERIAL.GLASS.opacity,
      envMapIntensity: MATERIAL.GLASS.envMapIntensity,
      side: THREE.DoubleSide,
    });
    allMaterials.push(templates.glassStandard);
  }
  return templates.glassStandard;
}

/**
 * Clone glass material - uses Physical for Safari, Standard for Chrome
 */
export function cloneGlassMaterial(): NodeMaterial {
  const quality = getQualitySettings();

  if (quality.useTransmission) {
    const mat = createGlassTemplate().clone();
    allMaterials.push(mat);
    return mat;
  }

  const mat = createGlassStandardTemplate().clone();
  allMaterials.push(mat);
  return mat;
}

// ============================================================================
// OBSIDIAN MATERIAL - Inactive node appearance
// ============================================================================

export function createObsidianMaterial(): THREE.MeshPhysicalMaterial {
  if (!templates.obsidian) {
    templates.obsidian = new THREE.MeshPhysicalMaterial({
      color: COLORS.OBSIDIAN,
      metalness: MATERIAL.OBSIDIAN.metalness,
      roughness: MATERIAL.OBSIDIAN.roughness,
      transparent: true,
      opacity: 1.0,
      transmission: MATERIAL.OBSIDIAN.transmission,
      clearcoat: MATERIAL.OBSIDIAN.clearcoat,
      clearcoatRoughness: MATERIAL.OBSIDIAN.clearcoatRoughness,
      reflectivity: MATERIAL.OBSIDIAN.reflectivity,
      ior: MATERIAL.OBSIDIAN.ior,
      envMapIntensity: MATERIAL.OBSIDIAN.envMapIntensity,
      side: THREE.DoubleSide,
    });
    allMaterials.push(templates.obsidian);
  }
  return templates.obsidian;
}

// ============================================================================
// EMISSIVE MATERIALS - For glowing effects
// ============================================================================

export function createEmissiveMaterial(
  color: number | string = COLORS.WHITE,
  toneMapped = false
): THREE.MeshBasicMaterial {
  const mat = new THREE.MeshBasicMaterial({
    color,
    transparent: true,
    opacity: 0,
    toneMapped,
  });
  allMaterials.push(mat);
  return mat;
}

// ============================================================================
// LINE MATERIAL - For edge highlights
// ============================================================================

export function createLineMaterial(): THREE.LineBasicMaterial {
  const mat = new THREE.LineBasicMaterial({
    transparent: true,
    opacity: 0.8,
  });
  allMaterials.push(mat);
  return mat;
}

// ============================================================================
// POINT MATERIAL - For particle systems
// ============================================================================

export function createPointMaterial(
  color: number | string = COLORS.WHITE,
  size = 0.15
): THREE.PointsMaterial {
  const mat = new THREE.PointsMaterial({
    color,
    size,
    transparent: true,
    opacity: 0,
    sizeAttenuation: true,
  });
  allMaterials.push(mat);
  return mat;
}

// ============================================================================
// CYCLORAMA MATERIAL - Background sphere
// ============================================================================

export function createCycloramaMaterial(): THREE.MeshBasicMaterial {
  const mat = new THREE.MeshBasicMaterial({
    color: COLORS.DARK_GRAY,
    side: THREE.BackSide,
    transparent: true,
    opacity: 0.3,
  });
  allMaterials.push(mat);
  return mat;
}

// ============================================================================
// MATERIAL STATE UPDATES - For per-frame animations
// ============================================================================

/**
 * Check if material is MeshPhysicalMaterial (has transmission support)
 */
function isPhysicalMaterial(mat: NodeMaterial): mat is THREE.MeshPhysicalMaterial {
  return 'transmission' in mat;
}

/**
 * Apply glowing crystal state to a node material
 * Handles both Physical (Safari) and Standard (Chrome) materials
 */
export function applyGlowingState(
  mat: NodeMaterial,
  glowColor: THREE.Color,
  glowIntensity: number
): void {
  // Common properties for both material types
  mat.color.setHex(COLORS.DARK_GRAY);
  mat.emissive.copy(glowColor);
  mat.emissiveIntensity = 0.2 * glowIntensity;
  mat.metalness = MATERIAL.CRYSTAL.metalness;
  mat.roughness = MATERIAL.CRYSTAL.roughness;
  mat.envMapIntensity = MATERIAL.CRYSTAL.envMapIntensity;
  mat.opacity = 0.9;

  // Physical-only properties (Safari - full quality)
  if (isPhysicalMaterial(mat)) {
    mat.ior = MATERIAL.CRYSTAL.ior;
    mat.transmission = MATERIAL.CRYSTAL.transmission;
    mat.thickness = MATERIAL.CRYSTAL.thickness;
    mat.attenuationColor.copy(glowColor);
    mat.attenuationDistance = MATERIAL.CRYSTAL.attenuationDistance;
    mat.clearcoat = MATERIAL.CRYSTAL.clearcoat;
    mat.clearcoatRoughness = MATERIAL.CRYSTAL.clearcoatRoughness;
    mat.reflectivity = MATERIAL.CRYSTAL.reflectivity;
  } else {
    // Standard material (Chrome) - boost emissive to compensate for no transmission
    mat.emissiveIntensity = 0.35 * glowIntensity;
  }
}

/**
 * Apply obsidian state to a node material
 * Handles both Physical (Safari) and Standard (Chrome) materials
 */
export function applyObsidianState(mat: NodeMaterial): void {
  // Common properties for both material types
  mat.color.setHex(COLORS.OBSIDIAN);
  mat.emissive.setHex(0x000000);
  mat.emissiveIntensity = 0;
  mat.metalness = MATERIAL.OBSIDIAN.metalness;
  mat.roughness = MATERIAL.OBSIDIAN.roughness;
  mat.envMapIntensity = MATERIAL.OBSIDIAN.envMapIntensity;
  mat.opacity = 1.0;

  // Physical-only properties (Safari - full quality)
  if (isPhysicalMaterial(mat)) {
    mat.transmission = MATERIAL.OBSIDIAN.transmission;
    mat.thickness = 0;
    mat.clearcoat = MATERIAL.OBSIDIAN.clearcoat;
    mat.clearcoatRoughness = MATERIAL.OBSIDIAN.clearcoatRoughness;
    mat.reflectivity = MATERIAL.OBSIDIAN.reflectivity;
    mat.ior = MATERIAL.OBSIDIAN.ior;
  }
}

// ============================================================================
// CLEANUP
// ============================================================================

/**
 * Dispose a single material and remove from tracking
 */
export function disposeMaterial(mat: THREE.Material): void {
  const idx = allMaterials.indexOf(mat);
  if (idx !== -1) {
    allMaterials.splice(idx, 1);
  }
  mat.dispose();
}

/**
 * Dispose all tracked materials
 */
export function disposeAllMaterials(): void {
  for (const mat of allMaterials) {
    mat.dispose();
  }
  allMaterials.length = 0;

  // Clear templates
  templates.glass = null;
  templates.glassStandard = null;
  templates.obsidian = null;
  templates.crystal = null;
  templates.emissiveWhite = null;
  templates.emissiveGreen = null;
  templates.line = null;
  templates.point = null;
}

/**
 * Get current material count for debugging
 */
export function getMaterialCount(): number {
  return allMaterials.length;
}
