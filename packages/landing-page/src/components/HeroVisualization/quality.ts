/**
 * Quality Settings - Browser-adaptive rendering configuration
 *
 * Chrome's ANGLE WebGL layer handles certain features much slower than Safari's
 * native Metal backend. This module detects the browser and provides appropriate
 * quality presets to maintain smooth performance across all browsers.
 *
 * Key Chrome bottlenecks:
 * 1. MeshPhysicalMaterial transmission (SSS) - ~3x slower than Safari
 * 2. Bloom post-processing with mipmapBlur - ~2x slower
 * 3. Frequent material uniform updates - may trigger shader recompilation
 */

export interface QualitySettings {
  /** Use MeshPhysicalMaterial with transmission (expensive SSS) */
  useTransmission: boolean;

  /** Bloom effect intensity (0-10) */
  bloomIntensity: number;

  /** Bloom luminance threshold (lower = more bloom) */
  bloomThreshold: number;

  /** Bloom luminance smoothing */
  bloomSmoothing: number;

  /** Use mipmapBlur for bloom (expensive) */
  useMipmapBlur: boolean;

  /** Maximum number of nodes to render */
  maxNodes: number;

  /** Particle count for birth effects */
  particleCount: number;

  /** Device pixel ratio range [min, max] */
  dpr: [number, number];

  /** Material update throttle (frames between full material updates) */
  materialUpdateThrottle: number;
}

export type BrowserType = 'chrome' | 'safari' | 'firefox' | 'other';
export type QualityTier = 'high' | 'medium' | 'low';

// Cache browser detection result
let cachedBrowser: BrowserType | null = null;
let cachedSettings: QualitySettings | null = null;

/**
 * Detect current browser type
 */
export function detectBrowser(): BrowserType {
  if (cachedBrowser !== null) {
    return cachedBrowser;
  }

  // Server-side rendering check
  if (typeof navigator === 'undefined') {
    cachedBrowser = 'other';
    return cachedBrowser;
  }

  const ua = navigator.userAgent;

  // Order matters - Chrome UA includes Safari, so check Chrome first
  if (/Chrome/.test(ua) && !/Edg|Edge|OPR|Opera/.test(ua)) {
    cachedBrowser = 'chrome';
  } else if (/Safari/.test(ua) && !/Chrome/.test(ua)) {
    cachedBrowser = 'safari';
  } else if (/Firefox/.test(ua)) {
    cachedBrowser = 'firefox';
  } else {
    cachedBrowser = 'other';
  }

  return cachedBrowser;
}

/**
 * Quality presets by tier
 */
const QUALITY_PRESETS: Record<QualityTier, QualitySettings> = {
  high: {
    useTransmission: true,
    bloomIntensity: 4,
    bloomThreshold: 0.1,
    bloomSmoothing: 0.9,
    useMipmapBlur: true,
    maxNodes: 80,
    particleCount: 50,
    dpr: [1, 2],
    materialUpdateThrottle: 1,
  },
  medium: {
    useTransmission: false,
    bloomIntensity: 2.5,
    bloomThreshold: 0.2,
    bloomSmoothing: 0.7,
    useMipmapBlur: false,
    maxNodes: 50,
    particleCount: 30,
    dpr: [1, 2],
    materialUpdateThrottle: 2,
  },
  low: {
    useTransmission: false,
    bloomIntensity: 1.5,
    bloomThreshold: 0.3,
    bloomSmoothing: 0.5,
    useMipmapBlur: false,
    maxNodes: 30,
    particleCount: 20,
    dpr: [1, 1.5],
    materialUpdateThrottle: 3,
  },
};

/**
 * Map browsers to quality tiers
 */
const BROWSER_QUALITY: Record<BrowserType, QualityTier> = {
  safari: 'high',
  chrome: 'medium',
  firefox: 'medium',
  other: 'low',
};

/**
 * Get quality settings for current browser
 */
export function getQualitySettings(): QualitySettings {
  if (cachedSettings !== null) {
    return cachedSettings;
  }

  const browser = detectBrowser();
  const tier = BROWSER_QUALITY[browser];
  cachedSettings = { ...QUALITY_PRESETS[tier] };

  return cachedSettings;
}

/**
 * Get quality settings for a specific tier (for testing/debugging)
 */
export function getQualitySettingsForTier(tier: QualityTier): QualitySettings {
  return { ...QUALITY_PRESETS[tier] };
}

/**
 * Check if current browser is Chrome
 */
export function isChrome(): boolean {
  return detectBrowser() === 'chrome';
}

/**
 * Check if current browser is Safari
 */
export function isSafari(): boolean {
  return detectBrowser() === 'safari';
}

/**
 * Clear cached values (useful for testing)
 */
export function clearQualityCache(): void {
  cachedBrowser = null;
  cachedSettings = null;
}
