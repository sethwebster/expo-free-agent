import { useEffect, useState } from 'react';

interface SmokeAnimation {
  x: number;
  y: number;
  intensity: number;
}

export function useSmokeAnimation() {
  const [smokeAnimation, setSmokeAnimation] = useState<SmokeAnimation>({ x: 0, y: 0, intensity: 1 });

  useEffect(() => {
    // Organic smoke-like animation
    let animationFrame: number;
    const startTime = Date.now();

    const animate = () => {
      const time = (Date.now() - startTime) / 1000;

      // Multiple sine waves at different frequencies for organic movement
      const x = Math.sin(time * 0.3) * 3 + Math.sin(time * 0.7) * 1.5;
      const y = Math.cos(time * 0.4) * 2 + Math.cos(time * 0.8) * 1;

      // Wax and wane intensity (breathing effect)
      const intensity = 0.85 + Math.sin(time * 0.5) * 0.15;

      setSmokeAnimation({ x, y, intensity });
      animationFrame = requestAnimationFrame(animate);
    };

    animate();
    return () => cancelAnimationFrame(animationFrame);
  }, []);

  return smokeAnimation;
}
