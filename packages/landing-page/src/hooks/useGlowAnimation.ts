import { useEffect, useState } from 'react';

export function useGlowAnimation() {
  const [glowOpacity, setGlowOpacity] = useState(0);

  useEffect(() => {
    // Wait 2 seconds, then fade in glow over 1.5 seconds
    const delayTimeout = setTimeout(() => {
      const startTime = Date.now();
      const fadeInDuration = 1500;

      const fadeInterval = setInterval(() => {
        const elapsed = Date.now() - startTime;
        const progress = Math.min(elapsed / fadeInDuration, 1);
        setGlowOpacity(progress);

        if (progress >= 1) {
          clearInterval(fadeInterval);
        }
      }, 16);
    }, 2000);

    return () => clearTimeout(delayTimeout);
  }, []);

  return glowOpacity;
}
