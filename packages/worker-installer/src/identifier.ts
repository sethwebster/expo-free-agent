import { randomBytes } from 'crypto';

// Word lists for generating human-friendly identifiers
const adjectives = [
  'swift', 'brave', 'bright', 'calm', 'cool', 'dark', 'eager', 'fair',
  'fast', 'gentle', 'happy', 'keen', 'light', 'mighty', 'noble', 'proud',
  'quick', 'quiet', 'rapid', 'silent', 'smooth', 'steady', 'strong', 'wise',
  'bold', 'clever', 'cosmic', 'crystal', 'electric', 'golden', 'silver', 'stellar'
];

const nouns = [
  'phoenix', 'dragon', 'falcon', 'hawk', 'eagle', 'raven', 'tiger', 'wolf',
  'bear', 'fox', 'lion', 'panda', 'cobra', 'viper', 'shark', 'whale',
  'comet', 'meteor', 'nova', 'star', 'moon', 'sun', 'cloud', 'storm',
  'mountain', 'river', 'ocean', 'forest', 'thunder', 'lightning', 'aurora', 'nebula'
];

/**
 * Generate a unique, memorable public identifier safe for display
 * Format: adjective-noun-number (e.g., "swift-phoenix-42")
 * No PII, safe for public network maps
 */
export function generatePublicIdentifier(): string {
  const adjective = adjectives[Math.floor(Math.random() * adjectives.length)];
  const noun = nouns[Math.floor(Math.random() * nouns.length)];

  // Generate a random 2-digit number
  const number = randomBytes(1)[0] % 100;

  return `${adjective}-${noun}-${number}`;
}

/**
 * Validate public identifier format
 */
export function isValidPublicIdentifier(id: string): boolean {
  // Format: word-word-number
  const pattern = /^[a-z]+-[a-z]+-\d{1,3}$/;
  return pattern.test(id);
}
